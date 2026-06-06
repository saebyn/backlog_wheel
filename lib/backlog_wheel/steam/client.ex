defmodule BacklogWheel.Steam.Client do
  @moduledoc """
  Minimal Steam Web API client for importing owned games.

  Steam may include `rtime_last_played` in owned game results even though the
  Valve docs do not consistently list it. Treat it as optional metadata.
  """

  @owned_games_url "https://api.steampowered.com/IPlayerService/GetOwnedGames/v0001/"

  def configured? do
    steam_api_key() not in [nil, ""] and steam_id64() not in [nil, ""]
  end

  def fetch_owned_games do
    with {:ok, api_key} <- fetch_config(:api_key, steam_api_key()),
         {:ok, steam_id} <- fetch_config(:steam_id64, steam_id64()),
         {:ok, %{status: 200, body: body}} <- request_owned_games(api_key, steam_id) do
      {:ok, normalize_owned_games(body)}
    else
      {:ok, %{status: status}} -> {:error, {:steam_http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def normalize_owned_games(%{"response" => %{"games" => games}}) when is_list(games) do
    games
    |> Enum.map(&normalize_game/1)
    |> Enum.reject(&is_nil/1)
  end

  def normalize_owned_games(_body), do: []

  defp normalize_game(%{"appid" => appid, "name" => name} = game) when is_binary(name) do
    %{
      appid: appid,
      name: name,
      image_url: steam_icon_url(appid, game["img_icon_url"]),
      last_played_at: normalize_last_played_at(game["rtime_last_played"])
    }
  end

  defp normalize_game(_game), do: nil

  defp normalize_last_played_at(nil), do: nil
  defp normalize_last_played_at(0), do: nil
  defp normalize_last_played_at("0"), do: nil

  defp normalize_last_played_at(unix_timestamp) when is_integer(unix_timestamp) do
    DateTime.from_unix!(unix_timestamp)
  end

  defp normalize_last_played_at(unix_timestamp) when is_binary(unix_timestamp) do
    case Integer.parse(unix_timestamp) do
      {timestamp, ""} -> normalize_last_played_at(timestamp)
      _ -> nil
    end
  end

  defp normalize_last_played_at(_unix_timestamp), do: nil

  defp steam_icon_url(_appid, icon_hash) when icon_hash in [nil, ""], do: nil

  defp steam_icon_url(appid, icon_hash) do
    "https://media.steampowered.com/steamcommunity/public/images/apps/#{appid}/#{icon_hash}.jpg"
  end

  defp request_owned_games(api_key, steam_id) do
    Req.get(@owned_games_url,
      params: [
        key: api_key,
        steamid: steam_id,
        format: "json",
        include_appinfo: true,
        include_played_free_games: true
      ]
    )
  end

  defp fetch_config(_name, value) when value not in [nil, ""], do: {:ok, value}
  defp fetch_config(name, _value), do: {:error, {:missing_config, name}}

  defp steam_api_key do
    Application.get_env(:backlog_wheel, :steam_api_key) || System.get_env("STEAM_API_KEY")
  end

  defp steam_id64 do
    Application.get_env(:backlog_wheel, :steam_id64) || System.get_env("STEAM_ID64")
  end
end
