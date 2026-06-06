defmodule BacklogWheel.BacklogFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `BacklogWheel.Backlog` context.
  """

  @doc """
  Generate a game.
  """
  def game_fixture(attrs \\ %{}) do
    {:ok, game} =
      attrs
      |> Enum.into(%{
        external_id: "some external_id",
        include_in_wheel: true,
        last_played_at: ~U[2026-06-05 17:55:00Z],
        platform: "some platform",
        played_on_stream: true,
        title: "some title"
      })
      |> BacklogWheel.Backlog.create_game()

    game
  end
end
