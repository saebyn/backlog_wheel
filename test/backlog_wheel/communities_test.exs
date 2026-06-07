defmodule BacklogWheel.CommunitiesTest do
  use BacklogWheel.DataCase

  alias BacklogWheel.Communities
  alias BacklogWheel.Communities.Community

  describe "default community" do
    test "exists in data case setup" do
      assert %Community{name: "Default Community", slug: "default"} =
               Communities.get_default_community!()
    end

    test "get_or_create_default_community/0 returns the default community" do
      assert %Community{name: "Default Community", slug: "default"} =
               Communities.get_or_create_default_community()
    end

    test "get_or_create_default_community/0 does not duplicate the default community" do
      first = Communities.get_or_create_default_community()
      second = Communities.get_or_create_default_community()

      assert first.id == second.id
      assert Repo.aggregate(Community, :count, :id) == 1
    end

    test "slug is unique" do
      assert {:error, changeset} =
               %Community{}
               |> Community.changeset(%{name: "Duplicate", slug: "default"})
               |> Repo.insert()

      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end
  end
end
