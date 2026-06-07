defmodule BacklogWheel.Voting.ViewerIdentity do
  use Ecto.Schema
  import Ecto.Changeset

  alias BacklogWheel.Communities.Community
  alias BacklogWheel.Voting.Viewer

  @platforms ["local", "twitch", "discord"]

  schema "viewer_identities" do
    field :platform, :string
    field :platform_user_id, :string
    field :display_name, :string

    belongs_to :community, Community
    belongs_to :viewer, Viewer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(viewer_identity, attrs) do
    viewer_identity
    |> cast(attrs, [:platform, :platform_user_id, :display_name])
    |> validate_required([:community_id, :viewer_id, :platform, :platform_user_id])
    |> validate_inclusion(:platform, @platforms)
    |> unique_constraint([:community_id, :platform, :platform_user_id])
  end
end
