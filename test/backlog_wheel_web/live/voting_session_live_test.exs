defmodule BacklogWheelWeb.VotingSessionLiveTest do
  use BacklogWheelWeb.ConnCase

  import Phoenix.LiveViewTest
  import BacklogWheel.BacklogFixtures
  import BacklogWheel.VotingFixtures

  alias BacklogWheel.Backlog
  alias BacklogWheel.Voting

  test "creates a voting session", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/voting")

    assert html =~ "Voting Sessions"
    assert has_element?(view, "#empty-voting-sessions")

    assert view |> element("#create-voting-session") |> render_click()

    assert has_element?(view, "#voting-session-detail")
    assert has_element?(view, "#selected-session-status", "draft")
    assert has_element?(view, "#selected-session-pool-size", "0 pool games")
  end

  test "populates pool from wheel-eligible games", %{conn: conn} do
    wheel_game = game_fixture(%{title: "Wheel Candidate", include_in_wheel: true})

    excluded_game =
      game_fixture(%{
        title: "Excluded Candidate",
        include_in_wheel: false,
        external_id: "excluded-candidate"
      })

    voting_session_fixture()

    {:ok, view, _html} = live(conn, ~p"/voting")

    assert view |> element("#populate-session-pool") |> render_click()

    assert has_element?(view, "#voting-session-pool", wheel_game.title)
    refute has_element?(view, "#voting-session-pool", excluded_game.title)
    assert has_element?(view, "#selected-session-pool-size", "1 pool games")
  end

  test "adds and removes games without changing wheel eligibility", %{conn: conn} do
    voting_session = voting_session_fixture()

    excluded_game =
      game_fixture(%{
        title: "Manual Pool Game",
        include_in_wheel: false,
        external_id: "manual-pool-game"
      })

    {:ok, view, _html} = live(conn, ~p"/voting")

    assert has_element?(view, "#available-voting-games", excluded_game.title)
    assert view |> element("#add-session-game-#{excluded_game.id}") |> render_click()
    assert has_element?(view, "#voting-session-pool", excluded_game.title)

    voting_session = Voting.get_voting_session!(voting_session.id)
    [pool_item] = voting_session.voting_session_games

    assert view |> element("#remove-pool-game-#{pool_item.id}") |> render_click()
    refute has_element?(view, "#voting-session-pool", excluded_game.title)
    assert Backlog.get_game!(excluded_game.id).include_in_wheel == false
  end

  test "updates voting session status", %{conn: conn} do
    voting_session_fixture()

    {:ok, view, _html} = live(conn, ~p"/voting")

    assert view |> element("#set-session-open") |> render_click()
    assert has_element?(view, "#selected-session-status", "open")

    assert view |> element("#set-session-locked") |> render_click()
    assert has_element?(view, "#selected-session-status", "locked")

    assert view |> element("#set-session-closed") |> render_click()
    assert has_element?(view, "#selected-session-status", "closed")

    assert view |> element("#set-session-cancelled") |> render_click()
    assert has_element?(view, "#selected-session-status", "cancelled")
  end
end
