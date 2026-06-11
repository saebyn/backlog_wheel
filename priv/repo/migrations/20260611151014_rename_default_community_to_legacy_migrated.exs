defmodule BacklogWheel.Repo.Migrations.RenameDefaultCommunityToLegacyMigrated do
  use Ecto.Migration

  def change do
    execute """
            UPDATE communities
            SET name = 'Legacy Migrated Community',
                slug = 'legacy-migrated',
                updated_at = datetime('now')
            WHERE slug = 'default'
              AND NOT EXISTS (SELECT 1 FROM communities WHERE slug = 'legacy-migrated')
            """,
            """
            UPDATE communities
            SET name = 'Default Community',
                slug = 'default',
                updated_at = datetime('now')
            WHERE slug = 'legacy-migrated'
            """
  end
end
