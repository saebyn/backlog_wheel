defmodule BacklogWheelWeb.WheelLiveTest do
  use BacklogWheelWeb.ConnCase

  import Phoenix.LiveViewTest
  import BacklogWheel.BacklogFixtures

  alias BacklogWheel.Backlog

  test "renders wheel with no candidates", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/wheel")

    assert html =~ "Wheel"
    assert html =~ "No spins yet"
    assert html =~ "0"
  end

  test "spins, records, and reveals a selected game after animation", %{conn: conn} do
    game = game_fixture(%{title: "Wheel Game", include_in_wheel: true, played_on_stream: true})

    {:ok, view, _html} = live(conn, ~p"/wheel")

    assert has_element?(view, "#wheel-candidate-count", "1")
    assert view |> element("#spin-wheel-button") |> render_click()
    assert has_element?(view, "#wheel-spinning")
    refute has_element?(view, "#spin-history", game.title)

    [spin] = Backlog.list_recent_spins()

    assert render_hook(view, "spin_finished", %{"spinId" => spin.id})
    assert has_element?(view, "#wheel-result", game.title)
    assert has_element?(view, "#wheel-winner-modal", game.title)
    assert has_element?(view, "#spin-history", game.title)

    assert view |> element("#dismiss-winner-modal") |> render_click()
    refute has_element?(view, "#wheel-winner-modal")
  end
end
