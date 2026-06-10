defmodule BacklogWheel.Twitch do
  @moduledoc """
  Boundary for future Twitch integration work.

  This module intentionally exposes only local configuration status for now.
  OAuth, EventSub, reward creation, and live Twitch API calls are out of scope.
  """

  alias BacklogWheel.Twitch.Config
  alias BacklogWheel.Twitch.Credential
  alias BacklogWheel.Repo

  @spec configured?() :: boolean()
  def configured?, do: Config.configured?()

  @spec config() :: {:ok, Config.t()} | {:error, {:missing_config, [atom()]}}
  def config, do: Config.new()

  @spec client() :: module()
  def client, do: Application.get_env(:backlog_wheel, :twitch_client, BacklogWheel.Twitch.Client)

  @spec redirect_uri(Plug.Conn.t()) :: String.t()
  def redirect_uri(conn) do
    port = if conn.port in [80, 443], do: "", else: ":#{conn.port}"

    "#{conn.scheme}://#{conn.host}#{port}/twitch/oauth/callback"
  end

  @spec eventsub_callback_url(Plug.Conn.t(), Config.t()) :: String.t()
  def eventsub_callback_url(_conn, %Config{eventsub_callback_url: callback_url})
      when is_binary(callback_url) and callback_url != "" do
    callback_url
  end

  def eventsub_callback_url(conn, %Config{}) do
    port = if conn.port in [80, 443], do: "", else: ":#{conn.port}"

    "#{conn.scheme}://#{conn.host}#{port}/twitch/eventsub"
  end

  @spec eventsub_secret(Config.t()) :: {:ok, String.t()} | {:error, {:missing_config, [atom()]}}
  def eventsub_secret(%Config{eventsub_secret: secret}) when is_binary(secret) and secret != "" do
    {:ok, secret}
  end

  def eventsub_secret(%Config{}), do: {:error, {:missing_config, [:eventsub_secret]}}

  @spec ensure_redemption_eventsub_subscription(Plug.Conn.t()) :: {:ok, map()} | {:error, term()}
  def ensure_redemption_eventsub_subscription(conn) do
    with {:ok, config} <- config(),
         {:ok, secret} <- eventsub_secret(config),
         credential when not is_nil(credential) <- get_credential() do
      client().create_redemption_eventsub_subscription(
        config,
        credential,
        eventsub_callback_url(conn, config),
        secret
      )
    else
      nil -> {:error, :missing_twitch_credential}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec get_credential() :: Credential.t() | nil
  def get_credential do
    Credential
    |> Ecto.Query.last(:inserted_at)
    |> Repo.one()
  end

  @spec credential_configured?() :: boolean()
  def credential_configured?, do: not is_nil(get_credential())

  @spec save_credential(map()) :: {:ok, Credential.t()} | {:error, Ecto.Changeset.t()}
  def save_credential(attrs) do
    case get_credential() do
      nil -> %Credential{}
      credential -> credential
    end
    |> Credential.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @spec refresh_credential(Config.t(), module()) :: {:ok, Credential.t()} | {:error, term()}
  def refresh_credential(%Config{} = config, client \\ client()) do
    with %Credential{} = credential <- get_credential(),
         {:ok, token_attrs} <- client.refresh_access_token(config, credential) do
      token_attrs
      |> preserve_refresh_token(credential)
      |> save_credential()
    else
      nil -> {:error, :missing_twitch_credential}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec delete_credential() :: :ok
  def delete_credential do
    Repo.delete_all(Credential)
    :ok
  end

  defp preserve_refresh_token(attrs, %Credential{} = credential) do
    refresh_token = Map.get(attrs, :refresh_token) || Map.get(attrs, "refresh_token")

    if refresh_token in [nil, ""] do
      Map.put(attrs, :refresh_token, credential.refresh_token)
    else
      attrs
    end
  end
end
