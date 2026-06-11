defmodule BacklogWheelWeb.SpinHistoryLiveTest do
  use BacklogWheelWeb.ConnCase

  import Phoenix.LiveViewTest
  import BacklogWheel.BacklogFixtures

  alias BacklogWheel.Backlog

  test "renders empty spin history", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/history")

    assert html =~ "Spin History"
    assert html =~ "No spins recorded yet"
  end

  test "lists recent spins with game details", %{conn: conn} do
    community = Process.get(:test_community)

    game =
      game_fixture(%{
        title: "History Game",
        image_url: "https://example.com/history.jpg"
      })

    {:ok, _spin} =
      Backlog.create_spin(community, %{
        game_id: game.id,
        source: "wheel",
        spun_at: ~U[2026-06-06 12:00:00Z]
      })

    {:ok, _view, html} = live(conn, ~p"/history")

    assert html =~ "History Game"
    assert html =~ "https://example.com/history.jpg"
    assert html =~ "2026-06-06 12:00 UTC"
    assert html =~ "wheel"
  end

  test "shows snapshotted winner odds context", %{conn: conn} do
    community = Process.get(:test_community)
    winner = game_fixture(%{title: "Snapshot History Winner"})
    other = game_fixture(%{title: "Snapshot History Other", external_id: "history-other"})

    {:ok, spin} =
      Backlog.create_spin(community, %{
        game_id: winner.id,
        source: "voting_session",
        spun_at: ~U[2026-06-06 12:00:00Z],
        snapshot: %{
          "source" => "voting_session",
          "winning_game_id" => winner.id,
          "total_weight" => 8,
          "entries" => [
            %{
              "game_id" => winner.id,
              "title" => winner.title,
              "base_weight" => 2,
              "channel_point_vote_total" => 2,
              "final_weight" => 4
            },
            %{
              "game_id" => other.id,
              "title" => other.title,
              "base_weight" => 1,
              "channel_point_vote_total" => 3,
              "final_weight" => 4
            }
          ]
        }
      })

    {:ok, view, _html} = live(conn, ~p"/history")

    assert has_element?(view, "#spin-snapshot-summary-#{spin.id}", "Winner votes: 4 of 8")
    assert has_element?(view, "#spin-snapshot-summary-#{spin.id}", "50.0%")

    assert has_element?(
             view,
             "#spin-snapshot-summary-#{spin.id}",
             "Starting votes 2 + channel point votes 2"
           )

    assert has_element?(view, "#spin-snapshot-summary-#{spin.id}", "2 entries snapshotted")
  end

  test "deletes spin history entries", %{conn: conn} do
    community = Process.get(:test_community)
    game = game_fixture(%{title: "Delete Me"})

    {:ok, spin} =
      Backlog.create_spin(community, %{
        game_id: game.id,
        source: "wheel",
        spun_at: ~U[2026-06-06 12:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/history")

    assert has_element?(view, "#history-spin-#{spin.id}", "Delete Me")
    assert view |> element("#delete-spin-#{spin.id}") |> render_click()
    refute has_element?(view, "#history-spin-#{spin.id}")
    assert has_element?(view, "#empty-spin-history")
  end
end
