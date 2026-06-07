defmodule BacklogWheel.Repo.Migrations.ScopeRecordsToDefaultCommunity do
  use Ecto.Migration

  def change do
    execute """
            INSERT INTO communities (name, slug, inserted_at, updated_at)
            SELECT 'Default Community', 'default', datetime('now'), datetime('now')
            WHERE NOT EXISTS (SELECT 1 FROM communities WHERE slug = 'default')
            """,
            "SELECT 1"

    alter table(:games) do
      add :community_id, references(:communities, on_delete: :restrict)
    end

    alter table(:spins) do
      add :community_id, references(:communities, on_delete: :restrict)
    end

    execute """
            UPDATE games
            SET community_id = (SELECT id FROM communities WHERE slug = 'default')
            WHERE community_id IS NULL
            """,
            "UPDATE games SET community_id = NULL"

    execute """
            UPDATE spins
            SET community_id = (SELECT id FROM communities WHERE slug = 'default')
            WHERE community_id IS NULL
            """,
            "UPDATE spins SET community_id = NULL"

    create index(:games, [:community_id])
    create index(:spins, [:community_id])
  end
end
