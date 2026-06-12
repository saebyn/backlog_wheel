defmodule BacklogWheelWeb.PageControllerTest do
  use BacklogWheelWeb.ConnCase

  @moduletag :unauthenticated

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)

    assert response =~ "Backlog Wheel"
    assert response =~ "Manage Games"
    assert response =~ "Built for indecisive stream nights"
  end
end
