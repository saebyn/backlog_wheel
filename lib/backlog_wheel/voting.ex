defmodule BacklogWheel.Voting do
  @moduledoc """
  The Voting context.
  """

  import Ecto.Query, warn: false

  alias BacklogWheel.Backlog.Game
  alias BacklogWheel.Communities
  alias BacklogWheel.Repo
  alias BacklogWheel.Voting.{VotingSession, VotingSessionGame}

  @doc """
  Gets a voting session with its game pool.
  """
  def get_voting_session!(id) do
    VotingSession
    |> Repo.get!(id)
    |> Repo.preload([:community, voting_session_games: :game])
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
  Adds a game to a voting session pool.
  """
  def add_game_to_session(%VotingSession{} = voting_session, %Game{} = game, attrs \\ %{}) do
    %VotingSessionGame{voting_session_id: voting_session.id, game_id: game.id}
    |> VotingSessionGame.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Populates a voting session pool from the current wheel-eligible games.
  """
  def populate_session_from_wheel_candidates(%VotingSession{} = voting_session) do
    existing_game_ids =
      VotingSessionGame
      |> where([pool_item], pool_item.voting_session_id == ^voting_session.id)
      |> select([pool_item], pool_item.game_id)
      |> Repo.all()
      |> MapSet.new()

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

  defp list_populatable_wheel_games(%VotingSession{} = voting_session) do
    Game
    |> where([game], game.community_id == ^voting_session.community_id)
    |> where([game], game.include_in_wheel)
    |> order_by([game], asc: game.title)
    |> Repo.all()
  end
end
