defmodule BacklogWheel.Repo.Migrations.CreateCommunityMemberships do
  use Ecto.Migration

  def change do
    create table(:community_memberships) do
      add :role, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :community_id, references(:communities, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:community_memberships, [:user_id])
    create index(:community_memberships, [:community_id])
    create unique_index(:community_memberships, [:user_id, :community_id])
  end
end
