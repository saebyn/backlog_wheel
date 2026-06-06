defmodule BacklogWheel.Backlog do
  @moduledoc """
  The Backlog context.
  """

  import Ecto.Query, warn: false
  alias BacklogWheel.Repo

  alias BacklogWheel.Backlog.Game

  @doc """
  Returns the list of games.

  ## Examples

      iex> list_games()
      [%Game{}, ...]

  """
  def list_games do
    Repo.all(Game)
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
end
