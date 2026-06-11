defmodule BacklogWheel.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :discord_id, :string, null: false
      add :username, :string, null: false
      add :avatar_hash, :string
      add :role, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:discord_id])
  end
end
