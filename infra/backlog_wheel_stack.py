import json

import aws_cdk as cdk
from aws_cdk import (
    RemovalPolicy,
    Stack,
    aws_iam as iam,
    aws_ec2 as ec2,
    aws_ecr_assets as ecr_assets,
    aws_route53 as route53,
    aws_secretsmanager as secretsmanager,
    aws_ssm as ssm,
)
from constructs import Construct


class BacklogWheelEc2Stack(Stack):
    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        domain_name = self.node.try_get_context("domainName") or "wheel.streamosaic.app"
        hosted_zone_domain = self.node.try_get_context("hostedZoneDomain") or "streamosaic.app"
        record_name = domain_name.removesuffix(f".{hosted_zone_domain}")
        instance_type = self.node.try_get_context("ec2InstanceType") or "t3a.micro"
        ssh_cidr = self.node.try_get_context("ec2SshCidr")
        manage_dns = self.node.try_get_context("ec2ManageDns") != "false"

        vpc = ec2.Vpc.from_lookup(
            self,
            "Vpc",
            is_default=True,
        )

        runtime_secret = secretsmanager.Secret.from_secret_name_v2(
            self,
            "RuntimeSecret",
            "backlog-wheel/prototype/runtime",
        )

        database_credentials = secretsmanager.Secret(
            self,
            "Ec2DatabaseCredentials",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template=json.dumps({"username": "backlog_wheel"}),
                generate_string_key="password",
                exclude_punctuation=True,
                password_length=30,
            ),
        )
        database_credentials.apply_removal_policy(RemovalPolicy.RETAIN)

        role = iam.Role(
            self,
            "InstanceRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonSSMManagedInstanceCore"
                )
            ],
        )
        runtime_secret.grant_read(role)
        database_credentials.grant_read(role)

        security_group = ec2.SecurityGroup(
            self,
            "InstanceSecurityGroup",
            vpc=vpc,
            allow_all_outbound=True,
        )
        security_group.add_ingress_rule(ec2.Peer.any_ipv4(), ec2.Port.tcp(80), "HTTP")
        security_group.add_ingress_rule(ec2.Peer.any_ipv4(), ec2.Port.tcp(443), "HTTPS")

        if ssh_cidr:
            security_group.add_ingress_rule(
                ec2.Peer.ipv4(ssh_cidr), ec2.Port.tcp(22), "SSH"
            )

        image = ecr_assets.DockerImageAsset(
            self,
            "Image",
            directory=".",
            platform=ecr_assets.Platform.LINUX_AMD64,
        )
        image.repository.grant_pull(role)
        ecr_registry = cdk.Fn.sub(
            "${AWS::AccountId}.dkr.ecr.${AWS::Region}.${AWS::URLSuffix}"
        )

        instance = ec2.Instance(
            self,
            "Instance",
            vpc=vpc,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),
            instance_type=ec2.InstanceType(instance_type),
            machine_image=ec2.MachineImage.latest_amazon_linux2023(),
            role=role,
            security_group=security_group,
            block_devices=[
                ec2.BlockDevice(
                    device_name="/dev/xvda",
                    volume=ec2.BlockDeviceVolume.ebs(
                        20,
                        encrypted=True,
                        volume_type=ec2.EbsDeviceVolumeType.GP3,
                    ),
                )
            ],
        )

        elastic_ip = ec2.CfnEIP(self, "ElasticIp", domain="vpc")
        ec2.CfnEIPAssociation(
            self,
            "ElasticIpAssociation",
            allocation_id=elastic_ip.attr_allocation_id,
            instance_id=instance.instance_id,
        )

        instance.add_user_data(
            "set -euxo pipefail",
            "dnf update -y",
            "dnf install -y awscli docker",
            "systemctl enable --now docker",
            "mkdir -p /opt/backlog-wheel",
            f"aws ecr get-login-password --region {self.region} | docker login --username AWS --password-stdin {ecr_registry}",
            f"aws secretsmanager get-secret-value --region {self.region} --secret-id {runtime_secret.secret_name} --query SecretString --output text > /opt/backlog-wheel/runtime-secret.json",
            f"aws secretsmanager get-secret-value --region {self.region} --secret-id {database_credentials.secret_arn} --query SecretString --output text > /opt/backlog-wheel/database-secret.json",
            "cat > /opt/backlog-wheel/write-env.py <<'PY'\n"
            "import json\n"
            "from pathlib import Path\n"
            "runtime = json.loads(Path('/opt/backlog-wheel/runtime-secret.json').read_text())\n"
            "database = json.loads(Path('/opt/backlog-wheel/database-secret.json').read_text())\n"
            "values = {\n"
            f"    'PHX_HOST': '{domain_name}',\n"
            "    'PHX_SERVER': 'true',\n"
            "    'PORT': '4000',\n"
            "    'DATABASE_HOST': 'backlog-wheel-postgres',\n"
            "    'DATABASE_NAME': 'backlog_wheel',\n"
            "    'DATABASE_PORT': '5432',\n"
            "    'DATABASE_SSL': 'false',\n"
            "    'DATABASE_USERNAME': database['username'],\n"
            "    'DATABASE_PASSWORD': database['password'],\n"
            "    'POOL_SIZE': '5',\n"
            "    'SECRET_KEY_BASE': runtime['SECRET_KEY_BASE'],\n"
            "    'DISCORD_CLIENT_ID': runtime.get('DISCORD_CLIENT_ID', ''),\n"
            "    'DISCORD_CLIENT_SECRET': runtime.get('DISCORD_CLIENT_SECRET', ''),\n"
            "    'TWITCH_CLIENT_ID': runtime.get('TWITCH_CLIENT_ID', ''),\n"
            "    'TWITCH_CLIENT_SECRET': runtime.get('TWITCH_CLIENT_SECRET', ''),\n"
            f"    'TWITCH_EVENTSUB_CALLBACK_URL': 'https://{domain_name}/twitch/eventsub',\n"
            "    'SIGNUP_ALLOWED_DISCORD_IDS': '335983615613730819,117000360039546887',\n"
            "}\n"
            "Path('/opt/backlog-wheel/app.env').write_text(''.join(f'{key}={value}\\n' for key, value in values.items()))\n"
            "PY",
            "python3 /opt/backlog-wheel/write-env.py",
            "chmod 600 /opt/backlog-wheel/app.env /opt/backlog-wheel/*-secret.json",
            "docker network create backlog-wheel || true",
            "docker volume create backlog-wheel-postgres",
            "docker volume create backlog-wheel-caddy-data",
            "docker volume create backlog-wheel-caddy-config",
            "DB_USERNAME=$(python3 -c \"import json; print(json.load(open('/opt/backlog-wheel/database-secret.json'))['username'])\")",
            "DB_PASSWORD=$(python3 -c \"import json; print(json.load(open('/opt/backlog-wheel/database-secret.json'))['password'])\")",
            "docker rm -f backlog-wheel-postgres || true",
            "docker run -d --name backlog-wheel-postgres --restart unless-stopped --network backlog-wheel --network-alias postgres -e POSTGRES_USER=\"$DB_USERNAME\" -e POSTGRES_PASSWORD=\"$DB_PASSWORD\" -e POSTGRES_DB=backlog_wheel -v backlog-wheel-postgres:/var/lib/postgresql/data postgres:17-alpine",
            "until docker exec backlog-wheel-postgres pg_isready -U \"$DB_USERNAME\" -d backlog_wheel; do sleep 2; done",
            f"docker pull {image.image_uri}",
            "docker rm -f backlog-wheel-app || true",
            f"docker run -d --name backlog-wheel-app --restart unless-stopped --network backlog-wheel --env-file /opt/backlog-wheel/app.env {image.image_uri}",
            f"cat > /opt/backlog-wheel/Caddyfile <<'CADDY'\n{domain_name} {{\n  encode zstd gzip\n  reverse_proxy backlog-wheel-app:4000\n}}\nCADDY",
            "docker rm -f backlog-wheel-caddy || true",
            "docker run -d --name backlog-wheel-caddy --restart unless-stopped --network backlog-wheel -p 80:80 -p 443:443 -v /opt/backlog-wheel/Caddyfile:/etc/caddy/Caddyfile:ro -v backlog-wheel-caddy-data:/data -v backlog-wheel-caddy-config:/config caddy:2-alpine",
        )

        refresh_env_document = ssm.CfnDocument(
            self,
            "RefreshRuntimeEnvDocument",
            document_type="Command",
            name="BacklogWheelRefreshRuntimeEnv",
            content={
                "schemaVersion": "2.2",
                "description": "Refresh Backlog Wheel runtime env from Secrets Manager",
                "mainSteps": [
                    {
                        "action": "aws:runShellScript",
                        "name": "refreshRuntimeEnv",
                        "inputs": {
                            "runCommand": [
                                "set -euxo pipefail",
                                f"aws secretsmanager get-secret-value --region {self.region} --secret-id {runtime_secret.secret_name} --query SecretString --output text > /opt/backlog-wheel/runtime-secret.json",
                                f"aws secretsmanager get-secret-value --region {self.region} --secret-id {database_credentials.secret_arn} --query SecretString --output text > /opt/backlog-wheel/database-secret.json",
                                "cat > /opt/backlog-wheel/write-env.py <<'PY'\n"
                                "import json\n"
                                "from pathlib import Path\n"
                                "runtime = json.loads(Path('/opt/backlog-wheel/runtime-secret.json').read_text())\n"
                                "database = json.loads(Path('/opt/backlog-wheel/database-secret.json').read_text())\n"
                                "values = {\n"
                                f"    'PHX_HOST': '{domain_name}',\n"
                                "    'PHX_SERVER': 'true',\n"
                                "    'PORT': '4000',\n"
                                "    'DATABASE_HOST': 'backlog-wheel-postgres',\n"
                                "    'DATABASE_NAME': 'backlog_wheel',\n"
                                "    'DATABASE_PORT': '5432',\n"
                                "    'DATABASE_SSL': 'false',\n"
                                "    'DATABASE_USERNAME': database['username'],\n"
                                "    'DATABASE_PASSWORD': database['password'],\n"
                                "    'POOL_SIZE': '5',\n"
                                "    'SECRET_KEY_BASE': runtime['SECRET_KEY_BASE'],\n"
                                "    'DISCORD_CLIENT_ID': runtime.get('DISCORD_CLIENT_ID', ''),\n"
                                "    'DISCORD_CLIENT_SECRET': runtime.get('DISCORD_CLIENT_SECRET', ''),\n"
                                "    'TWITCH_CLIENT_ID': runtime.get('TWITCH_CLIENT_ID', ''),\n"
                                "    'TWITCH_CLIENT_SECRET': runtime.get('TWITCH_CLIENT_SECRET', ''),\n"
                                f"    'TWITCH_EVENTSUB_CALLBACK_URL': 'https://{domain_name}/twitch/eventsub',\n"
                                "    'SIGNUP_ALLOWED_DISCORD_IDS': '335983615613730819,117000360039546887',\n"
                                "}\n"
                                "Path('/opt/backlog-wheel/app.env').write_text(''.join(f'{key}={value}\\n' for key, value in values.items()))\n"
                                "PY",
                                "python3 /opt/backlog-wheel/write-env.py",
                                "chmod 600 /opt/backlog-wheel/app.env /opt/backlog-wheel/*-secret.json",
                                "APP_IMAGE=$(docker inspect backlog-wheel-app | python3 -c 'import json, sys; print(json.load(sys.stdin)[0][\"Config\"][\"Image\"])')",
                                "docker rm -f backlog-wheel-app",
                                "docker run -d --name backlog-wheel-app --restart unless-stopped --network backlog-wheel --env-file /opt/backlog-wheel/app.env \"$APP_IMAGE\"",
                                "docker restart backlog-wheel-caddy || true",
                            ]
                        },
                    }
                ],
            },
        )

        deploy_app_document = ssm.CfnDocument(
            self,
            "DeployAppDocument",
            document_type="Command",
            name="BacklogWheelDeployApp",
            content={
                "schemaVersion": "2.2",
                "description": "Pull and restart Backlog Wheel app container",
                "parameters": {
                    "AppImageUri": {
                        "type": "String",
                        "description": "Docker image URI to run for the app container",
                    }
                },
                "mainSteps": [
                    {
                        "action": "aws:runShellScript",
                        "name": "deployApp",
                        "inputs": {
                            "runCommand": [
                                "set -euxo pipefail",
                                "for i in {1..60}; do test -f /opt/backlog-wheel/app.env && docker network inspect backlog-wheel >/dev/null 2>&1 && break; sleep 5; done",
                                "test -f /opt/backlog-wheel/app.env",
                                "docker network inspect backlog-wheel >/dev/null",
                                f"aws ecr get-login-password --region {self.region} | docker login --username AWS --password-stdin {ecr_registry}",
                                "docker pull {{ AppImageUri }}",
                                "docker rm -f backlog-wheel-app || true",
                                "docker run -d --name backlog-wheel-app --restart unless-stopped --network backlog-wheel --env-file /opt/backlog-wheel/app.env {{ AppImageUri }}",
                                "docker restart backlog-wheel-caddy || true",
                            ]
                        },
                    }
                ],
            },
        )

        deploy_app_association = ssm.CfnAssociation(
            self,
            "DeployAppAssociation",
            name=deploy_app_document.name,
            targets=[
                ssm.CfnAssociation.TargetProperty(
                    key="InstanceIds",
                    values=[instance.instance_id],
                )
            ],
            parameters={"AppImageUri": [image.image_uri]},
        )
        deploy_app_association.add_dependency(deploy_app_document)

        if manage_dns:
            hosted_zone = route53.HostedZone.from_lookup(
                self,
                "HostedZone",
                domain_name=hosted_zone_domain,
            )

            route53.ARecord(
                self,
                "DomainRecord",
                zone=hosted_zone,
                record_name=record_name,
                target=route53.RecordTarget.from_ip_addresses(elastic_ip.ref),
            )

        cdk.CfnOutput(self, "InstanceId", value=instance.instance_id)
        cdk.CfnOutput(self, "InstancePublicIp", value=elastic_ip.ref)
        cdk.CfnOutput(self, "Url", value=f"https://{domain_name}")
        cdk.CfnOutput(self, "DatabaseSecretName", value=database_credentials.secret_name)
        cdk.CfnOutput(self, "RefreshEnvDocument", value=refresh_env_document.name)
        cdk.CfnOutput(self, "DeployAppDocumentName", value=deploy_app_document.name)
