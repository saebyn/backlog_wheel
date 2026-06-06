defmodule BacklogWheelWeb.GameLive.Index do
  use BacklogWheelWeb, :live_view

  alias BacklogWheel.Backlog

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Games
        <:actions>
          <.button navigate={~p"/games/import/steam"}>Import Steam</.button>
          <.button variant="primary" navigate={~p"/games/new"}>
            <.icon name="hero-plus" /> New Game
          </.button>
        </:actions>
      </.header>

      <.table
        id="games"
        rows={@streams.games}
        row_click={fn {_id, game} -> JS.navigate(~p"/games/#{game}") end}
      >
        <:col :let={{_id, game}} label="Title">{game.title}</:col>
        <:col :let={{_id, game}} label="Platform">{game.platform}</:col>
        <:col :let={{_id, game}} label="External">{game.external_id}</:col>
        <:col :let={{_id, game}} label="Wheel candidate">
          <.button phx-click={JS.push("toggle_include", value: %{id: game.id})}>
            {if game.include_in_wheel, do: "Included", else: "Excluded"}
          </.button>
        </:col>
        <:col :let={{_id, game}} label="Played on stream">{game.played_on_stream}</:col>
        <:col :let={{_id, game}} label="Last played">
          <span title={format_utc_datetime(game.last_played_at)}>
            {format_last_played(game.last_played_at)}
          </span>
        </:col>
        <:action :let={{_id, game}}>
          <div class="sr-only">
            <.link navigate={~p"/games/#{game}"}>Show</.link>
          </div>
          <.link navigate={~p"/games/#{game}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, game}}>
          <.link
            phx-click={JS.push("delete", value: %{id: game.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Games")
     |> stream(:games, list_games())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    game = Backlog.get_game!(id)
    {:ok, _} = Backlog.delete_game(game)

    {:noreply, stream_delete(socket, :games, game)}
  end

  @impl true
  def handle_event("toggle_include", %{"id" => id}, socket) do
    game = Backlog.get_game!(id)
    {:ok, game} = Backlog.toggle_game_include_in_wheel(game)

    {:noreply, stream_insert(socket, :games, game)}
  end

  defp list_games() do
    Backlog.list_games()
  end

  defp format_last_played(nil), do: "Never"

  defp format_last_played(%DateTime{} = datetime) do
    "#{format_local_datetime(datetime)} (#{format_time_ago(datetime)} ago)"
  end

  defp format_local_datetime(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_unix(:second)
    |> :calendar.system_time_to_local_time(:second)
    |> NaiveDateTime.from_erl!()
    |> Calendar.strftime("%Y-%m-%d %H:%M")
  end

  defp format_utc_datetime(nil), do: "Never played"

  defp format_utc_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")
  end

  defp format_time_ago(%DateTime{} = datetime) do
    seconds = max(DateTime.diff(DateTime.utc_now(), datetime, :second), 0)

    cond do
      seconds < 60 ->
        "just now"

      seconds < 3_600 ->
        "#{div(seconds, 60)}m"

      seconds < 86_400 ->
        "#{div(seconds, 3_600)}h"

      true ->
        days = div(seconds, 86_400)
        years = div(days, 365)
        remaining_days = rem(days, 365)

        if years > 0 do
          "#{years}y #{remaining_days}d"
        else
          "#{days}d"
        end
    end
  end
end
