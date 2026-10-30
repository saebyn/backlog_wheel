defmodule BacklogWheelWeb.TwitchSimulatorLiveTest do
  use BacklogWheelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import BacklogWheel.BacklogFixtures
  import BacklogWheel.VotingFixtures

  alias BacklogWheel.Twitch
  alias BacklogWheel.Voting

  setup do
    original_enabled = Application.get_env(:backlog_wheel, :twitch_simulator)
    original_client = Application.get_env(:backlog_wheel, :twitch_client)
    original_config = Application.get_env(:backlog_wheel, :twitch)
    original_state_path = Application.get_env(:backlog_wheel, :twitch_simulator_state_path)
    Application.put_env(:backlog_wheel, :twitch_simulator, true)
    Application.put_env(:backlog_wheel, :twitch_client, BacklogWheel.Twitch.SimulatorClient)

    Application.put_env(:backlog_wheel, :twitch,
      client_id: "simulator",
      client_secret: "simulator"
    )

    start_supervised!(BacklogWheel.Twitch.SimulatorClient)

    on_exit(fn ->
      restore(:twitch_simulator, original_enabled)
      restore(:twitch_client, original_client)
      restore(:twitch, original_config)
      restore(:twitch_simulator_state_path, original_state_path)
    end)

    :ok
  end

  @tag :tmp_dir
  test "simulated rewards survive a simulator restart", %{conn: conn, tmp_dir: tmp_dir} do
    Application.put_env(
      :backlog_wheel,
      :twitch_simulator_state_path,
      Path.join(tmp_dir, "remote-state")
    )

    community = Process.get(:test_community)
    session = voting_session_fixture(%{community: community})

    voting_session_game_fixture(
      session,
      game_fixture(%{community: community, external_id: "first"})
    )

    voting_session_game_fixture(
      session,
      game_fixture(%{community: community, external_id: "second"})
    )

    {:ok, view, _html} = live(conn, "/dev/twitch-simulator")
    view |> element("#simulator-connect") |> render_click()
    assert {:ok, opened} = Voting.start_twitch_voting(session)

    stop_supervised!(BacklogWheel.Twitch.SimulatorClient)
    start_supervised!(BacklogWheel.Twitch.SimulatorClient)
    {:ok, restored, _html} = live(conn, "/dev/twitch-simulator")
    assert has_element?(restored, "#simulator-reward-#{opened.id}", "Backlog Wheel Vote")
  end

  test "shows the session reward created by Twitch voting", %{conn: conn} do
    community = Process.get(:test_community)
    session = voting_session_fixture(%{community: community})

    voting_session_game_fixture(
      session,
      game_fixture(%{community: community, external_id: "first"})
    )

    voting_session_game_fixture(
      session,
      game_fixture(%{community: community, external_id: "second"})
    )

    {:ok, view, _html} = live(conn, "/dev/twitch-simulator")
    view |> element("#simulator-connect") |> render_click()
    assert {:ok, opened} = Voting.start_twitch_voting(session)
    assert has_element?(view, "#simulator-reward-#{opened.id}", "Backlog Wheel Vote")
  end

  test "a viewer can redeem a game number and see the simulated fulfillment", %{conn: conn} do
    community = Process.get(:test_community)
    session = voting_session_fixture(%{community: community})

    first =
      voting_session_game_fixture(
        session,
        game_fixture(%{community: community, external_id: "first"})
      )

    voting_session_game_fixture(
      session,
      game_fixture(%{community: community, external_id: "second"})
    )

    {:ok, view, _html} = live(conn, "/dev/twitch-simulator")
    view |> element("#simulator-connect") |> render_click()
    assert {:ok, opened} = Voting.start_twitch_voting(session)
    assert has_element?(view, "#simulator-redeem-form-#{opened.id}")

    view
    |> form("#simulator-redeem-form-#{opened.id}",
      simulator: %{user_login: "viewer", user_input: "1"}
    )
    |> render_submit()

    assert has_element?(view, "#simulator-redemptions", "FULFILLED")
    assert Voting.voting_session_game_weight(first).channel_point_vote_total == 1
  end

  test "invalid entries are refunded with an addressed simulated chat message", %{conn: conn} do
    community = Process.get(:test_community)
    session = voting_session_fixture(%{community: community})

    first =
      voting_session_game_fixture(
        session,
        game_fixture(%{community: community, external_id: "first"})
      )

    voting_session_game_fixture(
      session,
      game_fixture(%{community: community, external_id: "second"})
    )

    {:ok, view, _html} = live(conn, "/dev/twitch-simulator")
    view |> element("#simulator-connect") |> render_click()
    assert {:ok, opened} = Voting.start_twitch_voting(session)

    view
    |> form("#simulator-redeem-form-#{opened.id}",
      simulator: %{user_login: "alice", user_input: "999"}
    )
    |> render_submit()

    assert has_element?(view, "#simulator-redemptions", "CANCELED")
    assert has_element?(view, "#simulator-messages", "@alice")
    assert has_element?(view, "#simulator-messages", "refunded")
    assert Voting.voting_session_game_weight(first).channel_point_vote_total == 0
  end

  test "newest redemptions and chat feedback appear first", %{conn: conn} do
    community = Process.get(:test_community)
    session = voting_session_fixture(%{community: community})

    voting_session_game_fixture(
      session,
      game_fixture(%{community: community, external_id: "first"})
    )

    voting_session_game_fixture(
      session,
      game_fixture(%{community: community, external_id: "second"})
    )

    {:ok, view, _html} = live(conn, "/dev/twitch-simulator")
    view |> element("#simulator-connect") |> render_click()
    assert {:ok, opened} = Voting.start_twitch_voting(session)

    for viewer <- ["alice", "bob"] do
      view
      |> form("#simulator-redeem-form-#{opened.id}",
        simulator: %{user_login: viewer, user_input: "invalid"}
      )
      |> render_submit()
    end

    assert has_element?(view, "#simulator-redemptions > article:nth-of-type(1)", "@bob")
    assert has_element?(view, "#simulator-messages > p:nth-of-type(2)", "@bob")
  end

  test "delayed notifications can be delivered and replayed without double counting", %{
    conn: conn
  } do
    community = Process.get(:test_community)
    session = voting_session_fixture(%{community: community})

    first =
      voting_session_game_fixture(
        session,
        game_fixture(%{community: community, external_id: "first"})
      )

    voting_session_game_fixture(
      session,
      game_fixture(%{community: community, external_id: "second"})
    )

    {:ok, view, _html} = live(conn, "/dev/twitch-simulator")
    view |> element("#simulator-connect") |> render_click()
    assert {:ok, opened} = Voting.start_twitch_voting(session)

    view
    |> form("#simulator-redeem-form-#{opened.id}",
      simulator: %{user_login: "viewer", user_input: "1", delay: "true"}
    )
    |> render_submit()

    assert has_element?(view, "#simulator-redemptions", "UNFULFILLED")

    assert has_element?(
             view,
             "#simulator-redemptions button[id^='simulator-deliver-']",
             "Deliver webhook"
           )

    assert Voting.voting_session_game_weight(first).channel_point_vote_total == 0
    view |> element("#simulator-redemptions button[id^='simulator-deliver-']") |> render_click()
    assert has_element?(view, "#simulator-redemptions", "FULFILLED")

    assert has_element?(
             view,
             "#simulator-redemptions button[id^='simulator-deliver-']",
             "Replay webhook"
           )

    view |> element("#simulator-redemptions button[id^='simulator-deliver-']") |> render_click()
    assert Voting.voting_session_game_weight(first).channel_point_vote_total == 1
  end

  test "simulated channels cannot see or deliver each other's redemptions", %{conn: conn} do
    first_community = Process.get(:test_community)
    first_session = voting_session_fixture(%{community: first_community})

    voting_session_game_fixture(
      first_session,
      game_fixture(%{community: first_community, external_id: "first"})
    )

    voting_session_game_fixture(
      first_session,
      game_fixture(%{community: first_community, external_id: "second"})
    )

    {:ok, view, _html} = live(conn, "/dev/twitch-simulator")
    view |> element("#simulator-connect") |> render_click()
    assert {:ok, _} = Voting.start_twitch_voting(first_session)

    other = community_fixture()
    assert {:ok, other} = BacklogWheel.Twitch.SimulatorClient.connect(other)
    other_session = voting_session_fixture(%{community: other})

    other_first =
      voting_session_game_fixture(
        other_session,
        game_fixture(%{community: other, external_id: "first"})
      )

    voting_session_game_fixture(
      other_session,
      game_fixture(%{community: other, external_id: "second"})
    )

    assert {:ok, other_opened} = Voting.start_twitch_voting(other_session)
    {:ok, refreshed, _html} = live(conn, "/dev/twitch-simulator")
    refute has_element?(refreshed, "#simulator-reward-#{other_session.id}")

    assert {:ok, redemption} =
             BacklogWheel.Twitch.SimulatorClient.redeem(
               other,
               other_opened.twitch_voting_reward.reward_id,
               "other_viewer",
               "1",
               true
             )

    render_click(view, "deliver", %{"id" => redemption.id})
    assert has_element?(view, "#flash-error", "Could not deliver")
    assert Voting.voting_session_game_weight(other_first).channel_point_vote_total == 0

    assert {:ok, _} = BacklogWheel.Twitch.SimulatorClient.deliver(other, redemption.id)
    BacklogWheel.Voting.TwitchRedemptions.process_pending(BacklogWheel.Twitch.SimulatorClient)
    assert {:ok, _} = Voting.close_voting_session(other_opened, "closed")
    assert :ok = Voting.cleanup_finished_twitch_rewards()
    {:ok, refreshed_after_cleanup, _html} = live(conn, "/dev/twitch-simulator")

    refute has_element?(
             refreshed_after_cleanup,
             "#simulator-deleted-#{other_opened.twitch_voting_reward.reward_id}"
           )
  end

  test "a redemption delayed until after freeze still counts when made on time", %{conn: conn} do
    community = Process.get(:test_community)
    session = voting_session_fixture(%{community: community})

    first =
      voting_session_game_fixture(
        session,
        game_fixture(%{community: community, external_id: "first"})
      )

    voting_session_game_fixture(
      session,
      game_fixture(%{community: community, external_id: "second"})
    )

    {:ok, view, _html} = live(conn, "/dev/twitch-simulator")
    view |> element("#simulator-connect") |> render_click()
    assert {:ok, opened} = Voting.start_twitch_voting(session)

    view
    |> form("#simulator-redeem-form-#{opened.id}",
      simulator: %{user_login: "viewer", user_input: "1", delay: "true"}
    )
    |> render_submit()

    assert {:ok, _} = Voting.close_voting_session(opened, "locked")
    view |> element("#simulator-redemptions button[id^='simulator-deliver-']") |> render_click()
    assert has_element?(view, "#simulator-redemptions", "FULFILLED")
    assert Voting.voting_session_game_weight(first).channel_point_vote_total == 1
  end

  test "a simulated refund failure can be retried from the browser", %{conn: conn} do
    community = Process.get(:test_community)
    session = voting_session_fixture(%{community: community})

    voting_session_game_fixture(
      session,
      game_fixture(%{community: community, external_id: "first"})
    )

    voting_session_game_fixture(
      session,
      game_fixture(%{community: community, external_id: "second"})
    )

    {:ok, view, _html} = live(conn, "/dev/twitch-simulator")
    view |> element("#simulator-connect") |> render_click()
    assert {:ok, opened} = Voting.start_twitch_voting(session)
    view |> element("#simulator-fail-resolution") |> render_click()

    view
    |> form("#simulator-redeem-form-#{opened.id}",
      simulator: %{user_login: "alice", user_input: "bad"}
    )
    |> render_submit()

    assert has_element?(view, "#simulator-redemptions", "UNFULFILLED")
    refute has_element?(view, "#simulator-messages", "@alice")

    view |> element("#simulator-fail-resolution") |> render_click()
    view |> element("#simulator-retry") |> render_click()
    assert has_element?(view, "#simulator-redemptions", "CANCELED")
    assert has_element?(view, "#simulator-messages", "@alice")
  end

  test "simulated reconciliation failures block and then permit a spin", %{conn: conn} do
    community = Process.get(:test_community)
    session = voting_session_fixture(%{community: community})

    voting_session_game_fixture(
      session,
      game_fixture(%{community: community, external_id: "first"})
    )

    voting_session_game_fixture(
      session,
      game_fixture(%{community: community, external_id: "second"})
    )

    {:ok, view, _html} = live(conn, "/dev/twitch-simulator")
    view |> element("#simulator-connect") |> render_click()
    assert {:ok, opened} = Voting.start_twitch_voting(session)
    view |> element("#simulator-fail-reconciliation") |> render_click()

    assert {:error, {:twitch_reconciliation_failed, :simulated_reconciliation_failure}} =
             Voting.spin_voting_session_wheel(opened)

    view |> element("#simulator-fail-reconciliation") |> render_click()
    assert {:ok, _} = Voting.spin_voting_session_wheel(opened)
  end

  test "connects the current community to a simulated Twitch channel", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dev/twitch-simulator")
    assert has_element?(view, "#simulator-connect")
    view |> element("#simulator-connect") |> render_click()
    assert has_element?(view, "#simulator-connected")
    assert Twitch.credential_configured?(Process.get(:test_community))
  end

  test "the simulator cannot be opened unless explicitly enabled", %{conn: conn} do
    Application.put_env(:backlog_wheel, :twitch_simulator, false)
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/dev/twitch-simulator")
  end

  test "the simulator cannot connect a channel when disabled" do
    community = Process.get(:test_community)
    Application.put_env(:backlog_wheel, :twitch_simulator, false)
    assert {:error, :simulator_disabled} = BacklogWheel.Twitch.SimulatorClient.connect(community)
    refute Twitch.credential_configured?(community)
  end

  test "an unknown redemption produces a visible error", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dev/twitch-simulator")
    view |> element("#simulator-connect") |> render_click()
    render_click(view, "deliver", %{"id" => "unknown-redemption"})
    assert has_element?(view, "#flash-error", "Could not deliver")
  end

  test "a sample vote is available for a fresh sandbox", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dev/twitch-simulator")
    view |> element("#simulator-connect") |> render_click()
    view |> element("#simulator-create-sample") |> render_click()
    assert has_element?(view, "#simulator-sample-vote-link")
  end

  test "finished reward cleanup is visible in simulator history", %{conn: conn} do
    community = Process.get(:test_community)
    session = voting_session_fixture(%{community: community})

    voting_session_game_fixture(
      session,
      game_fixture(%{community: community, external_id: "first"})
    )

    voting_session_game_fixture(
      session,
      game_fixture(%{community: community, external_id: "second"})
    )

    {:ok, view, _html} = live(conn, "/dev/twitch-simulator")
    view |> element("#simulator-connect") |> render_click()
    assert {:ok, opened} = Voting.start_twitch_voting(session)
    assert {:ok, _} = Voting.close_voting_session(opened, "closed")
    assert :ok = Voting.cleanup_finished_twitch_rewards()
    assert has_element?(view, "#simulator-deleted-rewards", "Backlog Wheel Vote")
  end

  defp restore(key, nil), do: Application.delete_env(:backlog_wheel, key)
  defp restore(key, value), do: Application.put_env(:backlog_wheel, key, value)
end
