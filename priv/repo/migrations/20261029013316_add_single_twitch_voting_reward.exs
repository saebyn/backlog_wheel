defmodule BacklogWheel.Repo.Migrations.AddSingleTwitchVotingReward do
  use Ecto.Migration

  def change do
    create table(:twitch_voting_rewards) do
      add :voting_session_id, references(:voting_sessions, on_delete: :restrict), null: false
      add :reward_id, :string, null: false
      add :title, :string, null: false
      add :cost, :integer, null: false
      add :status, :string, null: false, default: "enabled"
      add :cleanup_error, :text
      add :reconciliation_error, :text
      timestamps(type: :utc_datetime)
    end

    create unique_index(:twitch_voting_rewards, [:voting_session_id])
    create unique_index(:twitch_voting_rewards, [:reward_id])

    create table(:twitch_voting_redemptions) do
      add :twitch_voting_reward_id, references(:twitch_voting_rewards, on_delete: :restrict),
        null: false

      add :redemption_id, :string, null: false
      add :user_id, :string, null: false
      add :user_login, :string, null: false
      add :decision, :string, null: false
      add :resolution_status, :string, null: false, default: "pending"
      add :feedback_status, :string, null: false, default: "pending"
      add :last_error, :text
      timestamps(type: :utc_datetime)
    end

    create unique_index(:twitch_voting_redemptions, [:redemption_id])
    create index(:twitch_voting_redemptions, [:resolution_status, :feedback_status])
  end
end
