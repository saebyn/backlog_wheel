defmodule BacklogWheel.CommunitiesTest do
  use BacklogWheel.DataCase

  alias BacklogWheel.Communities
  alias BacklogWheel.Communities.Community

  import BacklogWheel.BacklogFixtures

  describe "communities" do
    test "slug is unique" do
      community_fixture(%{name: "Original", slug: "duplicate"})

      assert {:error, changeset} =
               %Community{}
               |> Community.changeset(%{name: "Duplicate", slug: "duplicate"})
               |> Repo.insert()

      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "community general settings" do
    test "updates name and normalized slug" do
      community = community_fixture()

      assert {:ok, %Community{} = community} =
               Communities.update_community_general_settings(community, %{
                 "name" => "New Community Name",
                 "slug" => "New Community Name!"
               })

      assert community.name == "New Community Name"
      assert community.slug == "new-community-name"
    end

    test "requires a valid slug" do
      community = community_fixture()

      changeset =
        Communities.change_community_general_settings(community, %{
          "name" => "New Community Name",
          "slug" => "!"
        })

      assert %{slug: ["can't be blank"]} = errors_on(changeset)
    end

    test "enforces unique slugs" do
      community_fixture(%{slug: "taken-slug"})
      community = community_fixture()

      assert {:error, changeset} =
               Communities.update_community_general_settings(community, %{
                 "name" => "Duplicate Slug",
                 "slug" => "taken-slug"
               })

      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "default theme" do
    test "returns CSS custom properties without a persisted community" do
      style = Communities.default_theme_style()

      assert style =~ "--theme-light-primary:"
      assert style =~ "--theme-dark-background:"
      refute Repo.get_by(Community, slug: "default")
    end
  end

  describe "community theme" do
    test "updates theme settings" do
      community = community_fixture()

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
      community = community_fixture()

      assert {:ok, community} =
               Communities.update_community_theme(community, %{
                 "light_primary_color" => "  ",
                 "dark_accent_color" => ""
               })

      assert community.light_primary_color == nil
      assert community.dark_accent_color == nil
    end

    test "rejects invalid colors" do
      community = community_fixture()

      changeset =
        Communities.change_community_theme(community, %{"light_primary_color" => "orange"})

      assert %{light_primary_color: ["must be a hex color"]} = errors_on(changeset)
    end

    test "resolves missing dark colors from light colors" do
      community = community_fixture()

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
      community = community_fixture()

      assert {:ok, community} =
               Communities.update_community_theme(community, %{
                 "light_primary_color" => "#336699",
                 "dark_primary_color" => "#ff00ff"
               })

      assert Communities.resolved_theme(community).dark.primary == "#ff00ff"
    end

    test "returns CSS custom properties" do
      community = community_fixture()

      assert {:ok, community} =
               Communities.update_community_theme(community, %{
                 "light_primary_color" => "#123abc"
               })

      style = Communities.theme_style(community)

      assert style =~ "--theme-light-primary: #123abc;"
      assert style =~ "--theme-dark-background:"
    end

    test "resets theme settings" do
      community = community_fixture()

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

  describe "community Steam credentials" do
    test "updates Steam credentials" do
      community = community_fixture()

      assert {:ok, %Community{} = community} =
               Communities.update_community_steam_credential(community, %{
                 "steam_api_key" => "api-key",
                 "steam_id64" => "76561198000000000"
               })

      assert community.steam_api_key == "api-key"
      assert community.steam_id64 == "76561198000000000"
      assert Communities.steam_configured?(community)
    end

    test "normalizes blank Steam credential fields to nil" do
      community = community_fixture()

      assert {:ok, community} =
               Communities.update_community_steam_credential(community, %{
                 "steam_api_key" => "  ",
                 "steam_id64" => ""
               })

      assert community.steam_api_key == nil
      assert community.steam_id64 == nil
      refute Communities.steam_configured?(community)
    end

    test "requires both Steam credential fields when one is present" do
      community = community_fixture()

      changeset =
        Communities.change_community_steam_credential(community, %{"steam_api_key" => "api-key"})

      assert %{steam_id64: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "community Twitch settings" do
    test "updates Twitch settings" do
      community = community_fixture()

      assert {:ok, %Community{} = community} =
               Communities.update_community_twitch_settings(community, %{
                 "twitch_broadcaster_id" => "28728577",
                 "twitch_eventsub_secret" => "eventsub-secret",
                 "twitch_reward_cost" => "250"
               })

      assert community.twitch_broadcaster_id == "28728577"
      assert community.twitch_eventsub_secret == "eventsub-secret"
      assert community.twitch_reward_cost == 250
      assert Communities.get_community_by_twitch_broadcaster_id("28728577").id == community.id
    end

    test "normalizes blank Twitch optional fields to nil" do
      community = community_fixture()

      assert {:ok, community} =
               Communities.update_community_twitch_settings(community, %{
                 "twitch_broadcaster_id" => "  ",
                 "twitch_eventsub_secret" => ""
               })

      assert community.twitch_broadcaster_id == nil
      assert community.twitch_eventsub_secret == nil
    end

    test "requires positive reward cost" do
      community = community_fixture()

      changeset =
        Communities.change_community_twitch_settings(community, %{"twitch_reward_cost" => "0"})

      assert %{twitch_reward_cost: ["must be greater than 0"]} = errors_on(changeset)
    end
  end

  describe "memberships" do
    test "resolves the first owner/admin community for a user" do
      user = user_fixture()
      viewer_community = community_fixture(%{slug: "viewer-only"})
      admin_community = community_fixture(%{slug: "admin-community"})

      assert {:ok, _membership} = Communities.create_membership(user, viewer_community, "viewer")
      assert {:ok, _membership} = Communities.create_membership(user, admin_community, "admin")

      assert Communities.current_admin_community_for_user(user).id == admin_community.id
    end

    test "ignores users with only viewer membership" do
      user = user_fixture()
      community = community_fixture(%{slug: "viewer-community"})

      assert {:ok, _membership} = Communities.create_membership(user, community, "viewer")
      assert Communities.current_admin_community_for_user(user) == nil
    end

    test "blocks membership creation for unallowlisted users" do
      original_allowlist = Application.get_env(:backlog_wheel, :signup_allowed_discord_ids)
      Application.put_env(:backlog_wheel, :signup_allowed_discord_ids, "approved-discord")

      on_exit(fn -> restore_env(:signup_allowed_discord_ids, original_allowlist) end)

      user = user_fixture(%{discord_id: "unapproved-discord"})
      community = community_fixture()

      assert {:error, :signup_not_allowed} =
               Communities.create_membership(user, community, "owner")
    end
  end

  describe "initial community" do
    test "blocks community creation for unallowlisted users" do
      original_allowlist = Application.get_env(:backlog_wheel, :signup_allowed_discord_ids)
      Application.put_env(:backlog_wheel, :signup_allowed_discord_ids, "approved-discord")

      on_exit(fn -> restore_env(:signup_allowed_discord_ids, original_allowlist) end)

      user = user_fixture(%{discord_id: "unapproved-discord"})

      assert {:error, :signup_not_allowed} =
               Communities.create_initial_community(user, %{"name" => "Blocked Community"})

      refute Repo.get_by(Community, name: "Blocked Community")
    end
  end

  defp user_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        discord_id: "discord-#{System.unique_integer([:positive])}",
        username: "Test User",
        role: "admin"
      })

    %BacklogWheel.Accounts.User{}
    |> BacklogWheel.Accounts.User.changeset(attrs)
    |> Repo.insert!()
  end

  defp restore_env(key, nil), do: Application.delete_env(:backlog_wheel, key)
  defp restore_env(key, value), do: Application.put_env(:backlog_wheel, key, value)
end
