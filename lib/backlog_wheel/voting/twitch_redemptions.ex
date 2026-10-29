defmodule BacklogWheel.Voting.TwitchRedemptions do
  @moduledoc """
  Persists Twitch redemption decisions and retries their remote resolution.
  """

  import Ecto.Query
  require Logger

  alias BacklogWheel.Repo
  alias BacklogWheel.Twitch
  alias BacklogWheel.Voting

  alias BacklogWheel.Voting.{
    TwitchVotingRedemption,
    TwitchVotingReward,
    VotingSession,
    VotingSessionGame
  }

  def ingest(
        %{
          "id" => id,
          "reward" => %{"id" => reward_id},
          "user_id" => user_id,
          "user_login" => login
        } = event
      )
      when is_binary(id) and id != "" and is_binary(user_id) and user_id != "" and
             is_binary(login) and login != "" do
    case Repo.get_by(TwitchVotingReward, reward_id: reward_id) do
      nil -> {:ignored, :unknown_twitch_reward}
      reward -> persist_decision(reward, id, user_id, login, event["user_input"])
    end
  end

  def ingest(_event), do: {:error, :invalid_twitch_redemption}

  defp persist_decision(reward, id, user_id, login, input) do
    result =
      Repo.transaction(fn ->
        session =
          VotingSession
          |> where([session], session.id == ^reward.voting_session_id)
          |> lock("FOR UPDATE")
          |> Repo.one!()

        case Repo.get_by(TwitchVotingRedemption, redemption_id: id) do
          %TwitchVotingRedemption{} = existing -> existing
          nil -> create_decision(session, reward, id, user_id, login, input)
        end
      end)

    if match?({:ok, _}, result) do
      Phoenix.PubSub.broadcast(
        BacklogWheel.PubSub,
        "voting_session:#{reward.voting_session_id}",
        {:voting_session_changed, reward.voting_session_id}
      )
    end

    result
  end

  defp create_decision(session, reward, id, user_id, login, input) do
    pool_item = matching_pool_item(session, input)
    valid? = session.status == "open" and not is_nil(pool_item)

    if valid? do
      case Voting.record_vote(pool_item, %{
             strength: 1,
             source: "twitch_channel_points",
             external_event_id: id
           }) do
        {:ok, _vote} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    end

    %TwitchVotingRedemption{twitch_voting_reward_id: reward.id}
    |> TwitchVotingRedemption.changeset(%{
      redemption_id: id,
      user_id: user_id,
      user_login: login,
      decision: if(valid?, do: "valid", else: "invalid"),
      feedback_status: if(valid?, do: "not_needed", else: "pending")
    })
    |> Repo.insert!()
  end

  defp matching_pool_item(session, input) when is_binary(input) do
    case Integer.parse(String.trim(input)) do
      {number, ""} when number > 0 and number <= 2_147_483_647 ->
        Repo.get_by(VotingSessionGame, voting_session_id: session.id, option_number: number)

      _ ->
        nil
    end
  end

  defp matching_pool_item(_session, _input), do: nil

  def failed_count(%VotingSession{id: id}) do
    TwitchVotingRedemption
    |> join(:inner, [redemption], reward in TwitchVotingReward,
      on: reward.id == redemption.twitch_voting_reward_id
    )
    |> where(
      [redemption, reward],
      reward.voting_session_id == ^id and not is_nil(redemption.last_error)
    )
    |> Repo.aggregate(:count)
  end

  def failed_count(nil), do: 0

  @doc """
  Recovers unfulfilled redemptions when EventSub delivery is delayed or unavailable.
  """
  def reconcile_rewards(client \\ Twitch.client()) do
    TwitchVotingReward
    |> Repo.all()
    |> Enum.each(&reconcile_reward(&1, client))
  end

  defp reconcile_reward(reward, client) do
    session = Repo.get!(VotingSession, reward.voting_session_id) |> Repo.preload(:community)

    result =
      with {:ok, config} <- Twitch.config(session.community),
           {:ok, credential} <- credential(session.community, config, client),
           {:ok, events} <-
             client.list_unfulfilled_redemptions(config, credential, reward.reward_id) do
        ingest_reconciled(events, reward.reward_id)
      end

    error =
      case result do
        :ok -> nil
        {:error, reason} -> inspect(reason)
      end

    if reward.reconciliation_error != error do
      reward |> TwitchVotingReward.changeset(%{reconciliation_error: error}) |> Repo.update!()

      Phoenix.PubSub.broadcast(
        BacklogWheel.PubSub,
        "voting_session:#{session.id}",
        {:voting_session_changed, session.id}
      )
    end
  end

  defp ingest_reconciled(events, reward_id) do
    Enum.reduce_while(events, :ok, fn event, :ok ->
      case ingest(Map.put(event, "reward", %{"id" => reward_id})) do
        {:ok, _redemption} -> {:cont, :ok}
        other -> {:halt, {:error, other}}
      end
    end)
  end

  def process_pending(client \\ Twitch.client()) do
    ids =
      TwitchVotingRedemption
      |> where(
        [redemption],
        redemption.resolution_status == "pending" or redemption.feedback_status == "pending"
      )
      |> order_by([redemption], asc: redemption.updated_at, asc: redemption.id)
      |> limit(100)
      |> select([redemption], redemption.id)
      |> Repo.all()

    Enum.each(ids, &process_one(&1, client))
  end

  defp process_one(id, client) do
    result =
      Repo.transaction(fn ->
        redemption =
          TwitchVotingRedemption
          |> where([redemption], redemption.id == ^id)
          |> lock("FOR UPDATE SKIP LOCKED")
          |> Repo.one()

        if redemption, do: process_locked(redemption, client)
      end)

    case result do
      {:ok, session_id} when is_integer(session_id) ->
        Phoenix.PubSub.broadcast(
          BacklogWheel.PubSub,
          "voting_session:#{session_id}",
          {:voting_session_changed, session_id}
        )

      _ ->
        :ok
    end
  rescue
    exception ->
      Logger.error("Twitch redemption retry crashed id=#{id}: #{Exception.message(exception)}")
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      from(redemption in TwitchVotingRedemption, where: redemption.id == ^id)
      |> Repo.update_all(set: [last_error: Exception.message(exception), updated_at: now])

      session_id =
        from(redemption in TwitchVotingRedemption,
          join: reward in TwitchVotingReward,
          on: reward.id == redemption.twitch_voting_reward_id,
          where: redemption.id == ^id,
          select: reward.voting_session_id
        )
        |> Repo.one()

      if session_id do
        Phoenix.PubSub.broadcast(
          BacklogWheel.PubSub,
          "voting_session:#{session_id}",
          {:voting_session_changed, session_id}
        )
      end
  end

  defp process_locked(redemption, client) do
    reward = Repo.get!(TwitchVotingReward, redemption.twitch_voting_reward_id)
    session = Repo.get!(VotingSession, reward.voting_session_id) |> Repo.preload(:community)

    result =
      with {:ok, config} <- Twitch.config(session.community),
           {:ok, credential} <- credential(session.community, config, client) do
        resolve(redemption, reward, config, credential, client)
      end

    attrs =
      case result do
        {:ok, attrs} -> attrs
        {:error, reason} -> %{last_error: inspect(reason)}
      end

    redemption |> TwitchVotingRedemption.changeset(attrs) |> Repo.update!()
    session.id
  end

  defp credential(community, config, client) do
    case Twitch.get_credential(community) do
      nil -> {:error, :missing_twitch_credential}
      %{expires_at: nil} = credential -> {:ok, credential}
      credential -> maybe_refresh_credential(credential, community, config, client)
    end
  end

  defp maybe_refresh_credential(credential, community, config, client) do
    if DateTime.compare(credential.expires_at, DateTime.add(DateTime.utc_now(), 60, :second)) ==
         :gt do
      {:ok, credential}
    else
      Twitch.refresh_credential(community, config, client)
    end
  end

  defp resolve(redemption, reward, config, credential, client) do
    desired = if redemption.decision == "valid", do: "FULFILLED", else: "CANCELED"

    with :ok <- ensure_resolution(redemption, reward, desired, config, credential, client) do
      send_feedback(redemption, config, credential, client)
    end
  end

  defp send_feedback(%{feedback_status: "pending"} = redemption, config, credential, client) do
    message =
      "@#{redemption.user_login} Your vote was invalid or voting has closed. Your points were refunded; enter a current game number to vote."

    case client.send_chat_message(config, credential, message) do
      :ok -> {:ok, %{resolution_status: "done", feedback_status: "done", last_error: nil}}
      {:error, reason} -> {:ok, %{resolution_status: "done", last_error: inspect(reason)}}
    end
  end

  defp send_feedback(_redemption, _config, _credential, _client),
    do: {:ok, %{resolution_status: "done", last_error: nil}}

  defp ensure_resolution(
         %{resolution_status: "done"},
         _reward,
         _desired,
         _config,
         _credential,
         _client
       ),
       do: :ok

  defp ensure_resolution(redemption, reward, desired, config, credential, client) do
    case client.update_redemption(
           config,
           credential,
           reward.reward_id,
           redemption.redemption_id,
           desired
         ) do
      :ok ->
        :ok

      {:error, reason} ->
        case client.get_redemption_status(
               config,
               credential,
               reward.reward_id,
               redemption.redemption_id
             ) do
          {:ok, ^desired} -> :ok
          _ -> {:error, reason}
        end
    end
  end
end
