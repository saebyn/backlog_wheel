defmodule BacklogWheel.Twitch.SimulatorClient do
  @moduledoc false
  use Agent
  @behaviour BacklogWheel.Twitch.Client

  alias BacklogWheel.Communities
  alias BacklogWheel.Backlog
  alias BacklogWheel.Backlog.Game
  alias BacklogWheel.Repo
  alias BacklogWheel.Twitch
  alias BacklogWheel.Voting

  @redemption_type "channel.channel_points_custom_reward_redemption.add"

  def start_link(_opts),
    do: Agent.start_link(&load_state/0, name: __MODULE__)

  defp load_state do
    case Application.get_env(:backlog_wheel, :twitch_simulator_state_path) do
      nil ->
        empty_state()

      path ->
        case File.read(path) do
          {:ok, binary} -> :erlang.binary_to_term(binary, [:safe])
          {:error, :enoent} -> empty_state()
          {:error, reason} -> raise File.Error, reason: reason, action: "read", path: path
        end
    end
  end

  defp empty_state, do: %{rewards: %{}, redemptions: %{}, messages: [], failures: %{}}

  defp persist_state(state) do
    if path = Application.get_env(:backlog_wheel, :twitch_simulator_state_path) do
      File.mkdir_p!(Path.dirname(path))
      temporary_path = path <> ".tmp"
      File.write!(temporary_path, :erlang.term_to_binary(state))
      File.rename!(temporary_path, path)
    end

    state
  end

  defp update_state(fun),
    do: Agent.update(__MODULE__, fn state -> state |> fun.() |> persist_state() end)

  defp get_and_update_state(fun) do
    Agent.get_and_update(__MODULE__, fn state ->
      {result, updated} = fun.(state)
      {result, persist_state(updated)}
    end)
  end

  def channel_id(community), do: "999999#{community.id}"

  def subscribe(community),
    do: Phoenix.PubSub.subscribe(BacklogWheel.PubSub, topic(channel_id(community)))

  def failures(community),
    do: Agent.get(__MODULE__, &Map.get(&1.failures, channel_id(community), %{}))

  def toggle_failure(community, kind)
      when kind in ["resolution", "reconciliation", "chat", "deletion", "disable", "creation"] do
    id = channel_id(community)

    update_state(fn state ->
      flags = Map.get(state.failures, id, %{})
      put_in(state, [:failures, id], Map.put(flags, kind, not Map.get(flags, kind, false)))
    end)

    broadcast(id)
    :ok
  end

  defp failing?(state, broadcaster_id, kind),
    do: get_in(state, [:failures, broadcaster_id, kind]) == true

  def rewards(community) do
    broadcaster_id = channel_id(community)

    Agent.get(__MODULE__, fn state ->
      state.rewards
      |> Map.values()
      |> Enum.filter(&(&1.broadcaster_id == broadcaster_id and not &1.deleted))
    end)
  end

  def deleted_rewards(community) do
    broadcaster_id = channel_id(community)

    Agent.get(__MODULE__, fn state ->
      state.rewards
      |> Map.values()
      |> Enum.filter(&(&1.broadcaster_id == broadcaster_id and &1.deleted))
    end)
  end

  def redemptions(community) do
    broadcaster_id = channel_id(community)

    Agent.get(__MODULE__, fn state ->
      state.redemptions
      |> Map.values()
      |> Enum.filter(&(&1.broadcaster_id == broadcaster_id))
      |> Enum.sort_by(& &1.redeemed_at, {:desc, DateTime})
    end)
  end

  def messages(community) do
    broadcaster_id = channel_id(community)

    Agent.get(__MODULE__, fn state ->
      Enum.filter(state.messages, &(&1.broadcaster_id == broadcaster_id))
    end)
  end

  def redeem(community, reward_id, user_login, user_input, delay?) do
    if enabled?(),
      do: do_redeem(community, reward_id, user_login, user_input, delay?),
      else: {:error, :simulator_disabled}
  end

  defp do_redeem(community, reward_id, user_login, user_input, delay?) do
    broadcaster_id = channel_id(community)
    login = String.trim(user_login)

    result =
      get_and_update_state(fn state ->
        case state.rewards[reward_id] do
          %{broadcaster_id: ^broadcaster_id, enabled: true, deleted: false} when login != "" ->
            redemption = %{
              id: Ecto.UUID.generate(),
              reward_id: reward_id,
              broadcaster_id: broadcaster_id,
              user_id: "viewer-#{login}",
              user_login: login,
              user_input: user_input,
              redeemed_at: DateTime.utc_now(),
              status: "UNFULFILLED",
              delivered: false
            }

            {{:ok, redemption}, put_in(state, [:redemptions, redemption.id], redemption)}

          _ ->
            {{:error, :reward_unavailable}, state}
        end
      end)

    case result do
      {:ok, redemption} ->
        broadcast(broadcaster_id)
        if delay?, do: {:ok, redemption}, else: deliver(community, redemption.id)

      error ->
        error
    end
  end

  def deliver(community, redemption_id) do
    if enabled?(), do: do_deliver(community, redemption_id), else: {:error, :simulator_disabled}
  end

  defp do_deliver(community, redemption_id) do
    redemption = Agent.get(__MODULE__, &get_in(&1, [:redemptions, redemption_id]))

    if redemption && redemption.broadcaster_id == channel_id(community) do
      deliver_event(community, redemption)
    else
      {:error, :unknown_redemption}
    end
  end

  defp deliver_event(community, redemption) do
    body =
      Jason.encode!(%{
        "subscription" => %{"type" => @redemption_type},
        "event" => event_payload(redemption)
      })

    message_id = Ecto.UUID.generate()
    timestamp = DateTime.to_iso8601(DateTime.utc_now())

    signature =
      "sha256=" <>
        Base.encode16(
          :crypto.mac(
            :hmac,
            :sha256,
            community.twitch_eventsub_secret,
            message_id <> timestamp <> body
          ),
          case: :lower
        )

    conn =
      Task.async(fn ->
        Plug.Test.conn(:post, "/twitch/eventsub", body)
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Conn.put_req_header("twitch-eventsub-message-id", message_id)
        |> Plug.Conn.put_req_header("twitch-eventsub-message-timestamp", timestamp)
        |> Plug.Conn.put_req_header("twitch-eventsub-message-signature", signature)
        |> BacklogWheelWeb.Endpoint.call([])
      end)
      |> Task.await(10_000)

    if conn.status == 204 do
      update_state(&put_in(&1, [:redemptions, redemption.id, :delivered], true))
      broadcast(redemption.broadcaster_id)
      {:ok, redemption}
    else
      {:error, {:webhook_failed, conn.status}}
    end
  end

  defp event_payload(redemption) do
    %{
      "id" => redemption.id,
      "broadcaster_user_id" => redemption.broadcaster_id,
      "user_id" => redemption.user_id,
      "user_login" => redemption.user_login,
      "user_name" => redemption.user_login,
      "user_input" => redemption.user_input,
      "redeemed_at" => DateTime.to_iso8601(redemption.redeemed_at),
      "reward" => %{"id" => redemption.reward_id}
    }
  end

  def find_custom_reward(config, _credential, title) do
    Agent.get(__MODULE__, fn state ->
      reward =
        Enum.find(
          Map.values(state.rewards),
          &(&1.broadcaster_id == config.broadcaster_id and &1.title == title and not &1.deleted)
        )

      {:ok, reward && remote_reward(reward)}
    end)
  end

  def create_custom_reward(config, _credential, attrs) do
    reward = %{
      id: Ecto.UUID.generate(),
      broadcaster_id: config.broadcaster_id,
      voting_session_id: attrs.voting_session_id,
      title: attrs.title,
      cost: attrs.cost,
      enabled: attrs.is_enabled,
      deleted: false
    }

    result =
      get_and_update_state(fn state ->
        if failing?(state, config.broadcaster_id, "creation") do
          {{:error, :simulated_creation_failure}, state}
        else
          {{:ok, remote_reward(reward)}, put_in(state, [:rewards, reward.id], reward)}
        end
      end)

    broadcast(reward.broadcaster_id)
    result
  end

  def set_reward_enabled(config, _credential, reward_id, enabled) do
    result =
      get_and_update_state(fn state ->
        case {failing?(state, config.broadcaster_id, "disable") and not enabled,
              state.rewards[reward_id]} do
          {true, _} ->
            {{:error, :simulated_disable_failure}, state}

          {false, %{broadcaster_id: id, deleted: false} = reward}
          when id == config.broadcaster_id ->
            {:ok, put_in(state, [:rewards, reward_id], %{reward | enabled: enabled})}

          _ ->
            {{:error, {:twitch_http_error, 404, %{}}}, state}
        end
      end)

    if result == :ok, do: broadcast(config.broadcaster_id)
    result
  end

  def delete_custom_reward(config, _credential, reward_id) do
    result =
      get_and_update_state(fn state ->
        case {failing?(state, config.broadcaster_id, "deletion"), state.rewards[reward_id]} do
          {true, _} ->
            {{:error, :simulated_deletion_failure}, state}

          {false, %{broadcaster_id: id, deleted: false} = reward}
          when id == config.broadcaster_id ->
            {:ok,
             state
             |> put_in([:rewards, reward_id], %{reward | enabled: false, deleted: true})
             |> Map.put(:redemptions, fulfill_deleted_reward(state.redemptions, reward_id))}

          _ ->
            {{:error, {:twitch_http_error, 404, %{}}}, state}
        end
      end)

    if result == :ok, do: broadcast(config.broadcaster_id)
    result
  end

  defp fulfill_deleted_reward(redemptions, reward_id) do
    Map.new(redemptions, fn {id, redemption} ->
      if redemption.reward_id == reward_id and redemption.status == "UNFULFILLED",
        do: {id, %{redemption | status: "FULFILLED"}},
        else: {id, redemption}
    end)
  end

  def list_unfulfilled_redemptions(config, _credential, reward_id) do
    Agent.get(__MODULE__, fn state ->
      case {failing?(state, config.broadcaster_id, "reconciliation"), state.rewards[reward_id]} do
        {true, _} ->
          {:error, :simulated_reconciliation_failure}

        {false, %{broadcaster_id: id, deleted: false}} when id == config.broadcaster_id ->
          events =
            state.redemptions
            |> Map.values()
            |> Enum.filter(&(&1.reward_id == reward_id and &1.status == "UNFULFILLED"))
            |> Enum.map(&event_payload/1)

          {:ok, events}

        _ ->
          {:error, {:twitch_http_error, 404, %{}}}
      end
    end)
  end

  def update_redemption(config, _credential, reward_id, redemption_id, status) do
    result =
      get_and_update_state(fn state ->
        case {failing?(state, config.broadcaster_id, "resolution"),
              state.redemptions[redemption_id]} do
          {true, _} ->
            {{:error, :simulated_resolution_failure}, state}

          {false,
           %{broadcaster_id: id, reward_id: ^reward_id, status: "UNFULFILLED"} = redemption}
          when id == config.broadcaster_id and status in ["CANCELED", "FULFILLED"] ->
            {:ok, put_in(state, [:redemptions, redemption_id], %{redemption | status: status})}

          _ ->
            {{:error, {:twitch_http_error, 400, %{}}}, state}
        end
      end)

    if result == :ok, do: broadcast(config.broadcaster_id)
    result
  end

  def get_redemption_status(config, _credential, reward_id, redemption_id) do
    Agent.get(__MODULE__, fn state ->
      case state.redemptions[redemption_id] do
        %{broadcaster_id: id, reward_id: ^reward_id, status: status}
        when id == config.broadcaster_id ->
          {:ok, status}

        _ ->
          {:error, {:twitch_http_error, 404, %{}}}
      end
    end)
  end

  def send_chat_message(config, _credential, text) do
    message = %{id: Ecto.UUID.generate(), broadcaster_id: config.broadcaster_id, text: text}

    result =
      get_and_update_state(fn state ->
        if failing?(state, config.broadcaster_id, "chat"),
          do: {{:error, :simulated_chat_failure}, state},
          else: {:ok, Map.update!(state, :messages, fn messages -> [message | messages] end)}
      end)

    if result == :ok, do: broadcast(config.broadcaster_id)
    result
  end

  def exchange_code(_config, _code, _redirect_uri), do: {:error, :use_simulator_connect}

  def authorize_url(_config, redirect_uri, _state) do
    redirect_uri
    |> URI.parse()
    |> Map.put(:path, "/dev/twitch-simulator")
    |> Map.put(:query, nil)
    |> URI.to_string()
  end

  def fetch_current_user(_config, _credential), do: {:error, :use_simulator_connect}
  def refresh_access_token(_config, _credential), do: {:error, :use_simulator_connect}

  def create_redemption_eventsub_subscription(_config, _credential, _callback_url, _secret),
    do: {:ok, %{id: "simulated-subscription", status: "enabled", type: @redemption_type}}

  defp remote_reward(reward) do
    %{
      id: reward.id,
      title: reward.title,
      cost: reward.cost,
      status: if(reward.enabled, do: "enabled", else: "disabled")
    }
  end

  defp topic(id), do: "twitch-simulator:#{id}"

  defp broadcast(id),
    do: Phoenix.PubSub.broadcast(BacklogWheel.PubSub, topic(id), :simulator_updated)

  def connect(community) do
    if enabled?(), do: do_connect(community), else: {:error, :simulator_disabled}
  end

  defp do_connect(community) do
    Repo.transaction(fn ->
      with {:ok, community} <-
             Communities.update_community_twitch_settings(community, %{
               twitch_broadcaster_id: channel_id(community),
               twitch_broadcaster_login: "simulated_channel_#{community.id}",
               twitch_broadcaster_display_name: "Simulated Channel",
               twitch_eventsub_secret:
                 Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
             }),
           {:ok, _} <-
             Twitch.save_credential(community, %{
               access_token: "simulated-token",
               scopes: "channel:manage:redemptions user:write:chat"
             }) do
        community
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def create_sample_vote(community) do
    if enabled?(), do: do_create_sample_vote(community), else: {:error, :simulator_disabled}
  end

  defp do_create_sample_vote(community) do
    Repo.transaction(fn ->
      games =
        for {title, external_id} <- [
              {"Celestial Cartographer", "simulator-one"},
              {"Mossy Hollow", "simulator-two"},
              {"Neon Drift", "simulator-three"}
            ] do
          sample_game(community, title, external_id)
        end

      case Voting.create_voting_session(community, %{title: "Simulator sample vote"}) do
        {:ok, session} ->
          add_sample_games(session, games)
          session

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  defp add_sample_games(session, games) do
    Enum.each(games, fn game ->
      case Voting.add_game_to_session(session, game) do
        {:ok, _} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp sample_game(community, title, external_id) do
    Repo.get_by(Game, community_id: community.id, platform: "simulator", external_id: external_id) ||
      case Backlog.create_game(community, %{
             title: title,
             platform: "simulator",
             external_id: external_id,
             include_in_wheel: true
           }) do
        {:ok, game} -> game
        {:error, reason} -> Repo.rollback(reason)
      end
  end

  defp enabled?, do: Application.get_env(:backlog_wheel, :twitch_simulator, false) == true
end
