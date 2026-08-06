defmodule BacklogWheel.Repo.Migrations.AddPhoenixAnalytics do
  use Ecto.Migration

  def up do
    PhoenixAnalytics.Migration.up()
    PhoenixAnalytics.Migration.add_indexes()
  end

  def down do
    PhoenixAnalytics.Migration.down()
  end
end
