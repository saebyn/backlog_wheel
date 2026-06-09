defmodule BacklogWheelWeb.TwitchOAuthControllerTest do
  use BacklogWheelWeb.ConnCase, async: false

  alias BacklogWheel.Twitch

  setup do
    original_config = Application.get_env(:backlog_wheel, :twitch)
    original_client = Application.get_env(:backlog_wheel, :twitch_client)

    Application.put_env(:backlog_wheel, :twitch,
      client_id: "client-id",
      client_secret: "client-secret",
      broadcaster_id: "broadcaster-id"
    )

    Application.put_env(:backlog_wheel, :twitch_client, BacklogWheel.FakeTwitchClient)

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

    assert redirected_to(conn) == ~p"/voting"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Twitch connected"
    assert Twitch.get_credential().access_token == "access-token"
  end

  test "callback rejects mismatched state", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(twitch_oauth_state: "state-1")
      |> get(~p"/twitch/oauth/callback?#{[code: "valid-code", state: "wrong-state"]}")

    assert redirected_to(conn) == ~p"/voting"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Twitch authorization state did not match"

    refute Twitch.get_credential()
  end

  defp restore_env(key, nil), do: Application.delete_env(:backlog_wheel, key)
  defp restore_env(key, value), do: Application.put_env(:backlog_wheel, key, value)
end
