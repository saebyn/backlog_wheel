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

  @spec sync_discord_user(map()) :: {:ok, User.t()} | {:error, :unauthorized | Ecto.Changeset.t()}
  def sync_discord_user(%{"id" => discord_id} = discord_user) do
    case get_user_by_discord_id(discord_id) do
      nil ->
        {:error, :unauthorized}

      user ->
        user
        |> User.changeset(%{
          username: discord_username(discord_user),
          avatar_hash: Map.get(discord_user, "avatar")
        })
        |> Repo.update()
    end
  end

  defp discord_username(%{"global_name" => name}) when is_binary(name) and name != "", do: name
  defp discord_username(%{"username" => username}) when is_binary(username), do: username
end
