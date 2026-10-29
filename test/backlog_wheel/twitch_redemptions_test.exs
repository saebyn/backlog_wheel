defmodule BacklogWheel.TwitchRedemptionsTest do
  use BacklogWheel.DataCase

  import BacklogWheel.BacklogFixtures
  import BacklogWheel.VotingFixtures

  alias BacklogWheel.FakeTwitchClient
  alias BacklogWheel.Repo
  alias BacklogWheel.Twitch
  alias BacklogWheel.Voting
  alias BacklogWheel.Voting.{TwitchRedemptions, TwitchVotingRedemption}

  setup do
    start_supervised!(FakeTwitchClient)
    original = Application.get_env(:backlog_wheel, :twitch)
    original_client = Application.get_env(:backlog_wheel, :twitch_client)
    Application.put_env(:backlog_wheel, :twitch, client_id: "id", client_secret: "secret")
    Application.put_env(:backlog_wheel, :twitch_client, FakeTwitchClient)

    on_exit(fn ->
      if original,
        do: Application.put_env(:backlog_wheel, :twitch, original),
        else: Application.delete_env(:backlog_wheel, :twitch)

      if original_client,
        do: Application.put_env(:backlog_wheel, :twitch_client, original_client),
        else: Application.delete_env(:backlog_wheel, :twitch_client)
    end)

    community = community_fixture(%{twitch_broadcaster_id: "123456", twitch_reward_cost: 100})
    session = voting_session_fixture(%{community: community})

    first =
      voting_session_game_fixture(
        session,
        game_fixture(%{community: community, external_id: "first"})
      )

    second =
      voting_session_game_fixture(
        session,
        game_fixture(%{community: community, external_id: "second"})
      )

    {:ok, _} =
      Twitch.save_credential(community, %{
        access_token: "token",
        scopes: "channel:manage:redemptions user:write:chat"
      })

    {:ok, session} = Voting.start_twitch_voting(session, client: FakeTwitchClient)
    %{session: session, first: first, second: second}
  end

  defp event(session, id, input) do
    %{
      "id" => id,
      "user_id" => "viewer-id",
      "user_login" => "viewer",
      "user_input" => input,
      "reward" => %{"id" => session.twitch_voting_reward.reward_id}
    }
  end

  test "one reward requires a number and duplicate events count once", %{
    session: session,
    second: second
  } do
    attrs = FakeTwitchClient.reward_attrs(session.id)
    assert attrs.is_user_input_required
    refute attrs.should_redemptions_skip_request_queue
    assert {:ok, first} = Voting.ingest_twitch_reward_redemption(event(session, "valid", " 2 "))
    assert {:ok, duplicate} = Voting.ingest_twitch_reward_redemption(event(session, "valid", "1"))
    assert first.id == duplicate.id
    assert Voting.voting_session_game_weight(second).channel_point_vote_total == 1
    TwitchRedemptions.process_pending(FakeTwitchClient)

    assert FakeTwitchClient.redemption_status("valid") ==
             {session.twitch_voting_reward.reward_id, "FULFILLED"}
  end

  test "invalid entries remain retryable until refunded and chat feedback succeeds", %{
    session: session
  } do
    FakeTwitchClient.fail_resolution(true)

    assert {:ok, redemption} =
             Voting.ingest_twitch_reward_redemption(event(session, "invalid", "999"))

    TwitchRedemptions.process_pending(FakeTwitchClient)
    assert Repo.get!(TwitchVotingRedemption, redemption.id).resolution_status == "pending"
    assert TwitchRedemptions.failed_count(session) == 1
    assert FakeTwitchClient.chat_messages() == []

    FakeTwitchClient.fail_resolution(false)
    FakeTwitchClient.fail_chat(true)
    TwitchRedemptions.process_pending(FakeTwitchClient)
    assert Repo.get!(TwitchVotingRedemption, redemption.id).resolution_status == "done"
    assert Repo.get!(TwitchVotingRedemption, redemption.id).feedback_status == "pending"

    assert FakeTwitchClient.redemption_status("invalid") ==
             {session.twitch_voting_reward.reward_id, "CANCELED"}

    FakeTwitchClient.fail_chat(false)
    TwitchRedemptions.process_pending(FakeTwitchClient)
    assert Repo.get!(TwitchVotingRedemption, redemption.id).feedback_status == "done"
    assert TwitchRedemptions.failed_count(session) == 0
    assert [message] = FakeTwitchClient.chat_messages()
    assert message =~ "@viewer"
    assert message =~ "refunded"
  end

  test "invalid and oversized inputs are canceled", %{session: session, first: first} do
    for {input, index} <-
          Enum.with_index(
            ["", "garbage", "1game", "0", "-1", "999999999999999999999999999999"],
            1
          ) do
      assert {:ok, %{decision: "invalid"}} =
               Voting.ingest_twitch_reward_redemption(event(session, "bad-#{index}", input))
    end

    TwitchRedemptions.process_pending(FakeTwitchClient)

    assert Enum.all?(1..6, fn index ->
             FakeTwitchClient.redemption_status("bad-#{index}") ==
               {session.twitch_voting_reward.reward_id, "CANCELED"}
           end)

    assert Voting.voting_session_game_weight(first).channel_point_vote_total == 0
  end

  test "removed numbers and late redemptions are refunded without voting for another game", %{
    session: session,
    first: first,
    second: second
  } do
    assert {:ok, _} = Voting.update_voting_session_status(session, "draft")
    assert {:ok, _} = Voting.remove_game_from_session(first)

    replacement =
      voting_session_game_fixture(
        session,
        game_fixture(%{community: session.community, external_id: "replacement"})
      )

    assert replacement.option_number > second.option_number
    assert {:ok, _} = Voting.update_voting_session_status(session, "open")

    assert {:ok, removed} = Voting.ingest_twitch_reward_redemption(event(session, "removed", "1"))
    assert removed.decision == "invalid"
    assert {:ok, _} = Voting.update_voting_session_status(session, "closed")
    assert {:ok, late} = Voting.ingest_twitch_reward_redemption(event(session, "late", "2"))
    assert late.decision == "invalid"
    TwitchRedemptions.process_pending(FakeTwitchClient)

    assert FakeTwitchClient.redemption_status("removed") ==
             {session.twitch_voting_reward.reward_id, "CANCELED"}

    assert FakeTwitchClient.redemption_status("late") ==
             {session.twitch_voting_reward.reward_id, "CANCELED"}

    assert Voting.voting_session_game_weight(second).channel_point_vote_total == 0
    assert Voting.voting_session_game_weight(replacement).channel_point_vote_total == 0
  end

  test "a game with Twitch votes cannot be removed", %{session: session, first: first} do
    assert {:ok, _} = Voting.ingest_twitch_reward_redemption(event(session, "valid", "1"))
    assert {:error, :game_has_twitch_votes} = Voting.remove_game_from_session(first)
  end

  test "an ambiguous cancellation is reconciled before sending feedback", %{session: session} do
    FakeTwitchClient.ambiguous_resolution(true)

    assert {:ok, redemption} =
             Voting.ingest_twitch_reward_redemption(event(session, "ambiguous", "bad"))

    TwitchRedemptions.process_pending(FakeTwitchClient)
    saved = Repo.get!(TwitchVotingRedemption, redemption.id)
    assert saved.resolution_status == "done"
    assert saved.feedback_status == "done"
    assert [_message] = FakeTwitchClient.chat_messages()
    TwitchRedemptions.process_pending(FakeTwitchClient)
    assert [_message] = FakeTwitchClient.chat_messages()
  end

  test "spinning freezes voting and disables the session reward", %{session: session} do
    assert {:ok, _spin} = Voting.spin_voting_session_wheel(session)
    refute FakeTwitchClient.reward_enabled?(session.twitch_voting_reward.reward_id)

    assert {:ok, redemption} =
             Voting.ingest_twitch_reward_redemption(event(session, "after-spin", "1"))

    assert redemption.decision == "invalid"
  end

  test "reconciliation recovers redemptions when EventSub was missed", %{
    session: session,
    first: first
  } do
    reward_id = session.twitch_voting_reward.reward_id

    FakeTwitchClient.set_unfulfilled(reward_id, [
      event(session, "missed", "1"),
      event(session, "missed-invalid", "bad")
    ])

    TwitchRedemptions.reconcile_rewards(FakeTwitchClient)
    TwitchRedemptions.reconcile_rewards(FakeTwitchClient)
    assert Voting.voting_session_game_weight(first).channel_point_vote_total == 1
    TwitchRedemptions.process_pending(FakeTwitchClient)
    assert FakeTwitchClient.redemption_status("missed") == {reward_id, "FULFILLED"}
    assert FakeTwitchClient.redemption_status("missed-invalid") == {reward_id, "CANCELED"}
  end
end
