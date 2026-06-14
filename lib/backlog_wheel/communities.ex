defmodule BacklogWheel.Communities do
  @moduledoc """
  The Communities context.
  """

  import Ecto.Query, warn: false

  alias BacklogWheel.Accounts.User
  alias BacklogWheel.Communities.{Community, CommunityMembership}
  alias BacklogWheel.Communities.Theme
  alias BacklogWheel.Repo

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
  Creates a membership connecting a user to a community.
  """
  def create_membership(%User{} = user, %Community{} = community, role) when is_binary(role) do
    %CommunityMembership{}
    |> CommunityMembership.changeset(%{user_id: user.id, community_id: community.id, role: role})
    |> Repo.insert()
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
