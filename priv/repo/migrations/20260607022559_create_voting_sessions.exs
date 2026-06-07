defmodule BacklogWheel.Repo.Migrations.CreateVotingSessions do
  use Ecto.Migration

  def change do
    create table(:voting_sessions) do
      add :community_id, references(:communities, on_delete: :restrict), null: false
      add :status, :string, default: "draft", null: false

      timestamps(type: :utc_datetime)
    end

    create table(:voting_session_games) do
      add :voting_session_id, references(:voting_sessions, on_delete: :delete_all), null: false
      add :game_id, references(:games, on_delete: :restrict), null: false
      add :base_weight, :integer, default: 1, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:voting_sessions, [:community_id])
    create index(:voting_sessions, [:status])
    create index(:voting_session_games, [:voting_session_id])
    create index(:voting_session_games, [:game_id])
    create unique_index(:voting_session_games, [:voting_session_id, :game_id])
  end
end
