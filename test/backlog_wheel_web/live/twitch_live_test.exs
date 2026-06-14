defmodule BacklogWheelWeb.TwitchLiveTest do
  use BacklogWheelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias BacklogWheel.Twitch

  setup do
    original_config = Application.get_env(:backlog_wheel, :twitch)

    Application.put_env(:backlog_wheel, :twitch,
      client_id: "client-id",
      client_secret: "client-secret",
      broadcaster_id: "broadcaster-id",
      reward_cost: 123
    )

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
    assert has_element?(view, "#twitch-settings-config-status", "Configured")
    assert has_element?(view, "#twitch-settings-reward-cost", "123")
    assert has_element?(view, "#settings-nav-theme", "Theme")
    assert has_element?(view, "#connect-twitch", "Connect Twitch")
    assert has_element?(view, "#disconnect-twitch[disabled]")
    assert has_element?(view, "#twitch-settings-eventsub-status", "Missing secret")
    assert has_element?(view, "#twitch-settings-eventsub-warning")
  end

  test "shows EventSub configured when signing secret exists", %{conn: conn} do
    Application.put_env(:backlog_wheel, :twitch,
      client_id: "client-id",
      client_secret: "client-secret",
      broadcaster_id: "broadcaster-id",
      reward_cost: 123,
      eventsub_secret: "eventsub-secret"
    )

    {:ok, view, _html} = live(conn, ~p"/settings/twitch")

    assert has_element?(view, "#twitch-settings-eventsub-status", "Configured")
    refute has_element?(view, "#twitch-settings-eventsub-warning")
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
