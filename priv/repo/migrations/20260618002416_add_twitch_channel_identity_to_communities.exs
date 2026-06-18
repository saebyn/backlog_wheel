defmodule BacklogWheel.Repo.Migrations.AddTwitchChannelIdentityToCommunities do
  use Ecto.Migration

  def change do
    alter table(:communities) do
      add :twitch_broadcaster_login, :string
      add :twitch_broadcaster_display_name, :string
    end
  end
end
