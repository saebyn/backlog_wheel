import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/backlog_wheel start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :backlog_wheel, BacklogWheelWeb.Endpoint, server: true
end

config :backlog_wheel, BacklogWheelWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

config :backlog_wheel,
  discord: [
    client_id: System.get_env("DISCORD_CLIENT_ID"),
    client_secret: System.get_env("DISCORD_CLIENT_SECRET")
  ],
  twitch: [
    client_id: System.get_env("TWITCH_CLIENT_ID"),
    client_secret: System.get_env("TWITCH_CLIENT_SECRET"),
    eventsub_callback_url: System.get_env("TWITCH_EVENTSUB_CALLBACK_URL")
  ]

if signup_allowed_discord_ids = System.get_env("SIGNUP_ALLOWED_DISCORD_IDS") do
  config :backlog_wheel, signup_allowed_discord_ids: signup_allowed_discord_ids
end

build_database_url = fn ->
  with username when is_binary(username) <- System.get_env("DATABASE_USERNAME"),
       password when is_binary(password) <- System.get_env("DATABASE_PASSWORD"),
       host when is_binary(host) <- System.get_env("DATABASE_HOST") do
    port = System.get_env("DATABASE_PORT", "5432")
    database = System.get_env("DATABASE_NAME", "backlog_wheel")

    "ecto://#{URI.encode_www_form(username)}:#{URI.encode_www_form(password)}@#{host}:#{port}/#{database}"
  else
    _missing -> nil
  end
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      build_database_url.() ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  database_ssl? = System.get_env("DATABASE_SSL", "true") == "true"
  database_host = System.get_env("DATABASE_HOST") || URI.parse(database_url).host
  database_ssl_ca_cert_path = System.get_env("DATABASE_SSL_CA_CERT_PATH")

  database_ssl_opts =
    cond do
      database_ssl? and is_binary(database_host) and is_binary(database_ssl_ca_cert_path) ->
        [
          verify: :verify_peer,
          cacertfile: String.to_charlist(database_ssl_ca_cert_path),
          server_name_indication: String.to_charlist(database_host)
        ]

      database_ssl? and is_binary(database_host) ->
        [
          verify: :verify_peer,
          cacerts: :public_key.cacerts_get(),
          server_name_indication: String.to_charlist(database_host)
        ]

      true ->
        []
    end

  config :backlog_wheel, BacklogWheel.Repo,
    url: database_url,
    ssl: database_ssl?,
    ssl_opts: database_ssl_opts,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :backlog_wheel, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :backlog_wheel, BacklogWheelWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :backlog_wheel, BacklogWheelWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :backlog_wheel, BacklogWheelWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :backlog_wheel, BacklogWheel.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
