defmodule BacklogWheel.Repo.Migrations.ScopeGameExternalIdsToCommunity do
  use Ecto.Migration

  def change do
    drop_if_exists index(:games, [:platform, :external_id],
                     name: :games_platform_external_id_index
                   )

    create unique_index(:games, [:community_id, :platform, :external_id],
             where: "external_id IS NOT NULL",
             name: :games_community_platform_external_id_index
           )
  end
end
