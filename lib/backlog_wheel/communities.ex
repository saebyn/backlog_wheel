defmodule BacklogWheel.Communities do
  @moduledoc """
  The Communities context.
  """

  alias BacklogWheel.Communities.Community
  alias BacklogWheel.Communities.Theme
  alias BacklogWheel.Repo

  @default_slug "default"

  @doc """
  Gets the default community.
  """
  def get_default_community! do
    Repo.get_by!(Community, slug: @default_slug)
  end

  @doc """
  Gets or creates the default community for this single-community app.
  """
  def get_or_create_default_community do
    case Repo.get_by(Community, slug: @default_slug) do
      %Community{} = community ->
        community

      nil ->
        attrs = default_community_attrs()

        %Community{}
        |> Community.changeset(attrs)
        |> Repo.insert!(on_conflict: :nothing, conflict_target: :slug)

        get_default_community!()
    end
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

  defp default_community_attrs do
    %{name: "Default Community", slug: @default_slug}
  end
end
