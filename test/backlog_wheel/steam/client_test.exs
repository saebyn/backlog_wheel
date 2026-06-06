defmodule BacklogWheel.Steam.ClientTest do
  use ExUnit.Case, async: true

  alias BacklogWheel.Steam.Client

  test "normalize_owned_games/1 extracts app ids and names" do
    body = %{
      "response" => %{
        "games" => [
          %{"appid" => 10, "name" => "Counter-Strike"},
          %{
            "appid" => 70,
            "name" => "Half-Life",
            "img_icon_url" => "abcdef",
            "playtime_forever" => 120,
            "rtime_last_played" => 1_717_206_400
          },
          %{"appid" => 999}
        ]
      }
    }

    assert Client.normalize_owned_games(body) == [
             %{appid: 10, name: "Counter-Strike", image_url: nil, last_played_at: nil},
             %{
               appid: 70,
               name: "Half-Life",
               image_url:
                 "https://media.steampowered.com/steamcommunity/public/images/apps/70/abcdef.jpg",
               last_played_at: ~U[2024-06-01 01:46:40Z]
             }
           ]
  end

  test "normalize_owned_games/1 handles missing games" do
    assert Client.normalize_owned_games(%{"response" => %{}}) == []
  end
end
