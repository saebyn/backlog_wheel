defmodule BacklogWheel.Repo.Migrations.CreateViewersAndVotingBoosts do
  use Ecto.Migration

  def change do
    create table(:viewers) do
      add :community_id, references(:communities, on_delete: :restrict), null: false
      add :display_name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create table(:viewer_identities) do
      add :community_id, references(:communities, on_delete: :restrict), null: false
      add :viewer_id, references(:viewers, on_delete: :delete_all), null: false
      add :platform, :string, null: false
      add :platform_user_id, :string, null: false
      add :display_name, :string

      timestamps(type: :utc_datetime)
    end

    create table(:voting_boosts) do
      add :voting_session_game_id, references(:voting_session_games, on_delete: :delete_all),
        null: false

      add :viewer_id, references(:viewers, on_delete: :nilify_all)
      add :strength, :integer, null: false
      add :source, :string, null: false
      add :external_event_id, :string

      timestamps(type: :utc_datetime)
    end

    create index(:viewers, [:community_id])
    create index(:viewer_identities, [:community_id])
    create index(:viewer_identities, [:viewer_id])
    create unique_index(:viewer_identities, [:community_id, :platform, :platform_user_id])
    create index(:voting_boosts, [:voting_session_game_id])
    create index(:voting_boosts, [:viewer_id])

    create unique_index(:voting_boosts, [:source, :external_event_id],
             where: "external_event_id IS NOT NULL"
           )
  end
end
