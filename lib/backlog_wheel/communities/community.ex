defmodule BacklogWheel.Communities.Community do
  use Ecto.Schema
  import Ecto.Changeset

  alias BacklogWheel.Backlog.{Game, Spin}
  alias BacklogWheel.Communities.{CommunityMembership, Theme}
  alias BacklogWheel.Voting.{Viewer, ViewerIdentity, VotingSession, WheelFormat}

  schema "communities" do
    field :name, :string
    field :slug, :string
    field :light_primary_color, :string
    field :light_accent_color, :string
    field :light_background_color, :string
    field :dark_primary_color, :string
    field :dark_accent_color, :string
    field :dark_background_color, :string
    field :steam_api_key, :string
    field :steam_id64, :string

    has_many :games, Game
    has_many :memberships, CommunityMembership
    has_many :spins, Spin
    has_many :viewers, Viewer
    has_many :viewer_identities, ViewerIdentity
    has_many :voting_sessions, VotingSession
    has_many :wheel_formats, WheelFormat

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(community, attrs) do
    community
    |> cast(attrs, [:name, :slug])
    |> validate_required([:name, :slug])
    |> validate_slug()
    |> unique_constraint(:slug)
  end

  @doc false
  def general_settings_changeset(community, attrs) do
    community
    |> cast(attrs, [:name, :slug])
    |> normalize_blanks([:name, :slug])
    |> update_change(:slug, &slugify/1)
    |> validate_required([:name, :slug])
    |> validate_slug()
    |> unique_constraint(:slug)
  end

  @doc false
  def onboarding_changeset(community, attrs) do
    community
    |> cast(attrs, [:name])
    |> validate_required([:name])
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

  @doc false
  def steam_credential_changeset(community, attrs) do
    community
    |> cast(attrs, [:steam_api_key, :steam_id64])
    |> normalize_blanks([:steam_api_key, :steam_id64])
    |> validate_steam_credential_pair()
  end

  defp validate_steam_credential_pair(changeset) do
    api_key = get_field(changeset, :steam_api_key)
    steam_id64 = get_field(changeset, :steam_id64)

    cond do
      api_key in [nil, ""] and steam_id64 in [nil, ""] ->
        changeset

      api_key in [nil, ""] ->
        add_error(changeset, :steam_api_key, "can't be blank")

      steam_id64 in [nil, ""] ->
        add_error(changeset, :steam_id64, "can't be blank")

      true ->
        changeset
    end
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

  defp validate_slug(changeset) do
    changeset
    |> validate_length(:slug, min: 2, max: 80)
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/,
      message: "must use lowercase letters, numbers, and hyphens"
    )
  end

  defp slugify(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp slugify(value), do: value
end
