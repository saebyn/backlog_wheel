defmodule BacklogWheel.Communities.Community do
  use Ecto.Schema
  import Ecto.Changeset

  alias BacklogWheel.Backlog.{Game, Spin}

  schema "communities" do
    field :name, :string
    field :slug, :string

    has_many :games, Game
    has_many :spins, Spin

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(community, attrs) do
    community
    |> cast(attrs, [:name, :slug])
    |> validate_required([:name, :slug])
    |> unique_constraint(:slug)
  end
end
