defmodule BacklogWheel.FakeDiscordClient do
  def authorize_url(_config, redirect_uri, state) do
    "https://discord.com/oauth2/authorize?redirect_uri=#{URI.encode_www_form(redirect_uri)}&state=#{state}"
  end

  def exchange_code(_config, "valid-code", _redirect_uri) do
    {:ok, %{"access_token" => "discord-access-token"}}
  end

  def exchange_code(_config, "other-user-code", _redirect_uri) do
    {:ok, %{"access_token" => "other-discord-access-token"}}
  end

  def exchange_code(_config, _code, _redirect_uri), do: {:error, :invalid_code}

  def get_current_user(%{"access_token" => "discord-access-token"}) do
    {:ok,
     %{
       "id" => "discord-user-1",
       "username" => "streamer-user",
       "global_name" => "Streamer User",
       "avatar" => "avatar-hash"
     }}
  end

  def get_current_user(%{"access_token" => "other-discord-access-token"}) do
    {:ok, %{"id" => "discord-user-2", "username" => "other-user"}}
  end
end
