defmodule BacklogWheelWeb.SpinRecapLiveTest do
  use BacklogWheelWeb.ConnCase

  import Phoenix.LiveViewTest
  import BacklogWheel.BacklogFixtures

  alias BacklogWheel.Backlog

  test "renders spin recap from snapshot", %{conn: conn} do
    community = Process.get(:test_community)
    winner = game_fixture(%{title: "Recap Winner"})
    other = game_fixture(%{title: "Recap Other", external_id: "recap-other"})

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

    {:ok, view, _html} = live(conn, ~p"/history/#{spin}")

    assert has_element?(view, "#spin-recap-page")
    assert has_element?(view, "#spin-recap-winner-#{spin.id}", "Recap Winner")
    assert has_element?(view, "#spin-recap-summary", "50.0%")
    assert has_element?(view, "#spin-recap-summary", "4 / 8")

    assert has_element?(
             view,
             "#spin-recap-entry-#{winner.id}",
             "Starting votes 2 + channel point votes 2"
           )

    assert has_element?(view, "#spin-recap-entry-#{other.id}", "Recap Other")
    refute has_element?(view, "#spin-recap-missing-snapshot")
  end

  test "handles older spins without snapshot data", %{conn: conn} do
    community = Process.get(:test_community)
    game = game_fixture(%{title: "Legacy Winner"})

    {:ok, spin} =
      Backlog.create_spin(community, %{
        game_id: game.id,
        source: "wheel",
        spun_at: ~U[2026-06-06 12:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/history/#{spin}")

    assert has_element?(view, "#spin-recap-winner-#{spin.id}", "Legacy Winner")
    assert has_element?(view, "#spin-recap-missing-snapshot")
    assert has_element?(view, "#spin-recap-summary", "0.0%")
  end
end
