defmodule BacklogWheel.Voting.VotingBoost do
  use Ecto.Schema
  import Ecto.Changeset

  alias BacklogWheel.Voting.{Viewer, VotingSessionGame}

  schema "voting_boosts" do
    field :strength, :integer
    field :source, :string
    field :external_event_id, :string

    belongs_to :voting_session_game, VotingSessionGame
    belongs_to :viewer, Viewer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(voting_boost, attrs) do
    voting_boost
    |> cast(attrs, [:strength, :source, :external_event_id])
    |> validate_required([:voting_session_game_id, :strength, :source])
    |> validate_number(:strength, greater_than: 0)
    |> unique_constraint([:source, :external_event_id])
  end
end
