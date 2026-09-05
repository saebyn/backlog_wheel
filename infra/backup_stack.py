from aws_cdk import CfnOutput, RemovalPolicy, Stack, aws_iam as iam, aws_s3 as s3
from constructs import Construct


class BacklogWheelBackupStack(Stack):
    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.database_backup_bucket = s3.Bucket(
            self,
            "DatabaseBackupBucket",
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            enforce_ssl=True,
            versioned=True,
        )
        self.database_backup_bucket.apply_removal_policy(RemovalPolicy.RETAIN)

        if ec2_instance_role_arn := self.node.try_get_context("ec2InstanceRoleArn"):
            current_instance_role = iam.Role.from_role_arn(
                self,
                "CurrentInstanceRole",
                ec2_instance_role_arn,
                mutable=True,
            )
            self.database_backup_bucket.grant_read_write(current_instance_role)

        CfnOutput(
            self,
            "DatabaseBackupBucketName",
            value=self.database_backup_bucket.bucket_name,
        )
