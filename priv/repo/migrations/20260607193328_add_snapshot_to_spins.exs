defmodule BacklogWheel.Repo.Migrations.AddSnapshotToSpins do
  use Ecto.Migration

  def change do
    alter table(:spins) do
      add :voting_session_id, references(:voting_sessions, on_delete: :nilify_all)
      add :snapshot, :map
    end

    create index(:spins, [:voting_session_id])
  end
end
