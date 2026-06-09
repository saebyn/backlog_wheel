defmodule BacklogWheel.Repo.Migrations.AddTwitchRewardsToVotingSessionGames do
  use Ecto.Migration

  def change do
    create table(:twitch_credentials) do
      add :access_token, :text, null: false
      add :refresh_token, :text
      add :scopes, :text, default: "", null: false
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    alter table(:voting_session_games) do
      add :twitch_reward_id, :string
      add :twitch_reward_title, :string
      add :twitch_reward_cost, :integer
      add :twitch_reward_status, :string
    end

    create unique_index(:voting_session_games, [:twitch_reward_id],
             where: "twitch_reward_id IS NOT NULL"
           )
  end
end
