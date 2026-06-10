defmodule BacklogWheel.Communities.Community do
  use Ecto.Schema
  import Ecto.Changeset

  alias BacklogWheel.Backlog.{Game, Spin}
  alias BacklogWheel.Communities.Theme
  alias BacklogWheel.Voting.{Viewer, ViewerIdentity, VotingSession}

  schema "communities" do
    field :name, :string
    field :slug, :string
    field :light_primary_color, :string
    field :light_accent_color, :string
    field :light_background_color, :string
    field :dark_primary_color, :string
    field :dark_accent_color, :string
    field :dark_background_color, :string

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

  @doc false
  def theme_changeset(community, attrs) do
    community
    |> cast(attrs, Theme.color_fields())
    |> normalize_blanks(Theme.color_fields())
    |> validate_format(:light_primary_color, ~r/^#(?:[0-9a-fA-F]{3}){1,2}$/,
      message: "must be a hex color"
    )
    |> validate_format(:light_accent_color, ~r/^#(?:[0-9a-fA-F]{3}){1,2}$/,
      message: "must be a hex color"
    )
    |> validate_format(:light_background_color, ~r/^#(?:[0-9a-fA-F]{3}){1,2}$/,
      message: "must be a hex color"
    )
    |> validate_format(:dark_primary_color, ~r/^#(?:[0-9a-fA-F]{3}){1,2}$/,
      message: "must be a hex color"
    )
    |> validate_format(:dark_accent_color, ~r/^#(?:[0-9a-fA-F]{3}){1,2}$/,
      message: "must be a hex color"
    )
    |> validate_format(:dark_background_color, ~r/^#(?:[0-9a-fA-F]{3}){1,2}$/,
      message: "must be a hex color"
    )
  end

  defp normalize_blanks(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, changeset ->
      case get_change(changeset, field) do
        value when is_binary(value) -> put_change(changeset, field, blank_to_nil(value))
        _value -> changeset
      end
    end)
  end

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end
end
