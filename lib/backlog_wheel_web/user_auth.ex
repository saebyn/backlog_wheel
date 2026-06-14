defmodule BacklogWheelWeb.UserAuth do
  import Phoenix.Controller
  import Plug.Conn
  use BacklogWheelWeb, :verified_routes

  alias BacklogWheel.{Accounts, Communities}

  def init(action), do: action

  def call(conn, action), do: apply(__MODULE__, action, [conn, []])

  def fetch_current_user(conn, _opts) do
    user = Accounts.get_user(get_session(conn, :user_id))

    conn
    |> assign(:current_user, user)
    |> assign(:current_community, Communities.current_admin_community_for_user(user))
  end

  def require_authenticated_user(%{assigns: %{current_user: nil}} = conn, _opts) do
    conn
    |> put_flash(:error, "Sign in with Discord to continue")
    |> maybe_store_return_to()
    |> redirect(to: ~p"/login")
    |> halt()
  end

  def require_authenticated_user(conn, _opts), do: conn

  def require_admin_community(%{assigns: %{current_community: nil}} = conn, _opts) do
    conn
    |> put_flash(:info, "Create your community to finish setup")
    |> redirect(to: ~p"/onboarding")
    |> halt()
  end

  def require_admin_community(conn, _opts), do: conn

  def log_in_user(conn, user) do
    return_to =
      if Communities.current_admin_community_for_user(user) do
        get_session(conn, :user_return_to) || ~p"/voting"
      else
        ~p"/onboarding"
      end

    conn
    |> renew_session()
    |> put_session(:user_id, user.id)
    |> put_flash(:info, "Signed in with Discord")
    |> redirect(to: return_to)
  end

  def log_out_user(conn) do
    conn
    |> renew_session()
    |> put_flash(:info, "Signed out")
    |> redirect(to: ~p"/login")
  end

  def on_mount(:require_authenticated_user, _params, session, socket) do
    user = Accounts.get_user(Map.get(session, "user_id"))
    community = Communities.current_admin_community_for_user(user)

    cond do
      is_nil(user) ->
        socket =
          socket
          |> Phoenix.LiveView.put_flash(:error, "Sign in with Discord to continue")
          |> Phoenix.LiveView.redirect(to: ~p"/login")

        {:halt, socket}

      is_nil(community) ->
        socket =
          socket
          |> Phoenix.LiveView.put_flash(:info, "Create your community to finish setup")
          |> Phoenix.LiveView.redirect(to: ~p"/onboarding")

        {:halt, socket}

      true ->
        {:cont,
         socket
         |> Phoenix.Component.assign(:current_user, user)
         |> Phoenix.Component.assign(:current_community, community)}
    end
  end

  defp maybe_store_return_to(%{method: "GET"} = conn),
    do: put_session(conn, :user_return_to, current_path(conn))

  defp maybe_store_return_to(conn), do: conn

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
