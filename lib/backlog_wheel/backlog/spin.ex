defmodule BacklogWheel.Backlog.Spin do
  use Ecto.Schema
  import Ecto.Changeset

  alias BacklogWheel.Backlog.Game
  alias BacklogWheel.Communities.Community

  schema "spins" do
    field :spun_at, :utc_datetime
    field :source, :string, default: "wheel"
    field :notes, :string
    field :snapshot, :map

    belongs_to :game, Game
    belongs_to :community, Community
    belongs_to :voting_session, BacklogWheel.Voting.VotingSession

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(spin, attrs) do
    spin
    |> cast(attrs, [:game_id, :voting_session_id, :spun_at, :source, :notes, :snapshot])
    |> validate_required([:game_id, :community_id, :spun_at, :source])
  end
end
