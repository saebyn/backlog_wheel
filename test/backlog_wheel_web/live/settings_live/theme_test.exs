defmodule BacklogWheelWeb.SettingsLive.ThemeTest do
  use BacklogWheelWeb.ConnCase

  import Phoenix.LiveViewTest

  alias BacklogWheel.Communities

  test "renders theme settings", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/theme")

    assert has_element?(view, "#theme-form")
    assert has_element?(view, "#light-theme-preview")
    assert has_element?(view, "#dark-theme-preview")

    assert has_element?(
             view,
             "#community_light_primary_color-picker[phx-hook='ThemeColorPicker']"
           )

    assert has_element?(
             view,
             "#community_dark_background_color-picker[phx-hook='ThemeColorPicker']"
           )

    refute has_element?(view, "#theme-form", "Wallpaper URL")
  end

  test "validates theme settings", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/theme")

    view
    |> form("#theme-form",
      community: %{
        light_primary_color: "orange"
      }
    )
    |> render_change()

    assert has_element?(view, "#theme-form", "must be a hex color")
  end

  test "saves theme settings", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/theme")

    view
    |> form("#theme-form",
      community: %{
        light_primary_color: "#123abc",
        light_accent_color: "#abcdef",
        light_background_color: "#f8fafc",
        dark_primary_color: "#fedcba",
        dark_accent_color: "#654321",
        dark_background_color: "#111827"
      }
    )
    |> render_submit()

    assert has_element?(view, "#flash-info", "Theme updated successfully")

    community = Communities.get_community!(Process.get(:test_community).id)

    assert community.light_primary_color == "#123abc"
    assert community.dark_background_color == "#111827"
  end

  test "renders saved theme variables in the app shell", %{conn: conn} do
    community = Process.get(:test_community)

    assert {:ok, _community} =
             Communities.update_community_theme(community, %{
               "light_primary_color" => "#123abc",
               "dark_background_color" => "#111827"
             })

    {:ok, view, _html} = live(conn, ~p"/settings/theme")

    assert has_element?(view, ~s|#app-theme[style*="--theme-light-primary: #123abc;"]|)
    assert has_element?(view, ~s|#app-theme[style*="--theme-dark-background: #111827;"]|)
  end

  test "resets theme settings", %{conn: conn} do
    community = Process.get(:test_community)

    assert {:ok, _community} =
             Communities.update_community_theme(community, %{
               "light_primary_color" => "#123abc",
               "dark_background_color" => "#111827"
             })

    {:ok, view, _html} = live(conn, ~p"/settings/theme")

    assert view |> element("#reset-theme-button") |> render_click()
    assert has_element?(view, "#flash-info", "Theme reset to defaults")

    community = Communities.get_community!(Process.get(:test_community).id)

    assert community.light_primary_color == nil
    assert community.dark_background_color == nil
  end
end
