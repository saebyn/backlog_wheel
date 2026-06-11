defmodule BacklogWheel.BacklogTest do
  use BacklogWheel.DataCase

  alias BacklogWheel.Backlog

  describe "games" do
    alias BacklogWheel.Backlog.Game

    import BacklogWheel.BacklogFixtures
    import BacklogWheel.VotingFixtures

    @invalid_attrs %{title: nil}

    test "list_games/1 returns games for a community" do
      community = community_fixture()
      game = game_fixture(%{community: community})
      assert Backlog.list_games(community) == [game]
    end

    test "scoped games only return records for the given community" do
      first_community = community_fixture(%{slug: "first-backlog"})
      second_community = community_fixture(%{slug: "second-backlog"})
      first_game = game_fixture(%{community: first_community, title: "First Community Game"})
      second_game = game_fixture(%{community: second_community, title: "Second Community Game"})

      assert Backlog.list_games(first_community, %{}) == [first_game]
      assert Backlog.list_games(second_community, %{}) == [second_game]

      assert_raise Ecto.NoResultsError, fn ->
        Backlog.get_game!(first_community, second_game.id)
      end
    end

    test "scoped create_game/2 attaches the current community" do
      community = community_fixture(%{slug: "created-backlog"})

      assert {:ok, game} = Backlog.create_game(community, %{title: "Scoped Game"})
      assert game.community_id == community.id
    end

    test "get_game!/1 returns the game with given id" do
      game = game_fixture()
      assert Backlog.get_game!(game.id) == game
    end

    test "list_games/2 searches, filters, and sorts games" do
      community = community_fixture()

      game_fixture(%{
        community: community,
        title: "Apex Legends",
        platform: "steam",
        external_id: "1172470",
        include_in_wheel: true,
        played_on_stream: false,
        last_played_at: ~U[2024-06-01 00:00:00Z]
      })

      game_fixture(%{
        community: community,
        title: "Baldur's Gate 3",
        platform: "steam",
        external_id: "1086940",
        include_in_wheel: false,
        played_on_stream: true,
        last_played_at: ~U[2025-06-01 00:00:00Z]
      })

      assert [%Game{title: "Apex Legends"}] =
               Backlog.list_games(community, %{
                 "q" => "apex",
                 "filter" => "wheel",
                 "sort" => "title"
               })

      assert [%Game{title: "Baldur's Gate 3"}, %Game{title: "Apex Legends"}] =
               Backlog.list_games(community, %{"filter" => "steam", "sort" => "last_played"})
    end

    test "game_counts/1 returns curation summary counts" do
      community = community_fixture()

      game_fixture(%{
        community: community,
        external_id: "one",
        include_in_wheel: true,
        played_on_stream: false
      })

      game_fixture(%{
        community: community,
        external_id: "two",
        include_in_wheel: false,
        played_on_stream: true
      })

      assert Backlog.game_counts(community) == %{
               total: 2,
               wheel: 1,
               excluded: 1,
               played: 1,
               unplayed: 1
             }
    end

    test "update_visible_games_include_in_wheel/3 updates matching games" do
      community = community_fixture()

      steam_game =
        game_fixture(%{
          community: community,
          title: "Steam Game",
          platform: "steam",
          external_id: "1",
          include_in_wheel: false
        })

      manual_game =
        game_fixture(%{
          community: community,
          title: "Manual Game",
          platform: "manual",
          external_id: "2",
          include_in_wheel: false
        })

      assert {1, _} =
               Backlog.update_visible_games_include_in_wheel(
                 community,
                 %{"filter" => "steam"},
                 true
               )

      assert Backlog.get_game!(steam_game.id).include_in_wheel == true
      assert Backlog.get_game!(manual_game.id).include_in_wheel == false
    end

    test "scoped bulk wheel inclusion ignores other communities" do
      first_community = community_fixture(%{slug: "first-bulk"})
      second_community = community_fixture(%{slug: "second-bulk"})

      first_game =
        game_fixture(%{community: first_community, platform: "steam", external_id: "first-bulk"})

      second_game =
        game_fixture(%{
          community: second_community,
          platform: "steam",
          external_id: "second-bulk"
        })

      assert {1, _} =
               Backlog.update_visible_games_include_in_wheel(
                 first_community,
                 %{"filter" => "steam"},
                 false
               )

      assert Backlog.get_game!(first_community, first_game.id).include_in_wheel == false
      assert Backlog.get_game!(second_community, second_game.id).include_in_wheel == true
    end

    test "list_wheel_candidates/1 returns included games including played games" do
      community = community_fixture()

      played_game =
        game_fixture(%{
          community: community,
          title: "Played Candidate",
          external_id: "played-candidate",
          include_in_wheel: true,
          played_on_stream: true
        })

      unplayed_game =
        game_fixture(%{
          community: community,
          title: "Unplayed Candidate",
          external_id: "unplayed-candidate",
          include_in_wheel: true,
          played_on_stream: false
        })

      game_fixture(%{
        community: community,
        title: "Excluded Game",
        external_id: "excluded-game",
        include_in_wheel: false
      })

      assert Backlog.list_wheel_candidates(community) == [played_game, unplayed_game]
    end

    test "spin_wheel/1 records a spin for a candidate" do
      community = community_fixture()
      game = game_fixture(%{community: community, include_in_wheel: true, played_on_stream: true})

      assert {:ok, %{game: selected_game, spin: spin}} = Backlog.spin_wheel(community)
      assert selected_game.id == game.id
      assert spin.game_id == game.id
      assert spin.community_id == community.id
      assert spin.source == "wheel"
      assert spin.snapshot["source"] == "wheel"
      assert spin.snapshot["winning_game_id"] == game.id
      assert spin.snapshot["total_weight"] == 1
      assert [entry] = spin.snapshot["entries"]
      assert entry["game_id"] == game.id
      assert entry["title"] == game.title
      assert entry["base_weight"] == 1
      assert entry["channel_point_vote_total"] == 0
      assert entry["final_weight"] == 1
      assert %DateTime{} = spin.spun_at
      assert [recent_spin] = Backlog.list_recent_spins(community)
      assert recent_spin.game.id == game.id
    end

    test "latest_voting_session_spin/2 returns the newest session spin" do
      community = community_fixture()
      voting_session = voting_session_fixture(%{community: community})
      game = game_fixture(%{community: community, external_id: "latest-session-spin"})

      {:ok, older_spin} =
        Backlog.create_spin(community, %{
          game_id: game.id,
          voting_session_id: voting_session.id,
          spun_at: ~U[2026-06-06 12:00:00Z],
          source: "voting_session"
        })

      {:ok, newer_spin} =
        Backlog.create_spin(community, %{
          game_id: game.id,
          voting_session_id: voting_session.id,
          spun_at: ~U[2026-06-06 12:01:00Z],
          source: "voting_session"
        })

      assert Backlog.latest_voting_session_spin(community, voting_session.id).id == newer_spin.id
      refute Backlog.latest_voting_session_spin(community, voting_session.id).id == older_spin.id
    end

    test "delete_spin/1 deletes a spin history entry" do
      community = community_fixture()
      game = game_fixture(%{community: community, include_in_wheel: true})

      {:ok, spin} =
        Backlog.create_spin(community, %{game_id: game.id, spun_at: ~U[2026-06-06 12:00:00Z]})

      assert {:ok, _spin} = Backlog.delete_spin(spin)
      assert Backlog.list_recent_spins(community) == []
    end

    test "spin_wheel/1 returns an error when there are no candidates" do
      community = community_fixture()
      game_fixture(%{community: community, include_in_wheel: false})

      assert {:error, :no_candidates} = Backlog.spin_wheel(community)
    end

    test "create_game/2 with valid data creates a game" do
      community = community_fixture()

      valid_attrs = %{
        title: "some title",
        platform: "some platform",
        external_id: "some external_id",
        include_in_wheel: true,
        played_on_stream: true,
        last_played_at: ~U[2026-06-05 17:55:00Z]
      }

      assert {:ok, %Game{} = game} = Backlog.create_game(community, valid_attrs)
      assert game.title == "some title"
      assert game.platform == "some platform"
      assert game.external_id == "some external_id"
      assert game.community_id == community.id
      assert game.include_in_wheel == true
      assert game.played_on_stream == true
      assert game.last_played_at == ~U[2026-06-05 17:55:00Z]
    end

    test "create_spin/2 attaches the given community" do
      community = community_fixture()
      game = game_fixture(%{community: community, include_in_wheel: true})

      assert {:ok, spin} =
               Backlog.create_spin(community, %{
                 game_id: game.id,
                 spun_at: ~U[2026-06-06 12:00:00Z]
               })

      assert spin.community_id == community.id
    end

    test "scoped create_spin/2 rejects games from another community" do
      first_community = community_fixture(%{slug: "first-spin"})
      second_community = community_fixture(%{slug: "second-spin"})
      game = game_fixture(%{community: second_community})

      assert {:error, changeset} =
               Backlog.create_spin(first_community, %{
                 game_id: game.id,
                 spun_at: ~U[2026-06-06 12:00:00Z]
               })

      assert %{game_id: ["does not belong to this community"]} = errors_on(changeset)
    end

    test "create_game/2 defaults optional metadata" do
      community = community_fixture()

      assert {:ok, %Game{} = game} = Backlog.create_game(community, %{title: "Untitled Game"})

      assert game.platform == "manual"
      assert game.external_id == nil
      assert game.include_in_wheel == false
      assert game.played_on_stream == false
      assert game.last_played_at == nil
    end

    test "create_game/2 with invalid data returns error changeset" do
      community = community_fixture()

      assert {:error, %Ecto.Changeset{}} = Backlog.create_game(community, @invalid_attrs)
    end

    test "update_game/2 with valid data updates the game" do
      game = game_fixture()

      update_attrs = %{
        title: "some updated title",
        platform: "some updated platform",
        external_id: "some updated external_id",
        include_in_wheel: false,
        played_on_stream: false,
        last_played_at: ~U[2026-06-06 17:55:00Z]
      }

      assert {:ok, %Game{} = game} = Backlog.update_game(game, update_attrs)
      assert game.title == "some updated title"
      assert game.platform == "some updated platform"
      assert game.external_id == "some updated external_id"
      assert game.include_in_wheel == false
      assert game.played_on_stream == false
      assert game.last_played_at == ~U[2026-06-06 17:55:00Z]
    end

    test "update_game/2 with invalid data returns error changeset" do
      game = game_fixture()
      assert {:error, %Ecto.Changeset{}} = Backlog.update_game(game, @invalid_attrs)
      assert game == Backlog.get_game!(game.id)
    end

    test "toggle_game_include_in_wheel/1 toggles wheel inclusion" do
      game = game_fixture(%{include_in_wheel: false})

      assert {:ok, %Game{} = game} = Backlog.toggle_game_include_in_wheel(game)
      assert game.include_in_wheel == true

      assert {:ok, %Game{} = game} = Backlog.toggle_game_include_in_wheel(game)
      assert game.include_in_wheel == false
    end

    test "toggle_game_played_on_stream/1 toggles stream play status" do
      game = game_fixture(%{played_on_stream: false})

      assert {:ok, %Game{} = game} = Backlog.toggle_game_played_on_stream(game)
      assert game.played_on_stream == true

      assert {:ok, %Game{} = game} = Backlog.toggle_game_played_on_stream(game)
      assert game.played_on_stream == false
    end

    test "import_steam_games/2 imports new Steam games included on the wheel" do
      community = community_fixture()

      assert {:ok, %{imported: 2, updated: 0, skipped: 0, errors: []}} =
               Backlog.import_steam_games(community, [
                 %{
                   appid: 10,
                   name: "Counter-Strike",
                   image_url: "https://example.com/counter-strike.jpg",
                   last_played_at: ~U[2024-06-01 00:00:00Z]
                 },
                 %{appid: 70, name: "Half-Life"}
               ])

      assert %Game{} =
               counter_strike =
               Backlog.get_game_by_platform_external_id(community, "steam", "10")

      assert counter_strike.title == "Counter-Strike"
      assert counter_strike.image_url == "https://example.com/counter-strike.jpg"
      assert counter_strike.include_in_wheel == true
      assert counter_strike.last_played_at == ~U[2024-06-01 00:00:00Z]

      assert %Game{} =
               half_life =
               Backlog.get_game_by_platform_external_id(community, "steam", "70")

      assert half_life.title == "Half-Life"
      assert half_life.include_in_wheel == true
    end

    test "import_steam_games/2 skips existing Steam games and preserves local edits" do
      community = community_fixture()

      existing =
        game_fixture(%{
          community: community,
          title: "My Edited Title",
          platform: "steam",
          external_id: "10",
          include_in_wheel: false
        })

      assert {:ok, %{imported: 0, updated: 1, skipped: 0, errors: []}} =
               Backlog.import_steam_games(community, [
                 %{appid: 10, name: "Counter-Strike", last_played_at: ~U[2024-06-01 00:00:00Z]}
               ])

      assert Backlog.get_game!(existing.id).title == "My Edited Title"
      assert Backlog.get_game!(existing.id).include_in_wheel == false
      assert Backlog.get_game!(existing.id).last_played_at == ~U[2024-06-01 00:00:00Z]
    end

    test "import_steam_games/2 updates last played time for existing Steam games" do
      community = community_fixture()

      existing =
        game_fixture(%{
          community: community,
          title: "My Edited Title",
          platform: "steam",
          external_id: "10",
          last_played_at: ~U[2024-05-01 00:00:00Z]
        })

      assert {:ok, %{imported: 0, updated: 1, skipped: 0, errors: []}} =
               Backlog.import_steam_games(community, [
                 %{appid: 10, name: "Counter-Strike", last_played_at: ~U[2024-06-01 00:00:00Z]}
               ])

      assert %Game{} = game = Backlog.get_game!(existing.id)
      assert game.title == "My Edited Title"
      assert game.last_played_at == ~U[2024-06-01 00:00:00Z]
    end

    test "import_steam_games/2 updates image URL for existing Steam games" do
      community = community_fixture()

      existing =
        game_fixture(%{
          community: community,
          title: "My Edited Title",
          platform: "steam",
          external_id: "10",
          image_url: nil
        })

      assert {:ok, %{imported: 0, updated: 1, skipped: 0, errors: []}} =
               Backlog.import_steam_games(community, [
                 %{appid: 10, name: "Counter-Strike", image_url: "https://example.com/icon.jpg"}
               ])

      assert %Game{} = game = Backlog.get_game!(existing.id)
      assert game.title == "My Edited Title"
      assert game.image_url == "https://example.com/icon.jpg"
    end

    test "import_steam_games/2 skips existing Steam games when Steam has no last played time" do
      community = community_fixture()

      existing =
        game_fixture(%{
          community: community,
          platform: "steam",
          external_id: "10",
          last_played_at: ~U[2024-05-01 00:00:00Z]
        })

      assert {:ok, %{imported: 0, updated: 0, skipped: 1, errors: []}} =
               Backlog.import_steam_games(community, [
                 %{appid: 10, name: "Counter-Strike", last_played_at: nil}
               ])

      assert Backlog.get_game!(existing.id).last_played_at == ~U[2024-05-01 00:00:00Z]
    end

    test "import_steam_games/2 reports invalid entries" do
      community = community_fixture()

      assert {:ok, %{imported: 0, updated: 0, skipped: 0, errors: [_error]}} =
               Backlog.import_steam_games(community, [%{appid: 10}])
    end

    test "delete_game/1 deletes the game" do
      game = game_fixture()
      assert {:ok, %Game{}} = Backlog.delete_game(game)
      assert_raise Ecto.NoResultsError, fn -> Backlog.get_game!(game.id) end
    end

    test "change_game/1 returns a game changeset" do
      game = game_fixture()
      assert %Ecto.Changeset{} = Backlog.change_game(game)
    end
  end
end
