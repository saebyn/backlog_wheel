defmodule BacklogWheelWeb.GameLive.Show do
  use BacklogWheelWeb, :live_view

  alias BacklogWheel.Backlog

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
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

      <.list>
        <:item title="Title">{@game.title}</:item>
        <:item title="Platform">{@game.platform}</:item>
        <:item title="External ID">{@game.external_id}</:item>
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
