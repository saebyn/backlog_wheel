defmodule BacklogWheelWeb.TwitchOAuthController do
  use BacklogWheelWeb, :controller

  alias BacklogWheel.Communities
  alias BacklogWheel.Twitch

  def start(conn, _params) do
    case Twitch.oauth_config() do
      {:ok, config} ->
        state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
        redirect_uri = Twitch.redirect_uri(conn)

        conn
        |> put_session(:twitch_oauth_state, state)
        |> redirect(external: Twitch.client().authorize_url(config, redirect_uri, state))

      {:error, {:missing_config, missing}} ->
        conn
        |> put_flash(:error, "Missing Twitch config: #{Enum.join(missing, ", ")}")
        |> redirect(to: ~p"/settings/twitch")
    end
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    with :ok <- verify_state(conn, state),
         {:ok, oauth_config} <- Twitch.oauth_config(),
         {:ok, token_attrs} <-
           Twitch.client().exchange_code(oauth_config, code, Twitch.redirect_uri(conn)),
         {:ok, credential} <- Twitch.save_credential(token_attrs),
         {:ok, twitch_user} <- Twitch.client().fetch_current_user(oauth_config, credential),
         {:ok, community} <-
           save_connection_settings(conn.assigns.current_community, twitch_user),
         {:ok, config} <- Twitch.config(community) do
      maybe_create_eventsub_subscription(conn, community, config)

      conn
      |> delete_session(:twitch_oauth_state)
      |> put_flash(:info, "Twitch connected")
      |> redirect(to: ~p"/settings/twitch")
    else
      {:error, :invalid_state} ->
        conn
        |> put_flash(:error, "Twitch authorization state did not match")
        |> redirect(to: ~p"/settings/twitch")

      {:error, {:missing_config, missing}} ->
        conn
        |> put_flash(:error, "Missing Twitch config: #{Enum.join(missing, ", ")}")
        |> redirect(to: ~p"/settings/twitch")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Twitch authorization failed")
        |> redirect(to: ~p"/settings/twitch")
    end
  end

  def callback(conn, %{"error" => error}) do
    conn
    |> put_flash(:error, "Twitch authorization failed: #{error}")
    |> redirect(to: ~p"/settings/twitch")
  end

  defp verify_state(conn, state) do
    if get_session(conn, :twitch_oauth_state) == state do
      :ok
    else
      {:error, :invalid_state}
    end
  end

  defp save_connection_settings(community, twitch_user) do
    Communities.update_community_twitch_settings(community, %{
      twitch_broadcaster_id: twitch_user.id,
      twitch_broadcaster_login: twitch_user.login,
      twitch_broadcaster_display_name: twitch_user.display_name,
      twitch_eventsub_secret: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    })
  end

  defp maybe_create_eventsub_subscription(conn, community, config) do
    with {:ok, _secret} <- Twitch.eventsub_secret(config),
         {:ok, _subscription} <- Twitch.ensure_redemption_eventsub_subscription(conn, community) do
      :ok
    else
      {:error, {:missing_config, [:eventsub_secret]}} -> :ok
      {:error, _reason} -> :ok
    end
  end
end
