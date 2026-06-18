defmodule BacklogWheelWeb.TwitchOAuthControllerTest do
  use BacklogWheelWeb.ConnCase, async: false

  alias BacklogWheel.Communities
  alias BacklogWheel.Twitch

  setup do
    original_config = Application.get_env(:backlog_wheel, :twitch)
    original_client = Application.get_env(:backlog_wheel, :twitch_client)

    Application.put_env(:backlog_wheel, :twitch,
      client_id: "client-id",
      client_secret: "client-secret"
    )

    Application.put_env(:backlog_wheel, :twitch_client, BacklogWheel.FakeTwitchClient)
    start_supervised!(BacklogWheel.FakeTwitchClient)

    on_exit(fn ->
      restore_env(:twitch, original_config)
      restore_env(:twitch_client, original_client)
    end)

    :ok
  end

  test "start redirects to Twitch authorization", %{conn: conn} do
    conn = get(conn, ~p"/twitch/oauth/start")

    assert redirected_to(conn) =~ "https://id.twitch.tv/oauth2/authorize"
    assert redirected_to(conn) =~ "state="
    assert get_session(conn, :twitch_oauth_state)
  end

  test "callback exchanges code and stores credential", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(twitch_oauth_state: "state-1")
      |> get(~p"/twitch/oauth/callback?#{[code: "valid-code", state: "state-1"]}")

    assert redirected_to(conn) == ~p"/settings/twitch"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Twitch connected"
    assert Twitch.get_credential().access_token == "access-token"

    community = Communities.get_community!(Process.get(:test_community).id)
    assert community.twitch_broadcaster_id == "28728577"
    assert community.twitch_broadcaster_login == "teststreamer"
    assert community.twitch_broadcaster_display_name == "TestStreamer"
    assert is_binary(community.twitch_eventsub_secret)
    refute community.twitch_eventsub_secret == ""
  end

  test "callback creates EventSub subscription when configured", %{conn: conn} do
    Application.put_env(:backlog_wheel, :twitch,
      client_id: "client-id",
      client_secret: "client-secret",
      eventsub_callback_url: "https://example.com/twitch/eventsub"
    )

    {:ok, community} =
      Communities.update_community_twitch_settings(Process.get(:test_community), %{
        twitch_eventsub_secret: "eventsub-secret"
      })

    Process.put(:test_community, community)

    conn =
      conn
      |> Plug.Test.init_test_session(twitch_oauth_state: "state-1")
      |> get(~p"/twitch/oauth/callback?#{[code: "valid-code", state: "state-1"]}")

    assert redirected_to(conn) == ~p"/settings/twitch"
    assert Twitch.get_credential().access_token == "access-token"

    community = Communities.get_community!(Process.get(:test_community).id)
    assert community.twitch_broadcaster_id == "28728577"
    assert community.twitch_broadcaster_login == "teststreamer"
    assert community.twitch_broadcaster_display_name == "TestStreamer"
    assert community.twitch_eventsub_secret != "eventsub-secret"

    assert BacklogWheel.FakeTwitchClient.eventsub_callback_url() ==
             "https://example.com/twitch/eventsub"
  end

  test "callback rejects mismatched state", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(twitch_oauth_state: "state-1")
      |> get(~p"/twitch/oauth/callback?#{[code: "valid-code", state: "wrong-state"]}")

    assert redirected_to(conn) == ~p"/settings/twitch"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Twitch authorization state did not match"

    refute Twitch.get_credential()
  end

  defp restore_env(key, nil), do: Application.delete_env(:backlog_wheel, key)
  defp restore_env(key, value), do: Application.put_env(:backlog_wheel, key, value)
end
