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

  test "requests permission to manage redemptions and send chat" do
    assert "channel:manage:redemptions" in Client.scopes()
    assert "user:write:chat" in Client.scopes()
  end

  test "creates a disabled input-required reward with a redemption queue" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/helix/channel_points/custom_rewards"

      assert Jason.decode!(Req.Test.raw_body(conn)) == %{
               "title" => "Vote",
               "cost" => 100,
               "prompt" => "Enter a number",
               "is_enabled" => false,
               "is_user_input_required" => true,
               "should_redemptions_skip_request_queue" => false
             }

      Req.Test.json(conn, %{data: [%{id: "reward", title: "Vote", cost: 100, is_enabled: false}]})
    end)

    config = %Config{
      client_id: "client-id",
      client_secret: "secret",
      broadcaster_id: "broadcaster-id",
      reward_cost: 100
    }

    credential = %Credential{access_token: "user-token"}

    assert {:ok, %{id: "reward"}} =
             Client.create_custom_reward(config, credential, %{
               title: "Vote",
               cost: 100,
               prompt: "Enter a number",
               is_enabled: false,
               is_user_input_required: true,
               should_redemptions_skip_request_queue: false
             })
  end

  test "cancels a redemption with the broadcaster user token" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "PATCH"
      assert conn.request_path == "/helix/channel_points/custom_rewards/redemptions"

      assert URI.decode_query(conn.query_string) == %{
               "broadcaster_id" => "broadcaster-id",
               "reward_id" => "reward-id",
               "id" => "redemption-id"
             }

      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer user-token"]
      assert Jason.decode!(Req.Test.raw_body(conn)) == %{"status" => "CANCELED"}
      Req.Test.json(conn, %{data: [%{id: "redemption-id", status: "CANCELED"}]})
    end)

    config = %Config{
      client_id: "client-id",
      client_secret: "secret",
      broadcaster_id: "broadcaster-id",
      reward_cost: 100
    }

    credential = %Credential{access_token: "user-token"}

    assert :ok =
             Client.update_redemption(
               config,
               credential,
               "reward-id",
               "redemption-id",
               "CANCELED"
             )
  end

  test "does not treat an empty redemption update as a successful refund" do
    Req.Test.expect(__MODULE__, fn conn -> Req.Test.json(conn, %{data: []}) end)

    config = %Config{
      client_id: "client-id",
      client_secret: "secret",
      broadcaster_id: "broadcaster-id",
      reward_cost: 100
    }

    credential = %Credential{access_token: "user-token"}

    assert {:error, _} =
             Client.update_redemption(
               config,
               credential,
               "reward-id",
               "redemption-id",
               "CANCELED"
             )
  end

  test "retrieves all pages of unfulfilled redemptions" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert URI.decode_query(conn.query_string)["status"] == "UNFULFILLED"
      Req.Test.json(conn, %{data: [%{id: "one"}], pagination: %{cursor: "next"}})
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      assert URI.decode_query(conn.query_string)["after"] == "next"
      Req.Test.json(conn, %{data: [%{id: "two"}], pagination: %{}})
    end)

    config = %Config{
      client_id: "client-id",
      client_secret: "secret",
      broadcaster_id: "broadcaster-id",
      reward_cost: 100
    }

    credential = %Credential{access_token: "user-token"}

    assert {:ok, [%{"id" => "one"}, %{"id" => "two"}]} =
             Client.list_unfulfilled_redemptions(config, credential, "reward-id")
  end

  test "reports a dropped chat message as a failure" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/helix/chat/messages"

      assert Jason.decode!(Req.Test.raw_body(conn)) == %{
               "broadcaster_id" => "broadcaster-id",
               "sender_id" => "broadcaster-id",
               "message" => "@viewer Please enter a valid game number."
             }

      Req.Test.json(conn, %{data: [%{is_sent: false, drop_reason: %{code: "dropped"}}]})
    end)

    config = %Config{
      client_id: "client-id",
      client_secret: "secret",
      broadcaster_id: "broadcaster-id",
      reward_cost: 100
    }

    credential = %Credential{access_token: "user-token"}

    assert {:error, _} =
             Client.send_chat_message(
               config,
               credential,
               "@viewer Please enter a valid game number."
             )
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
