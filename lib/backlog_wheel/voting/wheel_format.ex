defmodule BacklogWheel.Voting.WheelFormat do
  use Ecto.Schema
  import Ecto.Changeset

  alias BacklogWheel.Communities.Community
  alias BacklogWheel.Voting.VotingSession

  schema "wheel_formats" do
    field :name, :string
    field :description, :string
    field :default_session_title, :string
    field :default_session_description, :string
    field :is_default, :boolean, default: false
    field :is_enabled, :boolean, default: true
    field :candidate_rules, :map, default: %{}
    field :weighting_rules, :map, default: %{}

    belongs_to :community, Community
    has_many :voting_sessions, VotingSession

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(wheel_format, attrs) do
    wheel_format
    |> cast(attrs, [
      :name,
      :description,
      :default_session_title,
      :default_session_description,
      :is_default,
      :is_enabled,
      :candidate_rules,
      :weighting_rules
    ])
    |> validate_required([
      :community_id,
      :name,
      :default_session_title,
      :candidate_rules,
      :weighting_rules
    ])
    |> validate_length(:name, max: 120)
    |> validate_length(:default_session_title, max: 160)
    |> unique_constraint([:community_id, :name])
  end
end
