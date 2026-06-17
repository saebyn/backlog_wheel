defmodule BacklogWheel.Repo.Migrations.AddTwitchSettingsToCommunities do
  use Ecto.Migration

  def change do
    alter table(:communities) do
      add :twitch_broadcaster_id, :string
      add :twitch_eventsub_secret, :string
      add :twitch_reward_cost, :integer, null: false, default: 100
    end

    create unique_index(:communities, [:twitch_broadcaster_id],
             where: "twitch_broadcaster_id IS NOT NULL"
           )
  end
end
