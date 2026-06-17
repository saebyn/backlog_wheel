defmodule BacklogWheel.Communities do
  @moduledoc """
  The Communities context.
  """

  import Ecto.Query, warn: false

  alias BacklogWheel.Accounts
  alias BacklogWheel.Accounts.User
  alias BacklogWheel.Communities.{Community, CommunityMembership}
  alias BacklogWheel.Communities.Theme
  alias BacklogWheel.Repo
  alias BacklogWheel.Voting

  def get_community!(id), do: Repo.get!(Community, id)

  @doc """
  Returns the first community used for public/default app views.
  """
  def default_community do
    Community
    |> order_by([community], asc: community.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Returns CSS custom properties for the built-in public page theme.
  """
  def default_theme_style do
    %{}
    |> Theme.resolve()
    |> Theme.style()
  end

  @doc """
  Returns a changeset for first-run community onboarding.
  """
  def change_initial_community(attrs \\ %{}) do
    Community.onboarding_changeset(%Community{}, attrs)
  end

  @doc """
  Creates a user's initial owned community and starter data.
  """
  def create_initial_community(%User{} = user, attrs) do
    if Accounts.signup_allowed?(user) do
      do_create_initial_community(user, attrs)
    else
      {:error, :signup_not_allowed}
    end
  end

  defp do_create_initial_community(%User{} = user, attrs) do
    changeset = change_initial_community(attrs)

    if changeset.valid? do
      community_attrs =
        attrs
        |> normalize_attrs()
        |> Map.put("slug", unique_slug(Ecto.Changeset.get_field(changeset, :name)))

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:community, Community.changeset(%Community{}, community_attrs))
      |> Ecto.Multi.insert(:membership, fn %{community: community} ->
        CommunityMembership.changeset(%CommunityMembership{}, %{
          user_id: user.id,
          community_id: community.id,
          role: "owner"
        })
      end)
      |> Ecto.Multi.run(:wheel_formats, fn _repo, %{community: community} ->
        Voting.ensure_default_wheel_formats(community)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{community: community}} -> {:ok, community}
        {:error, :community, changeset, _changes} -> {:error, changeset}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    else
      {:error, %{changeset | action: :insert}}
    end
  end

  @doc """
  Creates a membership connecting a user to a community.
  """
  def create_membership(%User{} = user, %Community{} = community, role) when is_binary(role) do
    if Accounts.signup_allowed?(user) do
      %CommunityMembership{}
      |> CommunityMembership.changeset(%{
        user_id: user.id,
        community_id: community.id,
        role: role
      })
      |> Repo.insert()
    else
      {:error, :signup_not_allowed}
    end
  end

  defp normalize_attrs(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end

  defp unique_slug(name) do
    base_slug = slugify(name)

    Stream.iterate(0, &(&1 + 1))
    |> Stream.map(fn
      0 -> base_slug
      suffix -> "#{base_slug}-#{suffix}"
    end)
    |> Enum.find(fn slug ->
      not Repo.exists?(from community in Community, where: community.slug == ^slug)
    end)
  end

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "community"
      slug -> slug
    end
  end

  @doc """
  Returns the first owner/admin community for authenticated app access.
  """
  def current_admin_community_for_user(%User{} = user) do
    Community
    |> join(:inner, [community], membership in assoc(community, :memberships))
    |> where([_community, membership], membership.user_id == ^user.id)
    |> where([_community, membership], membership.role in ^CommunityMembership.admin_roles())
    |> order_by([community, membership], asc: membership.id, asc: community.id)
    |> limit(1)
    |> Repo.one()
  end

  def current_admin_community_for_user(nil), do: nil

  @doc """
  Returns a changeset for editing general community settings.
  """
  def change_community_general_settings(%Community{} = community, attrs \\ %{}) do
    Community.general_settings_changeset(community, attrs)
  end

  @doc """
  Updates general community settings.
  """
  def update_community_general_settings(%Community{} = community, attrs) do
    community
    |> Community.general_settings_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns a changeset for editing community theme settings.
  """
  def change_community_theme(%Community{} = community, attrs \\ %{}) do
    Community.theme_changeset(community, attrs)
  end

  @doc """
  Updates community theme settings.
  """
  def update_community_theme(%Community{} = community, attrs) do
    community
    |> Community.theme_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns a changeset for editing community Steam credentials.
  """
  def change_community_steam_credential(%Community{} = community, attrs \\ %{}) do
    Community.steam_credential_changeset(community, attrs)
  end

  @doc """
  Updates community Steam credentials.
  """
  def update_community_steam_credential(%Community{} = community, attrs) do
    community
    |> Community.steam_credential_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns a changeset for editing community Twitch settings.
  """
  def change_community_twitch_settings(%Community{} = community, attrs \\ %{}) do
    Community.twitch_settings_changeset(community, attrs)
  end

  @doc """
  Updates community Twitch settings.
  """
  def update_community_twitch_settings(%Community{} = community, attrs) do
    community
    |> Community.twitch_settings_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns the community configured for a Twitch broadcaster ID.
  """
  def get_community_by_twitch_broadcaster_id(nil), do: nil
  def get_community_by_twitch_broadcaster_id(""), do: nil

  def get_community_by_twitch_broadcaster_id(broadcaster_id) when is_binary(broadcaster_id) do
    Repo.get_by(Community, twitch_broadcaster_id: broadcaster_id)
  end

  @doc """
  Returns whether a community has enough Steam credential data to import games.
  """
  def steam_configured?(%Community{} = community) do
    community.steam_api_key not in [nil, ""] and community.steam_id64 not in [nil, ""]
  end

  @doc """
  Clears custom community theme settings so defaults are used.
  """
  def reset_community_theme(%Community{} = community) do
    theme_attrs = Map.new(Theme.color_fields(), &{&1, nil})

    update_community_theme(community, theme_attrs)
  end

  @doc """
  Returns the resolved light and dark theme values for a community.
  """
  def resolved_theme(%Community{} = community) do
    Theme.resolve(community)
  end

  @doc """
  Returns CSS custom properties for the resolved community theme.
  """
  def theme_style(%Community{} = community) do
    community
    |> resolved_theme()
    |> Theme.style()
  end
end
