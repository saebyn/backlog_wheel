defmodule BacklogWheel.QuickWheels do
  use Ecto.Schema
  import Ecto.Query
  alias BacklogWheel.Repo

  schema "quick_wheels" do
    belongs_to :user, BacklogWheel.Accounts.User
    field :preset, :boolean, default: false
    field :title, :string, default: "Quick Wheel"
    field :entries, {:array, :string}, default: []
    field :revision, :integer, default: 1
  end

  def current(user_id) do
    Repo.insert!(%__MODULE__{user_id: user_id}, on_conflict: :nothing)
    Repo.get_by!(__MODULE__, user_id: user_id, preset: false)
  end

  def presets(user_id) do
    Repo.all(from w in __MODULE__, where: w.user_id == ^user_id and w.preset, order_by: w.id)
  end

  def preset!(user_id, id), do: Repo.get_by!(__MODULE__, user_id: user_id, preset: true, id: id)

  def create_preset(user_id, title, entries) do
    Repo.insert!(%__MODULE__{user_id: user_id, preset: true, title: title, entries: entries})
  end

  def save(wheel, title, entries) do
    query = from w in __MODULE__, where: w.id == ^wheel.id and w.revision == ^wheel.revision

    case Repo.update_all(query, set: [title: title, entries: entries], inc: [revision: 1]) do
      {1, _} -> {:ok, %{wheel | title: title, entries: entries, revision: wheel.revision + 1}}
      {0, _} -> :stale
    end
  end
end
