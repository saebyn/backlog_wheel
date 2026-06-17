# Backlog Wheel

<img width="1231" height="1274" alt="image" src="https://github.com/user-attachments/assets/979b393d-30c7-4592-9215-701934dafdd1" />



## Development

Backlog Wheel is a small Phoenix LiveView app for choosing what game to play from a personal backlog. The first version is a local stream tool: maintain a backlog, mark games as eligible for the wheel, spin a wheel, and record the result.

I'm developing this project on NixOS with `nix-direnv`.

Copy example.envrc to .envrc and edit it as needed:

```sh
cp example.envrc .envrc
```

To enter the development environment:

```sh
direnv allow
```

If the shell is already allowed, entering the project directory should load the environment automatically.

If you aren't on NixOS, you may wish to follow the instructions at https://phoenix.hexdocs.pm/installation.html to get your environment set up.

The app expects PostgreSQL for development and tests. The default local database credentials are:

```text
user: postgres
password: postgres
host: localhost
database: backlog_wheel_dev
```

## Setup

Install dependencies, create the PostgreSQL database, run migrations, and build assets:

```sh
mix setup
```

Install the pre-commit hooks:

```sh
pre-commit install
```

Run the secret scanner manually:

```sh
pre-commit run gitleaks --all-files
```

Run migrations after pulling new schema changes:

```sh
mix ecto.migrate
```

## Running Locally

Start the Phoenix server:

```sh
mix phx.server
```

Or run it inside IEx:

```sh
iex -S mix phx.server
```

Visit <http://localhost:4000> in your browser. The games CRUD page is available at <http://localhost:4000/games>, the wheel page is available at <http://localhost:4000/wheel>, and spin history is available at <http://localhost:4000/history>.

## Steam Import

Steam library import uses the official Steam Web API. Visit <http://localhost:4000/games/import/steam>, save the community's Steam API key and Steam ID64, then click `Import Steam Library`.

Import behavior:

- New Steam games use `platform: "steam"` and the Steam app id as `external_id`.
- Imported Steam games are included on the wheel by default.
- `last_played_at` is set only when Steam returns the optional `rtime_last_played` field.
- Re-imports refresh `last_played_at` when Steam returns `rtime_last_played`.
- Existing Steam games are skipped so local edits are preserved.

## Discord Login

Discord login protects streamer/admin management pages. New Discord users can only complete sign-up when their Discord user ID is included in the sign-up allowlist.

Add these values to `.envrc`, then run `direnv allow`:

```sh
export DISCORD_CLIENT_ID="your-discord-client-id"
export DISCORD_CLIENT_SECRET="your-discord-client-secret"
export SIGNUP_ALLOWED_DISCORD_IDS="123456789012345678,234567890123456789"
```

`SIGNUP_ALLOWED_DISCORD_IDS` is a comma-separated list of Discord user IDs. Allowlisted users can create their initial community and owner membership after Discord login. Users not on the allowlist see an access-not-enabled page and cannot create communities or memberships.

When registering a local development app in the Discord Developer Portal, use this OAuth redirect URL:

```text
http://localhost:4000/auth/discord/callback
```

Required OAuth scope:

```text
identify
```

No bot permissions, `email`, or `guilds` scope are required.

## Twitch Configuration

Twitch integration supports OAuth authorization, temporary channel point reward creation for voting sessions, and EventSub redemption ingestion.

Add these values to `.envrc`, then run `direnv allow`:

```sh
export TWITCH_CLIENT_ID="your-twitch-client-id"
export TWITCH_CLIENT_SECRET="your-twitch-client-secret"
```

When registering a local development app at <https://dev.twitch.tv/console/apps/create>, use this OAuth redirect URL:

```text
http://localhost:4000/twitch/oauth/callback
```

Twitch allows HTTP redirect URLs for `localhost`. After setting the env vars, visit the Twitch page, save the community broadcaster ID, reward cost, and EventSub secret, then click `Connect Twitch` to authorize the app.

Behavior today:

- `TWITCH_CLIENT_ID` identifies the Twitch application/client.
- `TWITCH_CLIENT_SECRET` is used by the local OAuth callback to exchange authorization codes.
- Twitch broadcaster ID, reward cost, and EventSub secret are saved per community in Settings > Twitch.
- If required config is missing, `BacklogWheel.Twitch.config/1` returns `{:error, {:missing_config, keys}}` and `BacklogWheel.Twitch.configured?/1` returns `false`.
- Starting Twitch voting creates one positive channel point vote reward per game in the voting session.
- EventSub signature verification uses the secret saved for the event's broadcaster community.

## Terminology

Current code should use product language like voting sessions, wheel candidates, votes, and channel point votes. Prefer `ChannelPointVote`, `record_vote/2`, `record_vote/3`, and `channel_point_vote_total` in new code.

## Tests

Run the test suite:

```sh
mix test
```

Run the project precommit alias:

```sh
mix precommit
```

## Prototype Deployment

See [infra/README.md](infra/README.md) for Docker image and AWS CDK deployment details.

## License

This project is licensed under the GNU Affero General Public License v3.0. See [LICENSE](LICENSE) for details.
