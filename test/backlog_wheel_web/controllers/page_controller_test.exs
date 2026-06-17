defmodule BacklogWheelWeb.PageControllerTest do
  use BacklogWheelWeb.ConnCase

  @moduletag :unauthenticated

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)

    assert response =~ "Backlog Wheel"
    assert response =~ "Sign Up / Log In"
    assert response =~ "Built for indecisive stream nights"
  end

  test "hides authenticated nav items when logged out", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)

    refute response =~ ~s(id="main-nav-dashboard")
    refute response =~ ~s(id="main-nav-wheel")
    refute response =~ ~s(id="main-nav-games")
    refute response =~ ~s(id="main-nav-voting")
    refute response =~ ~s(id="main-nav-history")
    refute response =~ ~s(id="main-nav-settings")
    refute response =~ ~s(id="main-nav-add-game")
    assert response =~ ~s(href="/login")
  end
end
