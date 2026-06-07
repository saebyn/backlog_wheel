defmodule BacklogWheel.Voting.VotingSessionGame do
  use Ecto.Schema
  import Ecto.Changeset

  alias BacklogWheel.Backlog.Game
  alias BacklogWheel.Voting.VotingSession

  schema "voting_session_games" do
    field :base_weight, :integer, default: 1

    belongs_to :voting_session, VotingSession
    belongs_to :game, Game

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(voting_session_game, attrs) do
    voting_session_game
    |> cast(attrs, [:base_weight])
    |> validate_required([:voting_session_id, :game_id, :base_weight])
    |> validate_number(:base_weight, greater_than: 0)
    |> unique_constraint([:voting_session_id, :game_id])
  end
end
