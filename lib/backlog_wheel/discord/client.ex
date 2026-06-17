defmodule BacklogWheel.Discord.Client do
  @moduledoc """
  Discord OAuth API client.
  """

  alias BacklogWheel.Discord.Config

  @authorize_url "https://discord.com/oauth2/authorize"
  @token_url "https://discord.com/api/oauth2/token"
  @user_url "https://discord.com/api/users/@me"

  @spec authorize_url(Config.t(), String.t(), String.t()) :: String.t()
  def authorize_url(%Config{} = config, redirect_uri, state) do
    query =
      URI.encode_query(%{
        client_id: config.client_id,
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: "identify",
        state: state
      })

    "#{@authorize_url}?#{query}"
  end

  @spec exchange_code(Config.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def exchange_code(%Config{} = config, code, redirect_uri) do
    body =
      URI.encode_query(%{
        client_id: config.client_id,
        client_secret: config.client_secret,
        grant_type: "authorization_code",
        code: code,
        redirect_uri: redirect_uri
      })

    case Req.post(@token_url,
           body: body,
           headers: [{"content-type", "application/x-www-form-urlencoded"}]
         ) do
      {:ok, %{status: status, body: %{"access_token" => _access_token} = body}}
      when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:discord_token_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec get_current_user(map()) :: {:ok, map()} | {:error, term()}
  def get_current_user(%{"access_token" => access_token}) do
    case Req.get(@user_url, auth: {:bearer, access_token}) do
      {:ok, %{status: status, body: %{"id" => _id} = body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:discord_user_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
