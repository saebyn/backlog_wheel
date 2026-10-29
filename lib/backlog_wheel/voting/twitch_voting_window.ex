defmodule BacklogWheel.Voting.TwitchVotingWindow do
  use Ecto.Schema

  alias BacklogWheel.Voting.VotingSession

  schema "twitch_voting_windows" do
    field :opened_at, :utc_datetime_usec
    field :closed_at, :utc_datetime_usec
    field :reconciled_at, :utc_datetime_usec
    belongs_to :voting_session, VotingSession
    timestamps(type: :utc_datetime_usec)
  end
end
