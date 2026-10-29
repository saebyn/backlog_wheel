defmodule BacklogWheel.Voting.TwitchVotingRedemption do
  use Ecto.Schema
  import Ecto.Changeset

  alias BacklogWheel.Voting.TwitchVotingReward

  schema "twitch_voting_redemptions" do
    field :redemption_id, :string
    field :user_id, :string
    field :user_login, :string
    field :decision, :string
    field :resolution_status, :string, default: "pending"
    field :feedback_status, :string, default: "pending"
    field :last_error, :string
    belongs_to :twitch_voting_reward, TwitchVotingReward
    timestamps(type: :utc_datetime)
  end

  def changeset(redemption, attrs) do
    redemption
    |> cast(attrs, [
      :redemption_id,
      :user_id,
      :user_login,
      :decision,
      :resolution_status,
      :feedback_status,
      :last_error
    ])
    |> validate_required([
      :twitch_voting_reward_id,
      :redemption_id,
      :user_id,
      :user_login,
      :decision,
      :resolution_status,
      :feedback_status
    ])
    |> unique_constraint(:redemption_id)
  end
end
