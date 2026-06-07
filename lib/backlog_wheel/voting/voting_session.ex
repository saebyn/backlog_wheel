defmodule BacklogWheel.Voting.VotingSession do
  use Ecto.Schema
  import Ecto.Changeset

  alias BacklogWheel.Communities.Community
  alias BacklogWheel.Voting.VotingSessionGame

  @statuses ["draft", "open", "locked", "closed", "cancelled"]

  schema "voting_sessions" do
    field :status, :string, default: "draft"

    belongs_to :community, Community
    has_many :voting_session_games, VotingSessionGame

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(voting_session, attrs) do
    voting_session
    |> cast(attrs, [:status])
    |> validate_required([:community_id, :status])
    |> validate_inclusion(:status, @statuses)
  end
end
