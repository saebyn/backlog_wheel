defmodule BacklogWheel.Backlog.GameTag do
  use Ecto.Schema
  import Ecto.Changeset

  alias BacklogWheel.Backlog.Game
  alias BacklogWheel.Communities.Community

  schema "game_tags" do
    field :name, :string
    field :slug, :string

    belongs_to :community, Community

    many_to_many :games, Game,
      join_through: "game_taggings",
      join_keys: [game_tag_id: :id, game_id: :id]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(game_tag, attrs) do
    game_tag
    |> cast(attrs, [:name, :slug])
    |> validate_required([:name, :slug, :community_id])
    |> validate_length(:name, max: 64)
    |> validate_length(:slug, max: 64)
    |> unique_constraint([:community_id, :slug])
  end
end
