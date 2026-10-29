defmodule BacklogWheel.Repo.Migrations.ScopeTwitchCredentialsToCommunities do
  use Ecto.Migration

  def change do
    alter table(:twitch_credentials) do
      add :community_id, references(:communities, on_delete: :delete_all)
    end

    create unique_index(:twitch_credentials, [:community_id])
  end
end
