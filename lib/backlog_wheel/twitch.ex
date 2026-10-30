defmodule BacklogWheel.Twitch do
  @moduledoc """
  Boundary for future Twitch integration work.

  This module intentionally exposes only local configuration status for now.
  OAuth, EventSub, reward creation, and live Twitch API calls are out of scope.
  """

  import Ecto.Query

  alias BacklogWheel.Twitch.Config
  alias BacklogWheel.Twitch.Credential
  alias BacklogWheel.Communities
  alias BacklogWheel.Communities.Community
  alias BacklogWheel.Repo

  def configured?(%Community{} = community), do: match?({:ok, %Config{}}, config(community))

  @spec config(Community.t()) :: {:ok, Config.t()} | {:error, {:missing_config, [atom()]}}
  def config(%Community{} = community) do
    Application.get_env(:backlog_wheel, :twitch, [])
    |> Map.new(fn {key, value} -> {key, value} end)
    |> Map.merge(%{
      broadcaster_id: community.twitch_broadcaster_id,
      reward_cost: community.twitch_reward_cost,
      eventsub_secret: community.twitch_eventsub_secret
    })
    |> Config.new()
  end

  @spec oauth_config() :: {:ok, Config.t()} | {:error, {:missing_config, [atom()]}}
  def oauth_config do
    Application.get_env(:backlog_wheel, :twitch, [])
    |> Config.oauth()
  end

  @spec eventsub_config(map()) ::
          {:ok, Config.t()}
          | {:error, {:missing_config | :unknown_broadcaster, [atom()] | String.t()}}
  def eventsub_config(params) do
    broadcaster_id = eventsub_broadcaster_id(params)

    with {:ok, broadcaster_id} <- require_broadcaster_id(broadcaster_id),
         %Community{} = community <-
           Communities.get_community_by_twitch_broadcaster_id(broadcaster_id),
         {:ok, config} <- config(community),
         {:ok, _secret} <- eventsub_secret(config) do
      {:ok, config}
    else
      nil -> {:error, {:unknown_broadcaster, broadcaster_id || ""}}
      {:error, reason} -> {:error, reason}
    end
  end

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

  def ensure_redemption_eventsub_subscription(conn, %Community{} = community) do
    with {:ok, config} <- config(community),
         {:ok, secret} <- eventsub_secret(config),
         credential when not is_nil(credential) <- get_credential(community) do
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

  @spec get_credential(Community.t()) :: Credential.t() | nil
  def get_credential(%Community{id: community_id}) do
    Repo.get_by(Credential, community_id: community_id)
  end

  @spec credential_configured?(Community.t()) :: boolean()
  def credential_configured?(%Community{} = community), do: not is_nil(get_credential(community))

  @spec save_credential(Community.t(), map()) ::
          {:ok, Credential.t()} | {:error, Ecto.Changeset.t()}
  def save_credential(%Community{} = community, attrs) do
    (get_credential(community) || %Credential{community_id: community.id})
    |> Credential.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @spec refresh_credential(Community.t(), Config.t(), module()) ::
          {:ok, Credential.t()} | {:error, term()}
  def refresh_credential(%Community{} = community, %Config{} = config, client) do
    with %Credential{} = credential <- get_credential(community),
         {:ok, token_attrs} <- client.refresh_access_token(config, credential) do
      token_attrs
      |> preserve_refresh_token(credential)
      |> then(&save_credential(community, &1))
    else
      nil -> {:error, :missing_twitch_credential}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec delete_credential(Community.t()) :: :ok
  def delete_credential(%Community{id: community_id}) do
    Repo.delete_all(
      from credential in Credential, where: credential.community_id == ^community_id
    )

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

  defp eventsub_broadcaster_id(%{"event" => %{"broadcaster_user_id" => broadcaster_id}}),
    do: broadcaster_id

  defp eventsub_broadcaster_id(%{
         "subscription" => %{"condition" => %{"broadcaster_user_id" => broadcaster_id}}
       }),
       do: broadcaster_id

  defp eventsub_broadcaster_id(_params), do: nil

  defp require_broadcaster_id(broadcaster_id)
       when is_binary(broadcaster_id) and broadcaster_id != "" do
    {:ok, broadcaster_id}
  end

  defp require_broadcaster_id(_broadcaster_id), do: {:error, {:missing_config, [:broadcaster_id]}}
end
