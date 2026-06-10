defmodule BacklogWheel.Repo.Migrations.AddTwitchRewardCleanupToVotingSessionGames do
  use Ecto.Migration

  def change do
    alter table(:voting_session_games) do
      add :twitch_reward_deletion_status, :string
      add :twitch_reward_deletion_error, :text
      add :twitch_reward_deleted_at, :utc_datetime
    end
  end
end
