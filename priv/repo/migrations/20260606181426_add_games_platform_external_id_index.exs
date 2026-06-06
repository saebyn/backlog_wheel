defmodule BacklogWheel.Repo.Migrations.AddGamesPlatformExternalIdIndex do
  use Ecto.Migration

  def change do
    create unique_index(:games, [:platform, :external_id],
             where: "external_id IS NOT NULL",
             name: :games_platform_external_id_index
           )
  end
end
