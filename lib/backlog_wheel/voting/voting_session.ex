defmodule BacklogWheel.Voting.VotingSession do
  use Ecto.Schema
  import Ecto.Changeset

  alias BacklogWheel.Communities.Community
  alias BacklogWheel.Voting.{VotingSessionGame, WheelFormat}

  @statuses ["draft", "open", "locked", "closed", "cancelled"]

  schema "voting_sessions" do
    field :title, :string
    field :description, :string
    field :status, :string, default: "draft"

    belongs_to :community, Community
    belongs_to :wheel_format, WheelFormat
    has_many :voting_session_games, VotingSessionGame

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(voting_session, attrs) do
    voting_session
    |> cast(attrs, [:status, :title, :description, :wheel_format_id])
    |> validate_required([:community_id, :status])
    |> validate_length(:title, max: 160)
    |> validate_inclusion(:status, @statuses)
  end
end
