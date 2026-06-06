defmodule BacklogWheel.Backlog.Game do
  use Ecto.Schema
  import Ecto.Changeset

  schema "games" do
    field :title, :string
    field :platform, :string, default: "manual"
    field :external_id, :string
    field :include_in_wheel, :boolean, default: false
    field :played_on_stream, :boolean, default: false
    field :last_played_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(game, attrs) do
    game
    |> cast(attrs, [
      :title,
      :platform,
      :external_id,
      :include_in_wheel,
      :played_on_stream,
      :last_played_at
    ])
    |> validate_required([:title])
    |> unique_constraint([:platform, :external_id], name: :games_platform_external_id_index)
  end
end
