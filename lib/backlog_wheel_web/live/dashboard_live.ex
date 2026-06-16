defmodule BacklogWheelWeb.DashboardLive do
  use BacklogWheelWeb, :live_view

  alias BacklogWheel.{Accounts, Backlog, Communities, Voting}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_community={@current_community}>
      <section id="dashboard-page" class="space-y-6">
        <div class="brand-panel relative overflow-hidden rounded-[2rem] p-6 shadow-xl sm:p-8">
          <div
            class="absolute -right-24 -top-24 size-72 rounded-full bg-primary/20 blur-3xl"
            aria-hidden="true"
          />
          <div class="relative flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
            <div class="max-w-3xl">
              <p class="text-sm font-black uppercase tracking-[0.25em] text-primary">
                Community Dashboard
              </p>
              <h1 class="mt-3 text-4xl font-black tracking-tight text-base-content sm:text-6xl">
                Decide what happens next.
              </h1>
              <p class="mt-4 text-base leading-7 text-base-content/70 sm:text-lg">
                A quick read on the latest result, the current vote, and the Wheel Formats ready for stream.
              </p>
            </div>
            <div class="flex flex-wrap gap-2">
              <.link
                id="dashboard-history-link"
                navigate={~p"/history"}
                class="btn btn-primary hover-lift"
              >
                See Past Sessions
              </.link>
              <.link
                id="dashboard-voting-link"
                navigate={~p"/voting"}
                class="btn btn-secondary hover-lift"
              >
                Manage Voting
              </.link>
            </div>
          </div>
        </div>

        <div
          :if={!@current_community}
          id="dashboard-no-community"
          class="rounded-3xl border border-base-300 bg-base-100 p-6 shadow-sm"
        >
          <h2 class="text-2xl font-black">No community yet</h2>
          <p class="mt-2 text-base-content/70">
            Create or link a community to start tracking results, votes, and Wheel Formats.
          </p>
        </div>

        <div :if={@current_community} class="grid gap-6 lg:grid-cols-[1.15fr_0.85fr]">
          <section
            id="latest-recap-card"
            class="rounded-[2rem] border border-base-300 bg-base-100 p-6 shadow-xl"
          >
            <div class="flex items-start justify-between gap-4">
              <div>
                <p class="text-sm font-black uppercase tracking-[0.22em] text-primary">Last Result</p>
                <h2 class="mt-2 text-3xl font-black tracking-tight">What happened last time?</h2>
              </div>
              <.icon name="hero-trophy" class="size-8 text-primary" />
            </div>

            <div
              :if={!@latest_spin}
              id="dashboard-empty-history"
              class="mt-6 rounded-3xl bg-base-200 p-5"
            >
              <p class="font-bold">No spins recorded yet.</p>
              <p class="mt-2 text-sm leading-6 text-base-content/70">
                Once a wheel lands on a game, the recap will appear here with a link back to history.
              </p>
            </div>

            <div
              :if={@latest_spin}
              id={"dashboard-latest-spin-#{@latest_spin.id}"}
              class="mt-6 flex flex-col gap-5 sm:flex-row"
            >
              <div class="flex size-28 shrink-0 items-center justify-center overflow-hidden rounded-3xl border border-base-300 bg-base-200">
                <img
                  :if={@latest_spin.game.image_url}
                  src={@latest_spin.game.image_url}
                  alt={@latest_spin.game.title}
                  class="h-full w-full object-cover"
                />
                <.icon
                  :if={!@latest_spin.game.image_url}
                  name="hero-trophy"
                  class="size-10 text-primary"
                />
              </div>
              <div class="min-w-0 flex-1">
                <p class="text-sm font-semibold uppercase tracking-[0.18em] text-base-content/50">
                  Winner
                </p>
                <h3 class="mt-1 text-3xl font-black leading-tight">{@latest_spin.game.title}</h3>
                <p class="mt-2 text-sm text-base-content/60">
                  <span title={format_utc_datetime(@latest_spin.spun_at)}>
                    {format_datetime_with_age(@latest_spin.spun_at)}
                  </span>
                  · {@latest_spin.source}
                </p>
                <p
                  :if={winner_snapshot_entry(@latest_spin)}
                  id="dashboard-latest-spin-odds"
                  class="mt-3 rounded-2xl bg-base-200 px-4 py-3 text-sm text-base-content/70"
                >
                  <% winner_entry = winner_snapshot_entry(@latest_spin) %> Winner votes: {winner_entry[
                    "final_weight"
                  ]} of {snapshot_total_weight(@latest_spin)}.
                </p>
                <div class="mt-5 flex flex-wrap gap-2">
                  <.link
                    id="dashboard-latest-history-link"
                    navigate={~p"/history"}
                    class="btn btn-primary btn-sm hover-lift"
                  >
                    View History
                  </.link>
                  <.link
                    :if={@latest_spin.voting_session_id}
                    id="dashboard-latest-session-link"
                    navigate={~p"/history/#{@latest_spin}"}
                    class="btn btn-ghost btn-sm hover-lift"
                  >
                    Open Session Recap
                  </.link>
                </div>
              </div>
            </div>
          </section>

          <section
            id="active-session-card"
            class="rounded-[2rem] border border-base-300 bg-base-100 p-6 shadow-xl"
          >
            <div class="flex items-start justify-between gap-4">
              <div>
                <p class="text-sm font-black uppercase tracking-[0.22em] text-secondary">
                  Active Vote
                </p>
                <h2 class="mt-2 text-3xl font-black tracking-tight">Is chat voting?</h2>
              </div>
              <.icon name="hero-signal" class="size-8 text-secondary" />
            </div>

            <div
              :if={!@active_session}
              id="dashboard-no-active-session"
              class="mt-6 rounded-3xl bg-base-200 p-5"
            >
              <p class="font-bold">No draft, open, or ready-to-spin voting session.</p>
              <p class="mt-2 text-sm leading-6 text-base-content/70">
                Start a session when you are ready to collect votes or build tonight's pool.
              </p>
              <.link
                id="dashboard-create-session-link"
                navigate={~p"/voting"}
                class="btn btn-secondary btn-sm mt-4 hover-lift"
              >
                Create Voting Session
              </.link>
            </div>

            <div
              :if={@active_session}
              id={"dashboard-active-session-#{@active_session.id}"}
              class="mt-6 space-y-4"
            >
              <div class="flex flex-wrap items-center gap-2">
                <span id="dashboard-active-session-status" class="badge badge-secondary">
                  {status_label(@active_session.status)}
                </span>
                <span class="badge badge-ghost">
                  {length(@active_session.voting_session_games)} games
                </span>
              </div>
              <div>
                <h3 class="text-2xl font-black">
                  {@active_session.title || "Session #{@active_session.id}"}
                </h3>
                <p
                  :if={@active_session.description}
                  class="mt-2 text-sm leading-6 text-base-content/70"
                >
                  {@active_session.description}
                </p>
              </div>
              <p
                id="dashboard-active-session-action"
                class="rounded-2xl bg-base-200 px-4 py-3 text-sm text-base-content/70"
              >
                {active_session_action(@active_session)}
              </p>
              <div class="flex flex-wrap gap-2">
                <.link
                  id="dashboard-manage-active-session-link"
                  navigate={~p"/voting?#{[session_id: @active_session.id]}"}
                  class="btn btn-secondary btn-sm hover-lift"
                >
                  Manage Session
                </.link>
                <.link
                  id="dashboard-spin-active-session-link"
                  navigate={~p"/wheel?#{[voting_session_id: @active_session.id]}"}
                  class="btn btn-ghost btn-sm hover-lift"
                >
                  Spin Session
                </.link>
              </div>
            </div>
          </section>
        </div>

        <section
          :if={@current_community}
          id="wheel-formats-card"
          class="rounded-[2rem] border border-base-300 bg-base-100 p-6 shadow-xl"
        >
          <div class="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <p class="text-sm font-black uppercase tracking-[0.22em] text-accent">Wheel Formats</p>
              <h2 class="mt-2 text-3xl font-black tracking-tight">What should I use next?</h2>
            </div>
            <.link
              id="dashboard-wheel-formats-voting-link"
              navigate={~p"/voting"}
              class="btn btn-accent hover-lift"
            >
              Use a Format
            </.link>
          </div>

          <div
            :if={@wheel_formats == []}
            id="dashboard-empty-wheel-formats"
            class="mt-6 rounded-3xl bg-base-200 p-5"
          >
            <p class="font-bold">Wheel Formats are ready for a future setup flow.</p>
            <p class="mt-2 text-sm leading-6 text-base-content/70">
              When formats are configured, this dashboard will show reusable starting points for the next vote.
            </p>
          </div>

          <div
            :if={@wheel_formats != []}
            id="dashboard-wheel-formats"
            class="mt-6 grid gap-3 md:grid-cols-3"
          >
            <article
              :for={format <- @wheel_formats}
              id={"dashboard-wheel-format-#{format.id}"}
              class="rounded-3xl border border-base-300 bg-base-200 p-5"
            >
              <div class="flex items-start justify-between gap-3">
                <h3 class="text-xl font-black">{format.name}</h3>
                <span :if={format.is_default} class="badge badge-primary">Default</span>
              </div>
              <p class="mt-2 text-sm leading-6 text-base-content/70">
                {format.description || format.default_session_description ||
                  "Reusable setup for a voting session."}
              </p>
              <p class="mt-4 text-xs font-bold uppercase tracking-[0.18em] text-base-content/50">
                Starts as: {format.default_session_title}
              </p>
            </article>
          </div>
        </section>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    user = Accounts.get_user(Map.get(session, "user_id"))
    community = current_dashboard_community(user)

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:current_user, user)
     |> assign(:current_community, community)
     |> assign_dashboard(community)}
  end

  defp current_dashboard_community(nil), do: Communities.default_community()

  defp current_dashboard_community(user) do
    Communities.current_admin_community_for_user(user) || Communities.default_community()
  end

  defp assign_dashboard(socket, nil) do
    socket
    |> assign(:latest_spin, nil)
    |> assign(:active_session, nil)
    |> assign(:wheel_formats, [])
  end

  defp assign_dashboard(socket, community) do
    socket
    |> assign(:latest_spin, Backlog.latest_spin(community))
    |> assign(:active_session, Voting.active_voting_session(community))
    |> assign(:wheel_formats, Voting.list_wheel_formats(community))
  end

  defp active_session_action(%{status: "draft"}) do
    "Draft session: add games, review the pool, then open voting when chat is ready."
  end

  defp active_session_action(%{status: "open"}) do
    "Voting is open: monitor vote totals, then mark the session ready to spin."
  end

  defp active_session_action(%{status: "locked"}) do
    "Ready to spin: spin this session when you are ready to reveal the result."
  end

  defp status_label("locked"), do: "Ready to Spin"
  defp status_label(status), do: String.capitalize(status)

  defp winner_snapshot_entry(%{
         snapshot: %{"entries" => entries, "winning_game_id" => winning_game_id}
       })
       when is_list(entries) do
    Enum.find(entries, &(&1["game_id"] == winning_game_id))
  end

  defp winner_snapshot_entry(_spin), do: nil

  defp snapshot_total_weight(%{snapshot: %{"total_weight" => total_weight}}), do: total_weight
  defp snapshot_total_weight(_spin), do: 0
end
