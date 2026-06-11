defmodule BacklogWheel.Communities.CommunityMembership do
  use Ecto.Schema
  import Ecto.Changeset

  alias BacklogWheel.Accounts.User
  alias BacklogWheel.Communities.Community

  @roles ~w(owner admin viewer)
  @admin_roles ~w(owner admin)

  schema "community_memberships" do
    field :role, :string

    belongs_to :user, User
    belongs_to :community, Community

    timestamps(type: :utc_datetime)
  end

  def admin_roles, do: @admin_roles

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:user_id, :community_id, :role])
    |> validate_required([:user_id, :community_id, :role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:user_id, :community_id])
  end
end
