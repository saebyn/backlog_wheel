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

      <section
        id="games-curation"
        class="space-y-4 rounded-2xl border border-base-300 bg-base-100 p-4 shadow-sm"
      >
        <div class="grid gap-3 sm:grid-cols-4">
          <div class="rounded-xl bg-base-200 p-3">
            <p class="text-xs font-semibold uppercase tracking-wide text-base-content/60">Total</p>
            <p class="text-2xl font-bold">{@counts.total}</p>
          </div>
          <div class="rounded-xl bg-base-200 p-3">
            <p class="text-xs font-semibold uppercase tracking-wide text-base-content/60">Wheel</p>
            <p class="text-2xl font-bold">{@counts.wheel}</p>
          </div>
          <div class="rounded-xl bg-base-200 p-3">
            <p class="text-xs font-semibold uppercase tracking-wide text-base-content/60">Excluded</p>
            <p class="text-2xl font-bold">{@counts.excluded}</p>
          </div>
          <div class="rounded-xl bg-base-200 p-3">
            <p class="text-xs font-semibold uppercase tracking-wide text-base-content/60">Visible</p>
            <p class="text-2xl font-bold">{@visible_count}</p>
          </div>
        </div>

        <.form for={@filter_form} id="game-curation-form" phx-change="filter">
          <div class="grid gap-3 sm:grid-cols-[1fr_auto] sm:items-end">
            <.input
              field={@filter_form[:q]}
              type="text"
              label="Search games"
              placeholder="Search by title"
              autocomplete="off"
            />
            <.input
              field={@filter_form[:sort]}
              type="select"
              label="Sort"
              options={[
                {"Title", "title"},
                {"Last played", "last_played"},
                {"Recently added", "recently_added"},
                {"Platform", "platform"},
                {"Wheel status", "wheel"}
              ]}
            />
          </div>
        </.form>

        <div id="game-filter-pills" class="flex flex-wrap gap-2">
          <button
            :for={{label, filter} <- filter_options()}
            type="button"
            class={filter_button_class(@filters["filter"], filter)}
            phx-click="set_filter"
            phx-value-filter={filter}
          >
            {label}
          </button>
        </div>

        <div class="flex flex-wrap gap-2">
          <.button
            id="include-visible-games"
            phx-click="include_visible"
            disabled={@visible_count == 0}
          >
            Include visible
          </.button>
          <.button
            id="exclude-visible-games"
            phx-click="exclude_visible"
            disabled={@visible_count == 0}
          >
            Exclude visible
          </.button>
        </div>
      </section>

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
        <:col :let={{_id, game}} label="Played on stream">
          <.button phx-click={JS.push("toggle_played", value: %{id: game.id})}>
            {if game.played_on_stream, do: "Played", else: "Unplayed"}
          </.button>
        </:col>
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
    filters = default_filters()

    {:ok,
     socket
     |> assign(:page_title, "Listing Games")
     |> assign(:filters, filters)
     |> refresh_games()}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    game = Backlog.get_game!(id)
    {:ok, _} = Backlog.delete_game(game)

    {:noreply, refresh_games(socket)}
  end

  @impl true
  def handle_event("toggle_include", %{"id" => id}, socket) do
    game = Backlog.get_game!(id)
    {:ok, _game} = Backlog.toggle_game_include_in_wheel(game)

    {:noreply, refresh_games(socket)}
  end

  @impl true
  def handle_event("toggle_played", %{"id" => id}, socket) do
    game = Backlog.get_game!(id)
    {:ok, _game} = Backlog.toggle_game_played_on_stream(game)

    {:noreply, refresh_games(socket)}
  end

  @impl true
  def handle_event("filter", %{"filters" => filter_params}, socket) do
    filters =
      socket.assigns.filters
      |> Map.merge(Map.take(filter_params, ["q", "sort"]))
      |> normalize_filters()

    {:noreply, socket |> assign(:filters, filters) |> refresh_games()}
  end

  @impl true
  def handle_event("set_filter", %{"filter" => filter}, socket) do
    filters = socket.assigns.filters |> Map.put("filter", filter) |> normalize_filters()

    {:noreply, socket |> assign(:filters, filters) |> refresh_games()}
  end

  @impl true
  def handle_event("include_visible", _params, socket) do
    {updated_count, _} =
      Backlog.update_visible_games_include_in_wheel(socket.assigns.filters, true)

    {:noreply,
     socket
     |> put_flash(:info, "Included #{updated_count} visible games")
     |> refresh_games()}
  end

  @impl true
  def handle_event("exclude_visible", _params, socket) do
    {updated_count, _} =
      Backlog.update_visible_games_include_in_wheel(socket.assigns.filters, false)

    {:noreply,
     socket
     |> put_flash(:info, "Excluded #{updated_count} visible games")
     |> refresh_games()}
  end

  defp refresh_games(socket) do
    games = Backlog.list_games(socket.assigns.filters)

    socket
    |> assign(:filter_form, to_form(socket.assigns.filters, as: :filters))
    |> assign(:counts, Backlog.game_counts())
    |> assign(:visible_count, length(games))
    |> stream(:games, games, reset: true)
  end

  defp default_filters do
    %{"q" => "", "filter" => "all", "sort" => "title"}
  end

  defp normalize_filters(filters) do
    defaults = default_filters()

    defaults
    |> Map.merge(filters)
    |> Map.update!("q", &String.trim/1)
    |> Map.update!("filter", fn filter ->
      if filter in Enum.map(filter_options(), &elem(&1, 1)), do: filter, else: defaults["filter"]
    end)
    |> Map.update!("sort", fn sort ->
      if sort in ["title", "last_played", "recently_added", "platform", "wheel"],
        do: sort,
        else: defaults["sort"]
    end)
  end

  defp filter_options do
    [
      {"All", "all"},
      {"Wheel", "wheel"},
      {"Excluded", "excluded"},
      {"Played", "played"},
      {"Unplayed", "unplayed"},
      {"Steam", "steam"},
      {"Manual", "manual"}
    ]
  end

  defp filter_button_class(current_filter, filter) do
    [
      "btn btn-sm",
      current_filter == filter && "btn-primary",
      current_filter != filter && "btn-ghost"
    ]
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
