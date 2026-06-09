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

## Setup

Install dependencies, create the SQLite database, run migrations, and build assets:

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

Steam library import uses the official Steam Web API. Add these values to `.envrc`, then run `direnv allow`:

```sh
export STEAM_API_KEY="your-steam-web-api-key"
export STEAM_ID64="your-steam-id64"
```

Then visit <http://localhost:4000/games/import/steam> and click `Import Steam Library`.

Import behavior:

- New Steam games use `platform: "steam"` and the Steam app id as `external_id`.
- Imported Steam games are included on the wheel by default.
- `last_played_at` is set only when Steam returns the optional `rtime_last_played` field.
- Re-imports refresh `last_played_at` when Steam returns `rtime_last_played`.
- Existing Steam games are skipped so local edits are preserved.

## Twitch Configuration

Twitch integration supports local OAuth authorization and temporary channel point reward creation for voting sessions. EventSub and redemption ingestion are not implemented yet.

Add these values to `.envrc`, then run `direnv allow`:

```sh
export TWITCH_CLIENT_ID="your-twitch-client-id"
export TWITCH_CLIENT_SECRET="your-twitch-client-secret"
export TWITCH_BROADCASTER_ID="your-twitch-broadcaster-id"
export TWITCH_REWARD_COST="100"
```

When registering a local development app at <https://dev.twitch.tv/console/apps/create>, use this OAuth redirect URL:

```text
http://localhost:4000/twitch/oauth/callback
```

Twitch allows HTTP redirect URLs for `localhost`. After setting the env vars, visit the Twitch page and click `Connect Twitch` to authorize the local app.

Behavior today:

- `TWITCH_CLIENT_ID` identifies the Twitch application/client.
- `TWITCH_CLIENT_SECRET` is used by the local OAuth callback to exchange authorization codes.
- `TWITCH_BROADCASTER_ID` identifies the channel that future reward actions will target.
- `TWITCH_REWARD_COST` sets the channel point vote cost and defaults to `100`.
- If required config is missing, `BacklogWheel.Twitch.config/0` returns `{:error, {:missing_config, keys}}` and `BacklogWheel.Twitch.configured?/0` returns `false`.
- Starting Twitch voting creates one positive channel point vote reward per game in the voting session.
- Redemption ingestion is not implemented yet.

## Tests

Run the test suite:

```sh
mix test
```

Run the project precommit alias:

```sh
mix precommit
```

## License

This project is licensed under the GNU Affero General Public License v3.0. See [LICENSE](LICENSE) for details.
