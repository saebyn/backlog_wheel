# Backlog Wheel

Backlog Wheel is a small Phoenix LiveView app for choosing what game to play from a personal backlog. The first version is a local stream tool: maintain a backlog, mark games as wheel candidates, spin an equal-probability wheel, and eventually record the result.

## Current MVP Goal

The MVP is a local Phoenix LiveView app that can manage games, choose eligible games for a future wheel, show a stream-friendly wheel page, spin it, and record the result.

## Slice Status

- Slice 0: Project directory and Nix direnv development environment - complete
- Slice 1: Phoenix app generated and running - complete
- Slice 2: Games CRUD - complete
- Slice 3: Backlog workflow and curation - complete
- Slice 4: Wheel candidates and spin history domain - in progress
- Slice 5: Stream-friendly animated wheel
- Slice 6: Polish, history, backup, and tests

## Development Environment

This project is developed on NixOS with `nix-direnv`.

To enter the development environment:

```sh
direnv allow
```

If the shell is already allowed, entering the project directory should load the environment automatically.

## Setup

Install dependencies, create the SQLite database, run migrations, and build assets:

```sh
mix setup
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

Visit http://localhost:4000 in your browser. The games CRUD page is available at http://localhost:4000/games, and the basic wheel page is available at http://localhost:4000/wheel.

## Steam Import

Steam library import uses the official Steam Web API. Add these values to `.envrc`, then run `direnv allow`:

```sh
export STEAM_API_KEY="your-steam-web-api-key"
export STEAM_ID64="your-steam-id64"
```

Then visit http://localhost:4000/games/import/steam and click `Import Steam Library`.

Import behavior:

- New Steam games use `platform: "steam"` and the Steam app id as `external_id`.
- Imported Steam games are included on the wheel by default.
- `last_played_at` is set only when Steam returns the optional `rtime_last_played` field.
- Re-imports refresh `last_played_at` when Steam returns `rtime_last_played`.
- Existing Steam games are skipped so local edits are preserved.

## Tests

Run the test suite:

```sh
mix test
```

Run the project precommit alias:

```sh
mix precommit
```

## Near-Term Roadmap

- Slice 4: Finish wheel candidate queries and spin history domain objects.
- Slice 5: Build the stream-friendly animated wheel.
- Slice 6: Add polish, history views, backup workflow, and broader tests.

## Out Of Scope For Slice 2

- Wheel UI
- Weighted odds
- Steam import
- Twitch integration
- Discord integration
- Viewer voting
- Weekly elimination rounds
- Authentication or accounts
- Tags
