import json

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    RemovalPolicy,
    Stack,
    aws_certificatemanager as acm,
    aws_ec2 as ec2,
    aws_ecs as ecs,
    aws_efs as efs,
    aws_elasticloadbalancingv2 as elbv2,
    aws_ecr_assets as ecr_assets,
    aws_iam as iam,
    aws_logs as logs,
    aws_route53 as route53,
    aws_route53_targets as targets,
    aws_secretsmanager as secretsmanager,
)
from constructs import Construct


class BacklogWheelStack(Stack):
    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        domain_name = self.node.try_get_context("domainName") or "wheel.streamosaic.app"
        hosted_zone_domain = self.node.try_get_context("hostedZoneDomain") or "streamosaic.app"
        record_name = domain_name.removesuffix(f".{hosted_zone_domain}")

        vpc = ec2.Vpc.from_lookup(
            self,
            "Vpc",
            is_default=True,
        )

        cluster = ecs.Cluster(self, "Cluster", vpc=vpc)

        file_system = efs.FileSystem(
            self,
            "DataFileSystem",
            vpc=vpc,
            encrypted=True,
            removal_policy=RemovalPolicy.RETAIN,
        )

        access_point = file_system.add_access_point(
            "AppDataAccessPoint",
            path="/backlog-wheel",
            create_acl=efs.Acl(owner_gid="1000", owner_uid="1000", permissions="750"),
            posix_user=efs.PosixUser(gid="1000", uid="1000"),
        )

        runtime_secret = secretsmanager.Secret(
            self,
            "RuntimeSecret",
            secret_name="backlog-wheel/prototype/runtime",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template=json.dumps(
                    {
                        "DISCORD_CLIENT_ID": "",
                        "DISCORD_CLIENT_SECRET": "",
                        "STEAM_API_KEY": "",
                        "STEAM_ID64": "",
                        "TWITCH_CLIENT_ID": "",
                        "TWITCH_CLIENT_SECRET": "",
                        "TWITCH_BROADCASTER_ID": "",
                        "TWITCH_REWARD_COST": "100",
                        "TWITCH_EVENTSUB_SECRET": "",
                    }
                ),
                generate_string_key="SECRET_KEY_BASE",
                exclude_punctuation=True,
                password_length=64,
            ),
        )

        image = ecr_assets.DockerImageAsset(
            self,
            "Image",
            directory=".",
            platform=ecr_assets.Platform.LINUX_AMD64,
        )

        task_definition = ecs.FargateTaskDefinition(
            self,
            "TaskDefinition",
            cpu=512,
            memory_limit_mib=1024,
        )

        task_definition.add_volume(
            name="data",
            efs_volume_configuration=ecs.EfsVolumeConfiguration(
                file_system_id=file_system.file_system_id,
                transit_encryption="ENABLED",
                authorization_config=ecs.AuthorizationConfig(
                    access_point_id=access_point.access_point_id,
                    iam="ENABLED",
                ),
            ),
        )

        container = task_definition.add_container(
            "App",
            image=ecs.ContainerImage.from_docker_image_asset(image),
            logging=ecs.LogDrivers.aws_logs(
                stream_prefix="backlog-wheel",
                log_retention=logs.RetentionDays.ONE_MONTH,
            ),
            environment={
                "DATABASE_PATH": "/data/backlog_wheel.db",
                "PHX_HOST": domain_name,
                "PHX_SERVER": "true",
                "PORT": "4000",
                "TWITCH_EVENTSUB_CALLBACK_URL": f"https://{domain_name}/twitch/eventsub",
            },
            secrets={
                key: ecs.Secret.from_secrets_manager(runtime_secret, key)
                for key in [
                    "SECRET_KEY_BASE",
                    "DISCORD_CLIENT_ID",
                    "DISCORD_CLIENT_SECRET",
                    "STEAM_API_KEY",
                    "STEAM_ID64",
                    "TWITCH_CLIENT_ID",
                    "TWITCH_CLIENT_SECRET",
                    "TWITCH_BROADCASTER_ID",
                    "TWITCH_REWARD_COST",
                    "TWITCH_EVENTSUB_SECRET",
                ]
            },
        )
        container.add_port_mappings(ecs.PortMapping(container_port=4000))
        container.add_mount_points(
            ecs.MountPoint(
                container_path="/data",
                source_volume="data",
                read_only=False,
            )
        )

        task_definition.add_to_task_role_policy(
            iam.PolicyStatement(
                actions=[
                    "elasticfilesystem:ClientMount",
                    "elasticfilesystem:ClientRootAccess",
                    "elasticfilesystem:ClientWrite",
                ],
                resources=[file_system.file_system_arn],
            )
        )

        service_security_group = ec2.SecurityGroup(self, "ServiceSecurityGroup", vpc=vpc)
        file_system.connections.allow_default_port_from(service_security_group)

        service = ecs.FargateService(
            self,
            "Service",
            cluster=cluster,
            task_definition=task_definition,
            desired_count=1,
            assign_public_ip=True,
            security_groups=[service_security_group],
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),
            enable_execute_command=True,
        )

        hosted_zone = route53.HostedZone.from_lookup(
            self,
            "HostedZone",
            domain_name=hosted_zone_domain,
        )
        certificate = acm.Certificate(
            self,
            "Certificate",
            domain_name=domain_name,
            validation=acm.CertificateValidation.from_dns(hosted_zone),
        )

        load_balancer = elbv2.ApplicationLoadBalancer(
            self,
            "LoadBalancer",
            vpc=vpc,
            internet_facing=True,
        )

        http_listener = load_balancer.add_listener("Http", port=80, open=True)
        http_listener.add_action(
            "RedirectToHttps",
            action=elbv2.ListenerAction.redirect(protocol="HTTPS", port="443"),
        )

        https_listener = load_balancer.add_listener(
            "Https",
            port=443,
            certificates=[certificate],
            open=True,
        )
        https_listener.add_targets(
            "AppTarget",
            port=4000,
            protocol=elbv2.ApplicationProtocol.HTTP,
            targets=[service],
            health_check=elbv2.HealthCheck(
                path="/",
                healthy_http_codes="200,302",
                interval=Duration.seconds(30),
            ),
        )

        route53.ARecord(
            self,
            "DomainAlias",
            zone=hosted_zone,
            record_name=record_name,
            target=route53.RecordTarget.from_alias(targets.LoadBalancerTarget(load_balancer)),
        )

        cdk.CfnOutput(self, "Url", value=f"https://{domain_name}")
        cdk.CfnOutput(self, "RuntimeSecretName", value=runtime_secret.secret_name)
