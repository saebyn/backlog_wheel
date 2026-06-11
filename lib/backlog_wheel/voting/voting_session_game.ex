defmodule BacklogWheel.Voting.VotingSessionGame do
  use Ecto.Schema
  import Ecto.Changeset

  alias BacklogWheel.Backlog.Game
  alias BacklogWheel.Voting.{ChannelPointVote, VotingSession}

  schema "voting_session_games" do
    field :base_weight, :integer, default: 1
    field :twitch_reward_id, :string
    field :twitch_reward_title, :string
    field :twitch_reward_cost, :integer
    field :twitch_reward_status, :string
    field :twitch_reward_deletion_status, :string
    field :twitch_reward_deletion_error, :string
    field :twitch_reward_deleted_at, :utc_datetime

    belongs_to :voting_session, VotingSession
    belongs_to :game, Game
    has_many :channel_point_votes, ChannelPointVote

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(voting_session_game, attrs) do
    voting_session_game
    |> cast(attrs, [:base_weight])
    |> validate_required([:voting_session_id, :game_id, :base_weight])
    |> validate_number(:base_weight, greater_than: 0)
    |> unique_constraint([:voting_session_id, :game_id])
  end

  def twitch_reward_changeset(voting_session_game, attrs) do
    voting_session_game
    |> cast(attrs, [
      :twitch_reward_id,
      :twitch_reward_title,
      :twitch_reward_cost,
      :twitch_reward_status,
      :twitch_reward_deletion_status,
      :twitch_reward_deletion_error,
      :twitch_reward_deleted_at
    ])
    |> validate_required([
      :twitch_reward_id,
      :twitch_reward_title,
      :twitch_reward_cost,
      :twitch_reward_status
    ])
    |> validate_number(:twitch_reward_cost, greater_than: 0)
    |> unique_constraint(:twitch_reward_id)
  end

  def clear_twitch_reward_changeset(voting_session_game) do
    change(voting_session_game, %{
      twitch_reward_status: "deleted",
      twitch_reward_deletion_status: "deleted",
      twitch_reward_deletion_error: nil,
      twitch_reward_deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  def twitch_reward_deleting_changeset(voting_session_game) do
    change(voting_session_game, %{
      twitch_reward_deletion_status: "deleting",
      twitch_reward_deletion_error: nil
    })
  end

  def twitch_reward_deletion_failed_changeset(voting_session_game, reason) do
    change(voting_session_game, %{
      twitch_reward_deletion_status: "failed",
      twitch_reward_deletion_error: inspect(reason),
      twitch_reward_deleted_at: nil
    })
  end
end
