defmodule BacklogWheel.Repo.Migrations.AddSteamCredentialsToCommunities do
  use Ecto.Migration

  def change do
    alter table(:communities) do
      add :steam_api_key, :string
      add :steam_id64, :string
    end
  end
end
