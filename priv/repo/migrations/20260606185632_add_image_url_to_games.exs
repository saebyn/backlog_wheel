defmodule BacklogWheel.Repo.Migrations.AddImageUrlToGames do
  use Ecto.Migration

  def change do
    alter table(:games) do
      add :image_url, :string
    end
  end
end
