defmodule BacklogWheel.TwitchTest do
  use BacklogWheel.DataCase, async: false

  alias BacklogWheel.Twitch
  alias BacklogWheel.Twitch.Config
  import BacklogWheel.BacklogFixtures

  setup do
    original_config = Application.get_env(:backlog_wheel, :twitch)
    original_client = Application.get_env(:backlog_wheel, :twitch_client)

    on_exit(fn ->
      if is_nil(original_config) do
        Application.delete_env(:backlog_wheel, :twitch)
      else
        Application.put_env(:backlog_wheel, :twitch, original_config)
      end

      if is_nil(original_client) do
        Application.delete_env(:backlog_wheel, :twitch_client)
      else
        Application.put_env(:backlog_wheel, :twitch_client, original_client)
      end
    end)
  end

  test "config/1 is false when community Twitch config is incomplete" do
    Application.put_env(:backlog_wheel, :twitch, client_id: "client-id")
    community = community_fixture()

    refute Twitch.configured?(community)

    assert Twitch.config(community) ==
             {:error, {:missing_config, [:client_secret, :broadcaster_id]}}
  end

  test "config/1 returns app client and community channel config" do
    Application.put_env(:backlog_wheel, :twitch,
      client_id: "client-id",
      client_secret: "client-secret"
    )

    community =
      community_fixture(%{
        twitch_broadcaster_id: "broadcaster-id",
        twitch_reward_cost: 321,
        twitch_eventsub_secret: "eventsub-secret"
      })

    assert Twitch.configured?(community)

    assert Twitch.config(community) ==
             {:ok,
              %Config{
                client_id: "client-id",
                client_secret: "client-secret",
                broadcaster_id: "broadcaster-id",
                reward_cost: 321,
                eventsub_secret: "eventsub-secret"
              }}
  end

  test "eventsub_config/1 resolves config by event broadcaster ID" do
    Application.put_env(:backlog_wheel, :twitch,
      client_id: "client-id",
      client_secret: "client-secret"
    )

    community_fixture(%{
      twitch_broadcaster_id: "1234",
      twitch_eventsub_secret: "eventsub-secret"
    })

    assert {:ok, %Config{broadcaster_id: "1234", eventsub_secret: "eventsub-secret"}} =
             Twitch.eventsub_config(%{"event" => %{"broadcaster_user_id" => "1234"}})
  end

  test "save_credential/1 persists the latest Twitch OAuth token" do
    assert {:ok, credential} =
             Twitch.save_credential(%{
               access_token: "access-token",
               refresh_token: "refresh-token",
               scopes: "channel:manage:redemptions"
             })

    assert Twitch.credential_configured?()
    assert Twitch.get_credential().id == credential.id

    assert {:ok, updated_credential} =
             Twitch.save_credential(%{
               access_token: "new-access-token",
               refresh_token: "new-refresh-token",
               scopes: "channel:manage:redemptions"
             })

    assert updated_credential.id == credential.id
    assert Twitch.get_credential().access_token == "new-access-token"
  end

  test "refresh_credential/2 refreshes and stores the OAuth token" do
    start_supervised!(BacklogWheel.FakeTwitchClient)

    config = %Config{
      client_id: "client-id",
      client_secret: "client-secret",
      broadcaster_id: "broadcaster-id",
      reward_cost: 100
    }

    {:ok, credential} =
      Twitch.save_credential(%{
        access_token: "stale-access-token",
        refresh_token: "refresh-token",
        scopes: "channel:manage:redemptions"
      })

    assert {:ok, refreshed_credential} =
             Twitch.refresh_credential(config, BacklogWheel.FakeTwitchClient)

    assert refreshed_credential.id == credential.id
    assert refreshed_credential.access_token == "refreshed-stale-access-token"
    assert refreshed_credential.refresh_token == "refresh-token"
    assert Twitch.get_credential().access_token == "refreshed-stale-access-token"
  end

  test "delete_credential/0 removes stored Twitch OAuth tokens" do
    assert {:ok, _credential} =
             Twitch.save_credential(%{
               access_token: "access-token",
               refresh_token: "refresh-token",
               scopes: "channel:manage:redemptions"
             })

    assert Twitch.credential_configured?()

    assert :ok = Twitch.delete_credential()

    refute Twitch.credential_configured?()
    assert Twitch.get_credential() == nil
  end
end
