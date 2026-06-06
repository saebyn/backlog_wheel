defmodule BacklogWheel.Repo.Migrations.CreateSpins do
  use Ecto.Migration

  def change do
    create table(:spins) do
      add :game_id, references(:games, on_delete: :delete_all), null: false
      add :spun_at, :utc_datetime, null: false
      add :source, :string, default: "wheel", null: false
      add :notes, :string

      timestamps(type: :utc_datetime)
    end

    create index(:spins, [:game_id])
    create index(:spins, [:spun_at])
  end
end
