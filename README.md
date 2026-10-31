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

Frontend development and checks require Node.js 24 or newer and npm. The Nix shell
provides Node.js 24; other environments should install it separately. The app
expects PostgreSQL for development and tests. The default local database credentials are:

```text
user: postgres
password: postgres
host: localhost
database: backlog_wheel_dev
```

You can start a matching local Postgres with Docker Compose:

```sh
docker compose up -d postgres
```

This publishes Postgres on `localhost:5432`, so commands run outside Docker such as
`mix test`, `mix ecto.migrate`, and `mix precommit` use the same database defaults.

## Setup

Install Elixir and frontend dependencies, create the PostgreSQL database, run migrations,
and build assets:

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

Or run the Phoenix server and Postgres with Docker Compose:

```sh
docker compose up web
```

The `web` service reads `export ...` lines from `.envrc`, ignores `use nix`, runs pending migrations, and serves <http://localhost:4000>. Named Docker volumes are used for `/app/deps` and `/app/_build` so container dependencies do not overwrite your host checkout.

Or run it inside IEx:

```sh
iex -S mix phx.server
```

Visit <http://localhost:4000> in your browser. The games CRUD page is available at <http://localhost:4000/games>, the wheel page is available at <http://localhost:4000/wheel>, and spin history is available at <http://localhost:4000/history>.

### Local Twitch simulator

To test voting without contacting Twitch or spending channel points, start the opt-in simulator:

```sh
docker compose -f compose.yaml -f compose.simulator.yaml up -d web
```

This runs the app on <http://localhost:4000> using the separate `backlog_wheel_simulator` database and a separate persistent simulator-state volume. The normal `backlog_wheel_dev` database and its Twitch credentials are not used. Sign in with Discord and complete onboarding for the sandbox community, then open <http://localhost:4000/dev/twitch-simulator>.

1. Click **Connect simulated channel** and **Create sample vote**, then open the sample vote.
2. Open voting and start Twitch voting. Return to the simulator page to redeem a game number as a viewer.
3. Try an invalid number to see a simulated cancellation and chat explanation. Check **Delay webhook delivery** to deliver or replay a notification later; reconciliation can also discover delayed redemptions.
4. Use the failure controls and **Run retries now** to exercise recovery. Finished reward deletions appear in simulator history.

The simulator dispatches signed requests through the app's EventSub endpoint and simulates Twitch's reward and redemption API; it does not validate a real Twitch integration. To switch back to the ordinary development database and real Twitch client, run:

```sh
docker compose -f compose.yaml up -d --force-recreate web
```

## Steam Import

Steam library import uses the official Steam Web API. Visit <http://localhost:4000/games/import/steam>, save the community's Steam API key and SteamID64, then click `Import Steam Library`.

You can create or view a Steam Web API key at <https://steamcommunity.com/dev/apikey>. Steam asks for a domain name; for local or personal use, enter the domain where this app runs. Your SteamID64 is available from your Steam profile URL, or by pasting a custom profile URL into <https://steamid.io/>.

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

Twitch allows HTTP redirect URLs for `localhost`. After setting the env vars, visit the Twitch page, set the reward cost, then click `Connect Twitch` to authorize the app. The connected Twitch user's broadcaster ID is detected and saved automatically.

Behavior today:

- `TWITCH_CLIENT_ID` identifies the Twitch application/client.
- `TWITCH_CLIENT_SECRET` is used by the local OAuth callback to exchange authorization codes.
- Twitch broadcaster ID and reward cost are saved per community in Settings > Twitch. Broadcaster ID is detected when Twitch is connected.
- EventSub webhook signing is configured automatically when Twitch is connected or reconnected.
- If required config is missing, `BacklogWheel.Twitch.config/1` returns `{:error, {:missing_config, keys}}` and `BacklogWheel.Twitch.configured?/1` returns `false`.
- Starting Twitch voting creates one channel point reward for the session. Viewers enter the game number shown in the voting pool and wheel; each valid redemption adds one vote.
- Game numbers are assigned permanently within a session, including after a game is removed. Twitch's redemption time determines whether a vote was made while voting was open, even if its notification arrives later. Invalid numbers and redemptions made outside a voting window are canceled to refund points, with an addressed chat message explaining the refund.
- Resolution and feedback failures are retained and retried; the session page reports redemptions that need attention. The app also checks Twitch for unfulfilled redemptions to recover missed EventSub deliveries. Check the Twitch connection and permissions if retries continue to fail.
- Freezing records a cutoff and disables the reward. Before spinning, the app reconciles Twitch's unfulfilled redemptions; if Twitch cannot be reached, the spin is blocked until reconciliation succeeds.
- For finished sessions, the app automatically deletes the reward after Twitch's unfulfilled queue is empty and local redemption resolutions are complete. Subsequent notifications for that deleted reward are ignored. Legacy per-game rewards are not managed and can be removed manually.
- A finished session can be reused after reward cleanup. Returning it to draft or reopening it clears the previous round's votes while keeping its games and option numbers; starting Twitch voting creates a new reward.
- OAuth requests `channel:manage:redemptions` and `user:write:chat`; credentials are stored per community. Existing users must reconnect Twitch once because older global credentials cannot be safely attributed to a particular community.
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

This includes strict TypeScript checking and the frontend tests. To run either
frontend check separately:

```sh
npm --prefix assets run typecheck
npm --prefix assets test
```

## Prototype Deployment

See [infra/README.md](infra/README.md) for Docker image and AWS CDK deployment details.

## License

This project is licensed under the GNU Affero General Public License v3.0. See [LICENSE](LICENSE) for details.
