defmodule BacklogWheelWeb.DiscordOAuthController do
  use BacklogWheelWeb, :controller

  alias BacklogWheel.Accounts
  alias BacklogWheel.Discord

  def login(conn, _params) do
    render(conn, :login, discord_configured?: Discord.configured?())
  end

  def start(conn, _params) do
    with {:ok, config} <- Discord.config() do
      state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      redirect_uri = Discord.redirect_uri(conn)

      conn
      |> put_session(:discord_oauth_state, state)
      |> redirect(external: Discord.client().authorize_url(config, redirect_uri, state))
    else
      {:error, {:missing_config, missing}} ->
        conn
        |> put_flash(:error, "Missing Discord config: #{Enum.join(missing, ", ")}")
        |> redirect(to: ~p"/login")
    end
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    with :ok <- verify_state(conn, state),
         {:ok, config} <- Discord.config(),
         {:ok, token} <- Discord.client().exchange_code(config, code, Discord.redirect_uri(conn)),
         {:ok, discord_user} <- Discord.client().get_current_user(token),
         {:ok, user} <- Accounts.sync_discord_user(discord_user) do
      conn
      |> delete_session(:discord_oauth_state)
      |> BacklogWheelWeb.UserAuth.log_in_user(user)
    else
      {:error, :invalid_state} ->
        conn
        |> put_flash(:error, "Discord authorization state did not match")
        |> redirect(to: ~p"/login")

      {:error, :unauthorized} ->
        conn
        |> delete_session(:discord_oauth_state)
        |> put_flash(:error, "This Discord account has not been added to Backlog Wheel")
        |> redirect(to: ~p"/login")

      {:error, {:missing_config, missing}} ->
        conn
        |> put_flash(:error, "Missing Discord config: #{Enum.join(missing, ", ")}")
        |> redirect(to: ~p"/login")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Discord authorization failed")
        |> redirect(to: ~p"/login")
    end
  end

  def callback(conn, %{"error" => error}) do
    conn
    |> put_flash(:error, "Discord authorization failed: #{error}")
    |> redirect(to: ~p"/login")
  end

  def logout(conn, _params), do: BacklogWheelWeb.UserAuth.log_out_user(conn)

  defp verify_state(conn, state) do
    if get_session(conn, :discord_oauth_state) == state do
      :ok
    else
      {:error, :invalid_state}
    end
  end
end
