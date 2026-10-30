defmodule BacklogWheel.Repo.Migrations.AddVotingWindowsToTwitchSessions do
  use Ecto.Migration

  def up do
    create table(:twitch_voting_windows) do
      add :voting_session_id, references(:voting_sessions, on_delete: :delete_all), null: false
      add :opened_at, :utc_datetime_usec, null: false
      add :closed_at, :utc_datetime_usec
      add :reconciled_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:twitch_voting_windows, [:voting_session_id], where: "closed_at IS NULL")

    alter table(:twitch_voting_redemptions) do
      add :redeemed_at, :utc_datetime_usec
    end

    execute """
    INSERT INTO twitch_voting_windows (voting_session_id, opened_at, inserted_at, updated_at)
    SELECT id, inserted_at, now(), now() FROM voting_sessions WHERE status = 'open'
    """
  end

  def down do
    alter table(:twitch_voting_redemptions) do
      remove :redeemed_at
    end

    drop table(:twitch_voting_windows)
  end
end
