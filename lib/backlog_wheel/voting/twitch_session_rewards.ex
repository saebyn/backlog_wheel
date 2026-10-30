defmodule BacklogWheel.Voting.TwitchSessionRewards do
  @moduledoc """
  Creates and enables one input-required reward for each voting session.
  """
  import Ecto.Query

  alias BacklogWheel.Repo
  alias BacklogWheel.Twitch
  alias BacklogWheel.Voting

  alias BacklogWheel.Voting.{
    TwitchVotingRedemption,
    TwitchVotingReward,
    TwitchVotingWindow,
    VotingSession
  }

  def start(session, opts \\ []) do
    client = Keyword.get(opts, :client, Twitch.client())
    session = Repo.preload(session, :community)

    with :ok <- Voting.validate_twitch_reward_creation(session),
         {:ok, config} <- Twitch.config(session.community),
         {:ok, credential} <- credential(session.community, config, client),
         {:ok, session} <- Voting.update_voting_session_status(session, "open"),
         {:ok, reward} <- ensure_reward(session, config, credential, client),
         {:ok, reward} <- update_reward(reward, %{status: "enabling", cleanup_error: nil}),
         {:ok, _reward} <- enable_reward(session, reward, config, credential, client) do
      broadcast_change(session.id)
      {:ok, Voting.get_voting_session!(session.community, session.id)}
    end
  end

  defp enable_reward(session, reward, config, credential, client) do
    Repo.transaction(fn ->
      current =
        VotingSession |> where([s], s.id == ^session.id) |> lock("FOR UPDATE") |> Repo.one!()

      if current.status != "open", do: Repo.rollback(:voting_not_open)

      with :ok <- client.set_reward_enabled(config, credential, reward.reward_id, true),
           {:ok, reward} <- update_reward(reward, %{status: "enabled", cleanup_error: nil}) do
        reward
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def stop(session, opts \\ []) do
    client = Keyword.get(opts, :client, Twitch.client())
    session = Repo.preload(session, :community)

    case Repo.get_by(TwitchVotingReward, voting_session_id: session.id) do
      nil -> {:error, :no_twitch_rewards}
      %{status: status} when status in ["disabled", "deleted"] -> {:error, :no_twitch_rewards}
      reward -> disable(session, reward, client)
    end
  end

  def cleanup_finished(opts \\ []) do
    client = Keyword.get(opts, :client, Twitch.client())

    ids =
      from(reward in TwitchVotingReward,
        join: session in VotingSession,
        on: session.id == reward.voting_session_id,
        where:
          session.status in ["completed", "closed", "cancelled"] and reward.status != "deleted",
        select: session.id
      )
      |> Repo.all()

    Enum.each(ids, &cleanup_session(&1, client))
    :ok
  end

  def mark_missing_reward(session, reward) do
    result =
      Repo.transaction(fn ->
        session =
          VotingSession |> where([s], s.id == ^session.id) |> lock("FOR UPDATE") |> Repo.one!()

        reward = Repo.get!(TwitchVotingReward, reward.id)

        if session.status in ["completed", "closed", "cancelled"] and reward.status != "deleted" and
             not unresolved_redemptions?(reward) do
          {:ok, _} = mark_deleted(reward)
          :ok
        else
          Repo.rollback(:unresolved_redemptions)
        end
      end)

    case result do
      {:ok, :ok} ->
        broadcast_change(session.id)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cleanup_session(id, client) do
    result =
      Repo.transaction(fn ->
        session =
          VotingSession
          |> where([s], s.id == ^id)
          |> lock("FOR UPDATE")
          |> Repo.one!()
          |> Repo.preload(:community)

        reward = Repo.get_by!(TwitchVotingReward, voting_session_id: id)

        if session.status in ["completed", "closed", "cancelled"] and reward.status != "deleted" do
          cleanup_reward(session, reward, client)
        end
      end)

    if match?({:ok, _}, result), do: broadcast_change(id)
  end

  defp cleanup_reward(session, reward, client) do
    with {:ok, reward} <- ensure_disabled(session, reward, client),
         false <- unresolved_redemptions?(reward),
         {:ok, config} <- Twitch.config(session.community),
         {:ok, credential} <- credential(session.community, config, client) do
      cleanup_drained_reward(reward, config, credential, client)
    else
      true -> :pending
      {:error, reason} -> update_reward(reward, %{cleanup_error: inspect(reason)})
    end
  end

  defp ensure_disabled(_session, %{status: "disabled"} = reward, _client), do: {:ok, reward}

  defp ensure_disabled(session, reward, client) do
    case disable(session, reward, client) do
      {:ok, session} -> {:ok, session.twitch_voting_reward}
      {:error, reason} -> {:error, reason}
    end
  end

  defp unresolved_redemptions?(reward) do
    Repo.exists?(
      from redemption in TwitchVotingRedemption,
        where:
          redemption.twitch_voting_reward_id == ^reward.id and
            redemption.resolution_status != "done"
    )
  end

  defp cleanup_drained_reward(reward, config, credential, client) do
    case client.list_unfulfilled_redemptions(config, credential, reward.reward_id) do
      {:ok, []} -> delete_drained_reward(reward, config, credential, client)
      {:ok, _events} -> :pending
      {:error, {:twitch_http_error, 404, _}} -> mark_deleted(reward)
      {:error, reason} -> update_reward(reward, %{cleanup_error: inspect(reason)})
    end
  end

  defp delete_drained_reward(reward, config, credential, client) do
    case client.delete_custom_reward(config, credential, reward.reward_id) do
      :ok -> mark_deleted(reward)
      {:error, {:twitch_http_error, 404, _}} -> mark_deleted(reward)
      {:error, reason} -> update_reward(reward, %{cleanup_error: inspect(reason)})
    end
  end

  defp mark_deleted(reward) do
    with {:ok, reward} <-
           update_reward(reward, %{
             status: "deleted",
             cleanup_error: nil,
             reconciliation_error: nil
           }) do
      now = DateTime.utc_now()

      from(window in TwitchVotingWindow,
        where:
          window.voting_session_id == ^reward.voting_session_id and not is_nil(window.closed_at) and
            is_nil(window.reconciled_at)
      )
      |> Repo.update_all(set: [reconciled_at: now, updated_at: now])

      {:ok, reward}
    end
  end

  defp disable(session, reward, client) do
    result =
      with {:ok, config} <- Twitch.config(session.community),
           {:ok, credential} <- credential(session.community, config, client),
           :ok <- client.set_reward_enabled(config, credential, reward.reward_id, false) do
        update_reward(reward, %{status: "disabled", cleanup_error: nil})
      end

    case result do
      {:ok, _reward} ->
        broadcast_change(session.id)
        {:ok, Voting.get_voting_session!(session.community, session.id)}

      {:error, reason} ->
        update_reward(reward, %{cleanup_error: inspect(reason)})
        broadcast_change(session.id)
        {:error, reason}
    end
  end

  defp ensure_reward(session, config, credential, client) do
    Repo.transaction(fn ->
      VotingSession |> where([s], s.id == ^session.id) |> lock("FOR UPDATE") |> Repo.one!()

      case Repo.get_by(TwitchVotingReward, voting_session_id: session.id) do
        nil ->
          create_reward(session, nil, config, credential, client)

        %{status: "deleted"} = reward ->
          create_reward(session, reward, config, credential, client)

        reward ->
          reward
      end
    end)
  end

  defp create_reward(session, previous_reward, config, credential, client) do
    title = "Backlog Wheel Vote #{session.id}"

    result =
      with {:ok, existing} <- client.find_custom_reward(config, credential, title) do
        if existing do
          {:ok, existing}
        else
          client.create_custom_reward(config, credential, %{
            voting_session_id: session.id,
            title: title,
            cost: config.reward_cost,
            prompt: "Enter the number of the game you want to vote for.",
            is_enabled: false,
            is_user_input_required: true,
            should_redemptions_skip_request_queue: false
          })
        end
      end

    case result do
      {:ok, remote} ->
        (previous_reward || %TwitchVotingReward{voting_session_id: session.id})
        |> TwitchVotingReward.changeset(%{
          reward_id: remote.id,
          title: remote.title,
          cost: remote.cost,
          status: "disabled",
          cleanup_error: nil,
          reconciliation_error: nil
        })
        |> Repo.insert_or_update!()

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp update_reward(reward, attrs),
    do: reward |> TwitchVotingReward.changeset(attrs) |> Repo.update()

  defp broadcast_change(id),
    do:
      Phoenix.PubSub.broadcast(
        BacklogWheel.PubSub,
        "voting_session:#{id}",
        {:voting_session_changed, id}
      )

  defp credential(community, config, client) do
    case Twitch.get_credential(community) do
      nil -> {:error, :missing_twitch_credential}
      %{refresh_token: token} = credential when token in [nil, ""] -> {:ok, credential}
      _credential -> Twitch.refresh_credential(community, config, client)
    end
  end
end
