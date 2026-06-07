defmodule BacklogWheel.Voting.Viewer do
  use Ecto.Schema
  import Ecto.Changeset

  alias BacklogWheel.Communities.Community
  alias BacklogWheel.Voting.{ViewerIdentity, VotingBoost}

  schema "viewers" do
    field :display_name, :string

    belongs_to :community, Community
    has_many :viewer_identities, ViewerIdentity
    has_many :voting_boosts, VotingBoost

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(viewer, attrs) do
    viewer
    |> cast(attrs, [:display_name])
    |> validate_required([:community_id, :display_name])
  end
end
