defmodule BacklogWheel.Backlog do
  @moduledoc """
  The Backlog context.
  """

  import Ecto.Query, warn: false
  alias BacklogWheel.Repo

  alias BacklogWheel.Backlog.{Game, Spin}

  @doc """
  Returns the list of games.

  ## Examples

      iex> list_games()
      [%Game{}, ...]

  """
  def list_games(filters \\ %{}) do
    filters
    |> game_query()
    |> order_games(filters)
    |> Repo.all()
  end

  @doc """
  Returns summary counts for backlog curation.
  """
  def game_counts do
    %{
      total: Repo.aggregate(Game, :count, :id),
      wheel: Game |> where([game], game.include_in_wheel) |> Repo.aggregate(:count, :id),
      excluded: Game |> where([game], not game.include_in_wheel) |> Repo.aggregate(:count, :id),
      played: Game |> where([game], game.played_on_stream) |> Repo.aggregate(:count, :id),
      unplayed: Game |> where([game], not game.played_on_stream) |> Repo.aggregate(:count, :id)
    }
  end

  @doc """
  Updates wheel inclusion for games matching the given filters.
  """
  def update_visible_games_include_in_wheel(filters, include_in_wheel)
      when is_boolean(include_in_wheel) do
    filters
    |> game_query()
    |> Repo.update_all(set: [include_in_wheel: include_in_wheel])
  end

  @doc """
  Returns games currently eligible for the wheel.

  Played-on-stream games remain eligible when included on the wheel.
  """
  def list_wheel_candidates do
    Game
    |> where([game], game.include_in_wheel)
    |> order_by([game], asc: game.title)
    |> Repo.all()
  end

  @doc """
  Returns recent recorded spins.
  """
  def list_recent_spins(limit \\ 10) do
    Spin
    |> preload(:game)
    |> order_by([spin], desc: spin.spun_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Records a spin for a game.
  """
  def create_spin(attrs) do
    %Spin{}
    |> Spin.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Selects one wheel candidate uniformly at random and records the spin.
  """
  def spin_wheel do
    case list_wheel_candidates() do
      [] ->
        {:error, :no_candidates}

      candidates ->
        game = Enum.random(candidates)

        case create_spin(%{game_id: game.id, spun_at: DateTime.utc_now(), source: "wheel"}) do
          {:ok, spin} -> {:ok, %{game: game, spin: Repo.preload(spin, :game)}}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @doc """
  Returns the list of games from a specific platform.
  """
  def list_games_by_platform(platform) do
    Game
    |> where([game], game.platform == ^platform)
    |> Repo.all()
  end

  @doc """
  Gets a single game.

  Raises `Ecto.NoResultsError` if the Game does not exist.

  ## Examples

      iex> get_game!(123)
      %Game{}

      iex> get_game!(456)
      ** (Ecto.NoResultsError)

  """
  def get_game!(id), do: Repo.get!(Game, id)

  @doc """
  Gets a game by platform and external id.
  """
  def get_game_by_platform_external_id(platform, external_id)
      when is_binary(platform) and is_binary(external_id) do
    Repo.get_by(Game, platform: platform, external_id: external_id)
  end

  @doc """
  Creates a game.

  ## Examples

      iex> create_game(%{field: value})
      {:ok, %Game{}}

      iex> create_game(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_game(attrs) do
    %Game{}
    |> Game.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Imports normalized Steam games.

  Existing Steam games are preserved so local edits are not overwritten.
  New Steam imports are included on the wheel by default.
  """
  def import_steam_games(games) when is_list(games) do
    Enum.reduce(games, %{imported: 0, updated: 0, skipped: 0, errors: []}, fn game_attrs,
                                                                              summary ->
      case import_steam_game(game_attrs) do
        {:ok, :imported} -> update_in(summary.imported, &(&1 + 1))
        {:ok, :updated} -> update_in(summary.updated, &(&1 + 1))
        {:ok, :skipped} -> update_in(summary.skipped, &(&1 + 1))
        {:error, error} -> update_in(summary.errors, &[error | &1])
      end
    end)
    |> Map.update!(:errors, &Enum.reverse/1)
    |> then(&{:ok, &1})
  end

  defp import_steam_game(%{appid: appid, name: name} = game_attrs)
       when not is_nil(appid) and is_binary(name) do
    external_id = to_string(appid)

    case get_game_by_platform_external_id("steam", external_id) do
      %Game{} = game ->
        case Map.get(game_attrs, :last_played_at) do
          nil ->
            {:ok, :skipped}

          last_played_at ->
            case update_game(game, %{last_played_at: last_played_at}) do
              {:ok, _game} -> {:ok, :updated}
              {:error, changeset} -> {:error, %{appid: external_id, errors: changeset.errors}}
            end
        end

      nil ->
        case create_game(%{
               title: name,
               platform: "steam",
               external_id: external_id,
               include_in_wheel: true,
               last_played_at: Map.get(game_attrs, :last_played_at)
             }) do
          {:ok, _game} -> {:ok, :imported}
          {:error, changeset} -> {:error, %{appid: external_id, errors: changeset.errors}}
        end
    end
  end

  defp import_steam_game(game_attrs),
    do: {:error, %{game: game_attrs, errors: :invalid_steam_game}}

  @doc """
  Updates a game.

  ## Examples

      iex> update_game(game, %{field: new_value})
      {:ok, %Game{}}

      iex> update_game(game, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_game(%Game{} = game, attrs) do
    game
    |> Game.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Toggles whether a game is included on the wheel.
  """
  def toggle_game_include_in_wheel(%Game{} = game) do
    update_game(game, %{include_in_wheel: not game.include_in_wheel})
  end

  @doc """
  Toggles whether a game has been played on stream.
  """
  def toggle_game_played_on_stream(%Game{} = game) do
    update_game(game, %{played_on_stream: not game.played_on_stream})
  end

  @doc """
  Deletes a game.

  ## Examples

      iex> delete_game(game)
      {:ok, %Game{}}

      iex> delete_game(game)
      {:error, %Ecto.Changeset{}}

  """
  def delete_game(%Game{} = game) do
    Repo.delete(game)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking game changes.

  ## Examples

      iex> change_game(game)
      %Ecto.Changeset{data: %Game{}}

  """
  def change_game(%Game{} = game, attrs \\ %{}) do
    Game.changeset(game, attrs)
  end

  defp game_query(filters) do
    Game
    |> filter_by_search(Map.get(filters, "q", ""))
    |> filter_by_kind(Map.get(filters, "filter", "all"))
  end

  defp filter_by_search(query, query_text) when is_binary(query_text) do
    query_text = String.trim(query_text)

    if query_text == "" do
      query
    else
      pattern = "%#{String.downcase(query_text)}%"
      where(query, [game], fragment("lower(?) LIKE ?", game.title, ^pattern))
    end
  end

  defp filter_by_search(query, _query_text), do: query

  defp filter_by_kind(query, "wheel"), do: where(query, [game], game.include_in_wheel)
  defp filter_by_kind(query, "excluded"), do: where(query, [game], not game.include_in_wheel)
  defp filter_by_kind(query, "played"), do: where(query, [game], game.played_on_stream)
  defp filter_by_kind(query, "unplayed"), do: where(query, [game], not game.played_on_stream)
  defp filter_by_kind(query, "steam"), do: where(query, [game], game.platform == "steam")
  defp filter_by_kind(query, "manual"), do: where(query, [game], game.platform == "manual")
  defp filter_by_kind(query, _filter), do: query

  defp order_games(query, %{"sort" => "last_played"}) do
    order_by(query, [game], desc: game.last_played_at, asc: game.title)
  end

  defp order_games(query, %{"sort" => "recently_added"}) do
    order_by(query, [game], desc: game.inserted_at, asc: game.title)
  end

  defp order_games(query, %{"sort" => "platform"}) do
    order_by(query, [game], asc: game.platform, asc: game.title)
  end

  defp order_games(query, %{"sort" => "wheel"}) do
    order_by(query, [game], desc: game.include_in_wheel, asc: game.title)
  end

  defp order_games(query, _filters) do
    order_by(query, [game], asc: game.title)
  end
end
