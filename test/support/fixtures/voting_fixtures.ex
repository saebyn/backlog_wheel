defmodule BacklogWheel.VotingFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `BacklogWheel.Voting` context.
  """

  @doc """
  Generate a voting session.
  """
  def voting_session_fixture(attrs \\ %{}) do
    {:ok, voting_session} = BacklogWheel.Voting.create_voting_session(attrs)

    voting_session
  end

  @doc """
  Generate a voting session game.
  """
  def voting_session_game_fixture(voting_session, game, attrs \\ %{}) do
    {:ok, voting_session_game} =
      BacklogWheel.Voting.add_game_to_session(voting_session, game, attrs)

    voting_session_game
  end
end
