defmodule BacklogWheel.AccountsTest do
  use BacklogWheel.DataCase, async: false

  alias BacklogWheel.Accounts
  alias BacklogWheel.Accounts.User
  alias BacklogWheel.Repo

  test "sync_discord_user/1 updates existing users and preserves role" do
    user =
      %User{}
      |> User.changeset(%{
        discord_id: "discord-user-1",
        username: "Old User",
        avatar_hash: "old",
        role: "admin"
      })
      |> Repo.insert!()

    assert {:ok, updated_user} =
             Accounts.sync_discord_user(%{
               "id" => "discord-user-1",
               "username" => "new-user",
               "avatar" => "new"
             })

    assert updated_user.id == user.id
    assert updated_user.username == "new-user"
    assert updated_user.avatar_hash == "new"
    assert updated_user.role == "admin"
  end

  test "sync_discord_user/1 rejects Discord users missing from the database" do
    assert Accounts.sync_discord_user(%{"id" => "missing", "username" => "Missing"}) ==
             {:error, :unauthorized}
  end
end
