# Backlog Wheel Infrastructure

The repository includes a production Docker image and AWS CDK Python app for the small EC2 deployment at `https://wheel.streamosaic.app`.

The CDK app creates `BacklogWheelEc2Stack`, which owns:

- A small EC2 instance.
- An Elastic IP and Route 53 `A` record for `wheel.streamosaic.app`.
- A security group allowing HTTP and HTTPS.
- An IAM role with SSM Session Manager, ECR pull, and Secrets Manager read access.
- A generated local Postgres credentials secret with a retain policy.
- A production Docker image asset published through the CDK bootstrap ECR repository.

The instance runs Docker containers for Phoenix, Postgres, and Caddy. Caddy terminates HTTPS directly on the instance. Postgres data lives on the instance's Docker volume.

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

Create a local database backup from the instance:

```sh
DB_USERNAME=$(sudo python3 -c "import json; print(json.load(open('/opt/backlog-wheel/database-secret.json'))['username'])")
sudo docker exec backlog-wheel-postgres pg_dump -U "$DB_USERNAME" -d backlog_wheel > "backlog_wheel-$(date +%Y%m%d%H%M%S).sql"
```

For app updates after the initial EC2 provision, deploy the new CDK image asset and then recreate the app container on the instance with the new image URI.

## Docker

To build the production image without deploying:

```sh
docker build -t backlog-wheel:prod .
```
