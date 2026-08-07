defmodule BacklogWheel.Repo.Migrations.AddPlaytimeMinutesToGames do
  use Ecto.Migration

  def change do
    alter table(:games) do
      add :playtime_minutes, :integer
    end
  end
end
