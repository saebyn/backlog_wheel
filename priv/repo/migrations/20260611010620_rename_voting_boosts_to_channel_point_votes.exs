defmodule BacklogWheel.Repo.Migrations.RenameVotingBoostsToChannelPointVotes do
  use Ecto.Migration

  def change do
    rename table(:voting_boosts), to: table(:channel_point_votes)
  end
end
