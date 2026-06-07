defmodule BacklogWheel.Communities.Community do
  use Ecto.Schema
  import Ecto.Changeset

  alias BacklogWheel.Backlog.{Game, Spin}
  alias BacklogWheel.Voting.{Viewer, ViewerIdentity, VotingSession}

  schema "communities" do
    field :name, :string
    field :slug, :string

    has_many :games, Game
    has_many :spins, Spin
    has_many :viewers, Viewer
    has_many :viewer_identities, ViewerIdentity
    has_many :voting_sessions, VotingSession

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
