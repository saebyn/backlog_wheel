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

    assert has_element?(view, "h1", "Twitch integration")
    assert has_element?(view, "#twitch-connected-account")
    assert has_element?(view, "#twitch-settings-connection-status", "Not connected")
    assert has_element?(view, "#twitch-settings-account-status", "Not connected")
    refute has_element?(view, "#twitch-settings-config-status")
    refute has_element?(view, "#twitch-settings-reward-cost")

    assert has_element?(
             view,
             "#twitch-settings-channel-name",
             "Connect Twitch to choose a channel"
           )

    assert has_element?(
             view,
             "#twitch-settings-broadcaster-id",
             "Available after connecting Twitch"
           )

    assert has_element?(view, "#twitch-settings-capability")
    assert has_element?(view, "#settings-nav-general", "General")
    assert has_element?(view, "#settings-nav-theme", "Theme")
    assert has_element?(view, "#settings-nav-formats", "Wheel Formats")
    assert has_element?(view, "#settings-nav-twitch", "Twitch")
    assert has_element?(view, "#connect-twitch", "Connect Twitch")
    assert has_element?(view, "#disconnect-twitch[disabled]")
    assert has_element?(view, "#twitch-settings-form")
    assert has_element?(view, "#twitch-settings-reward-cost-help")
    assert has_element?(view, "#save-twitch-settings", "Save changes")
    refute has_element?(view, "#back-to-voting")
    refute has_element?(view, "#twitch-settings-eventsub-status")
    refute has_element?(view, "#twitch-settings-eventsub-secret-status")
    refute has_element?(view, "#twitch-settings-eventsub-warning")
    refute has_element?(view, "#rotate-eventsub-secret")
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
    assert community.twitch_broadcaster_login == nil
    assert community.twitch_broadcaster_display_name == nil
    assert community.twitch_reward_cost == 250
    assert community.twitch_eventsub_secret == nil
  end

  test "shows reconnect and disconnect when Twitch is connected", %{conn: conn} do
    {:ok, _credential} =
      Twitch.save_credential(%{
        access_token: "access-token",
        refresh_token: "refresh-token",
        scopes: "channel:manage:redemptions"
      })

    {:ok, community} =
      Communities.update_community_twitch_settings(Process.get(:test_community), %{
        twitch_broadcaster_id: "28728577",
        twitch_broadcaster_login: "teststreamer",
        twitch_broadcaster_display_name: "TestStreamer"
      })

    Process.put(:test_community, community)

    {:ok, view, _html} = live(conn, ~p"/settings/twitch")

    assert has_element?(view, "#twitch-settings-connection-status", "Connected")
    assert has_element?(view, "#twitch-settings-account-status", "Connected")
    assert has_element?(view, "#twitch-settings-channel-name", "TestStreamer")
    assert has_element?(view, "#twitch-settings-broadcaster-id", "28728577")
    assert has_element?(view, "#connect-twitch.btn-secondary", "Reconnect Twitch")
    assert has_element?(view, "#disconnect-twitch.btn-error", "Disconnect Twitch")
    assert has_element?(view, "#disconnect-twitch[data-confirm]")
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
