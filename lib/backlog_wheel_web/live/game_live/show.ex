defmodule BacklogWheelWeb.GameLive.Show do
  use BacklogWheelWeb, :live_view

  alias BacklogWheel.Backlog

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        {@game.title}
        <:subtitle>Backlog game details.</:subtitle>
        <:actions>
          <.button navigate={~p"/games"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/games/#{@game}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit game
          </.button>
        </:actions>
      </.header>

      <div class="flex items-center gap-4 rounded-2xl border border-base-300 bg-base-100 p-4 shadow-sm">
        <div class="flex size-24 shrink-0 items-center justify-center overflow-hidden rounded-2xl border border-base-300 bg-base-200">
          <img
            :if={@game.image_url}
            src={@game.image_url}
            alt={@game.title}
            class="h-full w-full object-cover"
          />
          <.icon :if={!@game.image_url} name="hero-photo" class="size-10 text-base-content/40" />
        </div>
        <div>
          <p class="text-sm font-semibold uppercase tracking-wide text-base-content/60">Game image</p>
          <p class="mt-1 text-sm text-base-content/70">
            {if @game.image_url, do: @game.image_url, else: "No image URL set"}
          </p>
        </div>
      </div>

      <.list>
        <:item title="Title">{@game.title}</:item>
        <:item title="Platform">{@game.platform}</:item>
        <:item title="External ID">{@game.external_id}</:item>
        <:item title="Image URL">{@game.image_url}</:item>
        <:item title="Include in wheel">{@game.include_in_wheel}</:item>
        <:item title="Played on stream">{@game.played_on_stream}</:item>
        <:item title="Last played at">{@game.last_played_at}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Show Game")
     |> assign(:game, Backlog.get_game!(id))}
  end
end
