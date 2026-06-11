defmodule BacklogWheelWeb.WheelLive do
  use BacklogWheelWeb, :live_view

  alias BacklogWheel.Backlog
  alias BacklogWheel.Voting

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
            data-voting-session-id={@selected_session && @selected_session.id}
            data-initial-rotation={@initial_rotation}
            class="relative flex min-h-[70vh] items-center justify-center overflow-hidden rounded-[2rem] border border-base-300 bg-radial-[at_50%_50%] from-base-100 via-base-200 to-base-300 shadow-2xl"
          >
            <div class="relative aspect-square w-[min(92vw,calc(100vh-9rem))] max-w-[78rem] rounded-full will-change-transform">
              <div class="pointer-events-none absolute left-1/2 top-0 z-20 -translate-x-1/2 -translate-y-5">
                <div
                  data-wheel-pointer
                  class="h-0 w-0 border-x-[1.05rem] border-t-[3.25rem] border-x-transparent border-t-primary drop-shadow-[0_0.6rem_0.45rem_rgba(0,0,0,0.38)]"
                >
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
                      d={wedge_path(candidate)}
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
                      transform={label_transform(candidate)}
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
                <p id="wheel-total-weight" class="text-xs font-semibold text-white/70">
                  Total weight: {@total_weight}
                </p>
              </div>
            </div>
          </div>

          <aside class="flex flex-col gap-4 rounded-[2rem] border border-base-300 bg-base-100 p-5 shadow-xl">
            <.header>
              Voting Wheel
              <:subtitle>Thirty-second spin from the selected voting session.</:subtitle>
              <:actions>
                <.button navigate={~p"/voting"}>Manage voting</.button>
              </:actions>
            </.header>

            <section
              id="wheel-session-selector"
              class="space-y-2 rounded-2xl border border-base-300 bg-base-200 p-4"
            >
              <h2 class="text-lg font-bold">Voting session</h2>
              <p :if={@voting_sessions == []} class="text-sm text-base-content/70">
                Create a voting session before spinning the wheel.
              </p>
              <div :if={@voting_sessions != []} class="space-y-2">
                <button
                  :for={session <- @voting_sessions}
                  id={"select-wheel-session-#{session.id}"}
                  type="button"
                  phx-click="select_session"
                  phx-value-id={session.id}
                  class={wheel_session_button_class(session, @selected_session)}
                >
                  <span class="font-semibold">Session #{session.id}</span>
                  <span class="badge badge-ghost capitalize">{session.status}</span>
                  <span class="text-xs text-base-content/60">
                    {length(session.voting_session_games)} games
                  </span>
                </button>
              </div>
            </section>

            <section
              :if={@selected_session}
              id="wheel-weight-summary"
              class="space-y-2 rounded-2xl border border-base-300 bg-base-200 p-4"
            >
              <h2 class="text-lg font-bold">Vote Totals</h2>
              <div id="wheel-weighted-candidates" class="space-y-2">
                <div
                  :for={candidate <- @candidates}
                  id={"wheel-candidate-#{candidate.pool_item.id}"}
                  class="rounded-xl bg-base-100 p-3"
                >
                  <div class="flex items-center justify-between gap-3">
                    <p class="font-semibold leading-tight">{candidate.title}</p>
                    <p class="text-sm font-black text-primary">{candidate.weight}</p>
                  </div>
                  <div class="mt-2 h-2 overflow-hidden rounded-full bg-base-300">
                    <div
                      class="h-full rounded-full bg-primary"
                      style={"width: #{candidate_weight_percent(candidate, @total_weight)}%"}
                    >
                    </div>
                  </div>
                  <p class="mt-1 text-xs text-base-content/60">
                    Starting votes {candidate.base_weight} + channel point votes {candidate.channel_point_vote_total}
                  </p>
                </div>
              </div>
            </section>

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
              disabled={!@selected_session || @candidate_count == 0 || @spinning?}
              class="btn btn-primary btn-lg w-full"
            >
              {if @spinning?, do: "Spinning...", else: "Spin Wheel"}
            </.button>

            <section class="min-h-0 flex-1 space-y-3">
              <h2 class="text-xl font-bold">Recent Spins</h2>
              <div id="spin-history" class="space-y-2">
                <p :if={@recent_spins == []} class="rounded-xl bg-base-200 p-4 text-base-content/70">
                  No spins yet.
                </p>
                <div
                  :for={spin <- @recent_spins}
                  id={"spin-#{spin.id}"}
                  class="rounded-xl bg-base-200 p-4"
                >
                  <p class="font-semibold leading-tight">{spin.game.title}</p>
                  <p class="mt-1 text-sm text-base-content/60">
                    <span title={format_utc_datetime(spin.spun_at)}>
                      {format_datetime_with_age(spin.spun_at)}
                    </span>
                  </p>
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
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Wheel")
     |> assign(:selected_session_id, selected_session_id_from_params(params))
     |> assign(:subscribed_voting_session_id, nil)
     |> assign(:selected_game, nil)
     |> assign(:pending_game, nil)
     |> assign(:pending_spin_id, nil)
     |> assign(:spinning?, false)
     |> refresh_wheel()}
  end

  @impl true
  def handle_event("spin", _params, socket) do
    if is_nil(socket.assigns.selected_session) do
      {:noreply, put_flash(socket, :error, "Create or select a voting session before spinning")}
    else
      spin_selected_session(socket)
    end
  end

  def handle_event("select_session", %{"id" => id}, socket) do
    {:noreply, socket |> assign(:selected_session_id, String.to_integer(id)) |> refresh_wheel()}
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

  @impl true
  def handle_info({:voting_session_changed, id}, socket) do
    if socket.assigns.selected_session_id == id do
      {:noreply, refresh_wheel(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:voting_session_spin_started, %{"votingSessionId" => id} = payload}, socket) do
    if socket.assigns.selected_session_id == id do
      socket = push_event(socket, "roulette:spin", payload)

      {:noreply,
       socket
       |> assign(:selected_game, nil)
       |> assign(:pending_game, Backlog.get_game!(payload["gameId"]))
       |> assign(:pending_spin_id, payload["spinId"])
       |> assign(:spinning?, true)}
    else
      {:noreply, socket}
    end
  end

  defp spin_selected_session(socket) do
    case Voting.spin_voting_session_wheel(socket.assigns.selected_session) do
      {:ok, _spin_result} ->
        {:noreply, socket}

      {:error, :no_candidates} ->
        {:noreply,
         put_flash(socket, :error, "Add at least one game to the voting session before spinning")}
    end
  end

  defp refresh_wheel(socket) do
    voting_sessions = Voting.list_voting_sessions()
    selected_session = selected_session(voting_sessions, socket.assigns.selected_session_id)

    candidates =
      if selected_session do
        selected_session
        |> Voting.list_voting_session_wheel_entries()
        |> with_wheel_geometry()
      else
        []
      end

    socket
    |> assign(:voting_sessions, voting_sessions)
    |> assign(:selected_session, selected_session)
    |> assign(:selected_session_id, selected_session && selected_session.id)
    |> assign(:candidates, candidates)
    |> assign(:candidate_count, length(candidates))
    |> assign(:total_weight, total_weight(candidates))
    |> assign(:initial_rotation, initial_rotation(selected_session))
    |> assign(:recent_spins, Backlog.list_recent_spins())
    |> subscribe_to_selected_session()
  end

  defp initial_rotation(nil), do: 0

  defp initial_rotation(selected_session) do
    case Backlog.latest_voting_session_spin(selected_session.id) do
      %{snapshot: %{"landing_degrees" => landing_degrees}} when is_number(landing_degrees) ->
        normalize_degrees(360 - landing_degrees)

      _spin ->
        0
    end
  end

  defp normalize_degrees(degrees), do: degrees - Float.floor(degrees / 360) * 360

  defp subscribe_to_selected_session(socket) do
    if connected?(socket) &&
         socket.assigns.subscribed_voting_session_id != socket.assigns.selected_session_id do
      Voting.unsubscribe_from_voting_session(socket.assigns.subscribed_voting_session_id)

      if socket.assigns.selected_session_id do
        Voting.subscribe_to_voting_session(socket.assigns.selected_session_id)
      end

      assign(socket, :subscribed_voting_session_id, socket.assigns.selected_session_id)
    else
      socket
    end
  end

  defp selected_session_id_from_params(%{"voting_session_id" => id}) do
    case Integer.parse(id) do
      {id, ""} -> id
      _invalid -> nil
    end
  end

  defp selected_session_id_from_params(_params), do: nil

  defp selected_session([], _selected_session_id), do: nil

  defp selected_session(sessions, nil), do: hd(sessions)

  defp selected_session(sessions, selected_session_id) do
    Enum.find(sessions, &(&1.id == selected_session_id)) || hd(sessions)
  end

  defp with_wheel_geometry(candidates) do
    total_weight = total_weight(candidates)

    candidates
    |> Enum.reduce({[], 0}, fn candidate, {candidates, accumulated_weight} ->
      start_degrees = accumulated_weight / total_weight * 360
      end_degrees = (accumulated_weight + candidate.weight) / total_weight * 360

      candidate =
        candidate
        |> Map.put(:start_degrees, start_degrees)
        |> Map.put(:end_degrees, end_degrees)

      {[candidate | candidates], accumulated_weight + candidate.weight}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp total_weight(candidates), do: Enum.reduce(candidates, 0, &(&1.weight + &2))

  defp wedge_path(%{start_degrees: start_degrees, end_degrees: end_degrees}) do
    segment = end_degrees - start_degrees

    if segment == 360 do
      "M 50 2 A 48 48 0 1 1 50 98 A 48 48 0 1 1 50 2 Z"
    else
      start_angle = -90 + start_degrees
      end_angle = -90 + end_degrees
      {start_x, start_y} = polar_to_cartesian(50, 50, 48, start_angle)
      {end_x, end_y} = polar_to_cartesian(50, 50, 48, end_angle)
      large_arc = if segment > 180, do: 1, else: 0

      "M 50 50 L #{point(start_x)} #{point(start_y)} A 48 48 0 #{large_arc} 1 #{point(end_x)} #{point(end_y)} Z"
    end
  end

  defp polar_to_cartesian(center_x, center_y, radius, angle_degrees) do
    angle_radians = angle_degrees * :math.pi() / 180
    {center_x + radius * :math.cos(angle_radians), center_y + radius * :math.sin(angle_radians)}
  end

  defp point(value), do: :erlang.float_to_binary(value, decimals: 3)

  defp label_transform(candidate) do
    angle = winner_center_degrees(candidate)
    "rotate(#{point(angle)} 50 50) translate(0 -31) rotate(90 50 50)"
  end

  defp winner_center_degrees(nil), do: 0
  defp winner_center_degrees(candidate), do: (candidate.start_degrees + candidate.end_degrees) / 2

  defp candidate_weight_percent(_candidate, 0), do: "0.0"

  defp candidate_weight_percent(candidate, total_weight) do
    (candidate.weight / total_weight * 100)
    |> point()
  end

  defp wheel_session_button_class(session, selected_session) do
    [
      "flex w-full items-center justify-between gap-2 rounded-xl border p-3 text-left transition hover:-translate-y-0.5 hover:shadow-md",
      selected_session && session.id == selected_session.id && "border-primary bg-primary/10",
      (!selected_session || session.id != selected_session.id) && "border-base-300 bg-base-100"
    ]
  end

  defp label_size(count) when count <= 8, do: "3.2"
  defp label_size(count) when count <= 16, do: "2.4"
  defp label_size(_count), do: "1.8"

  defp wheel_color(index), do: Enum.at(@wheel_colors, rem(index, length(@wheel_colors)))

  defp truncate_title(title) when byte_size(title) <= 24, do: title
  defp truncate_title(title), do: String.slice(title, 0, 23) <> "..."
end
