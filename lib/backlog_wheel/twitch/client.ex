defmodule BacklogWheel.Twitch.Client do
  @moduledoc """
  Twitch Helix API client for OAuth and channel point rewards.

  EventSub and redemption ingestion are intentionally outside this module.
  """

  require Logger

  alias BacklogWheel.Twitch.Config
  alias BacklogWheel.Twitch.Credential

  @callback exchange_code(Config.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback fetch_current_user(Config.t(), Credential.t()) :: {:ok, map()} | {:error, term()}
  @callback refresh_access_token(Config.t(), Credential.t()) :: {:ok, map()} | {:error, term()}
  @callback create_custom_reward(Config.t(), Credential.t(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback delete_custom_reward(Config.t(), Credential.t(), String.t()) :: :ok | {:error, term()}
  @callback update_redemption(Config.t(), Credential.t(), String.t(), String.t(), String.t()) ::
              :ok | {:error, term()}
  @callback send_chat_message(Config.t(), Credential.t(), String.t()) :: :ok | {:error, term()}
  @callback set_reward_enabled(Config.t(), Credential.t(), String.t(), boolean()) ::
              :ok | {:error, term()}
  @callback get_redemption_status(Config.t(), Credential.t(), String.t(), String.t()) ::
              {:ok, String.t()} | {:error, term()}
  @callback find_custom_reward(Config.t(), Credential.t(), String.t()) ::
              {:ok, map() | nil} | {:error, term()}
  @callback list_unfulfilled_redemptions(Config.t(), Credential.t(), String.t()) ::
              {:ok, [map()]} | {:error, term()}
  @callback create_redemption_eventsub_subscription(
              Config.t(),
              Credential.t(),
              String.t(),
              String.t()
            ) :: {:ok, map()} | {:error, term()}

  @token_url "https://id.twitch.tv/oauth2/token"
  @users_url "https://api.twitch.tv/helix/users"
  @custom_rewards_url "https://api.twitch.tv/helix/channel_points/custom_rewards"
  @redemptions_url "https://api.twitch.tv/helix/channel_points/custom_rewards/redemptions"
  @chat_url "https://api.twitch.tv/helix/chat/messages"
  @eventsub_subscriptions_url "https://api.twitch.tv/helix/eventsub/subscriptions"
  @scopes ["channel:manage:redemptions", "user:write:chat"]

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
    case request(:exchange_code, :post, @token_url,
           form: [
             client_id: config.client_id,
             client_secret: config.client_secret,
             code: code,
             grant_type: "authorization_code",
             redirect_uri: redirect_uri
           ]
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, normalize_token_response(body)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:twitch_http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def refresh_access_token(%Config{} = config, %Credential{} = credential) do
    with {:ok, refresh_token} <- fetch_refresh_token(credential),
         {:ok, %{status: status, body: body}} when status in 200..299 <-
           request(:refresh_access_token, :post, @token_url,
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

  def fetch_current_user(%Config{} = config, %Credential{} = credential) do
    case request(:fetch_current_user, :get, @users_url,
           headers: [
             {"client-id", config.client_id},
             {"authorization", "Bearer #{credential.access_token}"}
           ]
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        normalize_user_response(body)

      {:ok, %{status: status, body: body}} ->
        {:error, {:twitch_http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def create_custom_reward(%Config{} = config, %Credential{} = credential, attrs) do
    with {:ok, %{status: status, body: body}} when status in 200..299 <-
           request(:create_custom_reward, :post, @custom_rewards_url,
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
    case request(:delete_custom_reward, :delete, @custom_rewards_url,
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

  def update_redemption(
        %Config{} = config,
        %Credential{} = credential,
        reward_id,
        redemption_id,
        status
      ) do
    case request(:update_redemption, :patch, @redemptions_url,
           params: [
             broadcaster_id: config.broadcaster_id,
             reward_id: reward_id,
             id: redemption_id
           ],
           headers: [
             {"client-id", config.client_id},
             {"authorization", "Bearer #{credential.access_token}"}
           ],
           json: %{status: status}
         ) do
      {:ok,
       %{status: code, body: %{"data" => [%{"id" => ^redemption_id, "status" => ^status} | _]}}}
      when code in 200..299 ->
        :ok

      {:ok, %{status: code, body: body}} ->
        {:error, {:twitch_http_error, code, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def send_chat_message(%Config{} = config, %Credential{} = credential, message) do
    case request(:send_chat_message, :post, @chat_url,
           headers: [
             {"client-id", config.client_id},
             {"authorization", "Bearer #{credential.access_token}"}
           ],
           json: %{
             broadcaster_id: config.broadcaster_id,
             sender_id: config.broadcaster_id,
             message: message
           }
         ) do
      {:ok, %{status: code, body: %{"data" => [%{"is_sent" => true} | _]}}}
      when code in 200..299 ->
        :ok

      {:ok, %{status: code, body: body}} ->
        {:error, {:twitch_http_error, code, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def set_reward_enabled(%Config{} = config, %Credential{} = credential, reward_id, enabled) do
    case request(:set_reward_enabled, :patch, @custom_rewards_url,
           params: [broadcaster_id: config.broadcaster_id, id: reward_id],
           headers: [
             {"client-id", config.client_id},
             {"authorization", "Bearer #{credential.access_token}"}
           ],
           json: %{is_enabled: enabled}
         ) do
      {:ok,
       %{status: code, body: %{"data" => [%{"id" => ^reward_id, "is_enabled" => ^enabled} | _]}}}
      when code in 200..299 ->
        :ok

      {:ok, %{status: code, body: body}} ->
        {:error, {:twitch_http_error, code, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def find_custom_reward(%Config{} = config, %Credential{} = credential, title) do
    case request(:find_custom_reward, :get, @custom_rewards_url,
           params: [broadcaster_id: config.broadcaster_id, only_manageable_rewards: true],
           headers: [
             {"client-id", config.client_id},
             {"authorization", "Bearer #{credential.access_token}"}
           ]
         ) do
      {:ok, %{status: code, body: %{"data" => rewards}}}
      when code in 200..299 and is_list(rewards) ->
        case Enum.find(rewards, &(&1["title"] == title)) do
          nil -> {:ok, nil}
          reward -> normalize_reward_response(%{"data" => [reward]})
        end

      {:ok, %{status: code, body: body}} ->
        {:error, {:twitch_http_error, code, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def list_unfulfilled_redemptions(%Config{} = config, %Credential{} = credential, reward_id) do
    list_unfulfilled_redemptions(config, credential, reward_id, nil, [])
  end

  defp list_unfulfilled_redemptions(config, credential, reward_id, cursor, collected) do
    params = [
      broadcaster_id: config.broadcaster_id,
      reward_id: reward_id,
      status: "UNFULFILLED",
      first: 50
    ]

    params = if cursor, do: Keyword.put(params, :after, cursor), else: params

    case request(:list_unfulfilled_redemptions, :get, @redemptions_url,
           params: params,
           headers: [
             {"client-id", config.client_id},
             {"authorization", "Bearer #{credential.access_token}"}
           ]
         ) do
      {:ok, %{status: code, body: %{"data" => data} = body}}
      when code in 200..299 and is_list(data) ->
        next = get_in(body, ["pagination", "cursor"])
        collected = collected ++ data

        if next,
          do: list_unfulfilled_redemptions(config, credential, reward_id, next, collected),
          else: {:ok, collected}

      {:ok, %{status: code, body: body}} ->
        {:error, {:twitch_http_error, code, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_redemption_status(
        %Config{} = config,
        %Credential{} = credential,
        reward_id,
        redemption_id
      ) do
    case request(:get_redemption_status, :get, @redemptions_url,
           params: [
             broadcaster_id: config.broadcaster_id,
             reward_id: reward_id,
             id: redemption_id
           ],
           headers: [
             {"client-id", config.client_id},
             {"authorization", "Bearer #{credential.access_token}"}
           ]
         ) do
      {:ok, %{status: code, body: %{"data" => [%{"status" => status} | _]}}}
      when code in 200..299 ->
        {:ok, status}

      {:ok, %{status: code, body: body}} ->
        {:error, {:twitch_http_error, code, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def create_redemption_eventsub_subscription(
        %Config{} = config,
        %Credential{},
        callback_url,
        secret
      ) do
    with {:ok, app_access_token} <- fetch_app_access_token(config),
         {:ok, %{status: status, body: body}} when status in 200..299 <-
           request(:create_redemption_eventsub_subscription, :post, @eventsub_subscriptions_url,
             headers: [
               {"client-id", config.client_id},
               {"authorization", "Bearer #{app_access_token}"}
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
           ),
         {:ok, subscription} <- normalize_eventsub_subscription_response(body) do
      {:ok, subscription}
    else
      {:ok, %{status: status, body: body}} -> {:error, {:twitch_http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_app_access_token(%Config{} = config) do
    case request(:fetch_app_access_token, :post, @token_url,
           form: [
             client_id: config.client_id,
             client_secret: config.client_secret,
             grant_type: "client_credentials"
           ]
         ) do
      {:ok, %{status: status, body: %{"access_token" => access_token}}}
      when status in 200..299 and is_binary(access_token) and access_token != "" ->
        {:ok, access_token}

      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:error, {:invalid_twitch_app_token_response, body}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:twitch_http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
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

  defp request(operation, method, url, options) do
    started_at = System.monotonic_time()
    result = apply(Req, method, [url, options])

    duration_ms =
      System.convert_time_unit(System.monotonic_time() - started_at, :native, :millisecond)

    case result do
      {:ok, %{status: status}} when status in 200..299 ->
        Logger.info(
          "Twitch API request succeeded operation=#{operation} status=#{status} duration_ms=#{duration_ms}"
        )

      {:ok, %{status: status, body: body}} ->
        Logger.warning(
          "Twitch API request failed operation=#{operation} status=#{status} duration_ms=#{duration_ms} error=#{twitch_error(body)}"
        )

      {:error, reason} ->
        Logger.warning(
          "Twitch API request failed operation=#{operation} duration_ms=#{duration_ms} error=#{inspect(reason)}"
        )
    end

    result
  end

  defp twitch_error(%{"error" => error, "message" => message}), do: inspect({error, message})
  defp twitch_error(%{"message" => message}), do: inspect(message)
  defp twitch_error(_body), do: "unavailable"

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
      prompt: Map.get(attrs, :prompt, ""),
      is_enabled: Map.get(attrs, :is_enabled, true),
      is_user_input_required: Map.get(attrs, :is_user_input_required, false),
      should_redemptions_skip_request_queue:
        Map.get(attrs, :should_redemptions_skip_request_queue, true)
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

  defp normalize_user_response(%{"data" => [%{"id" => id} = user | _]}) do
    {:ok,
     %{
       id: id,
       login: user["login"],
       display_name: user["display_name"]
     }}
  end

  defp normalize_user_response(_body), do: {:error, :invalid_twitch_user_response}

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
