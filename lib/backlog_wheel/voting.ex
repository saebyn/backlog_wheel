defmodule BacklogWheel.Voting do
  @moduledoc """
  The Voting context.
  """

  import Ecto.Query, warn: false

  alias BacklogWheel.Backlog.Game
  alias BacklogWheel.Backlog
  alias BacklogWheel.Communities
  alias BacklogWheel.Communities.Community
  alias BacklogWheel.Repo

  alias BacklogWheel.Voting.{
    ChannelPointVote,
    TwitchVotingWindow,
    Viewer,
    ViewerIdentity,
    VotingSession,
    VotingSessionGame,
    WheelFormat
  }

  @default_wheel_formats [
    %{
      name: "Backlog buster",
      description: "Surface wheel-eligible games with less than one hour recorded playtime.",
      default_session_title: "Backlog Buster Vote",
      default_session_description: "A vote focused on barely-started or untouched backlog games.",
      is_default: true,
      candidate_rules: %{"include_in_wheel" => true, "max_playtime_minutes" => 59},
      weighting_rules: %{"base_weight" => 1, "intent" => "under_one_hour"}
    },
    %{
      name: "Fresh backlog",
      description: "Prioritize games that have never been played on stream.",
      default_session_title: "Fresh Backlog Vote",
      default_session_description: "A vote focused on games that have not had stream time yet.",
      is_default: true,
      candidate_rules: %{"include_in_wheel" => true, "played_on_stream" => false},
      weighting_rules: %{"base_weight" => 2, "intent" => "favor_unplayed"}
    },
    %{
      name: "Keep the streak alive",
      description:
        "Favor recent winners or recent stream games, with room to cool down long streaks.",
      default_session_title: "Streak Vote",
      default_session_description:
        "A vote for continuing momentum without letting one game dominate forever.",
      is_default: true,
      candidate_rules: %{"include_in_wheel" => true},
      weighting_rules: %{
        "base_weight" => 1,
        "favor_recent_activity" => true,
        "cooldown_long_streaks" => true
      }
    },
    %{
      name: "Chaos night",
      description: "Use the broad wheel pool with minimal filtering.",
      default_session_title: "Chaos Night Vote",
      default_session_description: "A wide-open vote from the current wheel-eligible backlog.",
      is_default: true,
      candidate_rules: %{"include_in_wheel" => true},
      weighting_rules: %{"base_weight" => 1, "intent" => "minimal_filtering"}
    }
  ]

  @pubsub BacklogWheel.PubSub
  @spin_duration_ms 30_000
  @spin_full_turns 12
  @landing_edge_inset_ratio 0.25
  @landing_edge_inset_degrees 18.0
  @voting_session_pool_min_size 2
  @spin_easing_profile %{
    "type" => "cubic-bezier",
    "x1" => 0.08,
    "y1" => 0.72,
    "x2" => 0.12,
    "y2" => 1.0
  }

  @doc """
  Subscribes the caller to updates for a voting session.
  """
  def subscribe_to_voting_session(%VotingSession{id: id}), do: subscribe_to_voting_session(id)

  def subscribe_to_voting_session(id) when is_integer(id) do
    Phoenix.PubSub.subscribe(@pubsub, voting_session_topic(id))
  end

  @doc """
  Unsubscribes the caller from updates for a voting session.
  """
  def unsubscribe_from_voting_session(nil), do: :ok

  def unsubscribe_from_voting_session(%VotingSession{id: id}),
    do: unsubscribe_from_voting_session(id)

  def unsubscribe_from_voting_session(id) when is_integer(id) do
    Phoenix.PubSub.unsubscribe(@pubsub, voting_session_topic(id))
  end

  @doc """
  Returns voting sessions for a community.
  """
  def list_voting_sessions(%Community{} = community) do
    VotingSession
    |> where([session], session.community_id == ^community.id)
    |> order_by([session], desc: session.inserted_at, desc: session.id)
    |> Repo.all()
    |> preload_pool_games_with_votes()
  end

  @doc """
  Returns enabled Wheel Formats for a community.
  """
  def list_wheel_formats(%Community{} = community) do
    WheelFormat
    |> where([format], format.community_id == ^community.id)
    |> where([format], format.is_enabled)
    |> order_by([format], asc: format.name)
    |> Repo.all()
  end

  @doc """
  Returns all Wheel Formats for a community, including disabled formats.
  """
  def list_all_wheel_formats(%Community{} = community) do
    WheelFormat
    |> where([format], format.community_id == ^community.id)
    |> order_by([format], asc: format.is_default, asc: format.name)
    |> Repo.all()
  end

  @doc """
  Returns the newest draft/open/locked voting session for a community.
  """
  def active_voting_session(%Community{} = community) do
    VotingSession
    |> where([session], session.community_id == ^community.id)
    |> where([session], session.status in ["draft", "open", "locked"])
    |> order_by([session], desc: session.inserted_at, desc: session.id)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> nil
      session -> preload_pool_games_with_votes(session)
    end
  end

  @doc """
  Gets a community Wheel Format.
  """
  def get_wheel_format!(%Community{} = community, id) do
    Repo.get_by!(WheelFormat, id: id, community_id: community.id)
  end

  @doc """
  Creates a Wheel Format for a community.
  """
  def create_wheel_format(%Community{} = community, attrs) do
    %WheelFormat{community_id: community.id}
    |> WheelFormat.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns a Wheel Format changeset.
  """
  def change_wheel_format(%WheelFormat{} = wheel_format, attrs \\ %{}) do
    WheelFormat.changeset(wheel_format, attrs)
  end

  @doc """
  Returns games matching a Wheel Format's candidate rules.
  """
  def list_wheel_format_candidate_games(%Community{} = community, %WheelFormat{} = wheel_format) do
    community
    |> wheel_format_candidate_query(wheel_format)
    |> order_by([game], asc: game.title)
    |> Repo.all()
  end

  @doc """
  Counts games matching a Wheel Format's candidate rules.
  """
  def count_wheel_format_candidate_games(%Community{} = community, %WheelFormat{} = wheel_format) do
    community
    |> wheel_format_candidate_query(wheel_format)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Updates a community Wheel Format.
  """
  def update_wheel_format(%Community{} = community, %WheelFormat{} = wheel_format, attrs) do
    if wheel_format.community_id == community.id do
      wheel_format
      |> WheelFormat.changeset(attrs)
      |> Repo.update()
    else
      {:error, :wheel_format_not_in_community}
    end
  end

  @doc """
  Deletes a custom Wheel Format while protecting seeded defaults.
  """
  def delete_wheel_format(%Community{} = community, %WheelFormat{} = wheel_format) do
    cond do
      wheel_format.community_id != community.id ->
        {:error, :wheel_format_not_in_community}

      wheel_format.is_default ->
        {:error, :default_wheel_format_protected}

      true ->
        Repo.delete(wheel_format)
    end
  end

  @doc """
  Seeds the default Wheel Formats for a community if they do not exist yet.
  """
  def ensure_default_wheel_formats(%Community{} = community) do
    formats =
      Enum.map(@default_wheel_formats, fn attrs ->
        Repo.get_by(WheelFormat, community_id: community.id, name: attrs.name) ||
          %WheelFormat{community_id: community.id}
          |> WheelFormat.changeset(attrs)
          |> Repo.insert!()
      end)

    {:ok, formats}
  end

  @doc """
  Gets a voting session with its game pool.
  """
  def get_voting_session!(%Community{} = community, id) do
    VotingSession
    |> Repo.get_by!(id: id, community_id: community.id)
    |> Repo.preload(:community)
    |> preload_pool_games_with_votes()
  end

  @doc """
  Creates a voting session for a community.
  """
  def create_voting_session(%Community{} = community, attrs \\ %{}) do
    Repo.transaction(fn ->
      case %VotingSession{community_id: community.id}
           |> VotingSession.changeset(attrs)
           |> Repo.insert() do
        {:ok, session} ->
          open_initial_window(session)

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp open_initial_window(%VotingSession{status: "open"} = session) do
    update_voting_window(session, "open", DateTime.utc_now())
    session
  end

  defp open_initial_window(session), do: session

  @doc """
  Creates a voting session from a Wheel Format and populates its initial game pool.
  """
  def create_voting_session_from_wheel_format(
        %Community{} = community,
        %WheelFormat{} = wheel_format
      ) do
    if wheel_format.community_id == community.id do
      Repo.transaction(fn ->
        {:ok, session} =
          create_voting_session(community, %{
            wheel_format_id: wheel_format.id,
            title: wheel_format.default_session_title,
            description: wheel_format.default_session_description
          })

        {:ok, _pool_items} = populate_session_from_wheel_format(session, wheel_format)
        session
      end)
    else
      {:error, :wheel_format_not_in_community}
    end
  end

  @doc """
  Updates a voting session status.
  """
  def update_voting_session_status(%VotingSession{} = voting_session, status)
      when is_binary(status) do
    with :ok <- validate_status_transition(voting_session, status) do
      transition_session(voting_session, status)
      |> broadcast_voting_session_change()
    end
  end

  defp transition_session(voting_session, status, allowed_statuses \\ nil) do
    Repo.transaction(fn ->
      session =
        VotingSession
        |> where([s], s.id == ^voting_session.id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      if allowed_statuses && session.status not in allowed_statuses,
        do: Repo.rollback(:session_not_ready)

      prepare_next_round!(session, status)
      now = DateTime.utc_now()
      update_voting_window(session, status, now)

      case session |> VotingSession.changeset(%{status: status}) |> Repo.update() do
        {:ok, session} -> Repo.preload(session, :community)
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp prepare_next_round!(%VotingSession{status: previous} = session, status)
       when previous in ["completed", "closed", "cancelled"] and status in ["open", "draft"] do
    reward = Repo.get_by(BacklogWheel.Voting.TwitchVotingReward, voting_session_id: session.id)
    if reward && reward.status != "deleted", do: Repo.rollback(:twitch_cleanup_pending)

    from(vote in ChannelPointVote,
      join: game in VotingSessionGame,
      on: game.id == vote.voting_session_game_id,
      where: game.voting_session_id == ^session.id
    )
    |> Repo.delete_all()
  end

  defp prepare_next_round!(_session, _status), do: :ok

  defp update_voting_window(session, "open", now) do
    active =
      from(window in TwitchVotingWindow,
        where: window.voting_session_id == ^session.id and is_nil(window.closed_at)
      )

    unless Repo.exists?(active) do
      Repo.insert!(%TwitchVotingWindow{voting_session_id: session.id, opened_at: now})
    end
  end

  defp update_voting_window(session, _status, now) do
    from(window in TwitchVotingWindow,
      where: window.voting_session_id == ^session.id and is_nil(window.closed_at)
    )
    |> Repo.update_all(set: [closed_at: now, updated_at: now])
  end

  @doc """
  Checks whether a voting session has a practical game pool size for opening.
  """
  def validate_voting_session_pool_size(%VotingSession{} = voting_session) do
    voting_session = reload_voting_session!(voting_session)
    pool_size = length(voting_session.voting_session_games)

    if pool_size < @voting_session_pool_min_size do
      {:error, {:voting_session_pool_too_small, pool_size, @voting_session_pool_min_size}}
    else
      :ok
    end
  end

  @doc """
  Changes the session status and attempts to disable its Twitch reward.
  """
  def close_voting_session(%VotingSession{} = voting_session, status, opts \\ [])
      when status in ["draft", "locked", "completed", "closed", "cancelled"] do
    with {:ok, session} <- update_voting_session_status(voting_session, status) do
      case remove_twitch_rewards(session, opts) do
        {:ok, session} ->
          reconcile_before_draft(session, status, opts)

        {:error, :no_twitch_rewards} ->
          reconcile_before_draft(reload_voting_session!(session), status, opts)

        {:error, reason} ->
          {:error, {:twitch_reward_cleanup_failed, reload_voting_session!(session), reason}}
      end
    end
  end

  defp reconcile_before_draft(session, "draft", opts) do
    client = Keyword.get(opts, :client, BacklogWheel.Twitch.client())

    case BacklogWheel.Voting.TwitchRedemptions.reconcile_session(session, client) do
      :ok ->
        {:ok, reload_voting_session!(session)}

      {:error, reason} ->
        {:error, {:twitch_reconciliation_failed, reload_voting_session!(session), reason}}
    end
  end

  defp reconcile_before_draft(session, _status, _opts), do: {:ok, session}

  @doc """
  Starts Twitch voting using one reward for the session.
  """
  def start_twitch_voting(%VotingSession{} = voting_session, opts \\ []) do
    BacklogWheel.Voting.TwitchSessionRewards.start(voting_session, opts)
  end

  @doc """
  Checks whether a voting session can safely create Twitch rewards.
  """
  def validate_twitch_reward_creation(%VotingSession{} = voting_session) do
    voting_session = reload_voting_session!(voting_session)
    pool_items = voting_session.voting_session_games

    case pool_size_error(pool_items) do
      nil -> :ok
      error -> {:error, error}
    end
  end

  @doc """
  Deletes Twitch rewards for a voting session without changing session status.
  """
  def remove_twitch_rewards(%VotingSession{} = voting_session, opts \\ []) do
    BacklogWheel.Voting.TwitchSessionRewards.stop(voting_session, opts)
  end

  @doc """
  Deletes finished session rewards after Twitch confirms their redemption queues are drained.
  """
  def cleanup_finished_twitch_rewards(opts \\ []) do
    BacklogWheel.Voting.TwitchSessionRewards.cleanup_finished(opts)
  end

  @doc """
  Creates a viewer for a community.
  """
  def create_viewer(%Community{} = community, attrs) do
    %Viewer{community_id: community.id}
    |> Viewer.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Adds a platform identity to a viewer.
  """
  def add_identity_to_viewer(%Viewer{} = viewer, attrs) do
    %ViewerIdentity{community_id: viewer.community_id, viewer_id: viewer.id}
    |> ViewerIdentity.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Adds a game to a voting session pool.
  """
  def add_game_to_session(%VotingSession{} = voting_session, %Game{} = game, attrs \\ %{}) do
    if game.community_id == voting_session.community_id do
      Repo.transaction(fn -> insert_numbered_session_game(voting_session, game, attrs) end)
      |> broadcast_voting_session_change()
    else
      {:error, :game_not_in_session_community}
    end
  end

  defp insert_numbered_session_game(voting_session, game, attrs) do
    session =
      VotingSession
      |> where([session], session.id == ^voting_session.id)
      |> lock("FOR UPDATE")
      |> Repo.one!()

    case %VotingSessionGame{
           voting_session_id: session.id,
           game_id: game.id,
           option_number: session.next_option_number
         }
         |> VotingSessionGame.changeset(attrs)
         |> Repo.insert() do
      {:ok, pool_item} ->
        session
        |> Ecto.Changeset.change(next_option_number: session.next_option_number + 1)
        |> Repo.update!()

        pool_item

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  @doc """
  Removes a game from a voting session pool.
  """
  def remove_game_from_session(%VotingSessionGame{} = voting_session_game) do
    Repo.transaction(fn ->
      session =
        VotingSession
        |> where([session], session.id == ^voting_session_game.voting_session_id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      if Repo.exists?(
           from vote in ChannelPointVote,
             where:
               vote.voting_session_game_id == ^voting_session_game.id and
                 vote.source == "twitch_channel_points"
         ) do
        Repo.rollback(:game_has_twitch_votes)
      end

      require_reconciled_pool!(session)

      case Repo.delete(voting_session_game) do
        {:ok, pool_item} -> pool_item
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> broadcast_voting_session_change(voting_session_game.voting_session_id)
  end

  defp require_reconciled_pool!(session) do
    reward = Repo.get_by(BacklogWheel.Voting.TwitchVotingReward, voting_session_id: session.id)

    pending_window? =
      Repo.exists?(
        from window in TwitchVotingWindow,
          where:
            window.voting_session_id == ^session.id and not is_nil(window.closed_at) and
              is_nil(window.reconciled_at)
      )

    if reward && (reward.status not in ["disabled", "deleted"] or pending_window?),
      do: Repo.rollback(:twitch_reconciliation_required)
  end

  @doc """
  Returns games that can still be added to a voting session pool.
  """
  def list_available_games_for_session(%VotingSession{} = voting_session) do
    existing_game_ids = existing_session_game_ids(voting_session)

    Game
    |> where([game], game.community_id == ^voting_session.community_id)
    |> maybe_exclude_game_ids(existing_game_ids)
    |> order_by([game], asc: game.title)
    |> Repo.all()
  end

  @doc """
  Records a positive vote against a voting session game.

  When `external_event_id` is present, repeated events from the same source are idempotent.
  """
  def record_vote(%VotingSessionGame{} = voting_session_game, attrs) do
    do_record_vote(voting_session_game, nil, attrs)
  end

  def record_vote(%VotingSessionGame{} = voting_session_game, %Viewer{} = viewer, attrs) do
    do_record_vote(voting_session_game, viewer.id, attrs)
  end

  @doc """
  Ingests a Twitch channel point reward redemption as one positive vote.

  Duplicate redemption IDs are idempotent. Known rewards are retained so late
  redemptions can be canceled and refunded after voting closes.
  """
  def ingest_twitch_reward_redemption(attrs) when is_map(attrs) do
    BacklogWheel.Voting.TwitchRedemptions.ingest(attrs)
  end

  @doc """
  Returns the channel point vote total and final weight for a voting session game.
  """
  def voting_session_game_weight(%VotingSessionGame{} = voting_session_game) do
    channel_point_vote_total = channel_point_vote_total_for_game(voting_session_game.id)

    %{
      base_weight: voting_session_game.base_weight,
      channel_point_vote_total: channel_point_vote_total,
      final_weight: voting_session_game.base_weight + channel_point_vote_total
    }
  end

  @doc """
  Returns weighted wheel entries for a voting session.

  Each entry uses `final_weight = base_weight + channel_point_votes`.
  """
  def list_voting_session_wheel_entries(%VotingSession{} = voting_session) do
    voting_session
    |> reload_voting_session!()
    |> Map.fetch!(:voting_session_games)
    |> Enum.map(fn pool_item ->
      %{
        pool_item: pool_item,
        game: pool_item.game,
        title: pool_item.game.title,
        weight: pool_item.final_weight,
        base_weight: pool_item.base_weight,
        channel_point_vote_total: pool_item.channel_point_vote_total
      }
    end)
    |> Enum.reject(&(&1.weight <= 0))
  end

  @doc """
  Selects one game from a voting session pool by final weight and records the spin.
  """
  def spin_voting_session_wheel(%VotingSession{} = voting_session) do
    with {:ok, session} <- freeze_for_spin(voting_session),
         {:ok, result} <- reconcile_and_spin(session) do
      result
    end
  end

  defp reconcile_and_spin(voting_session) do
    Repo.transaction(fn ->
      session =
        VotingSession
        |> where([s], s.id == ^voting_session.id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      if session.status != "locked", do: Repo.rollback(:session_not_ready)

      case BacklogWheel.Voting.TwitchRedemptions.reconcile_session(session) do
        :ok -> do_spin_voting_session_wheel(session)
        {:error, reason} -> Repo.rollback({:twitch_reconciliation_failed, reason})
      end
    end)
  end

  defp freeze_for_spin(voting_session) do
    with {:ok, session} <-
           transition_session(voting_session, "locked", ["draft", "open", "locked"]) do
      case remove_twitch_rewards(session) do
        {:ok, session} -> {:ok, session}
        {:error, :no_twitch_rewards} -> {:ok, session}
        {:error, reason} -> {:error, {:twitch_reward_cleanup_failed, session, reason}}
      end
    end
  end

  defp do_spin_voting_session_wheel(%VotingSession{} = voting_session) do
    entries =
      voting_session
      |> list_voting_session_wheel_entries()
      |> with_wheel_geometry()

    case select_weighted_entry(entries) do
      nil ->
        {:error, :no_candidates}

      entry ->
        spun_at = DateTime.utc_now() |> DateTime.truncate(:second)
        spin_seed = System.unique_integer([:positive])
        landing_degrees = random_landing_degrees(entry)

        snapshot =
          spin_snapshot(voting_session, entries, entry, %{
            spin_seed: spin_seed,
            landing_degrees: landing_degrees,
            spun_at: spun_at
          })

        community = Communities.get_community!(voting_session.community_id)

        case Backlog.create_spin(community, %{
               game_id: entry.game.id,
               voting_session_id: voting_session.id,
               spun_at: spun_at,
               source: "voting_session",
               notes: "Voting session #{voting_session.id}; final weight #{entry.weight}",
               snapshot: snapshot
             }) do
          {:ok, spin} ->
            {:ok, _session} =
              voting_session
              |> VotingSession.changeset(%{status: "completed"})
              |> Repo.update()

            spin = Repo.preload(spin, :game)
            payload = spin_start_payload(spin, snapshot)
            broadcast_voting_session_spin_started(voting_session.id, payload)

            {:ok, %{game: entry.game, spin: spin, entry: entry, spin_payload: payload}}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  defp do_record_vote(%VotingSessionGame{} = voting_session_game, viewer_id, attrs) do
    case get_existing_external_vote(attrs) do
      %ChannelPointVote{} = channel_point_vote ->
        {:ok, channel_point_vote}

      nil ->
        %ChannelPointVote{voting_session_game_id: voting_session_game.id, viewer_id: viewer_id}
        |> ChannelPointVote.changeset(attrs)
        |> Repo.insert()
        |> broadcast_voting_session_change(voting_session_game.voting_session_id)
    end
  end

  defp validate_status_transition(%VotingSession{} = voting_session, "open") do
    validate_voting_session_pool_size(voting_session)
  end

  defp validate_status_transition(%VotingSession{} = voting_session, "locked") do
    validate_voting_session_pool_size(voting_session)
  end

  defp validate_status_transition(_voting_session, _status), do: :ok

  defp pool_size_error(pool_items) do
    pool_size = length(pool_items)

    cond do
      pool_size == 0 ->
        :empty_pool

      pool_size < @voting_session_pool_min_size ->
        {:voting_session_pool_too_small, pool_size, @voting_session_pool_min_size}

      true ->
        nil
    end
  end

  defp channel_point_vote_total_for_game(voting_session_game_id) do
    ChannelPointVote
    |> where([vote], vote.voting_session_game_id == ^voting_session_game_id)
    |> select([vote], coalesce(sum(vote.strength), 0))
    |> Repo.one()
  end

  defp preload_pool_games_with_votes(%VotingSession{} = voting_session) do
    [voting_session]
    |> preload_pool_games_with_votes()
    |> hd()
  end

  defp preload_pool_games_with_votes(voting_sessions) when is_list(voting_sessions) do
    voting_sessions
    |> Repo.preload(
      twitch_voting_reward: [],
      twitch_voting_windows: [],
      voting_session_games: {ordered_voting_session_games_query(), [:game, :channel_point_votes]}
    )
    |> Enum.map(fn voting_session ->
      pool_items = Enum.map(voting_session.voting_session_games, &attach_weight/1)
      %{voting_session | voting_session_games: pool_items}
    end)
  end

  defp ordered_voting_session_games_query do
    order_by(VotingSessionGame, [pool_item], asc: pool_item.id)
  end

  defp attach_weight(%VotingSessionGame{} = voting_session_game) do
    channel_point_vote_total =
      Enum.reduce(voting_session_game.channel_point_votes, 0, &(&1.strength + &2))

    voting_session_game
    |> Map.put(:channel_point_vote_total, channel_point_vote_total)
    |> Map.put(:final_weight, voting_session_game.base_weight + channel_point_vote_total)
  end

  defp select_weighted_entry([]), do: nil

  defp select_weighted_entry(entries) do
    total_weight = Enum.reduce(entries, 0, &(&1.weight + &2))

    if total_weight > 0 do
      select_weighted_entry(entries, :rand.uniform(total_weight))
    end
  end

  defp select_weighted_entry(entries, target) do
    Enum.reduce_while(entries, 0, fn entry, accumulated_weight ->
      accumulated_weight = accumulated_weight + entry.weight

      if target <= accumulated_weight do
        {:halt, entry}
      else
        {:cont, accumulated_weight}
      end
    end)
  end

  defp reload_voting_session!(%VotingSession{id: id, community_id: community_id}) do
    community_id
    |> Communities.get_community!()
    |> get_voting_session!(id)
  end

  defp spin_snapshot(%VotingSession{} = voting_session, entries, winning_entry, spin_data) do
    total_weight = Enum.reduce(entries, 0, &(&1.weight + &2))

    %{
      "source" => "voting_session",
      "voting_session_id" => voting_session.id,
      "winning_game_id" => winning_entry.game.id,
      "winning_voting_session_game_id" => winning_entry.pool_item.id,
      "total_weight" => total_weight,
      "spin_seed" => spin_data.spin_seed,
      "landing_degrees" => spin_data.landing_degrees,
      "duration_ms" => @spin_duration_ms,
      "full_turns" => @spin_full_turns,
      "started_at" => DateTime.to_iso8601(spin_data.spun_at),
      "easing_profile" => @spin_easing_profile,
      "entries" => Enum.map(entries, &snapshot_entry/1)
    }
  end

  defp snapshot_entry(entry) do
    %{
      "game_id" => entry.game.id,
      "voting_session_game_id" => entry.pool_item.id,
      "title" => entry.title,
      "start_degrees" => entry.start_degrees,
      "end_degrees" => entry.end_degrees,
      "base_weight" => entry.base_weight,
      "channel_point_vote_total" => entry.channel_point_vote_total,
      "final_weight" => entry.weight
    }
  end

  defp spin_start_payload(spin, snapshot) do
    %{
      "spinId" => spin.id,
      "votingSessionId" => snapshot["voting_session_id"],
      "gameId" => snapshot["winning_game_id"],
      "votingSessionGameId" => snapshot["winning_voting_session_game_id"],
      "landingDegrees" => snapshot["landing_degrees"],
      "durationMs" => snapshot["duration_ms"],
      "fullTurns" => snapshot["full_turns"],
      "spinSeed" => snapshot["spin_seed"],
      "startedAt" => snapshot["started_at"],
      "easingProfile" => snapshot["easing_profile"],
      "segments" => snapshot["entries"]
    }
  end

  defp with_wheel_geometry(candidates) do
    total_weight = Enum.reduce(candidates, 0, &(&1.weight + &2))

    candidates
    |> Enum.reduce({[], 0}, fn candidate, {candidates, accumulated_weight} ->
      start_degrees = accumulated_weight / total_weight * 360
      end_degrees = (accumulated_weight + candidate.weight) / total_weight * 360

      candidate =
        candidate
        |> Map.put(:start_degrees, start_degrees)
        |> Map.put(:end_degrees, end_degrees)

      {[candidate | candidates], accumulated_weight + candidate.weight}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp random_landing_degrees(candidate) do
    segment_degrees = candidate.end_degrees - candidate.start_degrees
    inset_degrees = min(segment_degrees * @landing_edge_inset_ratio, @landing_edge_inset_degrees)
    position = :rand.uniform() |> max(0.000_001) |> min(0.999_999)

    candidate.start_degrees + inset_degrees + (segment_degrees - inset_degrees * 2) * position
  end

  @doc """
  Populates a voting session pool from the current wheel-eligible games.
  """
  def populate_session_from_wheel_candidates(%VotingSession{} = voting_session) do
    existing_game_ids = existing_session_game_ids(voting_session) |> MapSet.new()

    voting_session
    |> list_populatable_wheel_games()
    |> Enum.reject(&MapSet.member?(existing_game_ids, &1.id))
    |> Enum.map(fn game ->
      {:ok, voting_session_game} = add_game_to_session(voting_session, game)
      voting_session_game
    end)
    |> then(&{:ok, &1})
  end

  @doc """
  Populates a voting session pool from a Wheel Format's candidate rules.
  """
  def populate_session_from_wheel_format(
        %VotingSession{} = voting_session,
        %WheelFormat{} = wheel_format
      ) do
    existing_game_ids = existing_session_game_ids(voting_session) |> MapSet.new()
    base_weight = wheel_format_base_weight(wheel_format)

    voting_session
    |> list_populatable_format_games(wheel_format)
    |> Enum.reject(&MapSet.member?(existing_game_ids, &1.id))
    |> Enum.map(fn game ->
      {:ok, voting_session_game} =
        add_game_to_session(voting_session, game, %{base_weight: base_weight})

      voting_session_game
    end)
    |> then(&{:ok, &1})
  end

  defp get_existing_external_vote(attrs) do
    source = Map.get(attrs, :source) || Map.get(attrs, "source")
    external_event_id = Map.get(attrs, :external_event_id) || Map.get(attrs, "external_event_id")

    if is_nil(source) or is_nil(external_event_id) do
      nil
    else
      Repo.get_by(ChannelPointVote, source: source, external_event_id: external_event_id)
    end
  end

  defp list_populatable_wheel_games(%VotingSession{} = voting_session) do
    Game
    |> where([game], game.community_id == ^voting_session.community_id)
    |> where([game], game.include_in_wheel)
    |> order_by([game], asc: game.title)
    |> Repo.all()
  end

  defp list_populatable_format_games(
         %VotingSession{} = voting_session,
         %WheelFormat{} = wheel_format
       ) do
    %Community{id: voting_session.community_id}
    |> wheel_format_candidate_query(wheel_format)
    |> order_by([game], asc: game.title)
    |> Repo.all()
  end

  defp wheel_format_candidate_query(%Community{} = community, %WheelFormat{} = wheel_format) do
    Game
    |> where([game], game.community_id == ^community.id)
    |> apply_candidate_rules(wheel_format.candidate_rules || %{})
  end

  defp apply_candidate_rules(query, rules) do
    Enum.reduce(rules, query, fn
      {"include_in_wheel", value}, query when is_boolean(value) ->
        where(query, [game], game.include_in_wheel == ^value)

      {"played_on_stream", value}, query when is_boolean(value) ->
        where(query, [game], game.played_on_stream == ^value)

      {"min_playtime_minutes", value}, query ->
        case candidate_rule_integer(value) do
          minutes when is_integer(minutes) ->
            where(query, [game], fragment("coalesce(?, 0)", game.playtime_minutes) >= ^minutes)

          nil ->
            query
        end

      {"max_playtime_minutes", value}, query ->
        case candidate_rule_integer(value) do
          minutes when is_integer(minutes) ->
            where(query, [game], fragment("coalesce(?, 0)", game.playtime_minutes) <= ^minutes)

          nil ->
            query
        end

      _rule, query ->
        query
    end)
  end

  defp candidate_rule_integer(value) when is_integer(value) and value >= 0, do: value

  defp candidate_rule_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> integer
      _invalid -> nil
    end
  end

  defp candidate_rule_integer(_value), do: nil

  defp wheel_format_base_weight(%WheelFormat{weighting_rules: %{"base_weight" => weight}})
       when is_integer(weight) and weight > 0,
       do: weight

  defp wheel_format_base_weight(_wheel_format), do: 1

  defp existing_session_game_ids(%VotingSession{} = voting_session) do
    VotingSessionGame
    |> where([pool_item], pool_item.voting_session_id == ^voting_session.id)
    |> select([pool_item], pool_item.game_id)
    |> Repo.all()
  end

  defp maybe_exclude_game_ids(query, []), do: query

  defp maybe_exclude_game_ids(query, game_ids) do
    where(query, [game], game.id not in ^game_ids)
  end

  defp voting_session_topic(id), do: "voting_session:#{id}"

  defp broadcast_voting_session_change({:ok, %VotingSession{id: id}} = result) do
    broadcast_voting_session_changed(id)
    result
  end

  defp broadcast_voting_session_change({:ok, %VotingSessionGame{voting_session_id: id}} = result) do
    broadcast_voting_session_changed(id)
    result
  end

  defp broadcast_voting_session_change({:error, _changeset} = result), do: result

  defp broadcast_voting_session_change({:ok, _struct} = result, id) do
    broadcast_voting_session_changed(id)
    result
  end

  defp broadcast_voting_session_change({:error, _changeset} = result, _id), do: result

  defp broadcast_voting_session_changed(id) do
    Phoenix.PubSub.broadcast(@pubsub, voting_session_topic(id), {:voting_session_changed, id})
  end

  defp broadcast_voting_session_spin_started(id, payload) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      voting_session_topic(id),
      {:voting_session_spin_started, payload}
    )
  end
end
