defmodule BacklogWheelWeb.SettingsLive.GeneralTest do
  use BacklogWheelWeb.ConnCase

  import Phoenix.LiveViewTest

  alias BacklogWheel.Communities
  alias BacklogWheel.Communities.Community
  alias BacklogWheel.Repo

  test "renders general settings", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    assert has_element?(view, "#general-settings-form")
    assert has_element?(view, "#settings-nav-general", "General")
    assert has_element?(view, "#settings-nav-theme", "Theme")
    assert has_element?(view, "#settings-nav-formats", "Wheel Formats")
    assert has_element?(view, "#settings-nav-twitch", "Twitch")
  end

  test "validates general settings", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    view
    |> form("#general-settings-form",
      community: %{
        name: "",
        slug: ""
      }
    )
    |> render_change()

    assert has_element?(view, "#general-settings-form", "can't be blank")
  end

  test "saves general settings", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    view
    |> form("#general-settings-form",
      community: %{
        name: "Updated Community",
        slug: "Updated Community!"
      }
    )
    |> render_submit()

    assert has_element?(view, "#flash-info", "General settings updated successfully")

    community = Communities.get_community!(Process.get(:test_community).id)

    assert community.name == "Updated Community"
    assert community.slug == "updated-community"
  end

  test "shows duplicate slug errors", %{conn: conn} do
    duplicate =
      %Community{}
      |> Community.changeset(%{name: "Other Community", slug: "other-community"})
      |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/settings")

    view
    |> form("#general-settings-form",
      community: %{
        name: "Duplicate Community",
        slug: duplicate.slug
      }
    )
    |> render_submit()

    assert has_element?(view, "#general-settings-form", "has already been taken")
  end
end
