defmodule BacklogWheel.BacklogFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `BacklogWheel.Backlog` context.
  """

  @doc """
  Generate a game.
  """
  def game_fixture(attrs \\ %{}) do
    {community, attrs} = Map.pop(attrs, :community)
    community = community || Process.get(:test_community) || community_fixture()

    {:ok, game} =
      attrs
      |> Enum.into(%{
        external_id: "some external_id",
        image_url: "https://example.com/some-image.jpg",
        include_in_wheel: true,
        last_played_at: ~U[2026-06-05 17:55:00Z],
        platform: "some platform",
        played_on_stream: true,
        title: "some title"
      })
      |> then(&BacklogWheel.Backlog.create_game(community, &1))

    game
  end

  def community_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "Community #{System.unique_integer([:positive])}",
        slug: "community-#{System.unique_integer([:positive])}"
      })

    community =
      %BacklogWheel.Communities.Community{}
      |> BacklogWheel.Communities.Community.changeset(attrs)
      |> BacklogWheel.Repo.insert!()

    Process.put(:test_community, community)
    community
  end
end
