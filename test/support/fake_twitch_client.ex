defmodule BacklogWheel.FakeTwitchClient do
  @behaviour BacklogWheel.Twitch.Client

  @agent __MODULE__.Agent

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(_opts) do
    Agent.start_link(fn -> %{rewards: %{}} end, name: @agent)
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
    Agent.update(@agent, fn state ->
      deleted_rewards = MapSet.put(Map.get(state, :deleted_rewards, MapSet.new()), reward_id)
      Map.put(state, :deleted_rewards, deleted_rewards)
    end)

    :ok
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
end
