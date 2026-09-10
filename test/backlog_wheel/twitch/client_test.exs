defmodule BacklogWheel.Twitch.ClientTest do
  use ExUnit.Case, async: false

  alias BacklogWheel.Twitch.Client
  alias BacklogWheel.Twitch.Config
  alias BacklogWheel.Twitch.Credential

  setup {Req.Test, :verify_on_exit!}

  setup do
    original_options = Req.default_options()
    Req.default_options(plug: {Req.Test, __MODULE__})

    on_exit(fn -> Req.default_options(original_options) end)
  end

  test "EventSub webhook subscriptions use an app access token" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/oauth2/token"

      assert conn
             |> Req.Test.raw_body()
             |> URI.decode_query() == %{
               "client_id" => "client-id",
               "client_secret" => "client-secret",
               "grant_type" => "client_credentials"
             }

      Req.Test.json(conn, %{access_token: "app-access-token", expires_in: 5_000_000})
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/helix/eventsub/subscriptions"
      assert Plug.Conn.get_req_header(conn, "client-id") == ["client-id"]
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer app-access-token"]

      assert conn
             |> Req.Test.raw_body()
             |> Jason.decode!() == %{
               "type" => "channel.channel_points_custom_reward_redemption.add",
               "version" => "1",
               "condition" => %{"broadcaster_user_id" => "broadcaster-id"},
               "transport" => %{
                 "method" => "webhook",
                 "callback" => "https://example.com/twitch/eventsub",
                 "secret" => "eventsub-secret"
               }
             }

      Req.Test.json(conn, %{
        data: [
          %{
            id: "subscription-id",
            status: "webhook_callback_verification_pending",
            type: "channel.channel_points_custom_reward_redemption.add"
          }
        ]
      })
    end)

    config = %Config{
      client_id: "client-id",
      client_secret: "client-secret",
      broadcaster_id: "broadcaster-id",
      reward_cost: 100
    }

    credential = %Credential{access_token: "user-access-token"}

    assert {:ok, %{id: "subscription-id"}} =
             Client.create_redemption_eventsub_subscription(
               config,
               credential,
               "https://example.com/twitch/eventsub",
               "eventsub-secret"
             )
  end
end
