defmodule BacklogWheel.Repo.Migrations.AddVotingOptionNumbers do
  use Ecto.Migration

  def up do
    alter table(:voting_sessions) do
      add :next_option_number, :integer, null: false, default: 1
    end

    alter table(:voting_session_games) do
      add :option_number, :integer
    end

    execute """
    UPDATE voting_session_games AS games
    SET option_number = numbered.number
    FROM (
      SELECT id, row_number() OVER (PARTITION BY voting_session_id ORDER BY id) AS number
      FROM voting_session_games
    ) AS numbered
    WHERE games.id = numbered.id
    """

    execute """
    UPDATE voting_sessions AS sessions
    SET next_option_number = numbered.next_number
    FROM (
      SELECT voting_session_id, max(option_number) + 1 AS next_number
      FROM voting_session_games GROUP BY voting_session_id
    ) AS numbered
    WHERE sessions.id = numbered.voting_session_id
    """

    alter table(:voting_session_games) do
      modify :option_number, :integer, null: false
    end

    create unique_index(:voting_session_games, [:voting_session_id, :option_number])
  end

  def down do
    drop unique_index(:voting_session_games, [:voting_session_id, :option_number])

    alter table(:voting_session_games) do
      remove :option_number
    end

    alter table(:voting_sessions) do
      remove :next_option_number
    end
  end
end
