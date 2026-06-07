defmodule BacklogWheelWeb.VotingSessionLive.Index do
  use BacklogWheelWeb, :live_view

  alias BacklogWheel.Backlog
  alias BacklogWheel.Voting
  alias BacklogWheel.Voting.VotingSession

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} wide>
      <div class="grid gap-6 lg:grid-cols-[20rem_1fr]">
        <aside class="space-y-4 rounded-[2rem] border border-base-300 bg-base-100 p-5 shadow-xl">
          <.header>
            Voting Sessions
            <:subtitle>Create and manage local voting pools before Twitch integration.</:subtitle>
            <:actions>
              <.button id="create-voting-session" variant="primary" phx-click="create_session">
                <.icon name="hero-plus" /> New Session
              </.button>
            </:actions>
          </.header>

          <div id="voting-sessions" phx-update="stream" class="space-y-2">
            <p
              id="empty-voting-sessions"
              class="hidden rounded-xl bg-base-200 p-4 text-sm text-base-content/70 only:block"
            >
              No voting sessions yet.
            </p>
            <button
              :for={{id, session} <- @streams.voting_sessions}
              id={id}
              type="button"
              phx-click="select_session"
              phx-value-id={session.id}
              class={session_button_class(session, @selected_session)}
            >
              <span class="font-semibold">Session #{session.id}</span>
              <span class="badge badge-ghost capitalize">{session.status}</span>
              <span class="text-xs text-base-content/60">
                {length(session.voting_session_games)} games
              </span>
            </button>
          </div>
        </aside>

        <section class="min-h-[32rem] rounded-[2rem] border border-base-300 bg-base-100 p-5 shadow-xl">
          <div
            :if={!@selected_session}
            id="voting-session-empty"
            class="grid min-h-96 place-items-center text-center"
          >
            <div>
              <p class="text-sm font-semibold uppercase tracking-[0.24em] text-primary">No Session</p>
              <h1 class="mt-3 text-4xl font-black tracking-tight">Create a voting session</h1>
              <p class="mt-3 text-base-content/70">
                Start with the current wheel candidates, then adjust the pool locally.
              </p>
            </div>
          </div>

          <div :if={@selected_session} id="voting-session-detail" class="space-y-6">
            <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
              <div>
                <p class="text-sm font-semibold uppercase tracking-[0.24em] text-primary">
                  Session #{@selected_session.id}
                </p>
                <h1 class="mt-2 text-4xl font-black tracking-tight">Voting Pool</h1>
                <div class="mt-3 flex flex-wrap gap-2">
                  <span id="selected-session-status" class="badge badge-primary capitalize">
                    {@selected_session.status}
                  </span>
                  <span id="selected-session-pool-size" class="badge badge-ghost">
                    {@pool_size} pool games
                  </span>
                </div>
              </div>

              <div class="flex flex-wrap gap-2">
                <.button id="populate-session-pool" phx-click="populate_pool">
                  Populate from wheel
                </.button>
                <.button
                  id="spin-selected-voting-session"
                  navigate={~p"/wheel?#{[voting_session_id: @selected_session.id]}"}
                  disabled={@pool_size == 0}
                >
                  Spin this pool
                </.button>
                <.button
                  :for={status <- ["draft", "open", "locked", "closed", "cancelled"]}
                  id={"set-session-#{status}"}
                  phx-click="set_status"
                  phx-value-status={status}
                  disabled={@selected_session.status == status}
                >
                  {status_label(status)}
                </.button>
              </div>
            </div>

            <div class="grid gap-6 xl:grid-cols-[1fr_22rem]">
              <section class="space-y-3">
                <h2 class="text-xl font-bold">Session Pool</h2>
                <div id="voting-session-pool" phx-update="stream" class="grid gap-3 md:grid-cols-2">
                  <p
                    id="empty-session-pool"
                    class="hidden rounded-2xl bg-base-200 p-5 text-base-content/70 only:block md:col-span-2"
                  >
                    No games in this voting pool yet.
                  </p>
                  <article
                    :for={{id, pool_item} <- @streams.voting_session_pool}
                    id={id}
                    class="rounded-2xl border border-base-300 bg-base-200 p-4"
                  >
                    <div class="flex items-start justify-between gap-3">
                      <div>
                        <h3 class="font-bold leading-tight">{pool_item.game.title}</h3>
                        <div class="mt-3 grid grid-cols-3 gap-2 text-center text-xs">
                          <div class="rounded-xl bg-base-100 p-2">
                            <p class="font-semibold uppercase tracking-wide text-base-content/50">
                              Base
                            </p>
                            <p id={"pool-game-base-weight-#{pool_item.id}"} class="text-lg font-black">
                              {pool_item.base_weight}
                            </p>
                          </div>
                          <div class="rounded-xl bg-base-100 p-2">
                            <p class="font-semibold uppercase tracking-wide text-base-content/50">
                              Boosts
                            </p>
                            <p
                              id={"pool-game-boost-total-#{pool_item.id}"}
                              class="text-lg font-black text-primary"
                            >
                              +{pool_item.boost_total}
                            </p>
                          </div>
                          <div class="rounded-xl bg-base-100 p-2">
                            <p class="font-semibold uppercase tracking-wide text-base-content/50">
                              Final
                            </p>
                            <p
                              id={"pool-game-final-weight-#{pool_item.id}"}
                              class="text-lg font-black"
                            >
                              {pool_item.final_weight}
                            </p>
                          </div>
                        </div>
                      </div>
                      <div class="flex shrink-0 flex-col gap-2">
                        <.button
                          id={"boost-pool-game-#{pool_item.id}"}
                          phx-click="boost_pool_game"
                          phx-value-id={pool_item.id}
                        >
                          +1 Boost
                        </.button>
                        <.button
                          id={"remove-pool-game-#{pool_item.id}"}
                          phx-click="remove_pool_game"
                          phx-value-id={pool_item.id}
                          data-confirm="Remove this game from the voting pool?"
                        >
                          Remove
                        </.button>
                      </div>
                    </div>
                  </article>
                </div>
              </section>

              <section class="space-y-3 rounded-2xl border border-base-300 bg-base-200 p-4">
                <h2 class="text-xl font-bold">Available Games</h2>
                <p class="text-sm text-base-content/70">
                  Add or remove games here without changing wheel eligibility.
                </p>
                <div id="available-voting-games" phx-update="stream" class="space-y-2">
                  <p
                    id="empty-available-voting-games"
                    class="hidden rounded-xl bg-base-100 p-4 text-sm text-base-content/70 only:block"
                  >
                    Every game is already in this pool.
                  </p>
                  <div
                    :for={{id, game} <- @streams.available_games}
                    id={id}
                    class="flex items-center justify-between gap-3 rounded-xl bg-base-100 p-3"
                  >
                    <div>
                      <p class="font-semibold leading-tight">{game.title}</p>
                      <p class="text-xs text-base-content/60">
                        {if game.include_in_wheel, do: "Wheel eligible", else: "Not on wheel"}
                      </p>
                    </div>
                    <.button
                      id={"add-session-game-#{game.id}"}
                      phx-click="add_pool_game"
                      phx-value-id={game.id}
                    >
                      Add
                    </.button>
                  </div>
                </div>
              </section>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Voting Sessions")
     |> assign(:selected_session_id, nil)
     |> refresh()}
  end

  @impl true
  def handle_event("create_session", _params, socket) do
    {:ok, session} = Voting.create_voting_session()

    {:noreply,
     socket
     |> assign(:selected_session_id, session.id)
     |> put_flash(:info, "Voting session created")
     |> refresh()}
  end

  def handle_event("select_session", %{"id" => id}, socket) do
    {:noreply, socket |> assign(:selected_session_id, String.to_integer(id)) |> refresh()}
  end

  def handle_event("set_status", %{"status" => status}, socket) do
    {:ok, session} = Voting.update_voting_session_status(socket.assigns.selected_session, status)

    {:noreply,
     socket
     |> assign(:selected_session_id, session.id)
     |> put_flash(:info, "Session marked #{status}")
     |> refresh()}
  end

  def handle_event("populate_pool", _params, socket) do
    {:ok, pool_items} =
      Voting.populate_session_from_wheel_candidates(socket.assigns.selected_session)

    {:noreply,
     socket
     |> put_flash(:info, "Added #{length(pool_items)} wheel-eligible games")
     |> refresh()}
  end

  def handle_event("add_pool_game", %{"id" => id}, socket) do
    game = Backlog.get_game!(id)
    {:ok, _pool_item} = Voting.add_game_to_session(socket.assigns.selected_session, game)

    {:noreply, refresh(socket)}
  end

  def handle_event("remove_pool_game", %{"id" => id}, socket) do
    pool_item = Enum.find(socket.assigns.pool_items, &(&1.id == String.to_integer(id)))
    {:ok, _pool_item} = Voting.remove_game_from_session(pool_item)

    {:noreply, refresh(socket)}
  end

  def handle_event("boost_pool_game", %{"id" => id}, socket) do
    pool_item = Enum.find(socket.assigns.pool_items, &(&1.id == String.to_integer(id)))
    {:ok, _boost} = Voting.record_boost(pool_item, %{strength: 1, source: "local"})

    {:noreply, refresh(socket)}
  end

  defp refresh(socket) do
    sessions = Voting.list_voting_sessions()
    selected_session = selected_session(sessions, socket.assigns.selected_session_id)
    pool_items = if selected_session, do: selected_session.voting_session_games, else: []

    available_games =
      if selected_session, do: Voting.list_available_games_for_session(selected_session), else: []

    socket
    |> assign(:selected_session, selected_session)
    |> assign(:selected_session_id, selected_session && selected_session.id)
    |> assign(:pool_items, pool_items)
    |> assign(:pool_size, length(pool_items))
    |> stream(:voting_sessions, sessions, reset: true)
    |> stream(:voting_session_pool, pool_items, reset: true)
    |> stream(:available_games, available_games, reset: true)
  end

  defp selected_session([], _selected_session_id), do: nil

  defp selected_session(sessions, nil), do: hd(sessions)

  defp selected_session(sessions, selected_session_id) do
    Enum.find(sessions, &(&1.id == selected_session_id)) || hd(sessions)
  end

  defp session_button_class(%VotingSession{} = session, selected_session) do
    [
      "flex w-full items-center justify-between gap-2 rounded-xl border p-3 text-left transition hover:-translate-y-0.5 hover:shadow-md",
      selected_session && session.id == selected_session.id && "border-primary bg-primary/10",
      (!selected_session || session.id != selected_session.id) && "border-base-300 bg-base-200"
    ]
  end

  defp status_label("draft"), do: "Draft"
  defp status_label("open"), do: "Open"
  defp status_label("locked"), do: "Lock"
  defp status_label("closed"), do: "Close"
  defp status_label("cancelled"), do: "Cancel"
end
