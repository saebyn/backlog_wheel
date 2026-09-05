# Backlog Wheel Infrastructure

The repository includes a production Docker image and AWS CDK Python app for the small EC2 deployment at `https://wheel.streamosaic.app`.

The CDK app creates `BacklogWheelBackupStack`, which owns:

- A retained, versioned S3 bucket for database backups.

The CDK app also creates `BacklogWheelEc2Stack`, which owns:

- A small EC2 instance.
- An Elastic IP and Route 53 `A` record for `wheel.streamosaic.app`.
- A security group allowing HTTP and HTTPS.
- An IAM role with SSM Session Manager, ECR pull, and Secrets Manager read access.
- A generated local Postgres credentials secret with a retain policy.
- A production Docker image asset published through the CDK bootstrap ECR repository.

The instance runs Docker containers for Phoenix, Postgres, and Caddy. Caddy terminates HTTPS directly on the instance. Postgres data lives on the instance's Docker volume. On first boot, the instance starts Postgres and restores the latest retained S3 backup before starting Phoenix if the database has no public tables. App deploys upload a `pg_dump -Fc` backup to the retained backup bucket before replacing the app container. Backups also run hourly through a systemd timer and during graceful instance shutdown through a systemd service stop hook.

## Prerequisites

- AWS credentials for the target account.
- A default VPC in the target account and region.
- The `streamosaic.app` Route 53 hosted zone in the target account.
- Docker running locally for the CDK Docker image asset build.
- AWS CDK v2 available, for example with `npm install -g aws-cdk`.

## Setup

Install the CDK Python dependencies from the repository root:

```sh
python3 -m venv infra/.venv
infra/.venv/bin/pip install -r infra/requirements.txt
```

Bootstrap the account and region once:

```sh
cdk bootstrap aws://159222827421/us-west-2
```

The default account and region are set in `cdk.json` as `159222827421` and `us-west-2`.

Create the runtime secret before the first deploy. CDK imports this secret by name and must not manage its value:

```sh
aws secretsmanager create-secret \
  --name backlog-wheel/prototype/runtime \
  --secret-string '{"SECRET_KEY_BASE":"replace-with-mix-phx-gen-secret","DISCORD_CLIENT_ID":"","DISCORD_CLIENT_SECRET":"","TWITCH_CLIENT_ID":"","TWITCH_CLIENT_SECRET":""}'
```

If the secret already exists, update it only through Secrets Manager or the AWS CLI.

## Deploy

Deploy from the repository root:

Deploy the backup bucket first. This does not touch the EC2 instance:

```sh
AWS_PROFILE=your-profile cdk deploy BacklogWheelBackupStack
```

To immediately upload manual backups from the current instance before deploying the EC2 stack changes, deploy the backup stack with the current instance role ARN:

```sh
INSTANCE_ID=your-instance-id
PROFILE=your-profile
INSTANCE_PROFILE_ARN=$(AWS_PROFILE="$PROFILE" aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
  --output text)
INSTANCE_PROFILE_NAME=${INSTANCE_PROFILE_ARN##*/}
ROLE_NAME=$(AWS_PROFILE="$PROFILE" aws iam get-instance-profile \
  --instance-profile-name "$INSTANCE_PROFILE_NAME" \
  --query 'InstanceProfile.Roles[0].RoleName' \
  --output text)
ROLE_ARN=$(AWS_PROFILE="$PROFILE" aws iam get-role \
  --role-name "$ROLE_NAME" \
  --query 'Role.Arn' \
  --output text)
AWS_PROFILE="$PROFILE" cdk deploy BacklogWheelBackupStack \
  --context ec2InstanceRoleArn="$ROLE_ARN"
```

Then deploy the EC2 stack only after `cdk diff BacklogWheelEc2Stack` confirms the instance will not be replaced:

```sh
AWS_PROFILE=your-profile cdk deploy BacklogWheelEc2Stack
```

The stack uses `t3a.micro` by default. Override it with context if needed:

```sh
AWS_PROFILE=your-profile cdk deploy BacklogWheelEc2Stack \
  --context ec2InstanceType=t3a.nano
```

The stack enables SSM Session Manager for shell access. It does not open SSH by default. To allow SSH from a specific CIDR, pass `ec2SshCidr`:

```sh
AWS_PROFILE=your-profile cdk deploy BacklogWheelEc2Stack \
  --context ec2SshCidr=203.0.113.10/32
```

Each deploy publishes a new Docker image asset when application files change. The stack also updates a managed SSM association with that image URI, causing the EC2 instance to pull the image and recreate the `backlog-wheel-app` container automatically.

## Runtime Configuration

The runtime secret must contain these JSON keys. Update this secret in AWS Secrets Manager when Discord or Twitch integration should be enabled:

```json
{
  "SECRET_KEY_BASE": "generated-by-secrets-manager",
  "DISCORD_CLIENT_ID": "",
  "DISCORD_CLIENT_SECRET": "",
  "TWITCH_CLIENT_ID": "",
  "TWITCH_CLIENT_SECRET": ""
}
```

The app container also sets these non-secret runtime values:

- `DATABASE_HOST=backlog-wheel-postgres`
- `DATABASE_NAME=backlog_wheel`
- `DATABASE_PORT=5432`
- `DATABASE_SSL=false`
- `PHX_HOST=wheel.streamosaic.app`
- `PHX_SERVER=true`
- `PORT=4000`
- `SIGNUP_ALLOWED_DISCORD_IDS=335983615613730819,117000360039546887`
- `TWITCH_EVENTSUB_CALLBACK_URL=https://wheel.streamosaic.app/twitch/eventsub`

The Phoenix release runs migrations automatically on startup.

On new EC2 instance bootstrap, the stack starts Postgres and runs `/usr/local/bin/backlog-wheel-restore-latest-db` before starting Phoenix. The restore script skips restore when the database already has public tables, restores the newest `database/*.dump` object from the backup bucket when the database is empty, and continues with an empty database only when no backup exists.

The host backup/restore scripts live in `infra/scripts/`, and their systemd units live in `infra/systemd/`. CDK reads these files at synth time and writes them onto the EC2 host through user data and the app deploy SSM document.

## Updating Environment Variables

Runtime secrets live in Secrets Manager under `backlog-wheel/prototype/runtime`. Update that secret first, then run the CDK-managed SSM document to refresh the instance env file and recreate the app container.

```sh
AWS_PROFILE=your-profile aws secretsmanager update-secret \
  --secret-id backlog-wheel/prototype/runtime \
  --secret-string '{"SECRET_KEY_BASE":"existing-secret-key-base","DISCORD_CLIENT_ID":"","DISCORD_CLIENT_SECRET":"","TWITCH_CLIENT_ID":"","TWITCH_CLIENT_SECRET":""}'
```

Run the refresh command:

```sh
AWS_PROFILE=your-profile aws ssm send-command \
  --document-name BacklogWheelRefreshRuntimeEnv \
  --instance-ids INSTANCE_ID
```

Get `INSTANCE_ID` from the `BacklogWheelEc2Stack` outputs or EC2 console. The command rewrites `/opt/backlog-wheel/app.env`, recreates `backlog-wheel-app` with the current app image, and restarts Caddy.

## Operations

Use SSM Session Manager for access:

```sh
AWS_PROFILE=your-profile aws ssm start-session --target INSTANCE_ID
```

Useful instance commands:

```sh
sudo docker logs -f backlog-wheel-app
sudo docker logs -f backlog-wheel-caddy
sudo docker logs -f backlog-wheel-postgres
```

Create a database backup from the instance and upload it to the retained backup bucket:

```sh
sudo /usr/local/bin/backlog-wheel-backup-db
```

Inspect the scheduled backup timer and shutdown backup hook:

```sh
sudo systemctl status backlog-wheel-backup.timer
sudo systemctl list-timers backlog-wheel-backup.timer
sudo systemctl status backlog-wheel-backup-on-shutdown.service
```

Run the same scheduled backup unit manually:

```sh
sudo systemctl start backlog-wheel-backup.service
```

Run the bootstrap restore command manually. It will skip restore unless the database has no public tables:

```sh
sudo /usr/local/bin/backlog-wheel-restore-latest-db
```

After the backup bucket and SSM deploy document are in place, disable root volume deletion for the current EC2 instance without replacing it:

```sh
AWS_PROFILE=your-profile aws ec2 modify-instance-attribute \
  --instance-id INSTANCE_ID \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"DeleteOnTermination":false}}]'
```

Create a local SQL database backup from the instance:

```sh
DB_USERNAME=$(sudo python3 -c "import json; print(json.load(open('/opt/backlog-wheel/database-secret.json'))['username'])")
sudo docker exec backlog-wheel-postgres pg_dump -U "$DB_USERNAME" -d backlog_wheel > "backlog_wheel-$(date +%Y%m%d%H%M%S).sql"
```

List retained backup files:

```sh
AWS_PROFILE=your-profile aws s3 ls s3://BACKUP_BUCKET_NAME/database/
```

Use the `DatabaseBackupBucketName` stack output for `BACKUP_BUCKET_NAME`.

Restore a compressed backup on the instance:

```sh
AWS_PROFILE=your-profile aws s3 cp s3://BACKUP_BUCKET_NAME/database/BACKUP_FILE.dump ./BACKUP_FILE.dump
DB_USERNAME=$(sudo python3 -c "import json; print(json.load(open('/opt/backlog-wheel/database-secret.json'))['username'])")
sudo docker cp ./BACKUP_FILE.dump backlog-wheel-postgres:/tmp/restore.dump
sudo docker exec backlog-wheel-postgres pg_restore -U "$DB_USERNAME" -d backlog_wheel --clean --if-exists /tmp/restore.dump
```

For app updates after the initial EC2 provision, run `cdk deploy BacklogWheelEc2Stack`. The CDK-managed `BacklogWheelDeployApp` SSM association pulls the new image and recreates the app container.

## Docker

To build the production image without deploying:

```sh
docker build -t backlog-wheel:prod .
```
