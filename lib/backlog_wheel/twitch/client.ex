defmodule BacklogWheel.Twitch.Client do
  @moduledoc """
  Twitch Helix API client for OAuth and channel point rewards.

  EventSub and redemption ingestion are intentionally outside this module.
  """

  alias BacklogWheel.Twitch.Config
  alias BacklogWheel.Twitch.Credential

  @callback exchange_code(Config.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback refresh_access_token(Config.t(), Credential.t()) :: {:ok, map()} | {:error, term()}
  @callback create_custom_reward(Config.t(), Credential.t(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback delete_custom_reward(Config.t(), Credential.t(), String.t()) :: :ok | {:error, term()}
  @callback create_redemption_eventsub_subscription(
              Config.t(),
              Credential.t(),
              String.t(),
              String.t()
            ) :: {:ok, map()} | {:error, term()}

  @token_url "https://id.twitch.tv/oauth2/token"
  @custom_rewards_url "https://api.twitch.tv/helix/channel_points/custom_rewards"
  @eventsub_subscriptions_url "https://api.twitch.tv/helix/eventsub/subscriptions"
  @scopes ["channel:manage:redemptions"]

  def scopes, do: @scopes

  def authorize_url(%Config{} = config, redirect_uri, state) do
    URI.to_string(%URI{
      scheme: "https",
      host: "id.twitch.tv",
      path: "/oauth2/authorize",
      query:
        URI.encode_query(%{
          client_id: config.client_id,
          redirect_uri: redirect_uri,
          response_type: "code",
          scope: Enum.join(@scopes, " "),
          state: state
        })
    })
  end

  def exchange_code(%Config{} = config, code, redirect_uri) do
    with {:ok, %{status: status, body: body}} when status in 200..299 <-
           Req.post(@token_url,
             form: [
               client_id: config.client_id,
               client_secret: config.client_secret,
               code: code,
               grant_type: "authorization_code",
               redirect_uri: redirect_uri
             ]
           ) do
      {:ok, normalize_token_response(body)}
    else
      {:ok, %{status: status, body: body}} -> {:error, {:twitch_http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  def refresh_access_token(%Config{} = config, %Credential{} = credential) do
    with {:ok, refresh_token} <- fetch_refresh_token(credential),
         {:ok, %{status: status, body: body}} when status in 200..299 <-
           Req.post(@token_url,
             form: [
               client_id: config.client_id,
               client_secret: config.client_secret,
               grant_type: "refresh_token",
               refresh_token: refresh_token
             ]
           ) do
      {:ok, normalize_token_response(body)}
    else
      {:error, reason} -> {:error, reason}
      {:ok, %{status: status, body: body}} -> {:error, {:twitch_http_error, status, body}}
    end
  end

  def create_custom_reward(%Config{} = config, %Credential{} = credential, attrs) do
    with {:ok, %{status: status, body: body}} when status in 200..299 <-
           Req.post(@custom_rewards_url,
             params: [broadcaster_id: config.broadcaster_id],
             headers: [
               {"client-id", config.client_id},
               {"authorization", "Bearer #{credential.access_token}"}
             ],
             json: reward_payload(attrs)
           ),
         {:ok, reward} <- normalize_reward_response(body) do
      {:ok, reward}
    else
      {:ok, %{status: status, body: body}} -> {:error, {:twitch_http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  def delete_custom_reward(%Config{} = config, %Credential{} = credential, reward_id) do
    case Req.delete(@custom_rewards_url,
           params: [broadcaster_id: config.broadcaster_id, id: reward_id],
           headers: [
             {"client-id", config.client_id},
             {"authorization", "Bearer #{credential.access_token}"}
           ]
         ) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status, body: body}} -> {:error, {:twitch_http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_redemption_eventsub_subscription(
        %Config{} = config,
        %Credential{} = credential,
        callback_url,
        secret
      ) do
    with {:ok, %{status: status, body: body}} when status in 200..299 <-
           Req.post(@eventsub_subscriptions_url,
             headers: [
               {"client-id", config.client_id},
               {"authorization", "Bearer #{credential.access_token}"}
             ],
             json: %{
               type: "channel.channel_points_custom_reward_redemption.add",
               version: "1",
               condition: %{broadcaster_user_id: config.broadcaster_id},
               transport: %{
                 method: "webhook",
                 callback: callback_url,
                 secret: secret
               }
             }
           ) do
      normalize_eventsub_subscription_response(body)
    else
      {:ok, %{status: status, body: body}} -> {:error, {:twitch_http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_token_response(body) do
    expires_at =
      body
      |> Map.get("expires_in")
      |> expires_at()

    %{
      access_token: body["access_token"],
      refresh_token: body["refresh_token"],
      scopes: body |> Map.get("scope", []) |> Enum.join(" "),
      expires_at: expires_at
    }
  end

  defp expires_at(seconds) when is_integer(seconds) do
    DateTime.utc_now()
    |> DateTime.add(seconds, :second)
    |> DateTime.truncate(:second)
  end

  defp expires_at(_seconds), do: nil

  defp fetch_refresh_token(%Credential{refresh_token: refresh_token})
       when is_binary(refresh_token) and refresh_token != "" do
    {:ok, refresh_token}
  end

  defp fetch_refresh_token(%Credential{}), do: {:error, :missing_twitch_refresh_token}

  defp reward_payload(attrs) do
    %{
      title: fetch_attr!(attrs, :title),
      cost: fetch_attr!(attrs, :cost),
      is_enabled: true,
      is_user_input_required: false,
      should_redemptions_skip_request_queue: true
    }
  end

  defp normalize_reward_response(%{"data" => [reward | _]}) do
    {:ok,
     %{
       id: reward["id"],
       title: reward["title"],
       cost: reward["cost"],
       status: reward_status(reward)
     }}
  end

  defp normalize_reward_response(_body), do: {:error, :invalid_twitch_reward_response}

  defp normalize_eventsub_subscription_response(%{"data" => [subscription | _]}) do
    {:ok,
     %{
       id: subscription["id"],
       status: subscription["status"],
       type: subscription["type"]
     }}
  end

  defp normalize_eventsub_subscription_response(_body), do: {:error, :invalid_eventsub_response}

  defp reward_status(%{"is_enabled" => false}), do: "disabled"
  defp reward_status(%{"is_paused" => true}), do: "paused"
  defp reward_status(%{"is_enabled" => true}), do: "enabled"
  defp reward_status(_reward), do: "created"

  defp fetch_attr!(attrs, key) do
    Map.fetch!(attrs, key)
  rescue
    KeyError -> Map.fetch!(attrs, Atom.to_string(key))
  end
end
