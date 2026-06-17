defmodule BacklogWheelWeb.TwitchEventSubControllerTest do
  use BacklogWheelWeb.ConnCase, async: false

  import BacklogWheel.BacklogFixtures
  import BacklogWheel.VotingFixtures

  alias BacklogWheel.Repo
  alias BacklogWheel.Communities
  alias BacklogWheel.Voting.ChannelPointVote
  alias BacklogWheel.Voting.VotingSessionGame

  @eventsub_secret "eventsub-secret"
  @broadcaster_id "28728577"

  setup do
    original_config = Application.get_env(:backlog_wheel, :twitch)

    Application.put_env(:backlog_wheel, :twitch,
      client_id: "client-id",
      client_secret: "client-secret"
    )

    {:ok, community} =
      Communities.update_community_twitch_settings(Process.get(:test_community), %{
        twitch_broadcaster_id: @broadcaster_id,
        twitch_eventsub_secret: @eventsub_secret
      })

    Process.put(:test_community, community)

    on_exit(fn -> restore_env(:twitch, original_config) end)

    :ok
  end

  test "responds to Twitch EventSub challenge", %{conn: conn} do
    body =
      Jason.encode!(%{
        "challenge" => "challenge-token",
        "subscription" => %{"condition" => %{"broadcaster_user_id" => @broadcaster_id}}
      })

    conn =
      conn
      |> put_eventsub_signature(body)
      |> post(~p"/twitch/eventsub", body)

    assert response(conn, 200) == "challenge-token"
  end

  test "ingests signed channel point redemption notifications", %{conn: conn} do
    voting_session = voting_session_fixture(%{status: "open"})
    game = game_fixture(%{title: "Webhook Reward Game"})
    pool_item = voting_session_game_fixture(voting_session, game)

    pool_item
    |> VotingSessionGame.twitch_reward_changeset(%{
      twitch_reward_id: "webhook-reward",
      twitch_reward_title: "Vote ##{pool_item.id}: Webhook Reward Game",
      twitch_reward_cost: 100,
      twitch_reward_status: "enabled"
    })
    |> Repo.update!()

    body = redemption_notification_body("webhook-redemption", "webhook-reward")

    conn =
      conn
      |> put_eventsub_signature(body)
      |> post(~p"/twitch/eventsub", body)

    assert response(conn, 204) == ""
    assert [%ChannelPointVote{} = vote] = Repo.all(ChannelPointVote)
    assert vote.voting_session_game_id == pool_item.id
    assert vote.source == "twitch_channel_points"
    assert vote.external_event_id == "webhook-redemption"
  end

  test "rejects invalid Twitch EventSub signatures", %{conn: conn} do
    body = redemption_notification_body("bad-signature-redemption", "reward-id")

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("twitch-eventsub-message-id", "message-id")
      |> put_req_header("twitch-eventsub-message-timestamp", "2026-06-10T00:00:00Z")
      |> put_req_header("twitch-eventsub-message-signature", "sha256=invalid")
      |> post(~p"/twitch/eventsub", body)

    assert response(conn, 403) == ""
    assert Repo.aggregate(ChannelPointVote, :count, :id) == 0
  end

  test "ignores signed redemptions for unknown rewards", %{conn: conn} do
    body = redemption_notification_body("unknown-redemption", "unknown-reward")

    conn =
      conn
      |> put_eventsub_signature(body)
      |> post(~p"/twitch/eventsub", body)

    assert response(conn, 204) == ""
    assert Repo.aggregate(ChannelPointVote, :count, :id) == 0
  end

  defp redemption_notification_body(redemption_id, reward_id) do
    Jason.encode!(%{
      "subscription" => %{"type" => "channel.channel_points_custom_reward_redemption.add"},
      "event" => %{
        "broadcaster_user_id" => @broadcaster_id,
        "id" => redemption_id,
        "user_id" => "twitch-user-1",
        "user_name" => "WebhookViewer",
        "reward" => %{"id" => reward_id}
      }
    })
  end

  defp put_eventsub_signature(conn, body) do
    message_id = "message-id"
    timestamp = "2026-06-10T00:00:00Z"

    signature =
      :crypto.mac(:hmac, :sha256, @eventsub_secret, message_id <> timestamp <> body)
      |> Base.encode16(case: :lower)

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("twitch-eventsub-message-id", message_id)
    |> put_req_header("twitch-eventsub-message-timestamp", timestamp)
    |> put_req_header("twitch-eventsub-message-signature", "sha256=" <> signature)
  end

  defp restore_env(key, nil), do: Application.delete_env(:backlog_wheel, key)
  defp restore_env(key, value), do: Application.put_env(:backlog_wheel, key, value)
end
