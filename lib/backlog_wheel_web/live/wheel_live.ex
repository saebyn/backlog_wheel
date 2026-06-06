defmodule BacklogWheelWeb.WheelLive do
  use BacklogWheelWeb, :live_view

  alias BacklogWheel.Backlog

  @spin_duration_ms 30_000
  @wheel_colors [
    "#f97316",
    "#7c3aed",
    "#06b6d4",
    "#f43f5e",
    "#22c55e",
    "#eab308",
    "#3b82f6",
    "#d946ef"
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} wide>
      <section id="wheel-page" class="min-h-[calc(100vh-7rem)] overflow-hidden">
        <div class="grid min-h-[calc(100vh-7rem)] gap-6 lg:grid-cols-[1fr_22rem] lg:items-stretch">
          <div
            id="roulette-wheel-hook"
            phx-hook="RouletteWheel"
            phx-update="ignore"
            class="relative flex min-h-[70vh] items-center justify-center overflow-hidden rounded-[2rem] border border-base-300 bg-radial-[at_50%_50%] from-base-100 via-base-200 to-base-300 shadow-2xl"
          >
            <div class="relative aspect-square w-[min(92vw,calc(100vh-9rem))] max-w-[78rem] rounded-full will-change-transform">
              <div class="pointer-events-none absolute left-1/2 top-0 z-20 -translate-x-1/2 -translate-y-1">
                <div class="h-0 w-0 border-x-[1.5rem] border-t-[3.25rem] border-x-transparent border-t-primary drop-shadow-lg">
                </div>
              </div>

              <svg
                data-wheel-rotor
                viewBox="0 0 100 100"
                class="h-full w-full drop-shadow-2xl will-change-transform"
              >
                <defs>
                  <filter id="wheel-shadow" x="-20%" y="-20%" width="140%" height="140%">
                    <feDropShadow dx="0" dy="1" stdDeviation="1" flood-opacity="0.25" />
                  </filter>
                </defs>
                <g filter="url(#wheel-shadow)">
                  <%= for {candidate, index} <- Enum.with_index(@candidates) do %>
                    <path
                      d={wedge_path(index, @candidate_count)}
                      fill={wheel_color(index)}
                      stroke="rgba(255,255,255,0.72)"
                      stroke-width="0.35"
                    />
                    <text
                      x="50"
                      y="50"
                      fill="white"
                      font-size={label_size(@candidate_count)}
                      font-weight="800"
                      text-anchor="middle"
                      dominant-baseline="middle"
                      transform={label_transform(index, @candidate_count)}
                      class="select-none [paint-order:stroke] [stroke:rgba(0,0,0,0.55)] [stroke-width:0.45px]"
                    >
                      {truncate_title(candidate.title)}
                    </text>
                  <% end %>
                </g>
                <circle
                  cx="50"
                  cy="50"
                  r="8"
                  fill="oklch(21% 0.006 285.885)"
                  stroke="white"
                  stroke-width="1.2"
                />
                <circle cx="50" cy="50" r="3" fill="white" />
              </svg>
            </div>

            <div class="pointer-events-none absolute inset-x-0 bottom-6 z-10 flex justify-center px-4">
              <div class="rounded-full border border-white/20 bg-black/50 px-5 py-3 text-center text-white shadow-xl backdrop-blur">
                <p class="text-xs font-semibold uppercase tracking-[0.24em] text-white/70">
                  Candidates
                </p>
                <p id="wheel-candidate-count" class="text-3xl font-black">{@candidate_count}</p>
              </div>
            </div>
          </div>

          <aside class="flex flex-col gap-4 rounded-[2rem] border border-base-300 bg-base-100 p-5 shadow-xl">
            <.header>
              Stream Wheel
              <:subtitle>Thirty-second roulette spin from the current wheel candidates.</:subtitle>
              <:actions>
                <.button navigate={~p"/games"}>Curate games</.button>
              </:actions>
            </.header>

            <div
              :if={@spinning?}
              id="wheel-spinning"
              class="rounded-2xl border border-primary/30 bg-primary/10 p-4 text-center"
            >
              <p class="text-sm font-semibold uppercase tracking-[0.2em] text-primary">Spinning</p>
              <p class="mt-2 text-base-content/70">Winner reveals after the wheel lands.</p>
            </div>

            <div
              :if={@selected_game}
              id="wheel-result"
              class="rounded-2xl border border-primary/30 bg-primary/10 p-5 text-center shadow-sm"
            >
              <p class="text-sm font-semibold uppercase tracking-[0.2em] text-primary">
                Selected Game
              </p>
              <h2 class="mt-3 text-3xl font-black tracking-tight">{@selected_game.title}</h2>
              <p class="mt-2 text-base-content/70">Recorded in spin history.</p>
            </div>

            <.button
              id="spin-wheel-button"
              variant="primary"
              phx-click="spin"
              disabled={@candidate_count == 0 || @spinning?}
              class="btn btn-primary btn-lg w-full"
            >
              {if @spinning?, do: "Spinning...", else: "Spin Wheel"}
            </.button>

            <section class="min-h-0 flex-1 space-y-3 overflow-hidden">
              <h2 class="text-xl font-bold">Recent Spins</h2>
              <div id="spin-history" class="max-h-[38vh] space-y-2 overflow-auto pr-1">
                <p :if={@recent_spins == []} class="rounded-xl bg-base-200 p-4 text-base-content/70">
                  No spins yet.
                </p>
                <div
                  :for={spin <- @recent_spins}
                  id={"spin-#{spin.id}"}
                  class="rounded-xl bg-base-200 p-4"
                >
                  <p class="font-semibold leading-tight">{spin.game.title}</p>
                  <p class="mt-1 text-sm text-base-content/60">{format_spun_at(spin.spun_at)}</p>
                </div>
              </div>
            </section>
          </aside>
        </div>

        <div
          :if={@selected_game}
          id="wheel-winner-modal"
          class="fixed inset-0 z-40 flex items-center justify-center bg-black/60 p-6 backdrop-blur-md"
        >
          <div class="relative max-w-2xl overflow-hidden rounded-[2rem] border border-white/20 bg-base-100 p-8 text-center shadow-2xl">
            <button
              id="dismiss-winner-modal"
              type="button"
              phx-click="dismiss_winner"
              class="btn btn-circle btn-ghost absolute right-3 top-3"
              aria-label="Dismiss winner"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
            <div class="absolute inset-x-0 top-0 h-2 bg-gradient-to-r from-orange-500 via-fuchsia-500 to-cyan-400">
            </div>
            <p class="text-sm font-black uppercase tracking-[0.35em] text-primary">
              Winner
            </p>
            <div class="mx-auto mt-6 flex size-28 items-center justify-center overflow-hidden rounded-3xl border border-base-300 bg-base-200 shadow-lg">
              <img
                :if={@selected_game.image_url}
                src={@selected_game.image_url}
                alt={@selected_game.title}
                class="h-full w-full object-cover"
              />
              <.icon
                :if={!@selected_game.image_url}
                name="hero-trophy"
                class="size-14 text-primary"
              />
            </div>
            <h2 class="mt-6 text-5xl font-black tracking-tight text-balance">
              {@selected_game.title}
            </h2>
            <p class="mt-4 text-lg text-base-content/70">
              The wheel has spoken. Spin recorded in history.
            </p>
          </div>
        </div>
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
     |> assign(:pending_game, nil)
     |> assign(:pending_spin_id, nil)
     |> assign(:spinning?, false)
     |> refresh_wheel()}
  end

  @impl true
  def handle_event("spin", _params, socket) do
    case Backlog.spin_wheel() do
      {:ok, %{game: game, spin: spin}} ->
        winner_index = Enum.find_index(socket.assigns.candidates, &(&1.id == game.id)) || 0

        socket =
          push_event(socket, "roulette:spin", %{
            winnerIndex: winner_index,
            segmentCount: socket.assigns.candidate_count,
            spinId: spin.id,
            durationMs: @spin_duration_ms
          })

        {:noreply,
         socket
         |> assign(:selected_game, nil)
         |> assign(:pending_game, game)
         |> assign(:pending_spin_id, spin.id)
         |> assign(:spinning?, true)}

      {:error, :no_candidates} ->
        {:noreply, put_flash(socket, :error, "Add at least one wheel candidate before spinning")}
    end
  end

  @impl true
  def handle_event("spin_finished", %{"spinId" => spin_id}, socket) do
    if socket.assigns.pending_spin_id == spin_id do
      game = socket.assigns.pending_game

      {:noreply,
       socket
       |> assign(:selected_game, game)
       |> assign(:pending_game, nil)
       |> assign(:pending_spin_id, nil)
       |> assign(:spinning?, false)
       |> refresh_wheel()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("dismiss_winner", _params, socket) do
    {:noreply, assign(socket, :selected_game, nil)}
  end

  defp refresh_wheel(socket) do
    candidates = Backlog.list_wheel_candidates()

    socket
    |> assign(:candidates, candidates)
    |> assign(:candidate_count, length(candidates))
    |> assign(:recent_spins, Backlog.list_recent_spins())
  end

  defp wedge_path(_index, 0), do: ""
  defp wedge_path(_index, 1), do: "M 50 2 A 48 48 0 1 1 50 98 A 48 48 0 1 1 50 2 Z"

  defp wedge_path(index, count) do
    segment = 360 / count
    start_angle = -90 + index * segment
    end_angle = start_angle + segment
    {start_x, start_y} = polar_to_cartesian(50, 50, 48, start_angle)
    {end_x, end_y} = polar_to_cartesian(50, 50, 48, end_angle)
    large_arc = if segment > 180, do: 1, else: 0

    "M 50 50 L #{point(start_x)} #{point(start_y)} A 48 48 0 #{large_arc} 1 #{point(end_x)} #{point(end_y)} Z"
  end

  defp polar_to_cartesian(center_x, center_y, radius, angle_degrees) do
    angle_radians = angle_degrees * :math.pi() / 180
    {center_x + radius * :math.cos(angle_radians), center_y + radius * :math.sin(angle_radians)}
  end

  defp point(value), do: :erlang.float_to_binary(value, decimals: 3)

  defp label_transform(_index, 0), do: ""

  defp label_transform(index, count) do
    angle = index * (360 / count) + 180 / count
    "rotate(#{point(angle)} 50 50) translate(0 -31) rotate(90 50 50)"
  end

  defp label_size(count) when count <= 8, do: "3.2"
  defp label_size(count) when count <= 16, do: "2.4"
  defp label_size(_count), do: "1.8"

  defp wheel_color(index), do: Enum.at(@wheel_colors, rem(index, length(@wheel_colors)))

  defp truncate_title(title) when byte_size(title) <= 24, do: title
  defp truncate_title(title), do: String.slice(title, 0, 23) <> "..."

  defp format_spun_at(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")
  end
end
