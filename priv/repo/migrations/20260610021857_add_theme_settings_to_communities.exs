defmodule BacklogWheel.Repo.Migrations.AddThemeSettingsToCommunities do
  use Ecto.Migration

  def change do
    alter table(:communities) do
      add :light_primary_color, :string
      add :light_accent_color, :string
      add :light_background_color, :string
      add :dark_primary_color, :string
      add :dark_accent_color, :string
      add :dark_background_color, :string
    end
  end
end
