defmodule BacklogWheelWeb.WheelLiveTest do
  use BacklogWheelWeb.ConnCase

  import Phoenix.LiveViewTest
  import BacklogWheel.BacklogFixtures

  test "renders wheel with no candidates", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/wheel")

    assert html =~ "Wheel"
    assert html =~ "No spins yet"
    assert html =~ "0"
  end

  test "spins and records a selected game", %{conn: conn} do
    game = game_fixture(%{title: "Wheel Game", include_in_wheel: true, played_on_stream: true})

    {:ok, view, _html} = live(conn, ~p"/wheel")

    assert has_element?(view, "#wheel-candidate-count", "1")
    assert view |> element("#spin-wheel-button") |> render_click()
    assert has_element?(view, "#wheel-result", game.title)
    assert has_element?(view, "#spin-history", game.title)
  end
end
