defmodule BacklogWheelWeb.OnboardingLiveTest do
  use BacklogWheelWeb.ConnCase

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias BacklogWheel.Communities.{Community, CommunityMembership}
  alias BacklogWheel.Repo
  alias BacklogWheel.Voting.WheelFormat

  @tag :unauthenticated
  test "redirects an authenticated user without an admin community to onboarding", %{conn: conn} do
    user = user_fixture()
    conn = Plug.Test.init_test_session(conn, user_id: user.id)

    assert {:error, {:redirect, %{to: "/onboarding"}}} = live(conn, ~p"/voting")
  end

  @tag :unauthenticated
  test "redirects unallowlisted users without a community to access not enabled", %{conn: conn} do
    original_allowlist = Application.get_env(:backlog_wheel, :signup_allowed_discord_ids)
    Application.put_env(:backlog_wheel, :signup_allowed_discord_ids, "approved-discord")

    on_exit(fn -> restore_env(:signup_allowed_discord_ids, original_allowlist) end)

    user = user_fixture(%{discord_id: "unapproved-discord"})
    conn = Plug.Test.init_test_session(conn, user_id: user.id)

    assert {:error, {:redirect, %{to: "/access-not-enabled"}}} = live(conn, ~p"/onboarding")
    assert {:error, {:redirect, %{to: "/access-not-enabled"}}} = live(conn, ~p"/voting")
  end

  test "redirects users with an existing admin community away from onboarding", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, ~p"/onboarding")
  end

  @tag :unauthenticated
  test "creates the initial community and owner membership", %{conn: conn} do
    user = user_fixture()
    conn = Plug.Test.init_test_session(conn, user_id: user.id)

    {:ok, view, _html} = live(conn, ~p"/onboarding")

    view
    |> form("#onboarding-form", community: %{name: "Backlog Crew"})
    |> render_submit()

    assert_redirect(view, ~p"/dashboard")

    community = Repo.get_by!(Community, name: "Backlog Crew")

    assert Repo.get_by!(CommunityMembership,
             user_id: user.id,
             community_id: community.id,
             role: "owner"
           )

    assert Repo.aggregate(
             from(format in WheelFormat, where: format.community_id == ^community.id),
             :count
           ) == 3
  end

  @tag :unauthenticated
  test "shows validation errors without creating partial records", %{conn: conn} do
    user = user_fixture()
    conn = Plug.Test.init_test_session(conn, user_id: user.id)
    community_count = Repo.aggregate(Community, :count)
    membership_count = Repo.aggregate(CommunityMembership, :count)

    {:ok, view, _html} = live(conn, ~p"/onboarding")

    html =
      view
      |> form("#onboarding-form", community: %{name: ""})
      |> render_submit()

    assert html =~ "can&#39;t be blank"
    assert Repo.aggregate(Community, :count) == community_count
    assert Repo.aggregate(CommunityMembership, :count) == membership_count
  end

  defp user_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        discord_id: "onboarding-discord-#{System.unique_integer([:positive])}",
        username: "Onboarding Streamer",
        role: "admin"
      })

    %BacklogWheel.Accounts.User{}
    |> BacklogWheel.Accounts.User.changeset(attrs)
    |> Repo.insert!()
  end

  defp restore_env(key, nil), do: Application.delete_env(:backlog_wheel, key)
  defp restore_env(key, value), do: Application.put_env(:backlog_wheel, key, value)
end
