defmodule BacklogWheelWeb.GameLiveTest do
  use BacklogWheelWeb.ConnCase

  import Phoenix.LiveViewTest
  import BacklogWheel.BacklogFixtures

  alias BacklogWheel.Backlog.Game
  alias BacklogWheel.Repo

  @create_attrs %{
    title: "some title",
    platform: "some platform",
    external_id: "some other external_id",
    image_url: "https://example.com/create-image.jpg",
    include_in_wheel: true,
    played_on_stream: true,
    last_played_at: "2026-06-05T17:55:00Z"
  }
  @update_attrs %{
    title: "some updated title",
    platform: "some updated platform",
    external_id: "some updated external_id",
    image_url: "https://example.com/update-image.jpg",
    include_in_wheel: false,
    played_on_stream: false,
    last_played_at: "2026-06-06T17:55:00Z"
  }
  @invalid_attrs %{
    title: nil,
    platform: nil,
    external_id: nil,
    image_url: nil,
    include_in_wheel: false,
    played_on_stream: false,
    last_played_at: nil
  }
  defp create_game(_) do
    game = game_fixture()

    %{game: game}
  end

  describe "Index" do
    setup [:create_game]

    test "lists all games", %{conn: conn, game: game} do
      {:ok, _index_live, html} = live(conn, ~p"/games")

      assert html =~ "Listing Games"
      assert html =~ game.title
      assert html =~ game.image_url
      assert html =~ "Import Steam"
    end

    test "saves new game", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/games")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Game")
               |> render_click()
               |> follow_redirect(conn, ~p"/games/new")

      assert render(form_live) =~ "New Game"

      assert form_live
             |> form("#game-form", game: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#game-form", game: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/games")

      html = render(index_live)
      assert html =~ "Game created successfully"
      assert html =~ "some title"
      assert html =~ "https://example.com/create-image.jpg"
    end

    test "created games are assigned to the logged-in community", %{conn: conn} do
      community = community_fixture(%{slug: "live-created-games"})
      conn = conn |> recycle() |> log_in_test_user(%{community: community})

      {:ok, form_live, _html} = live(conn, ~p"/games/new")

      assert {:ok, _index_live, _html} =
               form_live
               |> form("#game-form", game: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/games")

      assert %Game{community_id: community_id} =
               Repo.get_by(Game, title: "some title", community_id: community.id)

      assert community_id == community.id
    end

    test "lists only games for the logged-in community", %{conn: conn} do
      first_community = community_fixture(%{slug: "first-live-list"})
      second_community = community_fixture(%{slug: "second-live-list"})
      first_game = game_fixture(%{community: first_community, title: "First Live Game"})
      second_game = game_fixture(%{community: second_community, title: "Second Live Game"})
      conn = conn |> recycle() |> log_in_test_user(%{community: first_community})

      {:ok, index_live, _html} = live(conn, ~p"/games")

      assert has_element?(index_live, "#games-#{first_game.id}")
      refute has_element?(index_live, "#games-#{second_game.id}")
    end

    test "isolates games between two logged-in users and communities", %{conn: conn} do
      first_community = community_fixture(%{slug: "first-user-community"})
      second_community = community_fixture(%{slug: "second-user-community"})
      first_game = game_fixture(%{community: first_community, title: "First User Game"})
      second_game = game_fixture(%{community: second_community, title: "Second User Game"})

      first_conn = conn |> recycle() |> log_in_test_user(%{community: first_community})
      second_conn = build_conn() |> log_in_test_user(%{community: second_community})

      {:ok, first_view, _html} = live(first_conn, ~p"/games")
      assert has_element?(first_view, "#games-#{first_game.id}")
      refute has_element?(first_view, "#games-#{second_game.id}")

      {:ok, second_view, _html} = live(second_conn, ~p"/games")
      assert has_element?(second_view, "#games-#{second_game.id}")
      refute has_element?(second_view, "#games-#{first_game.id}")
    end

    test "rejects direct access to another community game", %{conn: conn} do
      first_community = community_fixture(%{slug: "first-live-direct"})
      second_community = community_fixture(%{slug: "second-live-direct"})
      game = game_fixture(%{community: second_community})
      conn = conn |> recycle() |> log_in_test_user(%{community: first_community})

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/games/#{game}")
      end
    end

    test "updates game in listing", %{conn: conn, game: game} do
      {:ok, index_live, _html} = live(conn, ~p"/games")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#games-#{game.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/games/#{game}/edit")

      assert render(form_live) =~ "Edit Game"

      assert form_live
             |> form("#game-form", game: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#game-form", game: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/games")

      html = render(index_live)
      assert html =~ "Game updated successfully"
      assert html =~ "some updated title"
      assert html =~ "https://example.com/update-image.jpg"
    end

    test "deletes game in listing", %{conn: conn, game: game} do
      {:ok, index_live, _html} = live(conn, ~p"/games")

      assert index_live |> element("#games-#{game.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#games-#{game.id}")
    end

    test "toggles wheel inclusion in listing", %{conn: conn, game: game} do
      {:ok, index_live, _html} = live(conn, ~p"/games")

      assert has_element?(index_live, "#games-#{game.id} button", "Included")
      assert index_live |> element("#games-#{game.id} button", "Included") |> render_click()
      assert has_element?(index_live, "#games-#{game.id} button", "Excluded")
    end

    test "toggles played on stream in listing", %{conn: conn, game: game} do
      {:ok, index_live, _html} = live(conn, ~p"/games")

      assert has_element?(index_live, "#games-#{game.id} button", "Played")
      assert index_live |> element("#games-#{game.id} button", "Played") |> render_click()
      assert has_element?(index_live, "#games-#{game.id} button", "Unplayed")
    end

    test "searches and filters games", %{conn: conn, game: game} do
      excluded_game =
        game_fixture(%{
          title: "Portal 2",
          external_id: "portal-2",
          include_in_wheel: false
        })

      {:ok, index_live, _html} = live(conn, ~p"/games")

      assert index_live
             |> form("#game-curation-form", filters: %{q: "Portal", sort: "title"})
             |> render_change()

      assert has_element?(index_live, "#games-#{excluded_game.id}")
      refute has_element?(index_live, "#games-#{game.id}")

      assert index_live |> element("#game-filter-pills button", "Excluded") |> render_click()
      assert has_element?(index_live, "#games-#{excluded_game.id}")
    end

    test "bulk updates visible wheel inclusion", %{conn: conn, game: game} do
      {:ok, index_live, _html} = live(conn, ~p"/games")

      assert index_live |> element("#exclude-visible-games") |> render_click()
      assert has_element?(index_live, "#games-#{game.id} button", "Excluded")

      assert index_live |> element("#include-visible-games") |> render_click()
      assert has_element?(index_live, "#games-#{game.id} button", "Included")
    end
  end

  describe "Show" do
    setup [:create_game]

    test "displays game", %{conn: conn, game: game} do
      {:ok, _show_live, html} = live(conn, ~p"/games/#{game}")

      assert html =~ "Show Game"
      assert html =~ game.title
    end

    test "updates game and returns to show", %{conn: conn, game: game} do
      {:ok, show_live, _html} = live(conn, ~p"/games/#{game}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/games/#{game}/edit?return_to=show")

      assert render(form_live) =~ "Edit Game"
      assert render(form_live) =~ "Image preview"

      assert form_live
             |> form("#game-form", game: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#game-form", game: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/games/#{game}")

      html = render(show_live)
      assert html =~ "Game updated successfully"
      assert html =~ "some updated title"
      assert html =~ "https://example.com/update-image.jpg"
    end
  end

  describe "Steam import" do
    setup do
      previous_api_key = Application.get_env(:backlog_wheel, :steam_api_key)
      previous_steam_id = Application.get_env(:backlog_wheel, :steam_id64)

      Application.put_env(:backlog_wheel, :steam_api_key, "test-key")
      Application.put_env(:backlog_wheel, :steam_id64, "76561198000000000")

      on_exit(fn ->
        restore_env(:steam_api_key, previous_api_key)
        restore_env(:steam_id64, previous_steam_id)
      end)

      :ok
    end

    test "renders Steam import page", %{conn: conn} do
      {:ok, _import_live, html} = live(conn, ~p"/games/import/steam")

      assert html =~ "Import Steam Library"
      assert html =~ "Steam configured"
      assert html =~ "Imported games are included on the wheel by default"
      assert html =~ "Re-imports refresh last played times"
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:backlog_wheel, key)
  defp restore_env(key, value), do: Application.put_env(:backlog_wheel, key, value)
end
