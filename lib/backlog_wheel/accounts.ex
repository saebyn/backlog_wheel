defmodule BacklogWheel.Accounts do
  @moduledoc """
  Streamer/admin account boundary.
  """

  alias BacklogWheel.Accounts.User
  alias BacklogWheel.Repo

  @spec get_user(integer() | String.t() | nil) :: User.t() | nil
  def get_user(nil), do: nil
  def get_user(id), do: Repo.get(User, id)

  @spec get_user_by_discord_id(String.t()) :: User.t() | nil
  def get_user_by_discord_id(discord_id), do: Repo.get_by(User, discord_id: discord_id)

  @spec signup_allowed?(User.t() | String.t() | nil) :: boolean()
  def signup_allowed?(%User{discord_id: discord_id}), do: signup_allowed?(discord_id)
  def signup_allowed?(nil), do: false

  def signup_allowed?(discord_id) when is_binary(discord_id) do
    allowed_ids = signup_allowed_discord_ids()
    allowed_ids == :all or MapSet.member?(allowed_ids, discord_id)
  end

  @spec sync_discord_user(map()) ::
          {:ok, User.t()} | {:error, :signup_not_allowed | Ecto.Changeset.t()}
  def sync_discord_user(%{"id" => discord_id} = discord_user) do
    case get_user_by_discord_id(discord_id) do
      nil ->
        if signup_allowed?(discord_id) do
          %User{}
          |> User.changeset(%{
            discord_id: discord_id,
            username: discord_username(discord_user),
            avatar_hash: Map.get(discord_user, "avatar"),
            role: "admin"
          })
          |> Repo.insert()
        else
          {:error, :signup_not_allowed}
        end

      user ->
        user
        |> User.changeset(%{
          username: discord_username(discord_user),
          avatar_hash: Map.get(discord_user, "avatar")
        })
        |> Repo.update()
    end
  end

  defp signup_allowed_discord_ids do
    :backlog_wheel
    |> Application.get_env(:signup_allowed_discord_ids, "")
    |> parse_allowed_ids()
  end

  defp parse_allowed_ids(:all), do: :all
  defp parse_allowed_ids("*"), do: :all

  defp parse_allowed_ids(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> MapSet.new()
  end

  defp parse_allowed_ids(value) when is_list(value) do
    value
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> MapSet.new()
  end

  defp discord_username(%{"global_name" => name}) when is_binary(name) and name != "", do: name
  defp discord_username(%{"username" => username}) when is_binary(username), do: username
end
