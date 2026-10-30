defmodule BacklogWheel.Voting.TwitchVotingReward do
  use Ecto.Schema
  import Ecto.Changeset

  alias BacklogWheel.Voting.VotingSession

  schema "twitch_voting_rewards" do
    field :reward_id, :string
    field :title, :string
    field :cost, :integer
    field :status, :string, default: "enabled"
    field :cleanup_error, :string
    field :reconciliation_error, :string
    belongs_to :voting_session, VotingSession
    timestamps(type: :utc_datetime)
  end

  def changeset(reward, attrs) do
    reward
    |> cast(attrs, [:reward_id, :title, :cost, :status, :cleanup_error, :reconciliation_error])
    |> validate_required([:voting_session_id, :reward_id, :title, :cost, :status])
    |> unique_constraint(:reward_id)
    |> unique_constraint(:voting_session_id)
  end
end
