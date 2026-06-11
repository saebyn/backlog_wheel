# syntax=docker/dockerfile:1

ARG ELIXIR_VERSION=1.18
ARG DEBIAN_VERSION=bookworm

FROM elixir:${ELIXIR_VERSION}-slim AS build

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only prod && mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets

RUN mix compile
RUN mix assets.deploy
RUN mix release

FROM debian:${DEBIAN_VERSION}-slim AS app

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod \
  PHX_SERVER=true \
  PORT=4000 \
  HOME=/app

RUN useradd --create-home --home-dir /app --shell /usr/sbin/nologin app \
  && mkdir -p /data \
  && chown -R app:app /app /data

COPY --from=build --chown=app:app /app/_build/prod/rel/backlog_wheel ./

USER app

EXPOSE 4000

CMD ["/app/bin/backlog_wheel", "start"]
