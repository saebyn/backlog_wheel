defmodule BacklogWheel.Voting do
  @moduledoc """
  The Voting context.
  """

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

  defp default_community_id do
    Communities.get_or_create_default_community().id
  end
end
