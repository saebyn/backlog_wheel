defmodule BacklogWheel.FakeTwitchClient do
  @moduledoc false

  @behaviour BacklogWheel.Twitch.Client

  @agent __MODULE__.Agent

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(_opts) do
    Agent.start_link(fn -> %{rewards: %{}, failing_deletions: MapSet.new()} end, name: @agent)
  end

  def authorize_url(_config, redirect_uri, state) do
    "https://id.twitch.tv/oauth2/authorize?redirect_uri=#{URI.encode_www_form(redirect_uri)}&state=#{state}"
  end

  def exchange_code(_config, "valid-code", _redirect_uri) do
    {:ok,
     %{
       access_token: "access-token",
       refresh_token: "refresh-token",
       scopes: "channel:manage:redemptions"
     }}
  end

  def exchange_code(_config, _code, _redirect_uri), do: {:error, :invalid_code}

  def fetch_current_user(_config, _credential) do
    {:ok, %{id: "28728577", login: "teststreamer", display_name: "TestStreamer"}}
  end

  def refresh_access_token(_config, credential) do
    Agent.update(@agent, &Map.update(&1, :refresh_count, 1, fn count -> count + 1 end))

    refresh_token =
      Agent.get(@agent, &Map.get(&1, :rotated_refresh_token, credential.refresh_token))

    {:ok,
     %{
       access_token: "refreshed-#{credential.access_token}",
       refresh_token: refresh_token,
       scopes: credential.scopes,
       expires_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)
     }}
  end

  def rotate_refresh_token(token),
    do: Agent.update(@agent, &Map.put(&1, :rotated_refresh_token, token))

  def create_custom_reward(config, credential, attrs) do
    voting_session_game_id =
      Map.get(attrs, :voting_session_game_id) || Map.fetch!(attrs, :voting_session_id)

    reward_id =
      Agent.get_and_update(@agent, fn state ->
        generation = Map.get(Map.get(state, :generations, %{}), voting_session_game_id, 0) + 1
        suffix = if generation == 1, do: "", else: "-#{generation}"
        reward_id = "reward-#{voting_session_game_id}#{suffix}"

        state =
          state
          |> put_in([:rewards, voting_session_game_id], attrs)
          |> Map.update(
            :generations,
            %{voting_session_game_id => generation},
            &Map.put(&1, voting_session_game_id, generation)
          )
          |> Map.update(
            :reward_ids,
            %{voting_session_game_id => reward_id},
            &Map.put(&1, voting_session_game_id, reward_id)
          )
          |> Map.update(
            :reward_credentials,
            %{config.broadcaster_id => credential.access_token},
            &Map.put(&1, config.broadcaster_id, credential.access_token)
          )

        {reward_id, state}
      end)

    {:ok,
     %{
       id: reward_id,
       title: Map.fetch!(attrs, :title),
       cost: Map.fetch!(attrs, :cost),
       status: "enabled"
     }}
  end

  def reward_credential(broadcaster_id),
    do: Agent.get(@agent, &get_in(&1, [:reward_credentials, broadcaster_id]))

  def delete_custom_reward(_config, _credential, reward_id) do
    if fail_deletion?(reward_id) do
      {:error, :delete_failed}
    else
      Agent.update(@agent, fn state ->
        deleted_rewards = MapSet.put(Map.get(state, :deleted_rewards, MapSet.new()), reward_id)
        Map.put(state, :deleted_rewards, deleted_rewards)
      end)

      :ok
    end
  end

  def update_redemption(_config, _credential, reward_id, redemption_id, status) do
    Agent.get_and_update(@agent, fn state ->
      if Map.get(state, :fail_resolution, false) do
        {{:error, :resolution_failed}, state}
      else
        {resolution_result(state), put_redemption(state, reward_id, redemption_id, status)}
      end
    end)
  end

  defp resolution_result(%{ambiguous_resolution: true}), do: {:error, :timeout}
  defp resolution_result(_state), do: :ok

  defp put_redemption(state, reward_id, redemption_id, status) do
    state =
      Map.update(state, :redemptions, %{redemption_id => {reward_id, status}}, fn redemptions ->
        Map.put(redemptions, redemption_id, {reward_id, status})
      end)

    update_in(state, [:unfulfilled], fn unfulfilled ->
      Map.update(unfulfilled || %{}, reward_id, [], fn events ->
        Enum.reject(events, &(&1["id"] == redemption_id))
      end)
    end)
  end

  def send_chat_message(_config, _credential, message) do
    Agent.get_and_update(@agent, fn state ->
      if Map.get(state, :fail_chat, false) do
        {{:error, :chat_failed}, state}
      else
        {:ok,
         Map.update(state, :chat_messages, [message], fn messages -> [message | messages] end)}
      end
    end)
  end

  def fail_resolution(value), do: Agent.update(@agent, &Map.put(&1, :fail_resolution, value))

  def fail_reconciliation(value),
    do: Agent.update(@agent, &Map.put(&1, :fail_reconciliation, value))

  def ambiguous_resolution(value),
    do: Agent.update(@agent, &Map.put(&1, :ambiguous_resolution, value))

  def fail_chat(value), do: Agent.update(@agent, &Map.put(&1, :fail_chat, value))
  def chat_messages, do: Agent.get(@agent, &Map.get(&1, :chat_messages, []))
  def redemption_status(id), do: Agent.get(@agent, &get_in(&1, [:redemptions, id]))

  def set_reward_enabled(_config, _credential, reward_id, enabled) do
    if not enabled and fail_deletion?(reward_id) do
      {:error, :disable_failed}
    else
      Agent.update(
        @agent,
        &Map.update(&1, :reward_enabled, %{reward_id => enabled}, fn states ->
          Map.put(states, reward_id, enabled)
        end)
      )

      :ok
    end
  end

  def reward_enabled?(reward_id), do: Agent.get(@agent, &get_in(&1, [:reward_enabled, reward_id]))

  def list_unfulfilled_redemptions(_config, _credential, reward_id) do
    Agent.get_and_update(@agent, fn state ->
      calls = Map.update(Map.get(state, :list_calls, %{}), reward_id, 1, &(&1 + 1))

      result =
        cond do
          Map.get(state, :fail_reconciliation, false) ->
            {:error, :reconciliation_failed}

          MapSet.member?(Map.get(state, :deleted_rewards, MapSet.new()), reward_id) ->
            {:error, {:twitch_http_error, 404, %{}}}

          true ->
            {:ok, get_in(state, [:unfulfilled, reward_id]) || []}
        end

      {result, Map.put(state, :list_calls, calls)}
    end)
  end

  def list_calls(reward_id), do: Agent.get(@agent, &(get_in(&1, [:list_calls, reward_id]) || 0))

  def set_unfulfilled(reward_id, events) do
    Agent.update(
      @agent,
      &Map.update(&1, :unfulfilled, %{reward_id => events}, fn values ->
        Map.put(values, reward_id, events)
      end)
    )
  end

  def find_custom_reward(_config, _credential, title) do
    Agent.get(@agent, fn state ->
      case Enum.find(state.rewards, &reward_available?(&1, title, state)) do
        nil ->
          {:ok, nil}

        {id, attrs} ->
          {:ok,
           %{
             id: get_in(state, [:reward_ids, id]),
             title: attrs.title,
             cost: attrs.cost,
             status: "disabled"
           }}
      end
    end)
  end

  defp reward_available?({id, attrs}, title, state) do
    attrs.title == title and
      not MapSet.member?(
        Map.get(state, :deleted_rewards, MapSet.new()),
        get_in(state, [:reward_ids, id])
      )
  end

  def get_redemption_status(_config, _credential, _reward_id, redemption_id) do
    Agent.get(@agent, fn state ->
      case get_in(state, [:redemptions, redemption_id]) do
        {_reward_id, status} -> {:ok, status}
        nil -> {:ok, "UNFULFILLED"}
      end
    end)
  end

  def create_redemption_eventsub_subscription(_config, _credential, callback_url, _secret) do
    Agent.update(@agent, fn state ->
      Map.put(state, :eventsub_callback_url, callback_url)
    end)

    {:ok,
     %{
       id: "eventsub-subscription-1",
       status: "webhook_callback_verification_pending",
       type: "channel.channel_points_custom_reward_redemption.add"
     }}
  end

  def eventsub_callback_url do
    Agent.get(@agent, &Map.get(&1, :eventsub_callback_url))
  end

  def refresh_count do
    Agent.get(@agent, &Map.get(&1, :refresh_count, 0))
  end

  def fail_deletion(reward_id) do
    Agent.update(@agent, fn state ->
      Map.update!(state, :failing_deletions, &MapSet.put(&1, reward_id))
    end)
  end

  def allow_deletion(reward_id) do
    Agent.update(@agent, fn state ->
      Map.update!(state, :failing_deletions, &MapSet.delete(&1, reward_id))
    end)
  end

  def reward_attrs(voting_session_game_id) do
    Agent.get(@agent, &get_in(&1, [:rewards, voting_session_game_id]))
  end

  def deleted_reward?(reward_id) do
    Agent.get(@agent, fn state ->
      state
      |> Map.get(:deleted_rewards, MapSet.new())
      |> MapSet.member?(reward_id)
    end)
  end

  defp fail_deletion?(reward_id) do
    Agent.get(@agent, fn state ->
      state
      |> Map.fetch!(:failing_deletions)
      |> MapSet.member?(reward_id)
    end)
  end
end
