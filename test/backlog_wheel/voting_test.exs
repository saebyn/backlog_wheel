defmodule BacklogWheel.VotingTest do
  use BacklogWheel.DataCase

  alias BacklogWheel.Backlog
  alias BacklogWheel.Voting

  alias BacklogWheel.Voting.{
    ChannelPointVote,
    Viewer,
    ViewerIdentity,
    VotingSession,
    VotingSessionGame,
    WheelFormat
  }

  alias BacklogWheel.Twitch

  import BacklogWheel.BacklogFixtures
  import BacklogWheel.VotingFixtures

  describe "voting_sessions" do
    test "create_voting_session/1 creates a session for a community" do
      community = community_fixture()

      assert {:ok, %VotingSession{} = voting_session} = Voting.create_voting_session(community)
      assert voting_session.community_id == community.id
      assert voting_session.status == "draft"
    end

    test "scoped sessions only return records for the given community" do
      first_community = community_fixture(%{slug: "first-voting"})
      second_community = community_fixture(%{slug: "second-voting"})
      first_session = voting_session_fixture(%{community: first_community})
      second_session = voting_session_fixture(%{community: second_community})

      assert Enum.map(Voting.list_voting_sessions(first_community), & &1.id) == [first_session.id]

      assert Enum.map(Voting.list_voting_sessions(second_community), & &1.id) == [
               second_session.id
             ]

      assert_raise Ecto.NoResultsError, fn ->
        Voting.get_voting_session!(first_community, second_session.id)
      end
    end

    test "create_voting_session/2 attaches the current community" do
      community = community_fixture(%{slug: "created-voting"})

      assert {:ok, voting_session} = Voting.create_voting_session(community, %{})
      assert voting_session.community_id == community.id
    end

    test "create_voting_session/2 represents session status" do
      community = community_fixture()

      assert {:ok, %VotingSession{} = voting_session} =
               Voting.create_voting_session(community, %{status: "completed"})

      assert voting_session.status == "completed"

      assert {:error, changeset} = Voting.create_voting_session(community, %{status: "invalid"})
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "create_voting_session/2 stores title and description" do
      community = community_fixture()

      assert {:ok, voting_session} =
               Voting.create_voting_session(community, %{
                 title: "Community Vote",
                 description: "Pick the next game."
               })

      assert voting_session.title == "Community Vote"
      assert voting_session.description == "Pick the next game."
    end

    test "update_voting_session_status/2 requires at least two games to open voting" do
      voting_session = voting_session_fixture()
      voting_session_game_fixture(voting_session, game_fixture())

      assert Voting.update_voting_session_status(voting_session, "open") ==
               {:error, {:voting_session_pool_too_small, 1, 2}}
    end

    test "update_voting_session_status/2 rejects impractically large pools" do
      voting_session = voting_session_fixture()

      for index <- 1..51 do
        game =
          game_fixture(%{
            title: "Too Many Session Game #{index}",
            external_id: "too-many-session-game-#{index}"
          })

        voting_session_game_fixture(voting_session, game)
      end

      assert Voting.update_voting_session_status(voting_session, "open") ==
               {:error, {:voting_session_pool_too_large, 51, 50}}
    end

    test "update_voting_session_status/2 opens sessions with practical pool sizes" do
      voting_session = voting_session_fixture()

      voting_session_game_fixture(
        voting_session,
        game_fixture(%{title: "First Valid Pool", external_id: "first-valid-pool"})
      )

      voting_session_game_fixture(
        voting_session,
        game_fixture(%{title: "Second Valid Pool", external_id: "second-valid-pool"})
      )

      assert {:ok, voting_session} = Voting.update_voting_session_status(voting_session, "open")
      assert voting_session.status == "open"
    end
  end

  describe "wheel_formats" do
    test "create_wheel_format/2 creates a format for a community" do
      community = community_fixture()

      assert {:ok, %WheelFormat{} = wheel_format} =
               Voting.create_wheel_format(community, %{
                 name: "Fresh backlog",
                 description: "Unplayed games first.",
                 default_session_title: "Fresh Vote",
                 default_session_description: "Pick something untouched.",
                 candidate_rules: %{"include_in_wheel" => true, "played_on_stream" => false},
                 weighting_rules: %{"base_weight" => 2, "intent" => "favor_unplayed"}
               })

      assert wheel_format.community_id == community.id
      assert wheel_format.name == "Fresh backlog"
      assert wheel_format.default_session_title == "Fresh Vote"
      assert wheel_format.candidate_rules["played_on_stream"] == false
      assert wheel_format.weighting_rules["base_weight"] == 2
    end

    test "ensure_default_wheel_formats/1 seeds default formats once" do
      community = community_fixture()

      assert {:ok, formats} = Voting.ensure_default_wheel_formats(community)

      assert Enum.map(formats, & &1.name) == [
               "Fresh backlog",
               "Keep the streak alive",
               "Chaos night"
             ]

      assert {:ok, formats_again} = Voting.ensure_default_wheel_formats(community)
      assert Enum.map(formats_again, & &1.id) == Enum.map(formats, & &1.id)
    end

    test "list_all_wheel_formats/1 includes disabled formats" do
      community = community_fixture()
      enabled = wheel_format_fixture(%{community: community, name: "Enabled Format"})

      disabled =
        wheel_format_fixture(%{community: community, name: "Disabled Format", is_enabled: false})

      assert Enum.map(Voting.list_wheel_formats(community), & &1.id) == [enabled.id]

      assert Enum.map(Voting.list_all_wheel_formats(community), & &1.id) |> Enum.sort() == [
               enabled.id,
               disabled.id
             ]
    end

    test "update_wheel_format/3 updates custom format fields" do
      community = community_fixture()
      format = wheel_format_fixture(%{community: community})

      assert {:ok, updated_format} =
               Voting.update_wheel_format(community, format, %{
                 name: "Updated Format",
                 is_enabled: false,
                 candidate_rules: %{"include_in_wheel" => true, "played_on_stream" => false},
                 weighting_rules: %{"base_weight" => 4}
               })

      assert updated_format.name == "Updated Format"
      refute updated_format.is_enabled
      assert updated_format.candidate_rules["played_on_stream"] == false
      assert updated_format.weighting_rules["base_weight"] == 4
    end

    test "delete_wheel_format/2 removes custom formats and protects defaults" do
      community = community_fixture()
      format = wheel_format_fixture(%{community: community})
      {:ok, [default_format | _formats]} = Voting.ensure_default_wheel_formats(community)

      assert {:error, :default_wheel_format_protected} =
               Voting.delete_wheel_format(community, default_format)

      assert {:ok, _format} = Voting.delete_wheel_format(community, format)
      refute Enum.any?(Voting.list_all_wheel_formats(community), &(&1.id == format.id))
    end

    test "create_voting_session_from_wheel_format/2 creates and populates a session" do
      community = community_fixture()

      included_game =
        game_fixture(%{
          community: community,
          title: "Fresh Candidate",
          include_in_wheel: true,
          played_on_stream: false,
          external_id: "fresh-candidate"
        })

      played_game =
        game_fixture(%{
          community: community,
          title: "Played Candidate",
          include_in_wheel: true,
          played_on_stream: true,
          external_id: "played-candidate"
        })

      wheel_format =
        wheel_format_fixture(%{
          community: community,
          default_session_title: "Fresh Vote",
          default_session_description: "Only fresh games.",
          candidate_rules: %{"include_in_wheel" => true, "played_on_stream" => false},
          weighting_rules: %{"base_weight" => 3}
        })

      assert {:ok, voting_session} =
               Voting.create_voting_session_from_wheel_format(community, wheel_format)

      assert voting_session.title == "Fresh Vote"
      assert voting_session.description == "Only fresh games."
      assert voting_session.wheel_format_id == wheel_format.id

      voting_session = Voting.get_voting_session!(community, voting_session.id)

      assert [pool_item] = voting_session.voting_session_games
      assert pool_item.game_id == included_game.id
      assert pool_item.base_weight == 3
      refute Enum.any?(voting_session.voting_session_games, &(&1.game_id == played_game.id))
    end
  end

  describe "voting_session_games" do
    test "add_game_to_session/3 adds a game to the session pool with a base weight" do
      community = community_fixture()
      voting_session = voting_session_fixture(%{community: community})
      game = game_fixture(%{community: community, title: "Vote Candidate"})

      assert {:ok, %VotingSessionGame{} = voting_session_game} =
               Voting.add_game_to_session(voting_session, game, %{base_weight: 3})

      assert voting_session_game.voting_session_id == voting_session.id
      assert voting_session_game.game_id == game.id
      assert voting_session_game.base_weight == 3
    end

    test "add_game_to_session/3 rejects games from another community" do
      first_community = community_fixture(%{slug: "first-pool"})
      second_community = community_fixture(%{slug: "second-pool"})
      voting_session = voting_session_fixture(%{community: first_community})
      game = game_fixture(%{community: second_community})

      assert Voting.add_game_to_session(voting_session, game) ==
               {:error, :game_not_in_session_community}
    end

    test "add_game_to_session/3 defaults base weight" do
      community = community_fixture()
      voting_session = voting_session_fixture(%{community: community})
      game = game_fixture(%{community: community, title: "Default Weight Candidate"})

      assert {:ok, %VotingSessionGame{} = voting_session_game} =
               Voting.add_game_to_session(voting_session, game)

      assert voting_session_game.base_weight == 1
    end

    test "get_voting_session!/2 preloads pool games" do
      community = community_fixture()
      voting_session = voting_session_fixture(%{community: community})
      game = game_fixture(%{community: community, title: "Preloaded Candidate"})
      voting_session_game_fixture(voting_session, game, %{base_weight: 2})

      voting_session = Voting.get_voting_session!(community, voting_session.id)

      assert [voting_session_game] = voting_session.voting_session_games
      assert voting_session_game.base_weight == 2
      assert voting_session_game.game.title == "Preloaded Candidate"
    end

    test "add_game_to_session/3 requires positive base weight" do
      community = community_fixture()
      voting_session = voting_session_fixture(%{community: community})
      game = game_fixture(%{community: community, title: "Invalid Weight Candidate"})

      assert {:error, changeset} =
               Voting.add_game_to_session(voting_session, game, %{base_weight: 0})

      assert %{base_weight: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "add_game_to_session/3 prevents duplicate games in one session" do
      community = community_fixture()
      voting_session = voting_session_fixture(%{community: community})
      game = game_fixture(%{community: community, title: "Duplicate Candidate"})
      voting_session_game_fixture(voting_session, game)

      assert {:error, changeset} = Voting.add_game_to_session(voting_session, game)
      assert %{voting_session_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "populate_session_from_wheel_candidates/1 adds wheel-eligible games" do
      community = community_fixture()
      voting_session = voting_session_fixture(%{community: community})

      first_game =
        game_fixture(%{
          community: community,
          title: "First Candidate",
          include_in_wheel: true,
          external_id: "first"
        })

      second_game =
        game_fixture(%{
          community: community,
          title: "Second Candidate",
          include_in_wheel: true,
          external_id: "second"
        })

      excluded_game =
        game_fixture(%{
          community: community,
          title: "Excluded Candidate",
          include_in_wheel: false,
          external_id: "excluded"
        })

      assert {:ok, voting_session_games} =
               Voting.populate_session_from_wheel_candidates(voting_session)

      assert Enum.map(voting_session_games, & &1.game_id) == [first_game.id, second_game.id]
      assert Enum.map(voting_session_games, & &1.base_weight) == [1, 1]

      voting_session = Voting.get_voting_session!(community, voting_session.id)

      assert Enum.map(voting_session.voting_session_games, & &1.game_id) == [
               first_game.id,
               second_game.id
             ]

      refute Enum.any?(voting_session.voting_session_games, &(&1.game_id == excluded_game.id))
    end

    test "populate_session_from_wheel_candidates/1 avoids duplicate pool games" do
      community = community_fixture()
      voting_session = voting_session_fixture(%{community: community})

      existing_game =
        game_fixture(%{
          community: community,
          title: "Existing Candidate",
          include_in_wheel: true,
          external_id: "existing"
        })

      new_game =
        game_fixture(%{
          community: community,
          title: "New Candidate",
          include_in_wheel: true,
          external_id: "new"
        })

      voting_session_game_fixture(voting_session, existing_game, %{base_weight: 4})

      assert {:ok, voting_session_games} =
               Voting.populate_session_from_wheel_candidates(voting_session)

      assert Enum.map(voting_session_games, & &1.game_id) == [new_game.id]

      voting_session = Voting.get_voting_session!(community, voting_session.id)

      assert Enum.map(voting_session.voting_session_games, & &1.game_id) == [
               existing_game.id,
               new_game.id
             ]

      assert Enum.find(voting_session.voting_session_games, &(&1.game_id == existing_game.id)).base_weight ==
               4
    end

    test "populate_session_from_wheel_candidates/1 does not change backlog eligibility" do
      voting_session = voting_session_fixture()

      eligible_game =
        game_fixture(%{
          title: "Eligible Candidate",
          include_in_wheel: true,
          external_id: "eligible"
        })

      excluded_game =
        game_fixture(%{
          title: "Still Excluded",
          include_in_wheel: false,
          external_id: "still-excluded"
        })

      assert {:ok, _voting_session_games} =
               Voting.populate_session_from_wheel_candidates(voting_session)

      assert Backlog.get_game!(eligible_game.id).include_in_wheel == true
      assert Backlog.get_game!(excluded_game.id).include_in_wheel == false
    end
  end

  describe "twitch voting rewards" do
    setup do
      start_supervised!(BacklogWheel.FakeTwitchClient)

      original_config = Application.get_env(:backlog_wheel, :twitch)

      Application.put_env(:backlog_wheel, :twitch,
        client_id: "client-id",
        client_secret: "client-secret"
      )

      community =
        community_fixture(%{
          twitch_broadcaster_id: "28728577",
          twitch_reward_cost: 321
        })

      Process.put(:test_community, community)

      on_exit(fn ->
        if is_nil(original_config) do
          Application.delete_env(:backlog_wheel, :twitch)
        else
          Application.put_env(:backlog_wheel, :twitch, original_config)
        end
      end)

      :ok
    end

    test "start_twitch_voting/2 creates one reward per voting session game" do
      voting_session = voting_session_fixture()
      first_game = game_fixture(%{title: "First Twitch Candidate"})

      second_game =
        game_fixture(%{title: "Second Twitch Candidate", external_id: "second-twitch"})

      first_pool_item = voting_session_game_fixture(voting_session, first_game)
      second_pool_item = voting_session_game_fixture(voting_session, second_game)

      {:ok, _credential} =
        Twitch.save_credential(%{
          access_token: "access-token",
          refresh_token: "refresh-token",
          scopes: "channel:manage:redemptions"
        })

      assert {:ok, updated_session} =
               Voting.start_twitch_voting(voting_session, client: BacklogWheel.FakeTwitchClient)

      assert updated_session.status == "open"
      assert [first_updated, second_updated] = updated_session.voting_session_games

      assert first_updated.id == first_pool_item.id
      assert first_updated.twitch_reward_id == "reward-#{first_pool_item.id}"

      assert first_updated.twitch_reward_title ==
               "Vote ##{first_pool_item.id}: First Twitch Candidate"

      assert first_updated.twitch_reward_cost == 321
      assert first_updated.twitch_reward_status == "enabled"

      assert second_updated.id == second_pool_item.id
      assert second_updated.twitch_reward_id == "reward-#{second_pool_item.id}"

      assert second_updated.twitch_reward_title ==
               "Vote ##{second_pool_item.id}: Second Twitch Candidate"

      assert second_updated.twitch_reward_cost == 321
      assert second_updated.twitch_reward_status == "enabled"
      assert BacklogWheel.FakeTwitchClient.refresh_count() == 1
    end

    test "start_twitch_voting/2 requires a stored Twitch credential" do
      voting_session = voting_session_fixture()
      voting_session_game_fixture(voting_session, game_fixture())

      assert Voting.start_twitch_voting(voting_session, client: BacklogWheel.FakeTwitchClient) ==
               {:error, :missing_twitch_credential}
    end

    test "start_twitch_voting/2 rejects pools larger than Twitch reward limits" do
      voting_session = voting_session_fixture()

      pool_items =
        for index <- 1..51 do
          game =
            game_fixture(%{
              title: "Large Pool Game #{index}",
              external_id: "large-pool-game-#{index}"
            })

          voting_session_game_fixture(voting_session, game)
        end

      {:ok, _credential} =
        Twitch.save_credential(%{
          access_token: "access-token",
          refresh_token: "refresh-token",
          scopes: "channel:manage:redemptions"
        })

      assert Voting.start_twitch_voting(voting_session, client: BacklogWheel.FakeTwitchClient) ==
               {:error, {:twitch_reward_pool_too_large, 51, 50}}

      assert BacklogWheel.FakeTwitchClient.reward_attrs(hd(pool_items).id) == nil
    end

    test "validate_twitch_reward_creation/1 rejects long existing reward titles" do
      voting_session = voting_session_fixture()
      pool_item = voting_session_game_fixture(voting_session, game_fixture())

      voting_session_game_fixture(
        voting_session,
        game_fixture(%{title: "Valid Reward Title", external_id: "valid-reward-title"})
      )

      long_title = String.duplicate("A", 46)

      pool_item
      |> VotingSessionGame.twitch_reward_changeset(%{
        twitch_reward_id: "reward-#{pool_item.id}",
        twitch_reward_title: long_title,
        twitch_reward_cost: 100,
        twitch_reward_status: "enabled"
      })
      |> Repo.update!()

      assert Voting.validate_twitch_reward_creation(voting_session) ==
               {:error, {:twitch_reward_title_too_long, long_title, 45}}
    end

    test "validate_twitch_reward_creation/1 rejects duplicate reward titles" do
      voting_session = voting_session_fixture()
      first_pool_item = voting_session_game_fixture(voting_session, game_fixture())

      second_pool_item =
        voting_session_game_fixture(
          voting_session,
          game_fixture(%{external_id: "duplicate-reward-title"})
        )

      duplicate_title = "Vote for duplicate"

      for pool_item <- [first_pool_item, second_pool_item] do
        pool_item
        |> VotingSessionGame.twitch_reward_changeset(%{
          twitch_reward_id: "reward-#{pool_item.id}",
          twitch_reward_title: duplicate_title,
          twitch_reward_cost: 100,
          twitch_reward_status: "enabled"
        })
        |> Repo.update!()
      end

      assert Voting.validate_twitch_reward_creation(voting_session) ==
               {:error, {:duplicate_twitch_reward_titles, [duplicate_title]}}
    end

    test "start_twitch_voting/2 does not require viewers to type game names" do
      voting_session = voting_session_fixture()
      game = game_fixture(%{title: "No Typing Required"})
      pool_item = voting_session_game_fixture(voting_session, game)

      voting_session_game_fixture(
        voting_session,
        game_fixture(%{title: "No Typing Required 2", external_id: "no-typing-required-2"})
      )

      {:ok, _credential} =
        Twitch.save_credential(%{
          access_token: "access-token",
          refresh_token: "refresh-token",
          scopes: "channel:manage:redemptions"
        })

      assert {:ok, _session} =
               Voting.start_twitch_voting(voting_session, client: BacklogWheel.FakeTwitchClient)

      assert BacklogWheel.FakeTwitchClient.reward_attrs(pool_item.id).title ==
               "Vote ##{pool_item.id}: No Typing Required"
    end

    test "remove_twitch_rewards/2 deletes rewards and keeps voting status unchanged" do
      voting_session = voting_session_fixture(%{status: "open"})
      game = game_fixture(%{title: "Temporary Reward"})
      pool_item = voting_session_game_fixture(voting_session, game)

      voting_session_game_fixture(
        voting_session,
        game_fixture(%{title: "Temporary Reward 2", external_id: "temporary-reward-2"})
      )

      {:ok, _credential} =
        Twitch.save_credential(%{
          access_token: "access-token",
          refresh_token: "refresh-token",
          scopes: "channel:manage:redemptions"
        })

      {:ok, session_with_rewards} =
        Voting.start_twitch_voting(voting_session, client: BacklogWheel.FakeTwitchClient)

      pool_item_with_reward =
        Enum.find(session_with_rewards.voting_session_games, &(&1.id == pool_item.id))

      reward_id = pool_item_with_reward.twitch_reward_id

      assert {:ok, updated_session} =
               Voting.remove_twitch_rewards(voting_session, client: BacklogWheel.FakeTwitchClient)

      assert updated_session.status == "open"
      assert BacklogWheel.FakeTwitchClient.deleted_reward?(reward_id)

      updated_pool_item =
        Enum.find(updated_session.voting_session_games, &(&1.id == pool_item.id))

      assert updated_pool_item.id == pool_item.id
      assert updated_pool_item.twitch_reward_id == reward_id
      assert updated_pool_item.twitch_reward_title == "Vote ##{pool_item.id}: Temporary Reward"
      assert updated_pool_item.twitch_reward_cost == 321
      assert updated_pool_item.twitch_reward_status == "deleted"
      assert updated_pool_item.twitch_reward_deletion_status == "deleted"
      assert updated_pool_item.twitch_reward_deletion_error == nil
      assert updated_pool_item.twitch_reward_deleted_at
    end

    test "close_voting_session/3 closes voting and deletes rewards" do
      voting_session = voting_session_fixture(%{status: "open"})
      game = game_fixture(%{title: "Closing Reward"})
      pool_item = voting_session_game_fixture(voting_session, game)

      voting_session_game_fixture(
        voting_session,
        game_fixture(%{title: "Closing Reward 2", external_id: "closing-reward-2"})
      )

      {:ok, _credential} =
        Twitch.save_credential(%{
          access_token: "access-token",
          refresh_token: "refresh-token",
          scopes: "channel:manage:redemptions"
        })

      {:ok, session_with_rewards} =
        Voting.start_twitch_voting(voting_session, client: BacklogWheel.FakeTwitchClient)

      pool_item_with_reward =
        Enum.find(session_with_rewards.voting_session_games, &(&1.id == pool_item.id))

      reward_id = pool_item_with_reward.twitch_reward_id

      assert {:ok, closed_session} =
               Voting.close_voting_session(voting_session, "closed",
                 client: BacklogWheel.FakeTwitchClient
               )

      assert closed_session.status == "closed"
      assert BacklogWheel.FakeTwitchClient.deleted_reward?(reward_id)
      updated_pool_item = Enum.find(closed_session.voting_session_games, &(&1.id == pool_item.id))
      assert updated_pool_item.twitch_reward_deletion_status == "deleted"
    end

    test "close_voting_session/3 records failed deletions and keeps rewards retryable" do
      voting_session = voting_session_fixture(%{status: "open"})
      game = game_fixture(%{title: "Retry Reward"})
      pool_item = voting_session_game_fixture(voting_session, game)

      voting_session_game_fixture(
        voting_session,
        game_fixture(%{title: "Retry Reward 2", external_id: "retry-reward-2"})
      )

      {:ok, _credential} =
        Twitch.save_credential(%{
          access_token: "access-token",
          refresh_token: "refresh-token",
          scopes: "channel:manage:redemptions"
        })

      {:ok, session_with_rewards} =
        Voting.start_twitch_voting(voting_session, client: BacklogWheel.FakeTwitchClient)

      pool_item_with_reward =
        Enum.find(session_with_rewards.voting_session_games, &(&1.id == pool_item.id))

      reward_id = pool_item_with_reward.twitch_reward_id
      BacklogWheel.FakeTwitchClient.fail_deletion(reward_id)

      assert {:error,
              {:twitch_reward_cleanup_failed, closed_session, {:twitch_reward_deletion_failed, 1}}} =
               Voting.close_voting_session(voting_session, "closed",
                 client: BacklogWheel.FakeTwitchClient
               )

      assert closed_session.status == "closed"
      failed_pool_item = Enum.find(closed_session.voting_session_games, &(&1.id == pool_item.id))
      assert failed_pool_item.twitch_reward_id == reward_id
      assert failed_pool_item.twitch_reward_deletion_status == "failed"
      assert failed_pool_item.twitch_reward_deletion_error == ":delete_failed"

      BacklogWheel.FakeTwitchClient.allow_deletion(reward_id)

      assert {:ok, retried_session} =
               Voting.remove_twitch_rewards(closed_session, client: BacklogWheel.FakeTwitchClient)

      assert BacklogWheel.FakeTwitchClient.deleted_reward?(reward_id)

      retried_pool_item =
        Enum.find(retried_session.voting_session_games, &(&1.id == pool_item.id))

      assert retried_pool_item.twitch_reward_deletion_status == "deleted"
      assert retried_pool_item.twitch_reward_deletion_error == nil
    end

    test "remove_twitch_rewards/2 reports when no rewards exist" do
      voting_session = voting_session_fixture()
      voting_session_game_fixture(voting_session, game_fixture())

      {:ok, _credential} =
        Twitch.save_credential(%{
          access_token: "access-token",
          refresh_token: "refresh-token",
          scopes: "channel:manage:redemptions"
        })

      assert Voting.remove_twitch_rewards(voting_session, client: BacklogWheel.FakeTwitchClient) ==
               {:error, :no_twitch_rewards}
    end
  end

  describe "viewers" do
    test "create_viewer/2 creates a viewer for a community" do
      community = community_fixture()

      assert {:ok, %Viewer{} = viewer} =
               Voting.create_viewer(community, %{display_name: "Viewer One"})

      assert viewer.community_id == community.id
      assert viewer.display_name == "Viewer One"
    end

    test "add_identity_to_viewer/2 lets a viewer have platform identities" do
      viewer = viewer_fixture(%{display_name: "Identity Viewer"})

      assert {:ok, %ViewerIdentity{} = local_identity} =
               Voting.add_identity_to_viewer(viewer, %{
                 platform: "local",
                 platform_user_id: "local-viewer",
                 display_name: "Local Viewer"
               })

      assert {:ok, %ViewerIdentity{} = twitch_identity} =
               Voting.add_identity_to_viewer(viewer, %{
                 platform: "twitch",
                 platform_user_id: "12345",
                 display_name: "TwitchViewer"
               })

      assert local_identity.viewer_id == viewer.id
      assert local_identity.community_id == viewer.community_id
      assert twitch_identity.viewer_id == viewer.id
      assert twitch_identity.community_id == viewer.community_id
    end

    test "add_identity_to_viewer/2 prevents duplicate platform identities in a community" do
      viewer = viewer_fixture(%{display_name: "First Viewer"})
      other_viewer = viewer_fixture(%{display_name: "Second Viewer"})
      viewer_identity_fixture(viewer, %{platform: "twitch", platform_user_id: "duplicate-id"})

      assert {:error, changeset} =
               Voting.add_identity_to_viewer(other_viewer, %{
                 platform: "twitch",
                 platform_user_id: "duplicate-id"
               })

      assert %{community_id: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "channel_point_votes" do
    test "ingest_twitch_reward_redemption/1 records a channel point vote" do
      voting_session = voting_session_fixture(%{status: "open"})
      game = game_fixture(%{title: "Redeemable Game"})
      pool_item = voting_session_game_fixture(voting_session, game)

      pool_item
      |> VotingSessionGame.twitch_reward_changeset(%{
        twitch_reward_id: "reward-1",
        twitch_reward_title: "Vote ##{pool_item.id}: Redeemable Game",
        twitch_reward_cost: 100,
        twitch_reward_status: "enabled"
      })
      |> Repo.update!()

      assert {:ok, %ChannelPointVote{} = vote} =
               Voting.ingest_twitch_reward_redemption(%{
                 "id" => "redemption-1",
                 "user_id" => "twitch-user-1",
                 "user_name" => "Redeemer",
                 "reward" => %{"id" => "reward-1"}
               })

      assert vote.voting_session_game_id == pool_item.id
      assert vote.strength == 1
      assert vote.source == "twitch_channel_points"
      assert vote.external_event_id == "redemption-1"

      identity =
        Repo.get_by!(ViewerIdentity, platform: "twitch", platform_user_id: "twitch-user-1")

      viewer = Repo.get!(Viewer, identity.viewer_id)
      assert viewer.display_name == "Redeemer"
      assert vote.viewer_id == viewer.id
    end

    test "ingest_twitch_reward_redemption/1 reuses Twitch viewer identities" do
      voting_session = voting_session_fixture(%{status: "open"})
      game = game_fixture(%{title: "Known Viewer Game"})
      pool_item = voting_session_game_fixture(voting_session, game)
      viewer = viewer_fixture(%{display_name: "Known Viewer"})
      viewer_identity_fixture(viewer, %{platform: "twitch", platform_user_id: "twitch-user-2"})

      pool_item
      |> VotingSessionGame.twitch_reward_changeset(%{
        twitch_reward_id: "reward-2",
        twitch_reward_title: "Vote ##{pool_item.id}: Known Viewer Game",
        twitch_reward_cost: 100,
        twitch_reward_status: "enabled"
      })
      |> Repo.update!()

      assert {:ok, vote} =
               Voting.ingest_twitch_reward_redemption(%{
                 id: "redemption-2",
                 user_id: "twitch-user-2",
                 user_name: "Changed Name",
                 reward: %{id: "reward-2"}
               })

      assert vote.viewer_id == viewer.id
      assert Repo.aggregate(Viewer, :count, :id) == 1
    end

    test "ingest_twitch_reward_redemption/1 is idempotent by redemption id" do
      voting_session = voting_session_fixture(%{status: "open"})
      game = game_fixture(%{title: "Duplicate Redemption Game"})
      pool_item = voting_session_game_fixture(voting_session, game)

      pool_item
      |> VotingSessionGame.twitch_reward_changeset(%{
        twitch_reward_id: "reward-3",
        twitch_reward_title: "Vote ##{pool_item.id}: Duplicate Redemption Game",
        twitch_reward_cost: 100,
        twitch_reward_status: "enabled"
      })
      |> Repo.update!()

      attrs = %{
        "id" => "redemption-3",
        "user_id" => "twitch-user-3",
        "user_name" => "Duplicate Viewer",
        "reward" => %{"id" => "reward-3"}
      }

      assert {:ok, first_vote} = Voting.ingest_twitch_reward_redemption(attrs)
      assert {:ok, second_vote} = Voting.ingest_twitch_reward_redemption(attrs)

      assert first_vote.id == second_vote.id
      assert Repo.aggregate(ChannelPointVote, :count, :id) == 1
    end

    test "ingest_twitch_reward_redemption/1 ignores unknown and inactive rewards" do
      voting_session = voting_session_fixture(%{status: "closed"})
      game = game_fixture(%{title: "Closed Reward Game"})
      pool_item = voting_session_game_fixture(voting_session, game)

      pool_item
      |> VotingSessionGame.twitch_reward_changeset(%{
        twitch_reward_id: "closed-reward",
        twitch_reward_title: "Vote ##{pool_item.id}: Closed Reward Game",
        twitch_reward_cost: 100,
        twitch_reward_status: "enabled"
      })
      |> Repo.update!()

      assert Voting.ingest_twitch_reward_redemption(%{
               "id" => "unknown-redemption",
               "user_id" => "twitch-user-4",
               "reward" => %{"id" => "unknown-reward"}
             }) == {:ignored, :unknown_twitch_reward}

      assert Voting.ingest_twitch_reward_redemption(%{
               "id" => "closed-redemption",
               "user_id" => "twitch-user-5",
               "reward" => %{"id" => "closed-reward"}
             }) == {:ignored, :unknown_twitch_reward}

      assert Repo.aggregate(ChannelPointVote, :count, :id) == 0
    end

    test "record_vote/3 records a positive vote against a session game" do
      voting_session_game = voting_session_game_fixture(voting_session_fixture(), game_fixture())
      viewer = viewer_fixture(%{display_name: "Vote Viewer"})

      assert {:ok, %ChannelPointVote{} = channel_point_vote} =
               Voting.record_vote(voting_session_game, viewer, %{
                 strength: 5,
                 source: "twitch",
                 external_event_id: "event-1"
               })

      assert channel_point_vote.voting_session_game_id == voting_session_game.id
      assert channel_point_vote.viewer_id == viewer.id
      assert channel_point_vote.strength == 5
      assert channel_point_vote.source == "twitch"
      assert channel_point_vote.external_event_id == "event-1"
    end

    test "record_vote/2 can record a local admin vote without a viewer" do
      voting_session_game = voting_session_game_fixture(voting_session_fixture(), game_fixture())

      assert {:ok, %ChannelPointVote{} = channel_point_vote} =
               Voting.record_vote(voting_session_game, %{strength: 2, source: "local"})

      assert channel_point_vote.viewer_id == nil
      assert channel_point_vote.strength == 2
      assert channel_point_vote.source == "local"
    end

    test "record_vote/3 rejects non-positive strengths" do
      voting_session_game = voting_session_game_fixture(voting_session_fixture(), game_fixture())
      viewer = viewer_fixture(%{display_name: "Negative Viewer"})

      assert {:error, changeset} =
               Voting.record_vote(voting_session_game, viewer, %{strength: -1, source: "twitch"})

      assert %{strength: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "record_vote/3 is idempotent for duplicate external events" do
      voting_session_game = voting_session_game_fixture(voting_session_fixture(), game_fixture())
      viewer = viewer_fixture(%{display_name: "Idempotent Viewer"})

      assert {:ok, first_vote} =
               Voting.record_vote(voting_session_game, viewer, %{
                 strength: 3,
                 source: "twitch",
                 external_event_id: "event-2"
               })

      assert {:ok, second_vote} =
               Voting.record_vote(voting_session_game, viewer, %{
                 strength: 99,
                 source: "twitch",
                 external_event_id: "event-2"
               })

      assert first_vote.id == second_vote.id
      assert first_vote.strength == second_vote.strength
      assert Repo.aggregate(ChannelPointVote, :count, :id) == 1
    end

    test "record_vote/3 allows repeated votes without an external event id" do
      voting_session_game = voting_session_game_fixture(voting_session_fixture(), game_fixture())
      viewer = viewer_fixture(%{display_name: "Repeat Viewer"})

      assert {:ok, first_vote} =
               Voting.record_vote(voting_session_game, viewer, %{strength: 1, source: "local"})

      assert {:ok, second_vote} =
               Voting.record_vote(voting_session_game, viewer, %{strength: 1, source: "local"})

      assert first_vote.id != second_vote.id
      assert Repo.aggregate(ChannelPointVote, :count, :id) == 2
    end

    test "record_vote/2 broadcasts voting session changes" do
      voting_session = voting_session_fixture()
      voting_session_game = voting_session_game_fixture(voting_session, game_fixture())

      assert :ok = Voting.subscribe_to_voting_session(voting_session)

      assert {:ok, _vote} =
               Voting.record_vote(voting_session_game, %{strength: 1, source: "local"})

      assert_receive {:voting_session_changed, id}
      assert id == voting_session.id
    end

    test "voting_session_game_weight/1 calculates final weight from votes" do
      voting_session_game =
        voting_session_game_fixture(voting_session_fixture(), game_fixture(), %{base_weight: 2})

      channel_point_vote_fixture(voting_session_game, nil, %{strength: 3})
      channel_point_vote_fixture(voting_session_game, nil, %{strength: 4})

      assert Voting.voting_session_game_weight(voting_session_game) == %{
               base_weight: 2,
               channel_point_vote_total: 7,
               final_weight: 9
             }
    end

    test "list_voting_session_wheel_entries/1 returns final weights for the wheel" do
      voting_session = voting_session_fixture()
      base_game = game_fixture(%{title: "Base Weight Game"})
      voted_game = game_fixture(%{title: "Voted Weight Game", external_id: "voted"})
      base_pool_item = voting_session_game_fixture(voting_session, base_game, %{base_weight: 2})

      voted_pool_item =
        voting_session_game_fixture(voting_session, voted_game, %{base_weight: 1})

      channel_point_vote_fixture(voted_pool_item, nil, %{strength: 4})

      entries = Voting.list_voting_session_wheel_entries(voting_session)

      assert Enum.map(entries, & &1.title) == ["Base Weight Game", "Voted Weight Game"]

      assert Enum.map(
               entries,
               &{&1.pool_item.id, &1.weight, &1.base_weight, &1.channel_point_vote_total}
             ) == [
               {base_pool_item.id, 2, 2, 0},
               {voted_pool_item.id, 5, 1, 4}
             ]
    end

    test "list_voting_session_wheel_entries/1 keeps stable pool item order" do
      voting_session = voting_session_fixture()
      first_pool_item = voting_session_game_fixture(voting_session, game_fixture())

      second_pool_item =
        voting_session_game_fixture(voting_session, game_fixture(%{external_id: "stable-order"}))

      entries = Voting.list_voting_session_wheel_entries(voting_session)

      assert Enum.map(entries, & &1.pool_item.id) == [first_pool_item.id, second_pool_item.id]
    end

    test "spin_voting_session_wheel/1 records a voting-session spin" do
      voting_session = voting_session_fixture()
      game = game_fixture(%{title: "Only Voting Candidate"})
      voting_session_game_fixture(voting_session, game, %{base_weight: 3})

      assert {:ok, %{game: selected_game, spin: spin, entry: entry, spin_payload: payload}} =
               Voting.spin_voting_session_wheel(voting_session)

      assert selected_game.id == game.id
      assert entry.weight == 3
      assert spin.game.id == game.id
      assert spin.source == "voting_session"
      assert spin.notes =~ "Voting session #{voting_session.id}"
      assert payload["spinId"] == spin.id
      assert payload["gameId"] == game.id
      assert payload["votingSessionId"] == voting_session.id
      assert payload["landingDegrees"] > 18.0
      assert payload["landingDegrees"] < 342.0

      voting_session = Voting.get_voting_session!(Process.get(:test_community), voting_session.id)
      assert voting_session.status == "completed"
    end

    test "spin_voting_session_wheel/1 snapshots payload, entries, and geometry" do
      voting_session = voting_session_fixture()
      first_game = game_fixture(%{title: "Snapshot Winner"})
      second_game = game_fixture(%{title: "Snapshot Other", external_id: "snapshot-other"})
      first_pool_item = voting_session_game_fixture(voting_session, first_game, %{base_weight: 2})

      second_pool_item =
        voting_session_game_fixture(voting_session, second_game, %{base_weight: 1})

      channel_point_vote_fixture(first_pool_item, nil, %{strength: 3})
      channel_point_vote_fixture(second_pool_item, nil, %{strength: 1})

      assert {:ok, %{spin: spin, spin_payload: payload}} =
               Voting.spin_voting_session_wheel(voting_session)

      assert spin.voting_session_id == voting_session.id
      assert spin.snapshot["source"] == "voting_session"
      assert spin.snapshot["voting_session_id"] == voting_session.id
      assert spin.snapshot["total_weight"] == 7
      assert spin.snapshot["winning_game_id"] == spin.game_id
      assert is_float(spin.snapshot["landing_degrees"])
      assert spin.snapshot["duration_ms"] == 30_000
      assert spin.snapshot["full_turns"] == 12
      assert is_integer(spin.snapshot["spin_seed"])
      assert is_binary(spin.snapshot["started_at"])
      assert spin.snapshot["easing_profile"]["type"] == "cubic-bezier"

      assert payload["spinId"] == spin.id
      assert payload["landingDegrees"] == spin.snapshot["landing_degrees"]
      assert payload["durationMs"] == 30_000
      assert payload["fullTurns"] == 12
      assert payload["segments"] == spin.snapshot["entries"]

      assert [first_entry, second_entry] = spin.snapshot["entries"]

      assert first_entry == %{
               "game_id" => first_game.id,
               "voting_session_game_id" => first_pool_item.id,
               "title" => "Snapshot Winner",
               "start_degrees" => 0.0,
               "end_degrees" => 257.14285714285717,
               "base_weight" => 2,
               "channel_point_vote_total" => 3,
               "final_weight" => 5
             }

      assert second_entry == %{
               "game_id" => second_game.id,
               "voting_session_game_id" => second_pool_item.id,
               "title" => "Snapshot Other",
               "start_degrees" => 257.14285714285717,
               "end_degrees" => 360.0,
               "base_weight" => 1,
               "channel_point_vote_total" => 1,
               "final_weight" => 2
             }

      winning_entry = Enum.find(spin.snapshot["entries"], &(&1["game_id"] == spin.game_id))

      segment_degrees = winning_entry["end_degrees"] - winning_entry["start_degrees"]
      inset_degrees = min(segment_degrees * 0.25, 18.0)

      assert spin.snapshot["landing_degrees"] > winning_entry["start_degrees"] + inset_degrees
      assert spin.snapshot["landing_degrees"] < winning_entry["end_degrees"] - inset_degrees
    end

    test "spin_voting_session_wheel/1 broadcasts the canonical spin payload" do
      voting_session = voting_session_fixture()
      game = game_fixture(%{title: "Broadcast Winner"})
      voting_session_game_fixture(voting_session, game)

      assert :ok = Voting.subscribe_to_voting_session(voting_session)
      assert {:ok, %{spin_payload: payload}} = Voting.spin_voting_session_wheel(voting_session)

      assert_receive {:voting_session_spin_started, ^payload}
      assert payload["gameId"] == game.id
      assert [%{"game_id" => game_id} = segment] = payload["segments"]

      assert game_id == game.id
      assert segment["start_degrees"] == 0.0
      assert segment["end_degrees"] == 360.0
    end
  end
end
