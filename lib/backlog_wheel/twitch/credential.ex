defmodule BacklogWheel.Twitch.Credential do
  use Ecto.Schema
  import Ecto.Changeset

  schema "twitch_credentials" do
    field :access_token, :string
    field :refresh_token, :string
    field :scopes, :string, default: ""
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:access_token, :refresh_token, :scopes, :expires_at])
    |> validate_required([:access_token, :scopes])
  end
end
