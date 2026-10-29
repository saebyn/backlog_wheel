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
      "redeemed_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "reward" => %{"id" => session.twitch_voting_reward.reward_id}
    }
  end

  test "one reward requires a number and duplicate events count once", %{
    session: session,
    second: second
  } do
    attrs = FakeTwitchClient.reward_attrs(session.id)
    assert FakeTwitchClient.reward_enabled?(session.twitch_voting_reward.reward_id)
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
    assert {:ok, _} = Voting.close_voting_session(session, "draft", client: FakeTwitchClient)
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

  test "an on-time redemption delivered after freezing is included in the spin", %{
    session: session,
    first: first
  } do
    redemption =
      session
      |> event("delayed-on-time", "1")
      |> Map.put("redeemed_at", DateTime.to_iso8601(DateTime.utc_now()))

    assert {:ok, locked} =
             Voting.close_voting_session(session, "locked", client: FakeTwitchClient)

    assert {:ok, %{decision: "valid"}} = Voting.ingest_twitch_reward_redemption(redemption)
    assert Voting.voting_session_game_weight(first).channel_point_vote_total == 1
    assert {:ok, %{spin: spin}} = Voting.spin_voting_session_wheel(locked)

    assert Enum.any?(spin.snapshot["entries"], fn entry ->
             entry["voting_session_game_id"] == first.id and
               entry["channel_point_vote_total"] == 1
           end)
  end

  test "a redemption made while voting was frozen remains invalid after reopening", %{
    session: session,
    first: first
  } do
    assert {:ok, locked} =
             Voting.close_voting_session(session, "locked", client: FakeTwitchClient)

    during_gap = event(session, "during-gap", "1")
    assert {:ok, _} = Voting.update_voting_session_status(locked, "open")
    assert {:ok, %{decision: "invalid"}} = Voting.ingest_twitch_reward_redemption(during_gap)
    assert Voting.voting_session_game_weight(first).channel_point_vote_total == 0
  end

  test "returning to draft reconciles on-time votes before a game can be removed", %{
    session: session,
    first: first
  } do
    redemption = event(session, "before-draft", "1")
    FakeTwitchClient.set_unfulfilled(session.twitch_voting_reward.reward_id, [redemption])
    assert {:ok, _draft} = Voting.close_voting_session(session, "draft", client: FakeTwitchClient)
    assert {:error, :game_has_twitch_votes} = Voting.remove_game_from_session(first)
    assert Voting.voting_session_game_weight(first).channel_point_vote_total == 1
  end

  test "a failed draft reconciliation prevents removing games", %{session: session, first: first} do
    FakeTwitchClient.fail_reconciliation(true)

    assert {:error, {:twitch_reconciliation_failed, _draft, :reconciliation_failed}} =
             Voting.close_voting_session(session, "draft", client: FakeTwitchClient)

    assert {:error, :twitch_reconciliation_required} = Voting.remove_game_from_session(first)
  end

  test "redemptions at the opening are accepted and at the cutoff are refunded", %{
    session: session,
    first: first
  } do
    assert {:ok, locked} =
             Voting.close_voting_session(session, "locked", client: FakeTwitchClient)

    [window] = locked.twitch_voting_windows

    at_open =
      Map.put(
        event(session, "at-open", "1"),
        "redeemed_at",
        DateTime.to_iso8601(window.opened_at)
      )

    at_close =
      Map.put(
        event(session, "at-close", "1"),
        "redeemed_at",
        DateTime.to_iso8601(window.closed_at)
      )

    assert {:ok, %{decision: "valid"}} = Voting.ingest_twitch_reward_redemption(at_open)
    assert {:ok, %{decision: "invalid"}} = Voting.ingest_twitch_reward_redemption(at_close)
    assert Voting.voting_session_game_weight(first).channel_point_vote_total == 1
  end

  test "malformed Twitch identities are rejected for retry", %{session: session} do
    for {key, value} <- [
          {"id", ""},
          {"id", 5},
          {"user_id", ""},
          {"user_id", 5},
          {"user_login", ""},
          {"user_login", 5}
        ] do
      assert {:error, :invalid_twitch_redemption} =
               session
               |> event("malformed", "1")
               |> Map.put(key, value)
               |> Voting.ingest_twitch_reward_redemption()
    end
  end

  test "spinning reconciles on-time Twitch redemptions before selecting a winner", %{
    session: session,
    first: first
  } do
    redemption = event(session, "missed-before-spin", "1")
    FakeTwitchClient.set_unfulfilled(session.twitch_voting_reward.reward_id, [redemption])

    assert {:ok, %{spin: spin}} = Voting.spin_voting_session_wheel(session)

    assert Enum.any?(spin.snapshot["entries"], fn entry ->
             entry["voting_session_game_id"] == first.id and
               entry["channel_point_vote_total"] == 1
           end)
  end

  test "spinning is blocked if Twitch cannot reconcile redemptions", %{session: session} do
    FakeTwitchClient.fail_reconciliation(true)

    assert {:error, {:twitch_reconciliation_failed, :reconciliation_failed}} =
             Voting.spin_voting_session_wheel(session)

    assert BacklogWheel.Backlog.list_recent_spins(session.community) == []
  end

  test "a stale spin request cannot spin a completed session twice", %{session: session} do
    assert {:ok, _} = Voting.spin_voting_session_wheel(session)
    assert {:error, :session_not_ready} = Voting.spin_voting_session_wheel(session)
    assert length(BacklogWheel.Backlog.list_recent_spins(session.community)) == 1
  end

  test "finished sessions automatically delete their drained Twitch reward", %{session: session} do
    assert {:ok, _} = Voting.close_voting_session(session, "closed", client: FakeTwitchClient)
    assert :ok = Voting.cleanup_finished_twitch_rewards(client: FakeTwitchClient)
    assert FakeTwitchClient.deleted_reward?(session.twitch_voting_reward.reward_id)
  end

  test "successive finished sessions do not accumulate channel rewards", %{session: initial} do
    games = Enum.map(initial.voting_session_games, & &1.game)
    assert {:ok, _} = Voting.close_voting_session(initial, "closed", client: FakeTwitchClient)
    assert :ok = Voting.cleanup_finished_twitch_rewards(client: FakeTwitchClient)

    for _ <- 1..51 do
      assert {:ok, session} = Voting.create_voting_session(initial.community)
      Enum.each(games, fn game -> assert {:ok, _} = Voting.add_game_to_session(session, game) end)
      assert {:ok, opened} = Voting.start_twitch_voting(session, client: FakeTwitchClient)
      assert {:ok, _} = Voting.close_voting_session(opened, "closed", client: FakeTwitchClient)
      assert :ok = Voting.cleanup_finished_twitch_rewards(client: FakeTwitchClient)
      assert FakeTwitchClient.deleted_reward?(opened.twitch_voting_reward.reward_id)
    end
  end

  test "a finished session can start a new reward while old reward events are ignored", %{
    session: session,
    first: first
  } do
    old_id = session.twitch_voting_reward.reward_id
    old_event = event(session, "old-event", "1")
    assert {:ok, %{decision: "valid"}} = Voting.ingest_twitch_reward_redemption(old_event)
    assert {:ok, _} = Voting.record_vote(first, %{source: "local", strength: 1})
    assert Voting.voting_session_game_weight(first).channel_point_vote_total == 2
    TwitchRedemptions.process_pending(FakeTwitchClient)

    assert {:ok, finished} =
             Voting.close_voting_session(session, "closed", client: FakeTwitchClient)

    assert :ok = Voting.cleanup_finished_twitch_rewards(client: FakeTwitchClient)
    assert {:ok, _} = Voting.update_voting_session_status(finished, "draft")
    assert Voting.voting_session_game_weight(first).channel_point_vote_total == 0
    assert {:ok, reopened} = Voting.start_twitch_voting(finished, client: FakeTwitchClient)
    refute reopened.twitch_voting_reward.reward_id == old_id
    assert {:ignored, :unknown_twitch_reward} = Voting.ingest_twitch_reward_redemption(old_event)

    assert {:ok, %{decision: "valid"}} =
             Voting.ingest_twitch_reward_redemption(event(reopened, "new-event", "1"))

    assert Voting.voting_session_game_weight(first).channel_point_vote_total == 1
  end

  test "a finished session cannot reset votes until its previous reward is cleaned up", %{
    session: session,
    first: first
  } do
    assert {:ok, _} =
             Voting.ingest_twitch_reward_redemption(event(session, "previous-round", "1"))

    assert {:ok, finished} =
             Voting.close_voting_session(session, "closed", client: FakeTwitchClient)

    assert {:error, :twitch_cleanup_pending} =
             Voting.update_voting_session_status(finished, "draft")

    assert Voting.voting_session_game_weight(first).channel_point_vote_total == 1
    TwitchRedemptions.process_pending(FakeTwitchClient)
    assert :ok = Voting.cleanup_finished_twitch_rewards(client: FakeTwitchClient)
    assert {:ok, _} = Voting.update_voting_session_status(finished, "draft")
    assert Voting.voting_session_game_weight(first).channel_point_vote_total == 0
  end

  test "a manually deleted finished reward is not reconciled repeatedly", %{session: session} do
    reward_id = session.twitch_voting_reward.reward_id
    assert {:ok, _} = Voting.close_voting_session(session, "closed", client: FakeTwitchClient)
    assert :ok = FakeTwitchClient.delete_custom_reward(nil, nil, reward_id)

    TwitchRedemptions.reconcile_rewards(FakeTwitchClient)
    calls = FakeTwitchClient.list_calls(reward_id)
    TwitchRedemptions.reconcile_rewards(FakeTwitchClient)
    assert FakeTwitchClient.list_calls(reward_id) == calls

    assert Voting.get_voting_session!(session.community, session.id).twitch_voting_reward.status ==
             "deleted"
  end

  test "a manually deleted finished reward is recognized after disabling failed", %{
    session: session
  } do
    reward_id = session.twitch_voting_reward.reward_id
    FakeTwitchClient.fail_deletion(reward_id)

    assert {:error, {:twitch_reward_cleanup_failed, _finished, :disable_failed}} =
             Voting.close_voting_session(session, "closed", client: FakeTwitchClient)

    FakeTwitchClient.allow_deletion(reward_id)
    assert :ok = FakeTwitchClient.delete_custom_reward(nil, nil, reward_id)
    TwitchRedemptions.reconcile_rewards(FakeTwitchClient)
    calls = FakeTwitchClient.list_calls(reward_id)
    TwitchRedemptions.reconcile_rewards(FakeTwitchClient)
    assert FakeTwitchClient.list_calls(reward_id) == calls

    assert Voting.get_voting_session!(session.community, session.id).twitch_voting_reward.status ==
             "deleted"
  end

  test "cleanup waits until an invalid redemption has been refunded", %{session: session} do
    reward_id = session.twitch_voting_reward.reward_id
    invalid = event(session, "pending-refund", "invalid")
    FakeTwitchClient.set_unfulfilled(reward_id, [invalid])
    assert {:ok, _} = Voting.ingest_twitch_reward_redemption(invalid)
    assert {:ok, _} = Voting.close_voting_session(session, "closed", client: FakeTwitchClient)

    assert :ok = Voting.cleanup_finished_twitch_rewards(client: FakeTwitchClient)
    refute FakeTwitchClient.deleted_reward?(reward_id)
    TwitchRedemptions.process_pending(FakeTwitchClient)
    assert FakeTwitchClient.redemption_status("pending-refund") == {reward_id, "CANCELED"}
    assert :ok = Voting.cleanup_finished_twitch_rewards(client: FakeTwitchClient)
    assert FakeTwitchClient.deleted_reward?(reward_id)
  end

  test "cleanup retains a reward while a locally recorded refund is pending", %{session: session} do
    reward_id = session.twitch_voting_reward.reward_id

    assert {:ok, _} =
             Voting.ingest_twitch_reward_redemption(event(session, "local-pending", "bad"))

    assert {:ok, _} = Voting.close_voting_session(session, "closed", client: FakeTwitchClient)
    assert :ok = Voting.cleanup_finished_twitch_rewards(client: FakeTwitchClient)
    refute FakeTwitchClient.deleted_reward?(reward_id)
  end

  test "a manually removed reward with an unresolved refund remains visible as a failure", %{
    session: session
  } do
    reward_id = session.twitch_voting_reward.reward_id
    assert {:ok, _} = Voting.ingest_twitch_reward_redemption(event(session, "unresolved", "bad"))
    assert {:ok, _} = Voting.close_voting_session(session, "closed", client: FakeTwitchClient)
    assert :ok = FakeTwitchClient.delete_custom_reward(nil, nil, reward_id)

    TwitchRedemptions.reconcile_rewards(FakeTwitchClient)
    reward = Voting.get_voting_session!(session.community, session.id).twitch_voting_reward
    assert reward.status == "disabled"
    assert reward.reconciliation_error
  end

  test "a manually deleted frozen reward blocks spinning instead of hiding missed votes", %{
    session: session
  } do
    reward_id = session.twitch_voting_reward.reward_id

    assert {:ok, locked} =
             Voting.close_voting_session(session, "locked", client: FakeTwitchClient)

    assert :ok = FakeTwitchClient.delete_custom_reward(nil, nil, reward_id)
    TwitchRedemptions.reconcile_rewards(FakeTwitchClient)

    assert {:error, {:twitch_reconciliation_failed, {:twitch_http_error, 404, _}}} =
             Voting.spin_voting_session_wheel(locked)
  end

  test "failed reward deletion remains retryable", %{session: session} do
    reward_id = session.twitch_voting_reward.reward_id
    assert {:ok, _} = Voting.close_voting_session(session, "closed", client: FakeTwitchClient)
    FakeTwitchClient.fail_deletion(reward_id)
    assert :ok = Voting.cleanup_finished_twitch_rewards(client: FakeTwitchClient)
    refute FakeTwitchClient.deleted_reward?(reward_id)

    assert Voting.get_voting_session!(session.community, session.id).twitch_voting_reward.cleanup_error

    FakeTwitchClient.allow_deletion(reward_id)
    assert :ok = Voting.cleanup_finished_twitch_rewards(client: FakeTwitchClient)
    assert FakeTwitchClient.deleted_reward?(reward_id)
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
