defmodule BacklogWheelWeb.SiteAdminLiveTest do
  use BacklogWheelWeb.ConnCase

  import Phoenix.LiveViewTest

  alias BacklogWheel.Accounts.User
  alias BacklogWheel.Repo

  test "site admins can access the site admin page", %{conn: conn} do
    conn = conn |> recycle() |> log_in_test_user(%{site_admin: true})

    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(view, "#site-admin-page")
    assert has_element?(view, ~s|#site-admin-analytics-link[href="/admin/analytics"]|)
  end

  test "site admins without a community can access the site admin page", %{conn: conn} do
    user = user_fixture(%{site_admin: true})
    conn = conn |> recycle() |> Plug.Test.init_test_session(user_id: user.id)

    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(view, "#site-admin-page")
  end

  test "community admins without site admin access are redirected", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, ~p"/admin")
  end

  test "community admins cannot access analytics dashboard", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, ~p"/admin/analytics")
  end

  test "site admin nav is only visible to site admins", %{conn: conn} do
    {:ok, dashboard, _html} = live(conn, ~p"/dashboard")
    refute has_element?(dashboard, "#main-nav-site-admin")

    site_admin_conn = conn |> recycle() |> log_in_test_user(%{site_admin: true})
    {:ok, site_admin_dashboard, _html} = live(site_admin_conn, ~p"/dashboard")
    assert has_element?(site_admin_dashboard, "#main-nav-site-admin")
  end

  @tag :unauthenticated
  test "unauthenticated users are redirected to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/admin")
  end

  @tag :unauthenticated
  test "unauthenticated users are redirected from analytics to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/admin/analytics")
  end

  defp user_fixture(attrs) do
    attrs =
      Enum.into(attrs, %{
        discord_id: "site-admin-discord-#{System.unique_integer([:positive])}",
        username: "Site Admin",
        role: "admin"
      })

    %User{}
    |> User.changeset(attrs)
    |> Repo.insert!()
  end
end
