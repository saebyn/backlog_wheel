defmodule BacklogWheelWeb.QuickWheelLive do
  use BacklogWheelWeb, :live_view

  alias BacklogWheel.QuickWheels

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
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_community={@current_community}
      wide
    >
      <section id="quick-wheel-page" class="min-h-[calc(100vh-7rem)] overflow-hidden">
        <div class="grid min-h-[calc(100vh-7rem)] gap-6 lg:grid-cols-[1fr_24rem] lg:items-start">
          <div
            id="quick-wheel-hook"
            phx-hook="RouletteWheel"
            data-initial-rotation={@initial_rotation}
            class="relative flex min-h-[70vh] items-center justify-center overflow-hidden rounded-[2rem] border border-base-300 bg-radial-[at_50%_50%] from-base-100 via-base-200 to-base-300 shadow-2xl lg:sticky lg:top-24"
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
                id="quick-wheel-rotor"
                data-wheel-rotor
                phx-mounted={JS.ignore_attributes("style")}
                viewBox="0 0 100 100"
                class="h-full w-full drop-shadow-2xl will-change-transform"
              >
                <g>
                  <%= for {entry, index} <- Enum.with_index(@entries) do %>
                    <path
                      d={wedge_path(entry)}
                      fill={wheel_color(index)}
                      stroke="rgba(255,255,255,0.72)"
                      stroke-width="0.35"
                    />
                    <text
                      x="50"
                      y="50"
                      fill="white"
                      font-size={label_size(@entry_count)}
                      font-weight="800"
                      text-anchor="middle"
                      dominant-baseline="middle"
                      transform={label_transform(entry)}
                      class="select-none [paint-order:stroke] [stroke:rgba(0,0,0,0.55)] [stroke-width:0.45px]"
                    >
                      {truncate_title(entry.title)}
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
                  Quick entries
                </p>
                <p id="quick-wheel-entry-count" class="text-3xl font-black">{@entry_count}</p>
              </div>
            </div>
          </div>

          <aside class="flex flex-col gap-4 rounded-[2rem] border border-base-300 bg-base-100 p-5 shadow-xl">
            <.button
              id="quick-wheel-spin-button"
              variant="primary"
              phx-click="spin"
              disabled={@entry_count == 0 || @spinning?}
              class="btn btn-primary btn-lg w-full"
            >
              {if @spinning?, do: "Spinning...", else: "Spin Quick Wheel"}
            </.button>

            <.form for={@title_form} id="quick-wheel-title-form" phx-change="update_title">
              <.input field={@title_form[:title]} label="Wheel title" />
            </.form>

            <.form for={@entry_form} id="quick-wheel-entry-form" phx-change="update_entries">
              <.input
                field={@entry_form[:entries]}
                type="textarea"
                label="Entries (one per line)"
                rows="8"
                placeholder="Movie night"
              />
            </.form>

            <button :if={!@wheel.preset} class="btn" phx-click="create_preset">Save as preset</button>
            <button :if={@wheel.preset} class="btn" disabled={!@dirty} phx-click="save_preset">
              Save changes
            </button>
            <div
              id="quick-wheel-navigation"
              phx-hook="QuickWheelNavigation"
              data-dirty={to_string(@dirty and @wheel.preset)}
            >
              <a :if={@wheel.preset} href={~p"/quick-wheel"} class="link">Current Quick Wheel</a>
              <h2 :if={@presets != []} class="font-bold">Saved wheels</h2>
              <div :for={preset <- @presets} class="flex items-center gap-2">
                <a href={~p"/quick-wheel/presets/#{preset.id}"} class="link">{preset.title}</a>
                <a
                  href={~p"/quick-wheel/presets/#{preset.id}"}
                  target="_blank"
                  rel="noopener"
                  aria-label={"Open #{preset.title} in a new tab"}
                >
                  <.icon name="hero-arrow-top-right-on-square" class="size-4" />
                </a>
              </div>
            </div>

            <.wheel_volume id="quick-wheel-volume" />

            <div
              :if={@selected_entry}
              id="quick-wheel-result"
              class="rounded-2xl border border-primary/30 bg-primary/10 p-5 text-center shadow-sm"
            >
              <p class="text-sm font-semibold uppercase tracking-[0.2em] text-primary">Winner</p>
              <h2 class="mt-3 text-3xl font-black tracking-tight">{@selected_entry.title}</h2>
            </div>
          </aside>
        </div>

        <div
          :if={@selected_entry}
          id="quick-wheel-winner-modal"
          class="fixed inset-0 z-40 flex items-center justify-center bg-black/60 p-6 backdrop-blur-md"
        >
          <div class="relative max-w-2xl overflow-hidden rounded-[2rem] border border-white/20 bg-base-100 p-8 text-center shadow-2xl">
            <button
              id="quick-wheel-dismiss-winner"
              type="button"
              phx-click="dismiss_winner"
              class="btn btn-circle btn-ghost absolute right-3 top-3"
              aria-label="Dismiss winner"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
            <div class="absolute inset-x-0 top-0 h-2 bg-gradient-to-r from-orange-500 via-fuchsia-500 to-cyan-400">
            </div>
            <p class="text-sm font-black uppercase tracking-[0.35em] text-primary">{@title}</p>
            <h2 class="mt-6 text-5xl font-black tracking-tight text-balance">
              {@selected_entry.title}
            </h2>
            <p class="mt-4 text-lg text-base-content/70">The quick wheel has spoken.</p>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    user_id = socket.assigns.current_user.id

    wheel =
      case params do
        %{"id" => id} -> QuickWheels.preset!(user_id, id)
        _ -> QuickWheels.current(user_id)
      end

    {:ok,
     socket
     |> assign(:page_title, "Quick Wheel")
     |> assign(:wheel, wheel)
     |> assign(:dirty, false)
     |> assign(:presets, QuickWheels.presets(user_id))
     |> assign(:title, wheel.title)
     |> assign_entries(wheel.entries)
     |> assign(:selected_entry, nil)
     |> assign(:pending_entry, nil)
     |> assign(:pending_spin_id, nil)
     |> assign(:initial_rotation, 0)
     |> assign(:spinning?, false)
     |> assign_title_form()
     |> assign_entry_form(Enum.join(wheel.entries, "\n"))}
  end

  @impl true
  def handle_event("create_preset", _, %{assigns: %{wheel: %{preset: false}}} = socket) do
    %{wheel: wheel, title: title} = socket.assigns
    QuickWheels.create_preset(wheel.user_id, title, titles(socket))
    {:noreply, assign(socket, :presets, QuickWheels.presets(wheel.user_id))}
  end

  def handle_event("save_preset", _, %{assigns: %{wheel: %{preset: true}}} = socket) do
    socket = persist(socket)
    {:noreply, assign(socket, :presets, QuickWheels.presets(socket.assigns.wheel.user_id))}
  end

  def handle_event("update_title", %{"quick_wheel" => %{"title" => title}}, socket) do
    title = title |> String.trim() |> blank_to_default("Quick Wheel")

    {:noreply,
     socket
     |> assign(:title, title)
     |> assign_title_form()
     |> edited()}
  end

  def handle_event("update_entries", %{"entry" => %{"entries" => value}}, socket) do
    {:noreply,
     socket
     |> assign_entry_form(value)
     |> assign_entries(split_entries(value))
     |> assign(:selected_entry, nil)
     |> edited()}
  end

  def handle_event("spin", _params, %{assigns: %{entries: []}} = socket) do
    {:noreply, put_flash(socket, :error, "Add at least one entry before spinning")}
  end

  def handle_event("spin", _params, socket) do
    winner = Enum.random(socket.assigns.entries)
    landing_degrees = winner_center_degrees(winner)
    spin_id = "quick-#{System.unique_integer([:positive])}"

    segments =
      Enum.map(socket.assigns.entries, fn entry ->
        %{
          "entry_id" => entry.id,
          "start_degrees" => entry.start_degrees,
          "end_degrees" => entry.end_degrees
        }
      end)

    socket =
      push_event(socket, "roulette:spin", %{
        "spinId" => spin_id,
        "landingDegrees" => landing_degrees,
        "durationMs" => 5_000,
        "fullTurns" => 8,
        "segments" => segments
      })

    {:noreply,
     socket
     |> assign(:selected_entry, nil)
     |> assign(:pending_entry, winner)
     |> assign(:pending_spin_id, spin_id)
     |> assign(:spinning?, true)}
  end

  def handle_event("spin_finished", %{"spinId" => spin_id}, socket) do
    if socket.assigns.pending_spin_id == spin_id do
      {:noreply,
       socket
       |> assign(:selected_entry, socket.assigns.pending_entry)
       |> assign(:pending_entry, nil)
       |> assign(:pending_spin_id, nil)
       |> assign(
         :initial_rotation,
         normalize_degrees(360 - winner_center_degrees(socket.assigns.pending_entry))
       )
       |> assign(:spinning?, false)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("dismiss_winner", _params, socket) do
    {:noreply, assign(socket, :selected_entry, nil)}
  end

  defp titles(socket), do: Enum.map(socket.assigns.entries, & &1.title)

  defp edited(socket) do
    wheel = socket.assigns.wheel
    dirty = socket.assigns.title != wheel.title or titles(socket) != wheel.entries
    socket = assign(socket, :dirty, dirty)
    if dirty and !wheel.preset, do: persist(socket), else: socket
  end

  defp persist(socket) do
    case QuickWheels.save(socket.assigns.wheel, socket.assigns.title, titles(socket)) do
      {:ok, wheel} ->
        assign(socket, wheel: wheel, dirty: false)

      :stale ->
        put_flash(socket, :error, "Another tab changed this wheel. Copy your edits and reload.")
    end
  end

  defp assign_title_form(socket),
    do: assign(socket, :title_form, to_form(%{"title" => socket.assigns.title}, as: :quick_wheel))

  defp assign_entry_form(socket, value),
    do: assign(socket, :entry_form, to_form(%{"entries" => value}, as: :entry))

  defp assign_entries(socket, titles) do
    assign(socket, entries: with_wheel_geometry(titles), entry_count: length(titles))
  end

  defp split_entries(value) do
    value
    |> String.split(~r/\R/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp blank_to_default("", default), do: default
  defp blank_to_default(value, _default), do: value

  defp with_wheel_geometry([]), do: []

  defp with_wheel_geometry(titles) do
    segment_size = 360 / length(titles)

    titles
    |> Enum.with_index(1)
    |> Enum.map(fn {title, id} ->
      %{
        id: id,
        title: title,
        start_degrees: (id - 1) * segment_size,
        end_degrees: id * segment_size
      }
    end)
  end

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

  defp label_transform(entry) do
    angle = winner_center_degrees(entry)
    "rotate(#{point(angle)} 50 50) translate(0 -31) rotate(90 50 50)"
  end

  defp winner_center_degrees(nil), do: 0
  defp winner_center_degrees(entry), do: (entry.start_degrees + entry.end_degrees) / 2

  defp normalize_degrees(degrees), do: degrees - Float.floor(degrees / 360) * 360

  defp label_size(count) when count <= 8, do: "3.2"
  defp label_size(count) when count <= 16, do: "2.4"
  defp label_size(_count), do: "1.8"

  defp wheel_color(index), do: Enum.at(@wheel_colors, rem(index, length(@wheel_colors)))

  defp truncate_title(title) when byte_size(title) <= 24, do: title
  defp truncate_title(title), do: String.slice(title, 0, 23) <> "..."
end
