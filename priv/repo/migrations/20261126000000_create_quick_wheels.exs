defmodule BacklogWheel.Repo.Migrations.CreateQuickWheels do
  use Ecto.Migration

  def change do
    create table(:quick_wheels) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :preset, :boolean, null: false
      add :title, :text, null: false
      add :entries, {:array, :text}, null: false
      add :revision, :integer, null: false, default: 1
    end

    create unique_index(:quick_wheels, [:user_id], where: "NOT preset")
    create index(:quick_wheels, [:user_id, :preset])
  end
end
