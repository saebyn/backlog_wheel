defmodule BacklogWheel.Repo.Migrations.AddWheelFormats do
  use Ecto.Migration

  def change do
    create table(:wheel_formats) do
      add :community_id, references(:communities, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :default_session_title, :string
      add :default_session_description, :text
      add :is_default, :boolean, default: false, null: false
      add :is_enabled, :boolean, default: true, null: false
      add :candidate_rules, :map, default: %{}, null: false
      add :weighting_rules, :map, default: %{}, null: false

      timestamps(type: :utc_datetime)
    end

    alter table(:voting_sessions) do
      add :wheel_format_id, references(:wheel_formats, on_delete: :nilify_all)
      add :title, :string
      add :description, :text
    end

    create index(:wheel_formats, [:community_id])
    create index(:wheel_formats, [:community_id, :is_enabled])
    create unique_index(:wheel_formats, [:community_id, :name])
    create index(:voting_sessions, [:wheel_format_id])
  end
end
