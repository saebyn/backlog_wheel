defmodule BacklogWheelWeb.DashboardLiveTest do
  use BacklogWheelWeb.ConnCase

  import Phoenix.LiveViewTest
  import BacklogWheel.BacklogFixtures
  import BacklogWheel.VotingFixtures

  alias BacklogWheel.Backlog

  @tag :unauthenticated
  test "redirects unauthenticated visitors", %{conn: conn} do
    community_fixture()

    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/dashboard")
  end

  test "renders the dashboard for the current community", %{conn: conn} do
    community = Process.get(:test_community)

    {:ok, view, _html} = live(conn, ~p"/dashboard")

    assert has_element?(view, "#dashboard-page")
    assert has_element?(view, "#dashboard-empty-history")
    assert has_element?(view, "#dashboard-no-active-session")
    assert has_element?(view, "#dashboard-empty-wheel-formats")
    assert has_element?(view, "#dashboard-history-link")

    refute is_nil(community)
  end

  test "renders latest recap with session and history links", %{conn: conn} do
    community = Process.get(:test_community)
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

  test "renders active session and wheel formats", %{conn: conn} do
    community = Process.get(:test_community)
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
    assert has_element?(view, "#main-nav-dashboard[href='/dashboard']", "Dashboard")
    assert has_element?(view, "#main-nav-wheel[href='/wheel']", "Wheel")
    assert has_element?(view, "#main-nav-games[href='/games']", "Games")
    assert has_element?(view, "#main-nav-voting[href='/voting']", "Voting")
    assert has_element?(view, "#main-nav-history[href='/history']", "History")
    assert has_element?(view, "#main-nav-settings[href='/settings']", "Settings")
    assert has_element?(view, "#main-nav-add-game[href='/games/new']", "Add Game")
    assert has_element?(view, "#dashboard-wheel-formats-voting-link", "Manage Formats")
    assert has_element?(view, "#dashboard-wheel-formats-voting-link[href='/settings/formats']")
    assert has_element?(view, "#dashboard-wheel-format-#{format.id}", "Quick Vote")
    assert has_element?(view, "#dashboard-wheel-format-#{format.id}", "Quick Vote Session")

    assert has_element?(
             view,
             "#dashboard-use-wheel-format-#{format.id}[href='/voting?wheel_format_id=#{format.id}']"
           )
  end

  test "does not render data from another community", %{conn: conn} do
    current_community = Process.get(:test_community)
    other_community = community_fixture(%{slug: "other-dashboard-community"})
    other_game = game_fixture(%{community: other_community, title: "Other Winner"})

    {:ok, other_spin} =
      Backlog.create_spin(other_community, %{
        game_id: other_game.id,
        source: "manual",
        spun_at: ~U[2026-06-06 12:00:00Z]
      })

    current_format =
      wheel_format_fixture(%{
        community: current_community,
        name: "Current Format",
        default_session_title: "Current Session"
      })

    other_format =
      wheel_format_fixture(%{
        community: other_community,
        name: "Other Format",
        default_session_title: "Other Session"
      })

    {:ok, view, _html} = live(conn, ~p"/dashboard")

    assert has_element?(view, "#dashboard-empty-history")
    assert has_element?(view, "#dashboard-wheel-format-#{current_format.id}", "Current Format")
    refute has_element?(view, "#dashboard-latest-spin-#{other_spin.id}")
    refute has_element?(view, "#dashboard-wheel-format-#{other_format.id}")
    refute has_element?(view, "#dashboard-page", "Other Winner")
    refute has_element?(view, "#dashboard-page", "Other Format")
  end
end
