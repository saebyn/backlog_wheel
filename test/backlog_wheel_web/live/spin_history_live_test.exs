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
    game =
      game_fixture(%{
        title: "History Game",
        image_url: "https://example.com/history.jpg"
      })

    {:ok, _spin} =
      Backlog.create_spin(%{
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

  test "deletes spin history entries", %{conn: conn} do
    game = game_fixture(%{title: "Delete Me"})

    {:ok, spin} =
      Backlog.create_spin(%{
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
