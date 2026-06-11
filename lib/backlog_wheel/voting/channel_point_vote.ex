defmodule BacklogWheel.Voting.ChannelPointVote do
  use Ecto.Schema
  import Ecto.Changeset

  alias BacklogWheel.Voting.{Viewer, VotingSessionGame}

  schema "channel_point_votes" do
    field :strength, :integer
    field :source, :string
    field :external_event_id, :string

    belongs_to :voting_session_game, VotingSessionGame
    belongs_to :viewer, Viewer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(channel_point_vote, attrs) do
    channel_point_vote
    |> cast(attrs, [:strength, :source, :external_event_id])
    |> validate_required([:voting_session_game_id, :strength, :source])
    |> validate_number(:strength, greater_than: 0)
    |> unique_constraint([:source, :external_event_id])
  end
end
