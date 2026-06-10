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

  describe "community theme" do
    test "updates theme settings" do
      community = Communities.get_default_community!()

      assert {:ok, %Community{} = community} =
               Communities.update_community_theme(community, %{
                 "light_primary_color" => "#123abc",
                 "light_accent_color" => "#abcdef",
                 "light_background_color" => "#f8fafc"
               })

      assert community.light_primary_color == "#123abc"
      assert community.light_accent_color == "#abcdef"
      assert community.light_background_color == "#f8fafc"
    end

    test "normalizes blank theme fields to nil" do
      community = Communities.get_default_community!()

      assert {:ok, community} =
               Communities.update_community_theme(community, %{
                 "light_primary_color" => "  ",
                 "dark_accent_color" => ""
               })

      assert community.light_primary_color == nil
      assert community.dark_accent_color == nil
    end

    test "rejects invalid colors" do
      community = Communities.get_default_community!()

      changeset =
        Communities.change_community_theme(community, %{"light_primary_color" => "orange"})

      assert %{light_primary_color: ["must be a hex color"]} = errors_on(changeset)
    end

    test "resolves missing dark colors from light colors" do
      community = Communities.get_default_community!()

      assert {:ok, community} =
               Communities.update_community_theme(community, %{
                 "light_primary_color" => "#336699",
                 "light_accent_color" => "#cc33aa",
                 "light_background_color" => "#f9fafb"
               })

      theme = Communities.resolved_theme(community)

      assert theme.light.primary == "#336699"
      assert theme.dark.primary != nil
      assert theme.dark.primary != theme.light.primary
      assert theme.dark.background != theme.light.background
    end

    test "explicit dark overrides derived colors" do
      community = Communities.get_default_community!()

      assert {:ok, community} =
               Communities.update_community_theme(community, %{
                 "light_primary_color" => "#336699",
                 "dark_primary_color" => "#ff00ff"
               })

      assert Communities.resolved_theme(community).dark.primary == "#ff00ff"
    end

    test "returns CSS custom properties" do
      community = Communities.get_default_community!()

      assert {:ok, community} =
               Communities.update_community_theme(community, %{
                 "light_primary_color" => "#123abc"
               })

      style = Communities.theme_style(community)

      assert style =~ "--theme-light-primary: #123abc;"
      assert style =~ "--theme-dark-background:"
    end

    test "resets theme settings" do
      community = Communities.get_default_community!()

      assert {:ok, community} =
               Communities.update_community_theme(community, %{
                 "light_primary_color" => "#123abc",
                 "dark_background_color" => "#111827"
               })

      assert {:ok, community} = Communities.reset_community_theme(community)

      assert community.light_primary_color == nil
      assert community.dark_background_color == nil
    end
  end
end
