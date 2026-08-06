defmodule BacklogWheel.Repo.Migrations.AddSiteAdminToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :site_admin, :boolean, null: false, default: false
    end
  end
end
