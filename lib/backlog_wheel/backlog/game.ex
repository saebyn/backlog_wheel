defmodule BacklogWheel.Backlog.Game do
  use Ecto.Schema
  import Ecto.Changeset

  alias BacklogWheel.Backlog.{GameTag, Spin}
  alias BacklogWheel.Communities.Community
  alias BacklogWheel.Voting.VotingSessionGame

  schema "games" do
    field :title, :string
    field :platform, :string, default: "manual"
    field :external_id, :string
    field :image_url, :string
    field :include_in_wheel, :boolean, default: false
    field :played_on_stream, :boolean, default: false
    field :last_played_at, :utc_datetime
    field :tag_names, :string, virtual: true

    belongs_to :community, Community
    has_many :spins, Spin
    has_many :voting_session_games, VotingSessionGame
    many_to_many :tags, GameTag, join_through: "game_taggings", on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(game, attrs) do
    game
    |> cast(attrs, [
      :title,
      :platform,
      :external_id,
      :image_url,
      :include_in_wheel,
      :played_on_stream,
      :last_played_at,
      :tag_names
    ])
    |> validate_required([:title, :community_id])
    |> unique_constraint([:community_id, :platform, :external_id],
      name: :games_community_platform_external_id_index
    )
  end
end
