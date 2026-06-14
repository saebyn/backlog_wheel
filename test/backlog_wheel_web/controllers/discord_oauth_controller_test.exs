defmodule BacklogWheelWeb.DiscordOAuthControllerTest do
  use BacklogWheelWeb.ConnCase, async: false

  @moduletag :unauthenticated

  alias BacklogWheel.Accounts
  alias BacklogWheel.Communities

  alias BacklogWheel.Discord

  alias BacklogWheel.Repo

  alias BacklogWheel.Accounts.User

  import Phoenix.LiveViewTest

  setup do
    original_config = Application.get_env(:backlog_wheel, :discord)
    original_client = Application.get_env(:backlog_wheel, :discord_client)

    Application.put_env(:backlog_wheel, :discord,
      client_id: "client-id",
      client_secret: "client-secret"
    )

    Application.put_env(:backlog_wheel, :discord_client, BacklogWheel.FakeDiscordClient)

    on_exit(fn ->
      restore_env(:discord, original_config)
      restore_env(:discord_client, original_client)
    end)

    :ok
  end

  test "login renders Discord sign in", %{conn: conn} do
    conn = get(conn, ~p"/login")

    assert html_response(conn, 200) =~ "Streamer Sign In"
  end

  test "start redirects to Discord authorization", %{conn: conn} do
    conn = get(conn, ~p"/auth/discord/start")

    assert redirected_to(conn) =~ "https://discord.com/oauth2/authorize"
    assert redirected_to(conn) =~ "state="
    assert get_session(conn, :discord_oauth_state)
  end

  test "callback exchanges code, refreshes existing user, and starts onboarding", %{conn: conn} do
    user =
      %User{}
      |> User.changeset(%{
        discord_id: "discord-user-1",
        username: "Old User",
        role: "admin"
      })
      |> Repo.insert!()

    conn =
      conn
      |> Plug.Test.init_test_session(discord_oauth_state: "state-1")
      |> get(~p"/auth/discord/callback?#{[code: "valid-code", state: "state-1"]}")

    assert redirected_to(conn) == ~p"/onboarding"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Signed in with Discord"

    updated_user = Accounts.get_user_by_discord_id("discord-user-1")
    assert updated_user.id == user.id
    assert updated_user.username == "Streamer User"
    assert updated_user.role == "admin"
    assert get_session(conn, :user_id) == updated_user.id
  end

  test "callback rejects mismatched state", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(discord_oauth_state: "state-1")
      |> get(~p"/auth/discord/callback?#{[code: "valid-code", state: "wrong-state"]}")

    assert redirected_to(conn) == ~p"/login"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Discord authorization state did not match"
  end

  test "callback rejects Discord users missing from the database", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(discord_oauth_state: "state-1")
      |> get(~p"/auth/discord/callback?#{[code: "other-user-code", state: "state-1"]}")

    assert redirected_to(conn) == ~p"/login"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "This Discord account has not been added to Backlog Wheel"

    refute Accounts.get_user_by_discord_id("discord-user-2")
  end

  test "protected LiveViews require login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/voting")
  end

  test "protected LiveViews allow logged in users", %{conn: conn} do
    user =
      %User{}
      |> User.changeset(%{
        discord_id: "discord-user-1",
        username: "Streamer User",
        role: "admin"
      })
      |> Repo.insert!()

    community = test_community_fixture()
    {:ok, _membership} = Communities.create_membership(user, community, "owner")

    conn = Plug.Test.init_test_session(conn, user_id: user.id)

    assert {:ok, _view, _html} = live(conn, ~p"/voting")
  end

  test "logout clears session", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(user_id: 123)
      |> delete(~p"/logout")

    assert redirected_to(conn) == ~p"/login"
    refute get_session(conn, :user_id)
  end

  test "redirect_uri points at Discord callback", %{conn: conn} do
    assert Discord.redirect_uri(conn) == "http://www.example.com/auth/discord/callback"
  end

  defp restore_env(key, nil), do: Application.delete_env(:backlog_wheel, key)
  defp restore_env(key, value), do: Application.put_env(:backlog_wheel, key, value)
end
