defmodule BacklogWheel.Backlog do
  @moduledoc """
  The Backlog context.
  """

  import Ecto.Query, warn: false
  alias BacklogWheel.Repo

  alias BacklogWheel.Backlog.{Game, GameTag, Spin}
  alias BacklogWheel.Communities.Community

  @doc """
  Returns the list of games.

  ## Examples

      iex> list_games()
      [%Game{}, ...]

  """
  def list_games(%Community{} = community, filters \\ %{}) do
    filters
    |> game_query(community)
    |> order_games(filters)
    |> preload([:tags])
    |> Repo.all()
  end

  @doc """
  Returns all game tags for a community.
  """
  def list_game_tags(%Community{} = community) do
    GameTag
    |> where([tag], tag.community_id == ^community.id)
    |> order_by([tag], asc: tag.name)
    |> Repo.all()
  end

  @doc """
  Creates a community-scoped game tag.
  """
  def create_game_tag(%Community{} = community, attrs) do
    name = attrs |> Map.get(:name, Map.get(attrs, "name")) |> normalize_tag_name()

    %GameTag{community_id: community.id}
    |> GameTag.changeset(%{name: name, slug: tag_slug(name)})
    |> Repo.insert()
  end

  @doc """
  Adds an existing community tag to a community game.
  """
  def add_tag_to_game(%Community{} = community, %Game{} = game, %GameTag{} = tag) do
    with :ok <- validate_game_community(game, community),
         :ok <- validate_tag_community(tag, community) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert_all(
        "game_taggings",
        [
          %{
            game_id: game.id,
            game_tag_id: tag.id,
            inserted_at: now,
            updated_at: now
          }
        ],
        on_conflict: :nothing,
        conflict_target: [:game_id, :game_tag_id]
      )

      {:ok, get_game!(community, game.id)}
    end
  end

  @doc """
  Removes a tag from a community game.
  """
  def remove_tag_from_game(%Community{} = community, %Game{} = game, %GameTag{} = tag) do
    with :ok <- validate_game_community(game, community),
         :ok <- validate_tag_community(tag, community) do
      from(tagging in "game_taggings",
        where: tagging.game_id == ^game.id and tagging.game_tag_id == ^tag.id
      )
      |> Repo.delete_all()

      {:ok, get_game!(community, game.id)}
    end
  end

  @doc """
  Replaces the tags on a game, creating missing tags in the game's community.
  """
  def set_game_tags(%Community{} = community, %Game{} = game, tag_names) do
    with :ok <- validate_game_community(game, community) do
      Repo.transaction(fn ->
        tags =
          tag_names
          |> parse_tag_names()
          |> Enum.map(&get_or_create_game_tag!(community, &1))

        game
        |> Repo.preload(:tags)
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:tags, tags)
        |> Repo.update!()
      end)
      |> case do
        {:ok, game} -> {:ok, Repo.preload(game, :tags, force: true)}
        {:error, error} -> {:error, error}
      end
    end
  end

  @doc """
  Returns summary counts for backlog curation.
  """
  def game_counts(%Community{} = community) do
    query = from(game in Game, where: game.community_id == ^community.id)

    %{
      total: Repo.aggregate(query, :count, :id),
      wheel: query |> where([game], game.include_in_wheel) |> Repo.aggregate(:count, :id),
      excluded: query |> where([game], not game.include_in_wheel) |> Repo.aggregate(:count, :id),
      played: query |> where([game], game.played_on_stream) |> Repo.aggregate(:count, :id),
      unplayed: query |> where([game], not game.played_on_stream) |> Repo.aggregate(:count, :id)
    }
  end

  @doc """
  Updates wheel inclusion for games matching the given filters.
  """
  def update_visible_games_include_in_wheel(%Community{} = community, filters, include_in_wheel)
      when is_boolean(include_in_wheel) do
    filters
    |> game_query(community)
    |> Repo.update_all(set: [include_in_wheel: include_in_wheel])
  end

  @doc """
  Returns games currently eligible for the wheel.

  Played-on-stream games remain eligible when included on the wheel.
  """
  def list_wheel_candidates(%Community{} = community) do
    Game
    |> where([game], game.community_id == ^community.id)
    |> where([game], game.include_in_wheel)
    |> preload([:tags])
    |> order_by([game], asc: game.title)
    |> Repo.all()
  end

  @doc """
  Returns recent recorded spins.
  """
  def list_recent_spins(%Community{} = community, limit \\ 10) do
    Spin
    |> where([spin], spin.community_id == ^community.id)
    |> preload([:game, :voting_session])
    |> order_by([spin], desc: spin.spun_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Returns the latest recorded spin for a community.
  """
  def latest_spin(%Community{} = community) do
    Spin
    |> where([spin], spin.community_id == ^community.id)
    |> preload([:game, :voting_session])
    |> order_by([spin], desc: spin.spun_at, desc: spin.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Returns the latest recorded spin for a voting session.
  """
  def latest_voting_session_spin(%Community{} = community, voting_session_id)
      when is_integer(voting_session_id) do
    Spin
    |> where([spin], spin.voting_session_id == ^voting_session_id)
    |> where([spin], spin.community_id == ^community.id)
    |> order_by([spin], desc: spin.spun_at, desc: spin.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Records a spin for a game.
  """
  def create_spin(%Community{} = community, attrs) do
    %Spin{community_id: community.id}
    |> Spin.changeset(attrs)
    |> validate_game_belongs_to_community(community)
    |> Repo.insert()
  end

  @doc """
  Gets a single spin.
  """
  def get_spin!(id), do: Repo.get!(Spin, id)

  def get_spin!(%Community{} = community, id) do
    Spin
    |> Repo.get_by!(id: id, community_id: community.id)
    |> Repo.preload([:game, :voting_session])
  end

  @doc """
  Deletes a spin history entry.
  """
  def delete_spin(%Spin{} = spin) do
    Repo.delete(spin)
  end

  @doc """
  Selects one wheel candidate uniformly at random and records the spin.
  """
  def spin_wheel(%Community{} = community) do
    case list_wheel_candidates(community) do
      [] ->
        {:error, :no_candidates}

      candidates ->
        game = Enum.random(candidates)

        case create_spin(community, %{
               game_id: game.id,
               spun_at: DateTime.utc_now(),
               source: "wheel",
               snapshot: wheel_spin_snapshot(candidates, game)
             }) do
          {:ok, spin} -> {:ok, %{game: game, spin: Repo.preload(spin, :game)}}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @doc """
  Returns the list of games from a specific platform.
  """
  def list_games_by_platform(%Community{} = community, platform) do
    Game
    |> where([game], game.community_id == ^community.id)
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
  def get_game!(id), do: Game |> preload([:tags]) |> Repo.get!(id)

  def get_game!(%Community{} = community, id) do
    Game
    |> where([game], game.id == ^id and game.community_id == ^community.id)
    |> preload([:tags])
    |> Repo.one!()
  end

  @doc """
  Gets a game by platform and external id.
  """
  def get_game_by_platform_external_id(%Community{} = community, platform, external_id)
      when is_binary(platform) and is_binary(external_id) do
    Repo.get_by(Game, community_id: community.id, platform: platform, external_id: external_id)
  end

  @doc """
  Creates a game.

  ## Examples

      iex> create_game(%{field: value})
      {:ok, %Game{}}

      iex> create_game(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_game(%Community{} = community, attrs) do
    tag_names = Map.get(attrs, "tag_names", Map.get(attrs, :tag_names))

    Repo.transaction(fn ->
      game =
        %Game{community_id: community.id}
        |> Game.changeset(attrs)
        |> Repo.insert!()

      if is_nil(tag_names) do
        Repo.preload(game, :tags)
      else
        {:ok, game} = set_game_tags(community, game, tag_names)
        game
      end
    end)
    |> case do
      {:ok, game} -> {:ok, game}
      {:error, changeset} -> {:error, changeset}
    end
  rescue
    error in Ecto.InvalidChangesetError -> {:error, error.changeset}
  end

  @doc """
  Imports normalized Steam games.

  Existing Steam games are preserved so local edits are not overwritten.
  New Steam imports are included on the wheel by default.
  """
  def import_steam_games(%Community{} = community, games) when is_list(games) do
    Enum.reduce(games, %{imported: 0, updated: 0, skipped: 0, errors: []}, fn game_attrs,
                                                                              summary ->
      case import_steam_game(community, game_attrs) do
        {:ok, :imported} -> update_in(summary.imported, &(&1 + 1))
        {:ok, :updated} -> update_in(summary.updated, &(&1 + 1))
        {:ok, :skipped} -> update_in(summary.skipped, &(&1 + 1))
        {:error, error} -> update_in(summary.errors, &[error | &1])
      end
    end)
    |> Map.update!(:errors, &Enum.reverse/1)
    |> then(&{:ok, &1})
  end

  defp import_steam_game(%Community{} = community, %{appid: appid, name: name} = game_attrs)
       when not is_nil(appid) and is_binary(name) do
    external_id = to_string(appid)

    case get_game_by_platform_external_id(community, "steam", external_id) do
      %Game{} = game ->
        update_attrs =
          game_attrs
          |> Map.take([:last_played_at, :image_url])
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new()

        if update_attrs == %{} do
          {:ok, :skipped}
        else
          case update_game(game, update_attrs) do
            {:ok, _game} -> {:ok, :updated}
            {:error, changeset} -> {:error, %{appid: external_id, errors: changeset.errors}}
          end
        end

      nil ->
        case create_game(community, %{
               title: name,
               platform: "steam",
               external_id: external_id,
               image_url: Map.get(game_attrs, :image_url),
               include_in_wheel: true,
               last_played_at: Map.get(game_attrs, :last_played_at)
             }) do
          {:ok, _game} -> {:ok, :imported}
          {:error, changeset} -> {:error, %{appid: external_id, errors: changeset.errors}}
        end
    end
  end

  defp import_steam_game(_community, game_attrs),
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
    tag_names = Map.get(attrs, "tag_names", Map.get(attrs, :tag_names))

    Repo.transaction(fn ->
      game =
        game
        |> Game.changeset(attrs)
        |> Repo.update!()

      if is_nil(tag_names) do
        Repo.preload(game, :tags)
      else
        {:ok, game} = set_game_tags(%Community{id: game.community_id}, game, tag_names)
        game
      end
    end)
    |> case do
      {:ok, game} -> {:ok, game}
      {:error, changeset} -> {:error, changeset}
    end
  rescue
    error in Ecto.InvalidChangesetError -> {:error, error.changeset}
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
    game
    |> put_loaded_tag_names()
    |> Game.changeset(attrs)
  end

  defp game_query(filters, %Community{} = community) do
    Game
    |> where([game], game.community_id == ^community.id)
    |> filter_by_search(Map.get(filters, "q", ""))
    |> filter_by_kind(Map.get(filters, "filter", "all"))
    |> filter_by_tag(Map.get(filters, "tag", ""))
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

  defp filter_by_tag(query, tag_slug) when is_binary(tag_slug) do
    tag_slug = String.trim(tag_slug)

    if tag_slug == "" do
      query
    else
      from(game in query,
        join: tag in assoc(game, :tags),
        where: tag.slug == ^tag_slug,
        distinct: true
      )
    end
  end

  defp filter_by_tag(query, _tag_slug), do: query

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

  defp put_loaded_tag_names(%Game{tags: %Ecto.Association.NotLoaded{}} = game), do: game

  defp put_loaded_tag_names(%Game{tags: tags} = game),
    do: %{game | tag_names: format_tag_names(tags)}

  defp format_tag_names(tags) when is_list(tags) do
    tags
    |> Enum.map(& &1.name)
    |> Enum.sort()
    |> Enum.join(", ")
  end

  defp parse_tag_names(tag_names) when is_binary(tag_names) do
    tag_names
    |> String.split([",", "\n"], trim: true)
    |> Enum.map(&normalize_tag_name/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq_by(&tag_slug/1)
  end

  defp parse_tag_names(tag_names) when is_list(tag_names) do
    tag_names
    |> Enum.map(&normalize_tag_name/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq_by(&tag_slug/1)
  end

  defp parse_tag_names(_tag_names), do: []

  defp normalize_tag_name(name) when is_binary(name), do: String.trim(name)
  defp normalize_tag_name(_name), do: ""

  defp tag_slug(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  defp get_or_create_game_tag!(%Community{} = community, name) do
    slug = tag_slug(name)

    Repo.get_by(GameTag, community_id: community.id, slug: slug) ||
      Repo.insert!(
        %GameTag{community_id: community.id}
        |> GameTag.changeset(%{name: name, slug: slug})
      )
  end

  defp validate_game_community(%Game{community_id: community_id}, %Community{id: community_id}),
    do: :ok

  defp validate_game_community(_game, _community), do: {:error, :game_not_in_community}

  defp validate_tag_community(%GameTag{community_id: community_id}, %Community{id: community_id}),
    do: :ok

  defp validate_tag_community(_tag, _community), do: {:error, :tag_not_in_community}

  defp wheel_spin_snapshot(candidates, winning_game) do
    %{
      "source" => "wheel",
      "winning_game_id" => winning_game.id,
      "total_weight" => length(candidates),
      "entries" => Enum.map(candidates, &wheel_spin_snapshot_entry/1)
    }
  end

  defp wheel_spin_snapshot_entry(game) do
    %{
      "game_id" => game.id,
      "title" => game.title,
      "base_weight" => 1,
      "channel_point_vote_total" => 0,
      "final_weight" => 1
    }
  end

  defp validate_game_belongs_to_community(changeset, %Community{} = community) do
    case Ecto.Changeset.get_field(changeset, :game_id) do
      nil ->
        changeset

      game_id ->
        if Repo.exists?(
             from(game in Game, where: game.id == ^game_id and game.community_id == ^community.id)
           ) do
          changeset
        else
          Ecto.Changeset.add_error(changeset, :game_id, "does not belong to this community")
        end
    end
  end
end
