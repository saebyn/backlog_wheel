defmodule BacklogWheel.Repo.Migrations.CreateGames do
  use Ecto.Migration

  def change do
    create table(:games) do
      add :title, :string, null: false
      add :platform, :string, default: "manual", null: false
      add :external_id, :string
      add :include_in_wheel, :boolean, default: false, null: false
      add :played_on_stream, :boolean, default: false, null: false
      add :last_played_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end
  end
end
