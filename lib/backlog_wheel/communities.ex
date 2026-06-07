defmodule BacklogWheel.Communities do
  @moduledoc """
  The Communities context.
  """

  alias BacklogWheel.Communities.Community
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

  defp default_community_attrs do
    %{name: "Default Community", slug: @default_slug}
  end
end
