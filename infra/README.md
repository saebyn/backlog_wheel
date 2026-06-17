# Backlog Wheel Infrastructure

The repository includes a production Docker image and AWS CDK Python app for a small private deployment at `https://wheel.streamosaic.app`.

The CDK app creates two stacks:

- `BacklogWheelStatefulStack` owns stateful resources: Aurora PostgreSQL, database credentials, and runtime integration secrets.
- `BacklogWheelServiceStack` owns replaceable service resources: ECS cluster, task definition, Fargate service, service security group, load balancer, certificate, and Route 53 record.

Together they create:

- An ECS Fargate service running one Phoenix release container.
- An Aurora Serverless v2 PostgreSQL database.
- It uses the account's default VPC rather than creating a project-specific VPC.
- An internet-facing Application Load Balancer with HTTP to HTTPS redirect.
- An ACM certificate and Route 53 `A` record for `wheel.streamosaic.app`.
- A Secrets Manager secret named `backlog-wheel/prototype/runtime` for Phoenix and integration secrets.
- A generated RDS credentials secret for the application database user.

Docker image assets are still published through the CDK bootstrap ECR repository during `cdk deploy`. A dedicated application ECR repository would require a separate build/push/tag deployment flow.

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
Override them for one-off deploys with CDK context values:

```sh
cdk deploy --context account=123456789012 --context region=us-east-1
```

## Deploy

Deploy both stacks from the repository root:

```sh
AWS_PROFILE=your-profile cdk deploy
```

To deploy only the service after stateful resources exist:

```sh
AWS_PROFILE=your-profile cdk deploy BacklogWheelServiceStack
```

The first deploy creates `backlog-wheel/prototype/runtime` with a generated `SECRET_KEY_BASE` and blank optional integration values. Update that secret in AWS Secrets Manager when Discord or Twitch integration should be enabled. Keep the JSON keys in place:

```json
{
  "SECRET_KEY_BASE": "generated-by-secrets-manager",
  "DISCORD_CLIENT_ID": "",
  "DISCORD_CLIENT_SECRET": "",
  "TWITCH_CLIENT_ID": "",
  "TWITCH_CLIENT_SECRET": "",
  "TWITCH_BROADCASTER_ID": "",
  "TWITCH_REWARD_COST": "100",
  "TWITCH_EVENTSUB_SECRET": ""
}
```

The container also sets these non-secret runtime values:

- `DATABASE_HOST=<aurora-cluster-endpoint>`
- `DATABASE_NAME=backlog_wheel`
- `DATABASE_PORT=5432`
- `DATABASE_SSL=true`
- `PHX_HOST=wheel.streamosaic.app`
- `PHX_SERVER=true`
- `PORT=4000`
- `SIGNUP_ALLOWED_DISCORD_IDS=117000360039546887`
- `TWITCH_EVENTSUB_CALLBACK_URL=https://wheel.streamosaic.app/twitch/eventsub`

The database username and password are injected from the generated RDS credentials secret. Database migrations run automatically when the Phoenix release starts. The Aurora cluster is configured with deletion protection and a `RETAIN` removal policy so application data is not accidentally deleted with the stack.

## Docker

To build the production image without deploying:

```sh
docker build -t backlog-wheel:prod .
```
