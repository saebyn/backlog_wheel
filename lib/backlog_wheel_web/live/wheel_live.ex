defmodule BacklogWheelWeb.WheelLive do
  use BacklogWheelWeb, :live_view

  alias BacklogWheel.Backlog

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="wheel-page" class="space-y-8">
        <.header>
          Wheel
          <:subtitle>Spin an equal-probability wheel from the current candidate list.</:subtitle>
          <:actions>
            <.button navigate={~p"/games"}>Curate games</.button>
          </:actions>
        </.header>

        <div class="rounded-3xl border border-base-300 bg-base-100 p-6 text-center shadow-sm">
          <p class="text-sm font-semibold uppercase tracking-[0.25em] text-base-content/60">
            Candidates
          </p>
          <p id="wheel-candidate-count" class="mt-2 text-6xl font-black">
            {@candidate_count}
          </p>
        </div>

        <div
          :if={@selected_game}
          id="wheel-result"
          class="rounded-3xl border border-primary/30 bg-primary/10 p-8 text-center shadow-sm"
        >
          <p class="text-sm font-semibold uppercase tracking-[0.25em] text-primary">
            Selected Game
          </p>
          <h2 class="mt-3 text-4xl font-black tracking-tight">{@selected_game.title}</h2>
          <p class="mt-2 text-base-content/70">Recorded in spin history.</p>
        </div>

        <.button
          id="spin-wheel-button"
          variant="primary"
          phx-click="spin"
          disabled={@candidate_count == 0}
          class="btn btn-primary btn-lg w-full"
        >
          Spin Wheel
        </.button>

        <section class="space-y-3">
          <h2 class="text-xl font-bold">Recent Spins</h2>
          <div id="spin-history" class="space-y-2">
            <p :if={@recent_spins == []} class="rounded-xl bg-base-200 p-4 text-base-content/70">
              No spins yet.
            </p>
            <div
              :for={spin <- @recent_spins}
              id={"spin-#{spin.id}"}
              class="flex items-center justify-between rounded-xl bg-base-200 p-4"
            >
              <span class="font-semibold">{spin.game.title}</span>
              <span class="text-sm text-base-content/60">{format_spun_at(spin.spun_at)}</span>
            </div>
          </div>
        </section>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Wheel")
     |> assign(:selected_game, nil)
     |> refresh_wheel()}
  end

  @impl true
  def handle_event("spin", _params, socket) do
    case Backlog.spin_wheel() do
      {:ok, %{game: game}} ->
        {:noreply,
         socket
         |> assign(:selected_game, game)
         |> put_flash(:info, "Wheel selected #{game.title}")
         |> refresh_wheel()}

      {:error, :no_candidates} ->
        {:noreply, put_flash(socket, :error, "Add at least one wheel candidate before spinning")}
    end
  end

  defp refresh_wheel(socket) do
    socket
    |> assign(:candidate_count, length(Backlog.list_wheel_candidates()))
    |> assign(:recent_spins, Backlog.list_recent_spins())
  end

  defp format_spun_at(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")
  end
end
