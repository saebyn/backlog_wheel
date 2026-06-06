defmodule BacklogWheel.BacklogTest do
  use BacklogWheel.DataCase

  alias BacklogWheel.Backlog

  describe "games" do
    alias BacklogWheel.Backlog.Game

    import BacklogWheel.BacklogFixtures

    @invalid_attrs %{title: nil}

    test "list_games/0 returns all games" do
      game = game_fixture()
      assert Backlog.list_games() == [game]
    end

    test "get_game!/1 returns the game with given id" do
      game = game_fixture()
      assert Backlog.get_game!(game.id) == game
    end

    test "create_game/1 with valid data creates a game" do
      valid_attrs = %{
        title: "some title",
        platform: "some platform",
        external_id: "some external_id",
        include_in_wheel: true,
        played_on_stream: true,
        last_played_at: ~U[2026-06-05 17:55:00Z]
      }

      assert {:ok, %Game{} = game} = Backlog.create_game(valid_attrs)
      assert game.title == "some title"
      assert game.platform == "some platform"
      assert game.external_id == "some external_id"
      assert game.include_in_wheel == true
      assert game.played_on_stream == true
      assert game.last_played_at == ~U[2026-06-05 17:55:00Z]
    end

    test "create_game/1 defaults optional metadata" do
      assert {:ok, %Game{} = game} = Backlog.create_game(%{title: "Untitled Game"})

      assert game.platform == "manual"
      assert game.external_id == nil
      assert game.include_in_wheel == false
      assert game.played_on_stream == false
      assert game.last_played_at == nil
    end

    test "create_game/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Backlog.create_game(@invalid_attrs)
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

    test "import_steam_games/1 imports new Steam games included on the wheel" do
      assert {:ok, %{imported: 2, updated: 0, skipped: 0, errors: []}} =
               Backlog.import_steam_games([
                 %{appid: 10, name: "Counter-Strike", last_played_at: ~U[2024-06-01 00:00:00Z]},
                 %{appid: 70, name: "Half-Life"}
               ])

      assert %Game{} = counter_strike = Backlog.get_game_by_platform_external_id("steam", "10")
      assert counter_strike.title == "Counter-Strike"
      assert counter_strike.include_in_wheel == true
      assert counter_strike.last_played_at == ~U[2024-06-01 00:00:00Z]

      assert %Game{} = half_life = Backlog.get_game_by_platform_external_id("steam", "70")
      assert half_life.title == "Half-Life"
      assert half_life.include_in_wheel == true
    end

    test "import_steam_games/1 skips existing Steam games and preserves local edits" do
      existing =
        game_fixture(%{
          title: "My Edited Title",
          platform: "steam",
          external_id: "10",
          include_in_wheel: false
        })

      assert {:ok, %{imported: 0, updated: 1, skipped: 0, errors: []}} =
               Backlog.import_steam_games([
                 %{appid: 10, name: "Counter-Strike", last_played_at: ~U[2024-06-01 00:00:00Z]}
               ])

      assert Backlog.get_game!(existing.id).title == "My Edited Title"
      assert Backlog.get_game!(existing.id).include_in_wheel == false
      assert Backlog.get_game!(existing.id).last_played_at == ~U[2024-06-01 00:00:00Z]
    end

    test "import_steam_games/1 updates last played time for existing Steam games" do
      existing =
        game_fixture(%{
          title: "My Edited Title",
          platform: "steam",
          external_id: "10",
          last_played_at: ~U[2024-05-01 00:00:00Z]
        })

      assert {:ok, %{imported: 0, updated: 1, skipped: 0, errors: []}} =
               Backlog.import_steam_games([
                 %{appid: 10, name: "Counter-Strike", last_played_at: ~U[2024-06-01 00:00:00Z]}
               ])

      assert %Game{} = game = Backlog.get_game!(existing.id)
      assert game.title == "My Edited Title"
      assert game.last_played_at == ~U[2024-06-01 00:00:00Z]
    end

    test "import_steam_games/1 skips existing Steam games when Steam has no last played time" do
      existing =
        game_fixture(%{
          platform: "steam",
          external_id: "10",
          last_played_at: ~U[2024-05-01 00:00:00Z]
        })

      assert {:ok, %{imported: 0, updated: 0, skipped: 1, errors: []}} =
               Backlog.import_steam_games([
                 %{appid: 10, name: "Counter-Strike", last_played_at: nil}
               ])

      assert Backlog.get_game!(existing.id).last_played_at == ~U[2024-05-01 00:00:00Z]
    end

    test "import_steam_games/1 reports invalid entries" do
      assert {:ok, %{imported: 0, updated: 0, skipped: 0, errors: [_error]}} =
               Backlog.import_steam_games([%{appid: 10}])
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
