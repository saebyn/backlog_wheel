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

  @doc """
  Generate a viewer.
  """
  def viewer_fixture(attrs \\ %{}) do
    {:ok, viewer} =
      attrs
      |> Enum.into(%{display_name: "some viewer"})
      |> BacklogWheel.Voting.create_viewer()

    viewer
  end

  @doc """
  Generate a viewer identity.
  """
  def viewer_identity_fixture(viewer, attrs \\ %{}) do
    {:ok, viewer_identity} =
      attrs
      |> Enum.into(%{
        display_name: "some identity",
        platform: "local",
        platform_user_id: "some-id"
      })
      |> then(&BacklogWheel.Voting.add_identity_to_viewer(viewer, &1))

    viewer_identity
  end

  @doc """
  Generate a channel point vote.
  """
  def channel_point_vote_fixture(voting_session_game, viewer \\ nil, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{source: "local", strength: 1})

    {:ok, channel_point_vote} =
      if viewer do
        BacklogWheel.Voting.record_vote(voting_session_game, viewer, attrs)
      else
        BacklogWheel.Voting.record_vote(voting_session_game, attrs)
      end

    channel_point_vote
  end
end
