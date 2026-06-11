defmodule BacklogWheel.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(admin streamer)

  schema "users" do
    field :discord_id, :string
    field :username, :string
    field :avatar_hash, :string
    field :role, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:discord_id, :username, :avatar_hash, :role])
    |> validate_required([:discord_id, :username, :role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint(:discord_id)
  end
end
