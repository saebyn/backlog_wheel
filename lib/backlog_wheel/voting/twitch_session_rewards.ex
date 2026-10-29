defmodule BacklogWheel.Voting.TwitchSessionRewards do
  @moduledoc """
  Creates and enables one input-required reward for each voting session.
  """
  import Ecto.Query

  alias BacklogWheel.Repo
  alias BacklogWheel.Twitch
  alias BacklogWheel.Voting
  alias BacklogWheel.Voting.{TwitchVotingReward, VotingSession}

  def start(session, opts \\ []) do
    client = Keyword.get(opts, :client, Twitch.client())
    session = Repo.preload(session, :community)

    with :ok <- Voting.validate_twitch_reward_creation(session),
         {:ok, config} <- Twitch.config(session.community),
         {:ok, credential} <- credential(config, client),
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
      %{status: "disabled"} -> {:error, :no_twitch_rewards}
      reward -> disable(session, reward, client)
    end
  end

  defp disable(session, reward, client) do
    result =
      with {:ok, config} <- Twitch.config(session.community),
           {:ok, credential} <- credential(config, client),
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
        nil -> create_reward(session, config, credential, client)
        reward -> reward
      end
    end)
  end

  defp create_reward(session, config, credential, client) do
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
        %TwitchVotingReward{voting_session_id: session.id}
        |> TwitchVotingReward.changeset(%{
          reward_id: remote.id,
          title: remote.title,
          cost: remote.cost,
          status: "disabled"
        })
        |> Repo.insert!()

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

  defp credential(config, client) do
    case Twitch.get_credential() do
      nil -> {:error, :missing_twitch_credential}
      %{refresh_token: token} = credential when token in [nil, ""] -> {:ok, credential}
      _credential -> Twitch.refresh_credential(config, client)
    end
  end
end
