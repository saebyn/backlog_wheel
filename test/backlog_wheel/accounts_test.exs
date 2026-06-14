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

  test "sync_discord_user/1 creates allowlisted Discord users" do
    original_allowlist = Application.get_env(:backlog_wheel, :signup_allowed_discord_ids)
    Application.put_env(:backlog_wheel, :signup_allowed_discord_ids, "new-user")
    on_exit(fn -> restore_env(:signup_allowed_discord_ids, original_allowlist) end)

    assert {:ok, user} = Accounts.sync_discord_user(%{"id" => "new-user", "username" => "New"})

    assert user.discord_id == "new-user"
    assert user.username == "New"
    assert user.role == "admin"
  end

  test "sync_discord_user/1 rejects unallowlisted Discord users" do
    original_allowlist = Application.get_env(:backlog_wheel, :signup_allowed_discord_ids)
    Application.put_env(:backlog_wheel, :signup_allowed_discord_ids, "approved-user")
    on_exit(fn -> restore_env(:signup_allowed_discord_ids, original_allowlist) end)

    assert Accounts.sync_discord_user(%{"id" => "missing", "username" => "Missing"}) ==
             {:error, :signup_not_allowed}
  end

  defp restore_env(key, nil), do: Application.delete_env(:backlog_wheel, key)
  defp restore_env(key, value), do: Application.put_env(:backlog_wheel, key, value)
end
