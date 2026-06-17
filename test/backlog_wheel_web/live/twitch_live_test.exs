defmodule BacklogWheelWeb.TwitchLiveTest do
  use BacklogWheelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias BacklogWheel.Twitch
  alias BacklogWheel.Communities

  setup do
    original_config = Application.get_env(:backlog_wheel, :twitch)

    Application.put_env(:backlog_wheel, :twitch,
      client_id: "client-id",
      client_secret: "client-secret"
    )

    {:ok, community} =
      Communities.update_community_twitch_settings(Process.get(:test_community), %{
        twitch_reward_cost: 123
      })

    Process.put(:test_community, community)

    on_exit(fn ->
      if is_nil(original_config) do
        Application.delete_env(:backlog_wheel, :twitch)
      else
        Application.put_env(:backlog_wheel, :twitch, original_config)
      end
    end)

    :ok
  end

  test "shows Twitch connection status and connect action", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/twitch")

    assert has_element?(view, "#twitch-settings-connection-status", "Not connected")
    refute has_element?(view, "#twitch-settings-config-status")
    assert has_element?(view, "#twitch-settings-reward-cost", "123")
    assert has_element?(view, "#twitch-settings-broadcaster-id", "Connect Twitch")
    assert has_element?(view, "#settings-nav-general", "General")
    assert has_element?(view, "#settings-nav-theme", "Theme")
    assert has_element?(view, "#settings-nav-formats", "Wheel Formats")
    assert has_element?(view, "#settings-nav-twitch", "Twitch")
    assert has_element?(view, "#connect-twitch", "Connect Twitch")
    assert has_element?(view, "#disconnect-twitch[disabled]")
    assert has_element?(view, "#twitch-settings-eventsub-status", "Missing secret")
    assert has_element?(view, "#twitch-settings-eventsub-secret-status", "Missing")
    assert has_element?(view, "#twitch-settings-eventsub-warning")
    assert has_element?(view, "#twitch-settings-form")
    assert has_element?(view, "#rotate-eventsub-secret", "Generate EventSub secret")
  end

  test "shows EventSub configured when signing secret exists", %{conn: conn} do
    {:ok, community} =
      Communities.update_community_twitch_settings(Process.get(:test_community), %{
        twitch_reward_cost: 123,
        twitch_eventsub_secret: "eventsub-secret"
      })

    Process.put(:test_community, community)

    {:ok, view, _html} = live(conn, ~p"/settings/twitch")

    assert has_element?(view, "#twitch-settings-eventsub-status", "Configured")
    assert has_element?(view, "#twitch-settings-eventsub-secret-status", "Configured")
    assert has_element?(view, "#rotate-eventsub-secret", "Rotate EventSub secret")
    refute has_element?(view, "#twitch-settings-eventsub-warning")
  end

  test "saves editable community Twitch settings without exposing EventSub secret", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/twitch")

    view
    |> form("#twitch-settings-form",
      community: %{
        twitch_reward_cost: "250"
      }
    )
    |> render_submit()

    assert has_element?(view, "#flash-info", "Twitch settings updated successfully")

    community = Communities.get_community!(Process.get(:test_community).id)
    assert community.twitch_broadcaster_id == nil
    assert community.twitch_reward_cost == 250
    assert community.twitch_eventsub_secret == nil
  end

  test "generates and rotates EventSub secret server-side", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/twitch")

    assert view |> element("#rotate-eventsub-secret") |> render_click()
    assert has_element?(view, "#flash-info", "EventSub secret rotated")
    assert has_element?(view, "#twitch-settings-eventsub-secret-status", "Configured")

    community = Communities.get_community!(Process.get(:test_community).id)
    first_secret = community.twitch_eventsub_secret
    assert is_binary(first_secret)
    refute first_secret == ""

    assert view |> element("#rotate-eventsub-secret") |> render_click()

    community = Communities.get_community!(Process.get(:test_community).id)
    assert community.twitch_eventsub_secret != first_secret
  end

  test "shows reconnect and disconnect when Twitch is connected", %{conn: conn} do
    {:ok, _credential} =
      Twitch.save_credential(%{
        access_token: "access-token",
        refresh_token: "refresh-token",
        scopes: "channel:manage:redemptions"
      })

    {:ok, view, _html} = live(conn, ~p"/settings/twitch")

    assert has_element?(view, "#twitch-settings-connection-status", "Connected")
    assert has_element?(view, "#connect-twitch", "Reconnect Twitch")
    refute has_element?(view, "#disconnect-twitch[disabled]")
  end

  test "disconnect removes stored Twitch credential", %{conn: conn} do
    {:ok, _credential} =
      Twitch.save_credential(%{
        access_token: "access-token",
        refresh_token: "refresh-token",
        scopes: "channel:manage:redemptions"
      })

    {:ok, view, _html} = live(conn, ~p"/settings/twitch")

    assert view |> element("#disconnect-twitch") |> render_click()

    refute Twitch.credential_configured?()
    assert has_element?(view, "#twitch-settings-connection-status", "Not connected")
    assert has_element?(view, "#connect-twitch", "Connect Twitch")
  end
end
