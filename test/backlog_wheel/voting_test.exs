defmodule BacklogWheel.VotingTest do
  use BacklogWheel.DataCase

  alias BacklogWheel.Communities
  alias BacklogWheel.Backlog
  alias BacklogWheel.Voting

  alias BacklogWheel.Voting.{
    Viewer,
    ViewerIdentity,
    VotingBoost,
    VotingSession,
    VotingSessionGame
  }

  import BacklogWheel.BacklogFixtures
  import BacklogWheel.VotingFixtures

  describe "voting_sessions" do
    test "create_voting_session/1 creates a session for the default community" do
      default_community = Communities.get_default_community!()

      assert {:ok, %VotingSession{} = voting_session} = Voting.create_voting_session()
      assert voting_session.community_id == default_community.id
      assert voting_session.status == "draft"
    end

    test "create_voting_session/1 represents session status" do
      assert {:ok, %VotingSession{} = voting_session} =
               Voting.create_voting_session(%{status: "open"})

      assert voting_session.status == "open"

      assert {:error, changeset} = Voting.create_voting_session(%{status: "invalid"})
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "voting_session_games" do
    test "add_game_to_session/3 adds a game to the session pool with a base weight" do
      voting_session = voting_session_fixture()
      game = game_fixture(%{title: "Vote Candidate"})

      assert {:ok, %VotingSessionGame{} = voting_session_game} =
               Voting.add_game_to_session(voting_session, game, %{base_weight: 3})

      assert voting_session_game.voting_session_id == voting_session.id
      assert voting_session_game.game_id == game.id
      assert voting_session_game.base_weight == 3
    end

    test "add_game_to_session/3 defaults base weight" do
      voting_session = voting_session_fixture()
      game = game_fixture(%{title: "Default Weight Candidate"})

      assert {:ok, %VotingSessionGame{} = voting_session_game} =
               Voting.add_game_to_session(voting_session, game)

      assert voting_session_game.base_weight == 1
    end

    test "get_voting_session!/1 preloads pool games" do
      voting_session = voting_session_fixture()
      game = game_fixture(%{title: "Preloaded Candidate"})
      voting_session_game_fixture(voting_session, game, %{base_weight: 2})

      voting_session = Voting.get_voting_session!(voting_session.id)

      assert [voting_session_game] = voting_session.voting_session_games
      assert voting_session_game.base_weight == 2
      assert voting_session_game.game.title == "Preloaded Candidate"
    end

    test "add_game_to_session/3 requires positive base weight" do
      voting_session = voting_session_fixture()
      game = game_fixture(%{title: "Invalid Weight Candidate"})

      assert {:error, changeset} =
               Voting.add_game_to_session(voting_session, game, %{base_weight: 0})

      assert %{base_weight: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "add_game_to_session/3 prevents duplicate games in one session" do
      voting_session = voting_session_fixture()
      game = game_fixture(%{title: "Duplicate Candidate"})
      voting_session_game_fixture(voting_session, game)

      assert {:error, changeset} = Voting.add_game_to_session(voting_session, game)
      assert %{voting_session_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "populate_session_from_wheel_candidates/1 adds wheel-eligible games" do
      voting_session = voting_session_fixture()

      first_game =
        game_fixture(%{title: "First Candidate", include_in_wheel: true, external_id: "first"})

      second_game =
        game_fixture(%{title: "Second Candidate", include_in_wheel: true, external_id: "second"})

      excluded_game =
        game_fixture(%{
          title: "Excluded Candidate",
          include_in_wheel: false,
          external_id: "excluded"
        })

      assert {:ok, voting_session_games} =
               Voting.populate_session_from_wheel_candidates(voting_session)

      assert Enum.map(voting_session_games, & &1.game_id) == [first_game.id, second_game.id]
      assert Enum.map(voting_session_games, & &1.base_weight) == [1, 1]

      voting_session = Voting.get_voting_session!(voting_session.id)

      assert Enum.map(voting_session.voting_session_games, & &1.game_id) == [
               first_game.id,
               second_game.id
             ]

      refute Enum.any?(voting_session.voting_session_games, &(&1.game_id == excluded_game.id))
    end

    test "populate_session_from_wheel_candidates/1 avoids duplicate pool games" do
      voting_session = voting_session_fixture()

      existing_game =
        game_fixture(%{
          title: "Existing Candidate",
          include_in_wheel: true,
          external_id: "existing"
        })

      new_game =
        game_fixture(%{title: "New Candidate", include_in_wheel: true, external_id: "new"})

      voting_session_game_fixture(voting_session, existing_game, %{base_weight: 4})

      assert {:ok, voting_session_games} =
               Voting.populate_session_from_wheel_candidates(voting_session)

      assert Enum.map(voting_session_games, & &1.game_id) == [new_game.id]

      voting_session = Voting.get_voting_session!(voting_session.id)

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

  describe "viewers" do
    test "create_viewer/1 creates a viewer for the default community" do
      default_community = Communities.get_default_community!()

      assert {:ok, %Viewer{} = viewer} = Voting.create_viewer(%{display_name: "Viewer One"})
      assert viewer.community_id == default_community.id
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

  describe "voting_boosts" do
    test "record_boost/3 records a positive boost against a session game" do
      voting_session_game = voting_session_game_fixture(voting_session_fixture(), game_fixture())
      viewer = viewer_fixture(%{display_name: "Boost Viewer"})

      assert {:ok, %VotingBoost{} = voting_boost} =
               Voting.record_boost(voting_session_game, viewer, %{
                 strength: 5,
                 source: "twitch",
                 external_event_id: "event-1"
               })

      assert voting_boost.voting_session_game_id == voting_session_game.id
      assert voting_boost.viewer_id == viewer.id
      assert voting_boost.strength == 5
      assert voting_boost.source == "twitch"
      assert voting_boost.external_event_id == "event-1"
    end

    test "record_boost/2 can record a local admin boost without a viewer" do
      voting_session_game = voting_session_game_fixture(voting_session_fixture(), game_fixture())

      assert {:ok, %VotingBoost{} = voting_boost} =
               Voting.record_boost(voting_session_game, %{strength: 2, source: "local"})

      assert voting_boost.viewer_id == nil
      assert voting_boost.strength == 2
      assert voting_boost.source == "local"
    end

    test "record_boost/3 rejects non-positive strengths" do
      voting_session_game = voting_session_game_fixture(voting_session_fixture(), game_fixture())
      viewer = viewer_fixture(%{display_name: "Negative Viewer"})

      assert {:error, changeset} =
               Voting.record_boost(voting_session_game, viewer, %{strength: -1, source: "twitch"})

      assert %{strength: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "record_boost/3 is idempotent for duplicate external events" do
      voting_session_game = voting_session_game_fixture(voting_session_fixture(), game_fixture())
      viewer = viewer_fixture(%{display_name: "Idempotent Viewer"})

      assert {:ok, first_boost} =
               Voting.record_boost(voting_session_game, viewer, %{
                 strength: 3,
                 source: "twitch",
                 external_event_id: "event-2"
               })

      assert {:ok, second_boost} =
               Voting.record_boost(voting_session_game, viewer, %{
                 strength: 99,
                 source: "twitch",
                 external_event_id: "event-2"
               })

      assert first_boost.id == second_boost.id
      assert first_boost.strength == second_boost.strength
      assert Repo.aggregate(VotingBoost, :count, :id) == 1
    end

    test "record_boost/3 allows repeated boosts without an external event id" do
      voting_session_game = voting_session_game_fixture(voting_session_fixture(), game_fixture())
      viewer = viewer_fixture(%{display_name: "Repeat Viewer"})

      assert {:ok, first_boost} =
               Voting.record_boost(voting_session_game, viewer, %{strength: 1, source: "local"})

      assert {:ok, second_boost} =
               Voting.record_boost(voting_session_game, viewer, %{strength: 1, source: "local"})

      assert first_boost.id != second_boost.id
      assert Repo.aggregate(VotingBoost, :count, :id) == 2
    end

    test "record_boost/2 broadcasts voting session changes" do
      voting_session = voting_session_fixture()
      voting_session_game = voting_session_game_fixture(voting_session, game_fixture())

      assert :ok = Voting.subscribe_to_voting_session(voting_session)

      assert {:ok, _boost} =
               Voting.record_boost(voting_session_game, %{strength: 1, source: "local"})

      assert_receive {:voting_session_changed, id}
      assert id == voting_session.id
    end

    test "voting_session_game_weight/1 calculates final weight from boosts" do
      voting_session_game =
        voting_session_game_fixture(voting_session_fixture(), game_fixture(), %{base_weight: 2})

      voting_boost_fixture(voting_session_game, nil, %{strength: 3})
      voting_boost_fixture(voting_session_game, nil, %{strength: 4})

      assert Voting.voting_session_game_weight(voting_session_game) == %{
               base_weight: 2,
               boost_total: 7,
               final_weight: 9
             }
    end

    test "list_voting_session_wheel_entries/1 returns final weights for the wheel" do
      voting_session = voting_session_fixture()
      base_game = game_fixture(%{title: "Base Weight Game"})
      boosted_game = game_fixture(%{title: "Boosted Weight Game", external_id: "boosted"})
      base_pool_item = voting_session_game_fixture(voting_session, base_game, %{base_weight: 2})

      boosted_pool_item =
        voting_session_game_fixture(voting_session, boosted_game, %{base_weight: 1})

      voting_boost_fixture(boosted_pool_item, nil, %{strength: 4})

      entries = Voting.list_voting_session_wheel_entries(voting_session)

      assert Enum.map(entries, & &1.title) == ["Base Weight Game", "Boosted Weight Game"]

      assert Enum.map(entries, &{&1.pool_item.id, &1.weight, &1.base_weight, &1.boost_total}) == [
               {base_pool_item.id, 2, 2, 0},
               {boosted_pool_item.id, 5, 1, 4}
             ]
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
    end

    test "spin_voting_session_wheel/1 snapshots payload, entries, and geometry" do
      voting_session = voting_session_fixture()
      first_game = game_fixture(%{title: "Snapshot Winner"})
      second_game = game_fixture(%{title: "Snapshot Other", external_id: "snapshot-other"})
      first_pool_item = voting_session_game_fixture(voting_session, first_game, %{base_weight: 2})

      second_pool_item =
        voting_session_game_fixture(voting_session, second_game, %{base_weight: 1})

      voting_boost_fixture(first_pool_item, nil, %{strength: 3})
      voting_boost_fixture(second_pool_item, nil, %{strength: 1})

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
               "boost_total" => 3,
               "final_weight" => 5
             }

      assert second_entry == %{
               "game_id" => second_game.id,
               "voting_session_game_id" => second_pool_item.id,
               "title" => "Snapshot Other",
               "start_degrees" => 257.14285714285717,
               "end_degrees" => 360.0,
               "base_weight" => 1,
               "boost_total" => 1,
               "final_weight" => 2
             }
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
