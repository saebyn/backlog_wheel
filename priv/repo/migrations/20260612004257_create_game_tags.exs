defmodule BacklogWheel.Repo.Migrations.CreateGameTags do
  use Ecto.Migration

  def change do
    create table(:game_tags) do
      add :community_id, references(:communities, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :slug, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:game_tags, [:community_id, :slug])
    create index(:game_tags, [:community_id])

    create table(:game_taggings, primary_key: false) do
      add :game_id, references(:games, on_delete: :delete_all), null: false
      add :game_tag_id, references(:game_tags, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, default: fragment("CURRENT_TIMESTAMP"))
    end

    create unique_index(:game_taggings, [:game_id, :game_tag_id])
    create index(:game_taggings, [:game_tag_id])
  end
end
