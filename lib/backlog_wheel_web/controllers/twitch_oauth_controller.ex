defmodule BacklogWheelWeb.TwitchOAuthController do
  use BacklogWheelWeb, :controller

  alias BacklogWheel.Twitch

  def start(conn, _params) do
    with {:ok, config} <- Twitch.config() do
      state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      redirect_uri = Twitch.redirect_uri(conn)

      conn
      |> put_session(:twitch_oauth_state, state)
      |> redirect(external: Twitch.client().authorize_url(config, redirect_uri, state))
    else
      {:error, {:missing_config, missing}} ->
        conn
        |> put_flash(:error, "Missing Twitch config: #{Enum.join(missing, ", ")}")
        |> redirect(to: ~p"/voting")
    end
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    with :ok <- verify_state(conn, state),
         {:ok, config} <- Twitch.config(),
         {:ok, token_attrs} <-
           Twitch.client().exchange_code(config, code, Twitch.redirect_uri(conn)),
         {:ok, _credential} <- Twitch.save_credential(token_attrs) do
      conn
      |> delete_session(:twitch_oauth_state)
      |> put_flash(:info, "Twitch connected")
      |> redirect(to: ~p"/voting")
    else
      {:error, :invalid_state} ->
        conn
        |> put_flash(:error, "Twitch authorization state did not match")
        |> redirect(to: ~p"/voting")

      {:error, {:missing_config, missing}} ->
        conn
        |> put_flash(:error, "Missing Twitch config: #{Enum.join(missing, ", ")}")
        |> redirect(to: ~p"/voting")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Twitch authorization failed")
        |> redirect(to: ~p"/voting")
    end
  end

  def callback(conn, %{"error" => error}) do
    conn
    |> put_flash(:error, "Twitch authorization failed: #{error}")
    |> redirect(to: ~p"/voting")
  end

  defp verify_state(conn, state) do
    if get_session(conn, :twitch_oauth_state) == state do
      :ok
    else
      {:error, :invalid_state}
    end
  end
end
