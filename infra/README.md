# Backlog Wheel Infrastructure

The repository includes a production Docker image and AWS CDK Python stack for a small private deployment at `https://wheel.streamosaic.app`.

The stack creates:

- An ECS Fargate service running one Phoenix release container.
- An EFS file system mounted at `/data` for the production SQLite database.
- It uses the account's default VPC rather than creating a project-specific VPC.
- An internet-facing Application Load Balancer with HTTP to HTTPS redirect.
- An ACM certificate and Route 53 `A` record for `wheel.streamosaic.app`.
- A Secrets Manager secret named `backlog-wheel/prototype/runtime` for Phoenix and integration secrets.

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

Deploy the stack from the repository root:

```sh
AWS_PROFILE=your-profile cdk deploy
```

The first deploy creates `backlog-wheel/prototype/runtime` with a generated `SECRET_KEY_BASE` and blank optional integration values. Update that secret in AWS Secrets Manager when Steam or Twitch integration should be enabled. Keep the JSON keys in place:

```json
{
  "SECRET_KEY_BASE": "generated-by-secrets-manager",
  "STEAM_API_KEY": "",
  "STEAM_ID64": "",
  "TWITCH_CLIENT_ID": "",
  "TWITCH_CLIENT_SECRET": "",
  "TWITCH_BROADCASTER_ID": "",
  "TWITCH_REWARD_COST": "100",
  "TWITCH_EVENTSUB_SECRET": ""
}
```

The container also sets these non-secret runtime values:

- `DATABASE_PATH=/data/backlog_wheel.db`
- `PHX_HOST=wheel.streamosaic.app`
- `PHX_SERVER=true`
- `PORT=4000`
- `TWITCH_EVENTSUB_CALLBACK_URL=https://wheel.streamosaic.app/twitch/eventsub`

SQLite migrations run automatically when the Phoenix release starts. EFS is retained if the stack is destroyed so the prototype database is not accidentally deleted.

## Docker

To build the production image without deploying:

```sh
docker build -t backlog-wheel:prod .
```
