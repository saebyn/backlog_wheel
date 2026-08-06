defmodule BacklogWheelWeb.QuickWheelLiveTest do
  use BacklogWheelWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders an empty quick wheel", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/quick-wheel")

    assert has_element?(view, "#quick-wheel-page")
    assert has_element?(view, "#quick-wheel-title-form")
    assert has_element?(view, "#quick-wheel-entry-form")
    assert has_element?(view, "#quick-wheel-paste-form")
    assert has_element?(view, "#quick-wheel-entry-count", "0")
    assert has_element?(view, "#quick-wheel-empty", "Add entries to start spinning.")
  end

  test "adds, edits, and removes free-form entries", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/quick-wheel")

    view
    |> form("#quick-wheel-entry-form", entry: %{title: "First option"})
    |> render_submit()

    assert_push_event(view, "quick-wheel:entry-added", %{})

    assert has_element?(view, "#quick-wheel-entry-count", "1")
    assert has_element?(view, "#quick-wheel-entry-title-1[value='First option']")

    view
    |> form("#quick-wheel-edit-entry-form-1", entry: %{id: "1", title: "Edited option"})
    |> render_change()

    assert has_element?(view, "#quick-wheel-entry-title-1[value='Edited option']")

    view
    |> element("#quick-wheel-remove-entry-1")
    |> render_click()

    assert has_element?(view, "#quick-wheel-entry-count", "0")
    refute has_element?(view, "#quick-wheel-entry-1")
  end

  test "pastes multiple entries one per line", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/quick-wheel")

    view
    |> form("#quick-wheel-paste-form", paste: %{entries: "Alpha\n\nBeta\nGamma"})
    |> render_submit()

    assert has_element?(view, "#quick-wheel-entry-count", "3")
    assert has_element?(view, "#quick-wheel-entry-title-1[value='Alpha']")
    assert has_element?(view, "#quick-wheel-entry-title-2[value='Beta']")
    assert has_element?(view, "#quick-wheel-entry-title-3[value='Gamma']")
  end

  test "spins to select a winner after animation", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/quick-wheel")

    view
    |> form("#quick-wheel-entry-form", entry: %{title: "Only choice"})
    |> render_submit()

    assert view |> element("#quick-wheel-spin-button") |> render_click()

    assert_push_event(view, "roulette:spin", %{
      "landingDegrees" => 180.0,
      "durationMs" => 5_000,
      "fullTurns" => 8,
      "spinId" => spin_id,
      "segments" => [segment]
    })

    assert segment["entry_id"] == 1
    assert segment["start_degrees"] == 0.0
    assert segment["end_degrees"] == 360.0

    refute has_element?(view, "#quick-wheel-result", "Only choice")

    assert render_hook(view, "spin_finished", %{"spinId" => spin_id})
    assert has_element?(view, "#quick-wheel-result", "Only choice")
    assert has_element?(view, "#quick-wheel-winner-modal", "Only choice")

    view
    |> element("#quick-wheel-dismiss-winner")
    |> render_click()

    refute has_element?(view, "#quick-wheel-winner-modal")
  end
end
