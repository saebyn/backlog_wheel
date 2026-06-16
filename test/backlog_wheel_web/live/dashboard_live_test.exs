defmodule BacklogWheelWeb.DashboardLiveTest do
  use BacklogWheelWeb.ConnCase

  import Phoenix.LiveViewTest
  import BacklogWheel.BacklogFixtures
  import BacklogWheel.VotingFixtures

  alias BacklogWheel.Backlog

  @tag :unauthenticated
  test "renders the dashboard without login and handles empty community state", %{conn: conn} do
    community_fixture()

    {:ok, view, _html} = live(conn, ~p"/dashboard")

    assert has_element?(view, "#dashboard-page")
    assert has_element?(view, "#dashboard-empty-history")
    assert has_element?(view, "#dashboard-no-active-session")
    assert has_element?(view, "#dashboard-empty-wheel-formats")
    assert has_element?(view, "#dashboard-history-link")
  end

  @tag :unauthenticated
  test "renders latest recap with session and history links", %{conn: conn} do
    community = community_fixture()
    game = game_fixture(%{community: community, title: "Recap Winner"})

    session =
      voting_session_fixture(%{community: community, status: "closed", title: "Finished Vote"})

    {:ok, spin} =
      Backlog.create_spin(community, %{
        game_id: game.id,
        voting_session_id: session.id,
        source: "voting_session",
        spun_at: ~U[2026-06-06 12:00:00Z],
        snapshot: %{
          "winning_game_id" => game.id,
          "total_weight" => 7,
          "entries" => [
            %{
              "game_id" => game.id,
              "title" => game.title,
              "base_weight" => 2,
              "channel_point_vote_total" => 5,
              "final_weight" => 7
            }
          ]
        }
      })

    {:ok, view, _html} = live(conn, ~p"/dashboard")

    assert has_element?(view, "#dashboard-latest-spin-#{spin.id}", "Recap Winner")
    assert has_element?(view, "#dashboard-latest-spin-odds", "Winner votes: 7 of 7")
    assert has_element?(view, "#dashboard-latest-history-link")
    assert has_element?(view, "#dashboard-latest-session-link[href='/history/#{spin.id}']")
  end

  @tag :unauthenticated
  test "renders active session and wheel formats", %{conn: conn} do
    community = community_fixture()
    game = game_fixture(%{community: community, title: "Vote Candidate"})

    session =
      voting_session_fixture(%{
        community: community,
        status: "open",
        title: "Tonight's Vote",
        description: "Chat chooses the next game"
      })

    voting_session_game_fixture(session, game)

    format =
      wheel_format_fixture(%{
        community: community,
        name: "Quick Vote",
        description: "Fast shortlist format",
        default_session_title: "Quick Vote Session"
      })

    {:ok, view, _html} = live(conn, ~p"/dashboard")

    assert has_element?(view, "#dashboard-active-session-#{session.id}", "Tonight's Vote")
    assert has_element?(view, "#dashboard-active-session-status", "Open")
    assert has_element?(view, "#dashboard-active-session-action", "Voting is open")
    assert has_element?(view, "#dashboard-wheel-formats-voting-link", "Explore All Formats")
    assert has_element?(view, "#dashboard-wheel-format-#{format.id}", "Quick Vote")
    assert has_element?(view, "#dashboard-wheel-format-#{format.id}", "Quick Vote Session")

    assert has_element?(
             view,
             "#dashboard-use-wheel-format-#{format.id}[href='/voting?wheel_format_id=#{format.id}']"
           )
  end
end
