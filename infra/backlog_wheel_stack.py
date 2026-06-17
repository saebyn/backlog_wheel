import json

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    RemovalPolicy,
    Stack,
    aws_certificatemanager as acm,
    aws_ec2 as ec2,
    aws_ecs as ecs,
    aws_elasticloadbalancingv2 as elbv2,
    aws_ecr_assets as ecr_assets,
    aws_logs as logs,
    aws_rds as rds,
    aws_route53 as route53,
    aws_route53_targets as targets,
    aws_secretsmanager as secretsmanager,
)
from constructs import Construct


class BacklogWheelStatefulStack(Stack):
    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.vpc = ec2.Vpc.from_lookup(
            self,
            "Vpc",
            is_default=True,
        )

        self.database_credentials = secretsmanager.Secret(
            self,
            "DatabaseCredentials",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template=json.dumps({"username": "backlog_wheel"}),
                generate_string_key="password",
                exclude_punctuation=True,
                password_length=30,
            ),
        )
        self.database_credentials.apply_removal_policy(RemovalPolicy.RETAIN)

        self.database = rds.DatabaseCluster(
            self,
            "Database",
            engine=rds.DatabaseClusterEngine.aurora_postgres(
                version=rds.AuroraPostgresEngineVersion.VER_16_4
            ),
            writer=rds.ClusterInstance.serverless_v2(
                "writer",
                publicly_accessible=False,
            ),
            serverless_v2_min_capacity=0.5,
            serverless_v2_max_capacity=2,
            credentials=rds.Credentials.from_secret(
                self.database_credentials,
                username="backlog_wheel",
            ),
            default_database_name="backlog_wheel",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),
            backup=rds.BackupProps(retention=Duration.days(7)),
            deletion_protection=True,
            removal_policy=RemovalPolicy.RETAIN,
        )
        self.database_security_group = self.database.connections.security_groups[0]

        self.runtime_secret = secretsmanager.Secret.from_secret_name_v2(
            self,
            "RuntimeSecret",
            "backlog-wheel/prototype/runtime",
        )

        cdk.CfnOutput(self, "RuntimeSecretName", value=self.runtime_secret.secret_name)
        cdk.CfnOutput(
            self, "DatabaseSecretName", value=self.database_credentials.secret_name
        )


class BacklogWheelServiceStack(Stack):
    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        stateful_stack: BacklogWheelStatefulStack,
        **kwargs,
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        domain_name = self.node.try_get_context("domainName") or "wheel.streamosaic.app"
        hosted_zone_domain = self.node.try_get_context("hostedZoneDomain") or "streamosaic.app"
        record_name = domain_name.removesuffix(f".{hosted_zone_domain}")

        cluster = ecs.Cluster(self, "Cluster", vpc=stateful_stack.vpc)

        service_security_group = ec2.SecurityGroup(
            self,
            "ServiceSecurityGroup",
            vpc=stateful_stack.vpc,
        )

        ec2.CfnSecurityGroupIngress(
            self,
            "DatabaseIngressFromService",
            group_id=stateful_stack.database_security_group.security_group_id,
            ip_protocol="tcp",
            from_port=5432,
            to_port=5432,
            source_security_group_id=service_security_group.security_group_id,
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

        container = task_definition.add_container(
            "App",
            image=ecs.ContainerImage.from_docker_image_asset(image),
            logging=ecs.LogDrivers.aws_logs(
                stream_prefix="backlog-wheel",
                log_retention=logs.RetentionDays.ONE_MONTH,
            ),
            environment={
                "DATABASE_HOST": stateful_stack.database.cluster_endpoint.hostname,
                "DATABASE_NAME": "backlog_wheel",
                "DATABASE_PORT": "5432",
                "DATABASE_SSL": "true",
                "PHX_HOST": domain_name,
                "PHX_SERVER": "true",
                "PORT": "4000",
                "SIGNUP_ALLOWED_DISCORD_IDS": "335983615613730819,117000360039546887",
                "TWITCH_EVENTSUB_CALLBACK_URL": f"https://{domain_name}/twitch/eventsub",
            },
            secrets={
                key: ecs.Secret.from_secrets_manager(stateful_stack.runtime_secret, key)
                for key in [
                    "SECRET_KEY_BASE",
                    "DISCORD_CLIENT_ID",
                    "DISCORD_CLIENT_SECRET",
                    "TWITCH_CLIENT_ID",
                    "TWITCH_CLIENT_SECRET",
                ]
            }
            | {
                "DATABASE_USERNAME": ecs.Secret.from_secrets_manager(
                    stateful_stack.database_credentials,
                    "username",
                ),
                "DATABASE_PASSWORD": ecs.Secret.from_secrets_manager(
                    stateful_stack.database_credentials,
                    "password",
                ),
            },
        )
        container.add_port_mappings(ecs.PortMapping(container_port=4000))

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
            vpc=stateful_stack.vpc,
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
                path="/health",
                healthy_http_codes="200",
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
