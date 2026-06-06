defmodule BacklogWheelWeb.PageController do
  use BacklogWheelWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
