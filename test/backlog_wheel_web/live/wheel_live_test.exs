defmodule BacklogWheelWeb.WheelLiveTest do
  use BacklogWheelWeb.ConnCase

  import Phoenix.LiveViewTest
  import BacklogWheel.BacklogFixtures
  import BacklogWheel.VotingFixtures

  alias BacklogWheel.Backlog

  test "renders voting wheel with no sessions", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/wheel")

    assert html =~ "Voting Wheel"
    assert html =~ "Create a voting session before spinning the wheel."
    assert html =~ "No spins yet"
    assert html =~ "0"
  end

  test "renders weighted voting session candidates", %{conn: conn} do
    voting_session = voting_session_fixture()
    first_game = game_fixture(%{title: "Small Slice"})
    second_game = game_fixture(%{title: "Big Slice", external_id: "big-slice"})
    first_pool_item = voting_session_game_fixture(voting_session, first_game, %{base_weight: 1})
    second_pool_item = voting_session_game_fixture(voting_session, second_game, %{base_weight: 2})

    voting_boost_fixture(second_pool_item, nil, %{strength: 3})

    {:ok, view, _html} = live(conn, ~p"/wheel?voting_session_id=#{voting_session.id}")

    assert has_element?(
             view,
             "#roulette-wheel-hook[data-voting-session-id='#{voting_session.id}']"
           )

    assert has_element?(view, "#roulette-wheel-hook[data-initial-rotation='0']")

    assert has_element?(view, "#wheel-candidate-count", "2")
    assert has_element?(view, "#wheel-total-weight", "Total weight: 6")
    assert has_element?(view, "#wheel-candidate-#{first_pool_item.id}", "1")
    assert has_element?(view, "#wheel-candidate-#{second_pool_item.id}", "5")

    assert has_element?(
             view,
             "#wheel-weighted-candidates",
             "Starting votes 2 + channel point votes 3"
           )
  end

  test "spins a voting session, records, and reveals a selected game after animation", %{
    conn: conn
  } do
    voting_session = voting_session_fixture()
    game = game_fixture(%{title: "Voting Wheel Game", include_in_wheel: false})
    voting_session_game_fixture(voting_session, game)

    {:ok, view, _html} = live(conn, ~p"/wheel?voting_session_id=#{voting_session.id}")

    assert has_element?(view, "#wheel-candidate-count", "1")
    assert view |> element("#spin-wheel-button") |> render_click()

    voting_session_id = voting_session.id
    expected_game_id = game.id

    assert_push_event(view, "roulette:spin", %{
      "votingSessionId" => ^voting_session_id,
      "gameId" => ^expected_game_id,
      "landingDegrees" => landing_degrees,
      "durationMs" => 30_000,
      "fullTurns" => 12,
      "segments" => [%{"game_id" => game_id} = segment]
    })

    assert game_id == expected_game_id
    assert landing_degrees > 18.0
    assert landing_degrees < 342.0
    assert segment["start_degrees"] == 0.0
    assert segment["end_degrees"] == 360.0
    assert has_element?(view, "#wheel-spinning")
    refute has_element?(view, "#spin-history", game.title)

    [spin] = Backlog.list_recent_spins()
    assert spin.source == "voting_session"

    assert render_hook(view, "spin_finished", %{"spinId" => spin.id})

    assert has_element?(
             view,
             "#roulette-wheel-hook[data-initial-rotation='#{360 - landing_degrees}']"
           )

    assert has_element?(view, "#wheel-result", game.title)
    assert has_element?(view, "#wheel-winner-modal", game.title)
    assert has_element?(view, "#spin-history", game.title)

    assert view |> element("#dismiss-winner-modal") |> render_click()
    refute has_element?(view, "#wheel-winner-modal")
  end

  test "selects voting session from wheel page", %{conn: conn} do
    first_session = voting_session_fixture()
    first_game = game_fixture(%{title: "First Session Game"})
    voting_session_game_fixture(first_session, first_game)

    second_session = voting_session_fixture()
    second_game = game_fixture(%{title: "Second Session Game", external_id: "second-session"})
    voting_session_game_fixture(second_session, second_game)

    {:ok, view, _html} = live(conn, ~p"/wheel?voting_session_id=#{first_session.id}")

    assert has_element?(view, "#wheel-weighted-candidates", first_game.title)
    refute has_element?(view, "#wheel-weighted-candidates", second_game.title)

    assert view |> element("#select-wheel-session-#{second_session.id}") |> render_click()

    assert has_element?(view, "#wheel-weighted-candidates", second_game.title)
    refute has_element?(view, "#wheel-weighted-candidates", first_game.title)
  end

  test "broadcasts the same spin payload to multiple wheel windows", %{conn: conn} do
    voting_session = voting_session_fixture()
    game = game_fixture(%{title: "Shared Spin Game"})
    voting_session_game_fixture(voting_session, game)

    {:ok, first_view, _html} = live(conn, ~p"/wheel?voting_session_id=#{voting_session.id}")
    {:ok, second_view, _html} = live(conn, ~p"/wheel?voting_session_id=#{voting_session.id}")

    assert first_view |> element("#spin-wheel-button") |> render_click()

    assert_push_event(first_view, "roulette:spin", first_payload)
    assert_push_event(second_view, "roulette:spin", second_payload)
    assert first_payload == second_payload
  end

  test "refreshes selected voting session weights from pubsub", %{conn: conn} do
    voting_session = voting_session_fixture()
    game = game_fixture(%{title: "Live Boost Game"})
    pool_item = voting_session_game_fixture(voting_session, game, %{base_weight: 1})

    {:ok, view, _html} = live(conn, ~p"/wheel?voting_session_id=#{voting_session.id}")

    assert has_element?(view, "#wheel-candidate-#{pool_item.id}", "1")

    voting_boost_fixture(pool_item, nil, %{strength: 3})

    assert has_element?(view, "#wheel-candidate-#{pool_item.id}", "4")
    assert has_element?(view, "#wheel-total-weight", "Total weight: 4")
  end
end
