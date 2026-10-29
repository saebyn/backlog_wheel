defmodule BacklogWheel.TwitchTest do
  use BacklogWheel.DataCase, async: false

  alias BacklogWheel.Twitch
  alias BacklogWheel.Twitch.Config
  import BacklogWheel.BacklogFixtures
  import BacklogWheel.VotingFixtures

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
        twitch_broadcaster_id: "28728577",
        twitch_reward_cost: 321,
        twitch_eventsub_secret: "eventsub-secret"
      })

    assert Twitch.configured?(community)

    assert Twitch.config(community) ==
             {:ok,
              %Config{
                client_id: "client-id",
                client_secret: "client-secret",
                broadcaster_id: "28728577",
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

  test "connecting and disconnecting one community leaves another channel connected" do
    first = community_fixture(%{twitch_broadcaster_id: "111"})
    second = community_fixture(%{twitch_broadcaster_id: "222"})

    assert {:ok, _} =
             Twitch.save_credential(first, %{
               access_token: "first-token",
               scopes: "channel:manage:redemptions"
             })

    assert {:ok, _} =
             Twitch.save_credential(second, %{
               access_token: "second-token",
               scopes: "channel:manage:redemptions"
             })

    assert Twitch.get_credential(first).access_token == "first-token"
    assert Twitch.get_credential(second).access_token == "second-token"

    assert :ok = Twitch.delete_credential(first)
    refute Twitch.credential_configured?(first)
    assert Twitch.get_credential(second).access_token == "second-token"
  end

  test "each community creates its reward with its own Twitch credential" do
    start_supervised!(BacklogWheel.FakeTwitchClient)

    Application.put_env(:backlog_wheel, :twitch,
      client_id: "client-id",
      client_secret: "client-secret"
    )

    first = community_fixture(%{twitch_broadcaster_id: "111"})
    second = community_fixture(%{twitch_broadcaster_id: "222"})

    assert {:ok, _} =
             Twitch.save_credential(first, %{
               access_token: "first-token",
               scopes: "channel:manage:redemptions"
             })

    assert {:ok, _} =
             Twitch.save_credential(second, %{
               access_token: "second-token",
               scopes: "channel:manage:redemptions"
             })

    for community <- [first, second] do
      session = voting_session_fixture(%{community: community})

      voting_session_game_fixture(
        session,
        game_fixture(%{community: community, external_id: "one"})
      )

      voting_session_game_fixture(
        session,
        game_fixture(%{community: community, external_id: "two"})
      )

      assert {:ok, _} =
               BacklogWheel.Voting.start_twitch_voting(session,
                 client: BacklogWheel.FakeTwitchClient
               )
    end

    assert BacklogWheel.FakeTwitchClient.reward_credential("111") == "first-token"
    assert BacklogWheel.FakeTwitchClient.reward_credential("222") == "second-token"
  end

  test "save_credential/2 persists the community's latest Twitch OAuth token" do
    community = community_fixture()

    assert {:ok, credential} =
             Twitch.save_credential(community, %{
               access_token: "access-token",
               refresh_token: "refresh-token",
               scopes: "channel:manage:redemptions"
             })

    assert Twitch.credential_configured?(community)
    assert Twitch.get_credential(community).id == credential.id

    assert {:ok, updated_credential} =
             Twitch.save_credential(community, %{
               access_token: "new-access-token",
               refresh_token: "new-refresh-token",
               scopes: "channel:manage:redemptions"
             })

    assert updated_credential.id == credential.id
    assert Twitch.get_credential(community).access_token == "new-access-token"
  end

  test "refresh_credential/2 refreshes and stores the OAuth token" do
    start_supervised!(BacklogWheel.FakeTwitchClient)
    community = community_fixture()

    config = %Config{
      client_id: "client-id",
      client_secret: "client-secret",
      broadcaster_id: "broadcaster-id",
      reward_cost: 100
    }

    {:ok, credential} =
      Twitch.save_credential(community, %{
        access_token: "stale-access-token",
        refresh_token: "refresh-token",
        scopes: "channel:manage:redemptions"
      })

    assert {:ok, refreshed_credential} =
             Twitch.refresh_credential(community, config, BacklogWheel.FakeTwitchClient)

    assert refreshed_credential.id == credential.id
    assert refreshed_credential.access_token == "refreshed-stale-access-token"
    assert refreshed_credential.refresh_token == "refresh-token"
    assert Twitch.get_credential(community).access_token == "refreshed-stale-access-token"
  end

  test "refreshing a community token keeps a rotated refresh token" do
    start_supervised!(BacklogWheel.FakeTwitchClient)
    community = community_fixture()

    config = %Config{
      client_id: "client-id",
      client_secret: "secret",
      broadcaster_id: "123",
      reward_cost: 100
    }

    assert {:ok, _} =
             Twitch.save_credential(community, %{
               access_token: "old",
               refresh_token: "old-refresh",
               scopes: "channel:manage:redemptions"
             })

    BacklogWheel.FakeTwitchClient.rotate_refresh_token("new-refresh")

    assert {:ok, _} = Twitch.refresh_credential(community, config, BacklogWheel.FakeTwitchClient)
    assert Twitch.get_credential(community).refresh_token == "new-refresh"
  end

  test "creating a subscription requires the channel's own credential" do
    start_supervised!(BacklogWheel.FakeTwitchClient)
    Application.put_env(:backlog_wheel, :twitch_client, BacklogWheel.FakeTwitchClient)
    Application.put_env(:backlog_wheel, :twitch, client_id: "client-id", client_secret: "secret")

    community =
      community_fixture(%{twitch_broadcaster_id: "123", twitch_eventsub_secret: "secret"})

    assert {:error, :missing_twitch_credential} =
             Twitch.ensure_redemption_eventsub_subscription(Plug.Test.conn(:get, "/"), community)
  end

  test "delete_credential/1 removes the community's Twitch OAuth token" do
    community = community_fixture()

    assert {:ok, _credential} =
             Twitch.save_credential(community, %{
               access_token: "access-token",
               refresh_token: "refresh-token",
               scopes: "channel:manage:redemptions"
             })

    assert Twitch.credential_configured?(community)

    assert :ok = Twitch.delete_credential(community)

    refute Twitch.credential_configured?(community)
    assert Twitch.get_credential(community) == nil
  end
end
