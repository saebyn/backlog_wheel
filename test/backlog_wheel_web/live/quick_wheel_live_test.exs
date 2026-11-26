defmodule BacklogWheelWeb.QuickWheelLiveTest do
  use BacklogWheelWeb.ConnCase

  import Phoenix.LiveViewTest

  test "current wheel autosaves and presets retain edits only after explicit save", %{conn: conn} do
    {:ok, current, _} = live(conn, ~p"/quick-wheel")

    current
    |> form("#quick-wheel-entry-form", entry: %{entries: "Alpha\nBeta"})
    |> render_change()

    [path] =
      current
      |> element("#quick-wheel-entry-form ~ button", "Save as preset")
      |> render_click()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#quick-wheel-entry-form ~ #quick-wheel-navigation a:not([target])")
      |> LazyHTML.attribute("href")

    {:ok, editor, _} = live(conn, path)
    assert textarea_value(editor) == "Alpha\nBeta"

    editor
    |> form("#quick-wheel-entry-form", entry: %{entries: "Beta"})
    |> render_change()

    editor |> element("#quick-wheel-spin-button") |> render_click()
    assert_push_event(editor, "roulette:spin", %{"segments" => [_]})

    {:ok, before_save, _} = live(conn, path)
    assert textarea_value(before_save) == "Alpha\nBeta"
    editor |> element("#quick-wheel-entry-form ~ button", "Save changes") |> render_click()
    {:ok, after_save, _} = live(conn, path)
    assert textarea_value(after_save) == "Beta"
    assert has_element?(after_save, "#quick-wheel-entry-count", "1")
    assert has_element?(after_save, "#quick-wheel-rotor text", "Beta")
    {:ok, restored, _} = live(conn, ~p"/quick-wheel")
    assert textarea_value(restored) == "Alpha\nBeta"
    assert has_element?(restored, "#quick-wheel-entry-count", "2")
  end

  test "renders an empty quick wheel", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/quick-wheel")

    assert has_element?(view, "#quick-wheel-page")
    assert has_element?(view, "#quick-wheel-volume[phx-update='ignore']")
    assert has_element?(view, "#quick-wheel-volume-slider[type='range'][min='0'][max='100']")
    assert has_element?(view, "#quick-wheel-title-form")
    assert has_element?(view, "#quick-wheel-entry-form textarea")
    refute has_element?(view, "#quick-wheel-entry-form button")
    refute has_element?(view, "#quick-wheel-paste-form")
    refute has_element?(view, "#quick-wheel-entries")
    assert has_element?(view, "#quick-wheel-entry-count", "0")
    assert has_element?(view, "#quick-wheel-spin-button[disabled]")
  end

  test "starts the sidebar with the spin button and no introductory heading", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/quick-wheel")

    assert has_element?(view, "#quick-wheel-page aside > #quick-wheel-spin-button:first-child")
    refute has_element?(view, "#quick-wheel-page aside h1")

    refute has_element?(
             view,
             "#quick-wheel-page aside p",
             "Spin any free-form list without touching games, votes, or Twitch."
           )
  end

  test "typing, editing, and deleting lines updates the wheel without submitting", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/quick-wheel")

    view
    |> form("#quick-wheel-entry-form", entry: %{entries: "First option"})
    |> render_change()

    assert has_element?(view, "#quick-wheel-entry-count", "1")
    assert has_element?(view, "#quick-wheel-rotor text", "First option")
    refute has_element?(view, "#quick-wheel-spin-button[disabled]")

    view
    |> form("#quick-wheel-entry-form", entry: %{entries: "Edited option"})
    |> render_change()

    assert has_element?(view, "#quick-wheel-rotor text", "Edited option")
    refute has_element?(view, "#quick-wheel-rotor text", "First option")

    view
    |> form("#quick-wheel-entry-form", entry: %{entries: ""})
    |> render_change()

    assert has_element?(view, "#quick-wheel-entry-count", "0")
    assert has_element?(view, "#quick-wheel-spin-button[disabled]")
    refute has_element?(view, "#quick-wheel-rotor text")
  end

  test "pastes entries in line order, keeping duplicates but skipping blank lines", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/quick-wheel")
    value = "  Beta  \n\n  \nAlpha, first\nBeta\n"

    view
    |> form("#quick-wheel-entry-form", entry: %{entries: value})
    |> render_change()

    assert textarea_value(view) == value
    assert has_element?(view, "#quick-wheel-entry-count", "3")
    assert has_element?(view, "#quick-wheel-rotor g > text:nth-of-type(1)", "Beta")
    assert has_element?(view, "#quick-wheel-rotor g > text:nth-of-type(2)", "Alpha, first")
    assert has_element?(view, "#quick-wheel-rotor g > text:nth-of-type(3)", "Beta")

    {:ok, restored, _} = live(conn, ~p"/quick-wheel")
    assert textarea_value(restored) == "Beta\nAlpha, first\nBeta"
  end

  test "editing a wedge during a spin leaves its rotation under client control", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/quick-wheel")

    view
    |> form("#quick-wheel-entry-form", entry: %{entries: "Original"})
    |> render_change()

    view |> element("#quick-wheel-spin-button") |> render_click()
    assert_push_event(view, "roulette:spin", %{})

    view
    |> form("#quick-wheel-entry-form", entry: %{entries: "Updated"})
    |> render_change()

    assert has_element?(view, "#quick-wheel-rotor text", "Updated")

    assert has_element?(
             view,
             ~s(#quick-wheel-rotor[phx-mounted*='"ignore_attrs"'][phx-mounted*='"style"'])
           )
  end

  test "spins to select a winner after animation", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/quick-wheel")

    view
    |> form("#quick-wheel-entry-form", entry: %{entries: "Only choice"})
    |> render_change()

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

  defp textarea_value(view) do
    view
    |> element("#quick-wheel-entry-form textarea")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
  end
end
