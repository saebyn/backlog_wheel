defmodule BacklogWheel.Backlog.Spin do
  use Ecto.Schema
  import Ecto.Changeset

  alias BacklogWheel.Backlog.Game

  schema "spins" do
    field :spun_at, :utc_datetime
    field :source, :string, default: "wheel"
    field :notes, :string

    belongs_to :game, Game

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(spin, attrs) do
    spin
    |> cast(attrs, [:game_id, :spun_at, :source, :notes])
    |> validate_required([:game_id, :spun_at, :source])
  end
end
