defmodule BacklogWheel.VotingTest do
  use BacklogWheel.DataCase

  alias BacklogWheel.Communities
  alias BacklogWheel.Voting
  alias BacklogWheel.Voting.{VotingSession, VotingSessionGame}

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
  end
end
