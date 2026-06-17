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

    {:ok,
     %{
       access_token: "refreshed-#{credential.access_token}",
       refresh_token: credential.refresh_token,
       scopes: credential.scopes,
       expires_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)
     }}
  end

  def create_custom_reward(_config, _credential, attrs) do
    voting_session_game_id = Map.fetch!(attrs, :voting_session_game_id)

    Agent.update(@agent, fn state ->
      put_in(state, [:rewards, voting_session_game_id], attrs)
    end)

    {:ok,
     %{
       id: "reward-#{voting_session_game_id}",
       title: Map.fetch!(attrs, :title),
       cost: Map.fetch!(attrs, :cost),
       status: "enabled"
     }}
  end

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
