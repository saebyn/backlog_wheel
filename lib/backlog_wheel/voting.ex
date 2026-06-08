defmodule BacklogWheel.Voting do
  @moduledoc """
  The Voting context.
  """

  import Ecto.Query, warn: false

  alias BacklogWheel.Backlog.Game
  alias BacklogWheel.Backlog
  alias BacklogWheel.Communities
  alias BacklogWheel.Repo

  alias BacklogWheel.Voting.{
    Viewer,
    ViewerIdentity,
    VotingBoost,
    VotingSession,
    VotingSessionGame
  }

  @pubsub BacklogWheel.PubSub
  @spin_duration_ms 30_000
  @spin_full_turns 12
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
  Returns voting sessions for the default community.
  """
  def list_voting_sessions do
    default_community_id = default_community_id()

    VotingSession
    |> where([session], session.community_id == ^default_community_id)
    |> order_by([session], desc: session.inserted_at, desc: session.id)
    |> Repo.all()
    |> preload_pool_games_with_boosts()
  end

  @doc """
  Gets a voting session with its game pool.
  """
  def get_voting_session!(id) do
    VotingSession
    |> Repo.get!(id)
    |> Repo.preload(:community)
    |> preload_pool_games_with_boosts()
  end

  @doc """
  Creates a voting session for the default community.
  """
  def create_voting_session(attrs \\ %{}) do
    %VotingSession{community_id: default_community_id()}
    |> VotingSession.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a voting session status.
  """
  def update_voting_session_status(%VotingSession{} = voting_session, status)
      when is_binary(status) do
    voting_session
    |> VotingSession.changeset(%{status: status})
    |> Repo.update()
    |> broadcast_voting_session_change()
  end

  @doc """
  Creates a viewer for the default community.
  """
  def create_viewer(attrs) do
    %Viewer{community_id: default_community_id()}
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
    %VotingSessionGame{voting_session_id: voting_session.id, game_id: game.id}
    |> VotingSessionGame.changeset(attrs)
    |> Repo.insert()
    |> broadcast_voting_session_change()
  end

  @doc """
  Removes a game from a voting session pool.
  """
  def remove_game_from_session(%VotingSessionGame{} = voting_session_game) do
    Repo.delete(voting_session_game)
    |> broadcast_voting_session_change(voting_session_game.voting_session_id)
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
  Records a positive boost against a voting session game.

  When `external_event_id` is present, repeated events from the same source are idempotent.
  """
  def record_boost(%VotingSessionGame{} = voting_session_game, attrs) do
    do_record_boost(voting_session_game, nil, attrs)
  end

  def record_boost(%VotingSessionGame{} = voting_session_game, %Viewer{} = viewer, attrs) do
    do_record_boost(voting_session_game, viewer.id, attrs)
  end

  @doc """
  Returns the boost total and final weight for a voting session game.
  """
  def voting_session_game_weight(%VotingSessionGame{} = voting_session_game) do
    boost_total = boost_total_for_game(voting_session_game.id)

    %{
      base_weight: voting_session_game.base_weight,
      boost_total: boost_total,
      final_weight: voting_session_game.base_weight + boost_total
    }
  end

  @doc """
  Returns weighted wheel entries for a voting session.

  Each entry uses `final_weight = base_weight + boost_strength`.
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
        boost_total: pool_item.boost_total
      }
    end)
    |> Enum.reject(&(&1.weight <= 0))
  end

  @doc """
  Selects one game from a voting session pool by final weight and records the spin.
  """
  def spin_voting_session_wheel(%VotingSession{} = voting_session) do
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
        landing_degrees = winner_center_degrees(entry)

        snapshot =
          spin_snapshot(voting_session, entries, entry, %{
            spin_seed: spin_seed,
            landing_degrees: landing_degrees,
            spun_at: spun_at
          })

        case Backlog.create_spin(%{
               game_id: entry.game.id,
               voting_session_id: voting_session.id,
               spun_at: spun_at,
               source: "voting_session",
               notes: "Voting session #{voting_session.id}; final weight #{entry.weight}",
               snapshot: snapshot
             }) do
          {:ok, spin} ->
            spin = Repo.preload(spin, :game)
            payload = spin_start_payload(spin, snapshot)
            broadcast_voting_session_spin_started(voting_session.id, payload)

            {:ok, %{game: entry.game, spin: spin, entry: entry, spin_payload: payload}}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  defp do_record_boost(%VotingSessionGame{} = voting_session_game, viewer_id, attrs) do
    case get_existing_external_boost(attrs) do
      %VotingBoost{} = voting_boost ->
        {:ok, voting_boost}

      nil ->
        %VotingBoost{voting_session_game_id: voting_session_game.id, viewer_id: viewer_id}
        |> VotingBoost.changeset(attrs)
        |> Repo.insert()
        |> broadcast_voting_session_change(voting_session_game.voting_session_id)
    end
  end

  defp boost_total_for_game(voting_session_game_id) do
    VotingBoost
    |> where([boost], boost.voting_session_game_id == ^voting_session_game_id)
    |> select([boost], coalesce(sum(boost.strength), 0))
    |> Repo.one()
  end

  defp preload_pool_games_with_boosts(%VotingSession{} = voting_session) do
    [voting_session]
    |> preload_pool_games_with_boosts()
    |> hd()
  end

  defp preload_pool_games_with_boosts(voting_sessions) when is_list(voting_sessions) do
    voting_sessions
    |> Repo.preload(voting_session_games: [:game, :voting_boosts])
    |> Enum.map(fn voting_session ->
      pool_items = Enum.map(voting_session.voting_session_games, &attach_weight/1)
      %{voting_session | voting_session_games: pool_items}
    end)
  end

  defp attach_weight(%VotingSessionGame{} = voting_session_game) do
    boost_total = Enum.reduce(voting_session_game.voting_boosts, 0, &(&1.strength + &2))

    voting_session_game
    |> Map.put(:boost_total, boost_total)
    |> Map.put(:final_weight, voting_session_game.base_weight + boost_total)
  end

  defp select_weighted_entry([]), do: nil

  defp select_weighted_entry(entries) do
    total_weight = Enum.reduce(entries, 0, &(&1.weight + &2))

    if total_weight <= 0 do
      nil
    else
      target = :rand.uniform(total_weight)

      Enum.reduce_while(entries, 0, fn entry, accumulated_weight ->
        accumulated_weight = accumulated_weight + entry.weight

        if target <= accumulated_weight do
          {:halt, entry}
        else
          {:cont, accumulated_weight}
        end
      end)
    end
  end

  defp reload_voting_session!(%VotingSession{id: id}), do: get_voting_session!(id)

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
      "boost_total" => entry.boost_total,
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

  defp winner_center_degrees(candidate), do: (candidate.start_degrees + candidate.end_degrees) / 2

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

  defp default_community_id do
    Communities.get_or_create_default_community().id
  end

  defp get_existing_external_boost(attrs) do
    source = Map.get(attrs, :source) || Map.get(attrs, "source")
    external_event_id = Map.get(attrs, :external_event_id) || Map.get(attrs, "external_event_id")

    if is_nil(source) or is_nil(external_event_id) do
      nil
    else
      Repo.get_by(VotingBoost, source: source, external_event_id: external_event_id)
    end
  end

  defp list_populatable_wheel_games(%VotingSession{} = voting_session) do
    Game
    |> where([game], game.community_id == ^voting_session.community_id)
    |> where([game], game.include_in_wheel)
    |> order_by([game], asc: game.title)
    |> Repo.all()
  end

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
