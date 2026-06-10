defmodule BacklogWheelWeb.VotingSessionLiveTest do
  use BacklogWheelWeb.ConnCase

  import Phoenix.LiveViewTest
  import BacklogWheel.BacklogFixtures
  import BacklogWheel.VotingFixtures

  alias BacklogWheel.Backlog
  alias BacklogWheel.Twitch
  alias BacklogWheel.Voting

  test "creates a voting session", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/voting")

    assert html =~ "Voting Sessions"
    assert has_element?(view, "#empty-voting-sessions")

    assert view |> element("#create-voting-session") |> render_click()

    assert has_element?(view, "#voting-session-detail")
    assert has_element?(view, "#selected-session-status", "draft")
    assert has_element?(view, "#selected-session-pool-size", "0 games in this vote")
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
    assert has_element?(view, "#selected-session-pool-size", "1 games in this vote")
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

  test "filters available games by title", %{conn: conn} do
    voting_session_fixture()
    alpha_game = game_fixture(%{title: "Alpha Adventure"})
    beta_game = game_fixture(%{title: "Beta Quest", external_id: "beta-quest"})

    {:ok, view, _html} = live(conn, ~p"/voting")

    assert has_element?(view, "#available-voting-games", alpha_game.title)
    assert has_element?(view, "#available-voting-games", beta_game.title)

    view
    |> form("#available-games-filter-form", available_games_filter: %{query: "alpha"})
    |> render_change()

    assert has_element?(view, "#available-voting-games", alpha_game.title)
    refute has_element?(view, "#available-voting-games", beta_game.title)
  end

  test "shows an empty message when available game filter has no matches", %{conn: conn} do
    voting_session_fixture()
    game_fixture(%{title: "Visible Game"})

    {:ok, view, _html} = live(conn, ~p"/voting")

    view
    |> form("#available-games-filter-form", available_games_filter: %{query: "missing"})
    |> render_change()

    assert has_element?(
             view,
             "#empty-available-voting-games",
             "No available games match this search."
           )
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

  test "records local admin boosts and shows final weight", %{conn: conn} do
    voting_session = voting_session_fixture()
    game = game_fixture(%{title: "Boostable Game"})
    pool_item = voting_session_game_fixture(voting_session, game, %{base_weight: 2})

    {:ok, view, _html} = live(conn, ~p"/voting")

    assert has_element?(view, "#pool-game-base-weight-#{pool_item.id}", "2")
    assert has_element?(view, "#pool-game-boost-total-#{pool_item.id}", "+0")
    assert has_element?(view, "#pool-game-final-weight-#{pool_item.id}", "2")

    assert view |> element("#boost-pool-game-#{pool_item.id}") |> render_click()
    assert has_element?(view, "#pool-game-boost-total-#{pool_item.id}", "+1")
    assert has_element?(view, "#pool-game-final-weight-#{pool_item.id}", "3")

    assert view |> element("#boost-pool-game-#{pool_item.id}") |> render_click()
    assert has_element?(view, "#pool-game-boost-total-#{pool_item.id}", "+2")
    assert has_element?(view, "#pool-game-final-weight-#{pool_item.id}", "4")
  end

  test "shows Twitch connection and start prerequisites", %{conn: conn} do
    voting_session_fixture()

    {:ok, view, _html} = live(conn, ~p"/voting")

    assert has_element?(view, "#twitch-connection-status", "Twitch not connected")
    assert has_element?(view, "#manage-twitch", "Manage Twitch")
    assert has_element?(view, "#start-twitch-voting[disabled]")
    assert has_element?(view, "#remove-twitch-rewards[disabled]")

    assert has_element?(
             view,
             "#twitch-voting-hint",
             "Connect Twitch before starting Twitch voting."
           )
  end

  test "shows empty pool prerequisite after Twitch is connected", %{conn: conn} do
    voting_session_fixture()

    {:ok, _credential} =
      Twitch.save_credential(%{
        access_token: "access-token",
        refresh_token: "refresh-token",
        scopes: "channel:manage:redemptions"
      })

    {:ok, view, _html} = live(conn, ~p"/voting")

    assert has_element?(view, "#twitch-connection-status", "Twitch connected")
    assert has_element?(view, "#manage-twitch", "Manage Twitch")
    assert has_element?(view, "#start-twitch-voting[disabled]")
    assert has_element?(view, "#remove-twitch-rewards[disabled]")

    assert has_element?(
             view,
             "#twitch-voting-hint",
             "Add games to this vote before starting Twitch voting."
           )
  end

  test "enables starting Twitch voting when connected with a non-empty pool", %{conn: conn} do
    voting_session = voting_session_fixture()
    voting_session_game_fixture(voting_session, game_fixture(%{title: "Twitch Ready"}))

    {:ok, _credential} =
      Twitch.save_credential(%{
        access_token: "access-token",
        refresh_token: "refresh-token",
        scopes: "channel:manage:redemptions"
      })

    {:ok, view, _html} = live(conn, ~p"/voting")

    assert has_element?(view, "#twitch-connection-status", "Twitch connected")
    refute has_element?(view, "#start-twitch-voting[disabled]")
    assert has_element?(view, "#remove-twitch-rewards[disabled]")
    refute has_element?(view, "#twitch-voting-hint")
  end

  test "keeps start Twitch voting enabled for open sessions without rewards", %{conn: conn} do
    voting_session = voting_session_fixture()
    voting_session_game_fixture(voting_session, game_fixture(%{title: "Open But No Reward"}))
    {:ok, _session} = Voting.update_voting_session_status(voting_session, "open")

    {:ok, _credential} =
      Twitch.save_credential(%{
        access_token: "access-token",
        refresh_token: "refresh-token",
        scopes: "channel:manage:redemptions"
      })

    {:ok, view, _html} = live(conn, ~p"/voting")

    assert has_element?(view, "#selected-session-status", "open")
    refute has_element?(view, "#start-twitch-voting[disabled]")
    refute has_element?(view, "#twitch-voting-hint")
  end

  test "enables removing Twitch rewards after rewards exist", %{conn: conn} do
    voting_session = voting_session_fixture(%{status: "open"})
    game = game_fixture(%{title: "Rewarded Game"})
    pool_item = voting_session_game_fixture(voting_session, game)

    {:ok, _credential} =
      Twitch.save_credential(%{
        access_token: "access-token",
        refresh_token: "refresh-token",
        scopes: "channel:manage:redemptions"
      })

    pool_item
    |> BacklogWheel.Voting.VotingSessionGame.twitch_reward_changeset(%{
      twitch_reward_id: "reward-#{pool_item.id}",
      twitch_reward_title: "Boost ##{pool_item.id}: Rewarded Game",
      twitch_reward_cost: 100,
      twitch_reward_status: "enabled"
    })
    |> BacklogWheel.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/voting")

    assert has_element?(view, "#start-twitch-voting[disabled]")
    refute has_element?(view, "#remove-twitch-rewards[disabled]")
    assert has_element?(view, "#twitch-voting-hint", "Twitch voting rewards are already created")
  end

  test "shows failed Twitch reward cleanup as retryable", %{conn: conn} do
    voting_session = voting_session_fixture(%{status: "closed"})
    game = game_fixture(%{title: "Failed Cleanup Game"})
    pool_item = voting_session_game_fixture(voting_session, game)

    {:ok, _credential} =
      Twitch.save_credential(%{
        access_token: "access-token",
        refresh_token: "refresh-token",
        scopes: "channel:manage:redemptions"
      })

    pool_item
    |> BacklogWheel.Voting.VotingSessionGame.twitch_reward_changeset(%{
      twitch_reward_id: "reward-#{pool_item.id}",
      twitch_reward_title: "Boost ##{pool_item.id}: Failed Cleanup Game",
      twitch_reward_cost: 100,
      twitch_reward_status: "enabled",
      twitch_reward_deletion_status: "failed",
      twitch_reward_deletion_error: ":delete_failed"
    })
    |> BacklogWheel.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/voting")

    assert has_element?(view, "#failed-twitch-reward-deletions", "1 reward cleanup failed")
    assert has_element?(view, "#remove-twitch-rewards", "Retry Reward Cleanup")
    refute has_element?(view, "#remove-twitch-rewards[disabled]")

    assert has_element?(
             view,
             "#pool-game-twitch-reward-cleanup-error-#{pool_item.id}",
             "Cleanup failed: :delete_failed"
           )
  end

  test "links selected voting session to wheel", %{conn: conn} do
    voting_session = voting_session_fixture()
    game = game_fixture(%{title: "Linked Wheel Game"})
    voting_session_game_fixture(voting_session, game)

    {:ok, view, _html} = live(conn, ~p"/voting")

    assert has_element?(view, "#spin-selected-voting-session")

    assert {:error, {:live_redirect, %{to: path}}} =
             view
             |> element("#spin-selected-voting-session")
             |> render_click()

    assert path == "/wheel?voting_session_id=#{voting_session.id}"
  end

  test "refreshes selected session weights from pubsub", %{conn: conn} do
    voting_session = voting_session_fixture()
    game = game_fixture(%{title: "Externally Boosted Game"})
    pool_item = voting_session_game_fixture(voting_session, game, %{base_weight: 2})

    {:ok, view, _html} = live(conn, ~p"/voting")

    assert has_element?(view, "#pool-game-final-weight-#{pool_item.id}", "2")

    voting_boost_fixture(pool_item, nil, %{strength: 5})

    assert has_element?(view, "#pool-game-boost-total-#{pool_item.id}", "+5")
    assert has_element?(view, "#pool-game-final-weight-#{pool_item.id}", "7")
  end
end
