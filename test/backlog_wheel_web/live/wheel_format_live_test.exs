defmodule BacklogWheelWeb.WheelFormatLiveTest do
  use BacklogWheelWeb.ConnCase

  import Phoenix.LiveViewTest
  import BacklogWheel.BacklogFixtures
  import BacklogWheel.VotingFixtures

  alias BacklogWheel.Voting

  test "lists Wheel Formats for the current community", %{conn: conn} do
    community = Process.get(:test_community)
    other_community = community_fixture(%{slug: "other-format-community"})
    format = wheel_format_fixture(%{community: community, name: "Community Format"})
    other_format = wheel_format_fixture(%{community: other_community, name: "Other Format"})

    {:ok, view, _html} = live(conn, ~p"/settings/formats")

    assert has_element?(view, "#wheel-format-management")
    assert has_element?(view, "#settings-nav-general", "General")
    assert has_element?(view, "#settings-nav-theme", "Theme")
    assert has_element?(view, "#settings-nav-formats", "Wheel Formats")
    assert has_element?(view, "#settings-nav-twitch", "Twitch")
    assert has_element?(view, "#create-wheel-format", "Create Wheel Format")
    assert has_element?(view, "#wheel-format-#{format.id}", "Community Format")
    assert has_element?(view, "#edit-wheel-format-#{format.id}.btn", "Edit")
    assert has_element?(view, "#toggle-wheel-format-#{format.id}.btn", "Disable")
    refute has_element?(view, "#wheel-format-#{other_format.id}")
    assert has_element?(view, "#wheel-formats-list", "Fresh backlog")
  end

  test "creates a custom Wheel Format", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/formats")

    view
    |> form("#wheel-format-form",
      wheel_format: %{
        name: "Short Vote",
        description: "Quick community choice.",
        default_session_title: "Short Vote Night",
        default_session_description: "Pick something short.",
        is_enabled: "true",
        include_in_wheel: "true",
        unplayed_only: "true",
        base_weight: "3"
      }
    )
    |> render_submit()

    assert has_element?(view, "#wheel-formats-list", "Short Vote")
    assert has_element?(view, "#wheel-formats-list", "Unplayed games only")

    format =
      Process.get(:test_community)
      |> Voting.list_all_wheel_formats()
      |> Enum.find(&(&1.name == "Short Vote"))

    assert format.default_session_title == "Short Vote Night"
    assert format.candidate_rules["played_on_stream"] == false
    assert format.weighting_rules["base_weight"] == 3
  end

  test "edits and enables or disables a custom Wheel Format", %{conn: conn} do
    format = wheel_format_fixture(%{name: "Original Format"})

    {:ok, view, _html} = live(conn, ~p"/settings/formats")

    view
    |> form("#wheel-format-form",
      wheel_format: %{
        name: "Unsubmitted Create Format",
        description: "Draft create copy.",
        default_session_title: "Draft Create Vote",
        default_session_description: "Draft create session copy.",
        is_enabled: "true",
        include_in_wheel: "true",
        unplayed_only: "false",
        base_weight: "1"
      }
    )
    |> render_change()

    assert has_element?(
             view,
             "#edit-wheel-format-#{format.id}[data-confirm='Discard unsaved changes and edit this Wheel Format?']"
           )

    view |> element("#create-wheel-format") |> render_click()

    assert has_element?(view, "#wheel_format_name[value='Unsubmitted Create Format']")

    view |> element("#edit-wheel-format-#{format.id}") |> render_click()

    assert has_element?(view, "#wheel-format-editor.scroll-mt-24")
    assert has_element?(view, "#wheel-format-form-title", "Edit Format")
    assert has_element?(view, "#new-wheel-format.btn-warning", "Cancel Edit")

    view |> element("#create-wheel-format") |> render_click()

    assert has_element?(view, "#wheel-format-form-title", "Create Format")
    refute has_element?(view, "#new-wheel-format")

    view |> element("#edit-wheel-format-#{format.id}") |> render_click()

    view
    |> form("#wheel-format-form",
      wheel_format: %{
        name: "Changed Format",
        description: "Changed copy.",
        default_session_title: "Changed Vote",
        default_session_description: "Changed session copy.",
        is_enabled: "true",
        include_in_wheel: "true",
        unplayed_only: "false",
        base_weight: "2"
      }
    )
    |> render_change()

    assert has_element?(
             view,
             "#create-wheel-format[data-confirm='Discard unsaved changes and create a new Wheel Format?']"
           )

    default_format =
      Process.get(:test_community)
      |> Voting.list_all_wheel_formats()
      |> Enum.find(& &1.is_default)

    assert has_element?(
             view,
             "#edit-wheel-format-#{format.id}[data-confirm='Discard unsaved changes and edit this Wheel Format?']"
           )

    assert has_element?(
             view,
             "#edit-wheel-format-#{default_format.id}[data-confirm='Discard unsaved changes and edit this Wheel Format?']"
           )

    view
    |> form("#wheel-format-form",
      wheel_format: %{
        name: "Updated Format",
        description: "Updated copy.",
        default_session_title: "Updated Vote",
        default_session_description: "Updated session copy.",
        is_enabled: "true",
        include_in_wheel: "true",
        unplayed_only: "false",
        base_weight: "2"
      }
    )
    |> render_submit()

    assert has_element?(view, "#wheel-format-#{format.id}", "Updated Format")
    assert has_element?(view, "#start-wheel-format-#{format.id}")

    view |> element("#toggle-wheel-format-#{format.id}") |> render_click()

    assert has_element?(view, "#wheel-format-#{format.id}", "Disabled")
    refute has_element?(view, "#start-wheel-format-#{format.id}")
  end

  test "removes custom Wheel Formats and protects seeded defaults", %{conn: conn} do
    format = wheel_format_fixture(%{name: "Remove Me"})

    {:ok, view, _html} = live(conn, ~p"/settings/formats")

    default_format =
      Process.get(:test_community)
      |> Voting.list_all_wheel_formats()
      |> Enum.find(& &1.is_default)

    assert has_element?(view, "#protected-wheel-format-#{default_format.id}", "Removal protected")

    assert has_element?(
             view,
             "#protected-wheel-format-#{default_format.id}[title=\"Can't delete the default formats\"]"
           )

    view |> element("#delete-wheel-format-#{format.id}") |> render_click()

    refute has_element?(view, "#wheel-format-#{format.id}")
  end

  test "links enabled Wheel Formats to voting session creation", %{conn: conn} do
    format = wheel_format_fixture(%{name: "Startable Format"})

    {:ok, view, _html} = live(conn, ~p"/settings/formats")

    assert has_element?(
             view,
             "#start-wheel-format-#{format.id}[href='/voting?wheel_format_id=#{format.id}']",
             "Start Vote"
           )
  end
end
