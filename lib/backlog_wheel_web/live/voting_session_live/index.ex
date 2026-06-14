defmodule BacklogWheelWeb.VotingSessionLive.Index do
  use BacklogWheelWeb, :live_view

  require Logger

  alias BacklogWheel.Backlog
  alias BacklogWheel.Twitch
  alias BacklogWheel.Voting
  alias BacklogWheel.Voting.VotingSession

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_community={@current_community}
      wide
    >
      <nav
        id="voting-page-jump-nav"
        aria-label="Voting page sections"
        class="mb-4 rounded-2xl border border-base-300 bg-base-100/90 p-3 shadow-sm backdrop-blur xl:hidden"
      >
        <p class="px-2 text-xs font-bold uppercase tracking-[0.18em] text-base-content/50">
          Jump to
        </p>
        <div class="mt-2 flex gap-2 overflow-x-auto pb-1">
          <.link href="#voting-creation-section" class="btn btn-ghost btn-sm shrink-0">
            Voting creation
          </.link>
          <.link href="#session-admin-section" class="btn btn-ghost btn-sm shrink-0">
            Session admin
          </.link>
          <.link href="#voting-games-section" class="btn btn-ghost btn-sm shrink-0">
            Games
          </.link>
          <.link href="#add-games-section" class="btn btn-ghost btn-sm shrink-0">
            Add games
          </.link>
        </div>
      </nav>

      <div class="grid gap-6 lg:grid-cols-[20rem_1fr]">
        <aside
          id="voting-creation-section"
          class="scroll-mt-24 space-y-4 rounded-[2rem] border border-base-300 bg-base-100 p-5 shadow-xl"
        >
          <.header>
            Voting Sessions
            <:subtitle>Create game lists, collect channel point votes, and spin a winner.</:subtitle>
            <:actions>
              <.button id="create-voting-session" phx-click="create_session">
                <.icon name="hero-plus" /> Manual Session
              </.button>
            </:actions>
          </.header>

          <.form
            for={@wheel_format_form}
            id="create-session-from-format-form"
            phx-submit="create_session_from_format"
          >
            <div class="space-y-3 rounded-2xl border border-primary/20 bg-primary/5 p-4">
              <div>
                <p class="text-sm font-bold uppercase tracking-[0.18em] text-primary">Wheel Format</p>
                <p class="mt-1 text-sm text-base-content/70">
                  Start from a reusable format, then tune the game pool for this vote.
                </p>
              </div>
              <.input
                field={@wheel_format_form[:wheel_format_id]}
                type="select"
                label="Format"
                options={@wheel_format_options}
              />
              <.button
                id="create-voting-session-from-format"
                variant="primary"
                disabled={@wheel_format_options == []}
              >
                Create From Format
              </.button>
            </div>
          </.form>

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
              <span class="font-semibold">{session.title || "Session #{session.id}"}</span>
              <span class="badge badge-ghost">{status_label(session.status)}</span>
              <span class="text-xs text-base-content/60">
                {length(session.voting_session_games)} games
              </span>
            </button>
          </div>
        </aside>

        <section
          id="session-admin-section"
          class="scroll-mt-24 min-h-[32rem] rounded-[2rem] border border-base-300 bg-base-100 p-5 shadow-xl"
        >
          <div
            :if={!@selected_session}
            id="voting-session-empty"
            class="grid min-h-96 place-items-center text-center"
          >
            <div>
              <p class="text-sm font-semibold uppercase tracking-[0.24em] text-primary">No Session</p>
              <h1 class="mt-3 text-4xl font-black tracking-tight">Create a voting session</h1>
              <p class="mt-3 text-base-content/70">
                Start with the current wheel games, then adjust the game list locally.
              </p>
            </div>
          </div>

          <div :if={@selected_session} id="voting-session-detail" class="space-y-6">
            <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
              <div>
                <p class="text-sm font-semibold uppercase tracking-[0.24em] text-primary">
                  Session #{@selected_session.id}
                </p>
                <h1 id="selected-session-title" class="mt-2 text-4xl font-black tracking-tight">
                  {@selected_session.title || "Games In This Vote"}
                </h1>
                <p
                  :if={@selected_session.description}
                  id="selected-session-description"
                  class="mt-2 max-w-3xl text-base-content/70"
                >
                  {@selected_session.description}
                </p>
                <div class="mt-3 flex flex-wrap gap-2">
                  <span id="selected-session-status" class="badge badge-primary">
                    {status_label(@selected_session.status)}
                  </span>
                  <span id="selected-session-pool-size" class="badge badge-ghost">
                    {@pool_size} games in this vote
                  </span>
                  <span
                    :if={@failed_twitch_reward_deletions > 0}
                    id="failed-twitch-reward-deletions"
                    class="badge badge-error"
                  >
                    {@failed_twitch_reward_deletions} reward cleanup failed
                  </span>
                  <span
                    id="twitch-connection-status"
                    class={[
                      "badge",
                      @twitch_connected? && "badge-success",
                      !@twitch_connected? && "badge-warning"
                    ]}
                  >
                    {if @twitch_connected?, do: "Twitch connected", else: "Twitch not connected"}
                  </span>
                </div>
              </div>

              <div class="flex flex-wrap gap-2">
                <.button id="manage-twitch" href={~p"/settings/twitch"}>
                  Manage Twitch
                </.button>
              </div>
            </div>

            <section
              id="voting-session-next-action"
              class="overflow-hidden rounded-[1.75rem] border border-primary/20 bg-gradient-to-br from-primary/10 via-base-100 to-base-200 p-5 shadow-sm"
            >
              <div class="flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
                <div class="max-w-3xl">
                  <p class="text-sm font-semibold uppercase tracking-[0.22em] text-primary">
                    Current State
                  </p>
                  <h2 id="voting-session-state-label" class="mt-2 text-2xl font-black tracking-tight">
                    {@lifecycle.state_label}
                  </h2>
                  <p id="voting-session-state-description" class="mt-2 text-base-content/70">
                    {@lifecycle.state_description}
                  </p>
                  <p id="voting-session-next-action-copy" class="mt-4 text-lg font-bold">
                    {@lifecycle.next_action_copy}
                  </p>
                  <p
                    :if={@lifecycle.blocking_issue}
                    id="voting-session-blocking-issue"
                    class="mt-3 flex items-start gap-3 rounded-2xl border border-warning/40 bg-warning/15 px-4 py-3 text-sm font-semibold text-warning-content"
                  >
                    <.icon
                      name="hero-exclamation-triangle"
                      class="mt-0.5 size-5 shrink-0 text-warning"
                    />
                    <span>{@lifecycle.blocking_issue}</span>
                  </p>
                </div>

                <div class="flex shrink-0 flex-col gap-2 sm:min-w-56">
                  <.button
                    :if={@lifecycle.primary_action == :populate_pool}
                    id="populate-session-pool"
                    phx-click="populate_pool"
                    variant="primary"
                  >
                    Add wheel games
                  </.button>
                  <.button
                    :if={@lifecycle.primary_action == :open_voting}
                    id="set-session-open"
                    phx-click="set_status"
                    phx-value-status="open"
                    variant="primary"
                  >
                    Open voting
                  </.button>
                  <.button
                    :if={@lifecycle.primary_action == :start_twitch_voting}
                    id="start-twitch-voting"
                    phx-click="start_twitch_voting"
                    variant="primary"
                  >
                    Start Twitch voting
                  </.button>
                  <.button
                    :if={@lifecycle.primary_action == :manage_twitch}
                    id="manage-twitch-primary"
                    href={~p"/settings/twitch"}
                    variant="primary"
                  >
                    Connect Twitch
                  </.button>
                  <.button
                    :if={@lifecycle.primary_action == :ready_to_spin}
                    id="set-session-locked"
                    phx-click="set_status"
                    phx-value-status="locked"
                    variant="primary"
                  >
                    Freeze voting
                  </.button>
                  <.button
                    :if={@lifecycle.primary_action == :spin}
                    id="spin-selected-voting-session"
                    navigate={~p"/wheel?#{[voting_session_id: @selected_session.id]}"}
                    variant="primary"
                  >
                    Spin these games
                  </.button>
                  <.button
                    :if={@lifecycle.primary_action == :view_recap}
                    id="view-session-recap"
                    navigate={~p"/history"}
                    variant="primary"
                  >
                    View recap
                  </.button>
                  <.button
                    :if={@lifecycle.primary_action == :create_session}
                    id="create-next-voting-session"
                    phx-click="create_session"
                    variant="primary"
                  >
                    Create new session
                  </.button>
                </div>
              </div>
            </section>

            <section
              :if={@secondary_actions != [] || @advanced_actions != [] || @destructive_actions != []}
              id="voting-session-secondary-actions"
              class="rounded-2xl border border-base-300 bg-base-200 p-4"
            >
              <div
                :if={@secondary_actions != []}
                class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"
              >
                <div>
                  <h2 class="text-lg font-bold">Other available actions</h2>
                  <p class="text-sm text-base-content/60">
                    Use these when you need to adjust the vote instead of following the recommended next step.
                  </p>
                </div>
                <div class="grid gap-3 sm:min-w-96">
                  <div
                    :if={:populate_pool in @secondary_actions}
                    class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between"
                  >
                    <p class="text-sm text-base-content/70">
                      Add every wheel-eligible game that is not already in this vote.
                    </p>
                    <.button id="populate-session-pool-secondary" phx-click="populate_pool">
                      Add wheel games
                    </.button>
                  </div>
                  <div
                    :if={:start_twitch_voting in @secondary_actions}
                    class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between"
                  >
                    <p class="text-sm text-base-content/70">
                      Create Twitch channel point rewards so viewers can vote from chat.
                    </p>
                    <.button id="start-twitch-voting" phx-click="start_twitch_voting">
                      Start Twitch voting
                    </.button>
                  </div>
                  <div
                    :if={:remove_twitch_rewards in @secondary_actions}
                    class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between"
                  >
                    <p class="text-sm text-base-content/70">
                      Remove Twitch rewards for this vote while keeping the session status unchanged.
                    </p>
                    <.button
                      id="remove-twitch-rewards"
                      phx-click="remove_twitch_rewards"
                      data-confirm="Remove Twitch channel point rewards for this session? Voting stays open."
                    >
                      {if @failed_twitch_reward_deletions > 0,
                        do: "Retry reward cleanup",
                        else: "Remove Twitch rewards"}
                    </.button>
                  </div>
                  <div
                    :if={:spin_manually in @secondary_actions}
                    class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between"
                  >
                    <p class="text-sm text-base-content/70">
                      Freeze voting, snapshot the pool, and spin without starting Twitch rewards.
                    </p>
                    <.button
                      id="spin-selected-voting-session"
                      navigate={~p"/wheel?#{[voting_session_id: @selected_session.id]}"}
                    >
                      Spin now
                    </.button>
                  </div>
                  <div
                    :if={:ready_to_spin in @secondary_actions}
                    class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between"
                  >
                    <p class="text-sm text-base-content/70">
                      Stop accepting votes and freeze this pool for the wheel.
                    </p>
                    <.button id="set-session-locked" phx-click="set_status" phx-value-status="locked">
                      Freeze voting
                    </.button>
                  </div>
                  <div
                    :if={:reopen_voting in @secondary_actions}
                    class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between"
                  >
                    <p class="text-sm text-base-content/70">Let votes continue before you spin.</p>
                    <.button id="set-session-open" phx-click="set_status" phx-value-status="open">
                      Reopen voting
                    </.button>
                  </div>
                  <div
                    :if={:create_session in @secondary_actions}
                    class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between"
                  >
                    <p class="text-sm text-base-content/70">
                      Start a separate vote without changing this session.
                    </p>
                    <.button id="create-next-voting-session-secondary" phx-click="create_session">
                      Create new session
                    </.button>
                  </div>
                </div>
              </div>

              <div
                :if={@advanced_actions != [] || @destructive_actions != []}
                class={[
                  "flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between",
                  @secondary_actions != [] && "mt-4 border-t border-base-300 pt-4"
                ]}
              >
                <div>
                  <h2 class="text-lg font-bold">Advanced / destructive</h2>
                  <p class="text-sm text-base-content/60">
                    Use these only when you intentionally need to undo or abandon this vote.
                  </p>
                </div>
                <div class="grid gap-3 sm:min-w-96">
                  <div
                    :if={:back_to_draft in @advanced_actions}
                    class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between"
                  >
                    <p class="text-sm text-base-content/70">
                      Return to setup mode so you can freely revise the vote.
                    </p>
                    <.button id="set-session-draft" phx-click="set_status" phx-value-status="draft">
                      Back to draft
                    </.button>
                  </div>
                  <div
                    :if={:cancel in @destructive_actions}
                    class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between"
                  >
                    <p class="text-sm text-base-content/70">
                      Abandon this vote without recording a winner.
                    </p>
                    <.button
                      id="set-session-cancelled"
                      phx-click="set_status"
                      phx-value-status="cancelled"
                      data-confirm="Cancel this voting session without recording a winner?"
                    >
                      Cancel session
                    </.button>
                  </div>
                </div>
              </div>
            </section>

            <div class="grid gap-6 xl:grid-cols-[1fr_22rem]">
              <section id="voting-games-section" class="scroll-mt-24 space-y-3">
                <h2 class="text-xl font-bold">Games In This Vote</h2>
                <div id="voting-session-pool" phx-update="stream" class="grid gap-3 md:grid-cols-2">
                  <p
                    id="empty-session-pool"
                    class="hidden rounded-2xl bg-base-200 p-5 text-base-content/70 only:block md:col-span-2"
                  >
                    No games in this vote yet.
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
                              Starting Votes
                            </p>
                            <p id={"pool-game-base-weight-#{pool_item.id}"} class="text-lg font-black">
                              {pool_item.base_weight}
                            </p>
                          </div>
                          <div class="rounded-xl bg-base-100 p-2">
                            <p class="font-semibold uppercase tracking-wide text-base-content/50">
                              Channel Point Votes
                            </p>
                            <p
                              id={"pool-game-channel-point-vote-total-#{pool_item.id}"}
                              class="text-lg font-black text-primary"
                            >
                              +{pool_item.channel_point_vote_total}
                            </p>
                          </div>
                          <div class="rounded-xl bg-base-100 p-2">
                            <p class="font-semibold uppercase tracking-wide text-base-content/50">
                              Total Votes
                            </p>
                            <p
                              id={"pool-game-final-weight-#{pool_item.id}"}
                              class="text-lg font-black"
                            >
                              {pool_item.final_weight}
                            </p>
                          </div>
                        </div>
                        <div
                          :if={pool_item.twitch_reward_id}
                          class="mt-3 rounded-xl bg-base-100 p-3 text-xs"
                        >
                          <p class="font-semibold uppercase tracking-wide text-base-content/50">
                            Twitch Reward
                          </p>
                          <p id={"pool-game-twitch-reward-#{pool_item.id}"} class="mt-1 font-bold">
                            {pool_item.twitch_reward_title}
                          </p>
                          <p class="text-base-content/60">
                            {pool_item.twitch_reward_cost} points · {pool_item.twitch_reward_status}
                          </p>
                          <p
                            :if={pool_item.twitch_reward_deletion_status == "failed"}
                            id={"pool-game-twitch-reward-cleanup-error-#{pool_item.id}"}
                            class="mt-2 rounded-lg bg-error/10 px-2 py-1 font-semibold text-error"
                          >
                            Cleanup failed: {pool_item.twitch_reward_deletion_error}
                          </p>
                          <p
                            :if={pool_item.twitch_reward_deletion_status == "deleted"}
                            id={"pool-game-twitch-reward-cleanup-deleted-#{pool_item.id}"}
                            class="mt-2 rounded-lg bg-success/10 px-2 py-1 font-semibold text-success"
                          >
                            Twitch reward deleted
                          </p>
                        </div>
                      </div>
                      <div class="flex shrink-0 flex-col gap-2">
                        <.button
                          id={"vote-pool-game-#{pool_item.id}"}
                          phx-click="vote_pool_game"
                          phx-value-id={pool_item.id}
                        >
                          +1 Vote
                        </.button>
                        <.button
                          :if={@selected_session.status == "draft"}
                          id={"remove-pool-game-#{pool_item.id}"}
                          phx-click="remove_pool_game"
                          phx-value-id={pool_item.id}
                          data-confirm="Remove this game from this vote?"
                        >
                          Remove
                        </.button>
                      </div>
                    </div>
                  </article>
                </div>
              </section>

              <section
                id="add-games-section"
                class="scroll-mt-24 space-y-3 rounded-2xl border border-base-300 bg-base-200 p-4"
              >
                <h2 class="text-xl font-bold">Available Games</h2>
                <p class="text-sm text-base-content/70">
                  Add or remove games here without changing whether they appear on the main wheel.
                </p>
                <.form
                  for={@available_games_filter_form}
                  id="available-games-filter-form"
                  phx-change="filter_available_games"
                >
                  <.input
                    field={@available_games_filter_form[:query]}
                    type="search"
                    label="Search available games"
                    placeholder="Filter by title"
                    phx-debounce="200"
                  />
                </.form>
                <div id="available-voting-games" phx-update="stream" class="space-y-2">
                  <p
                    id="empty-available-voting-games"
                    class="hidden rounded-xl bg-base-100 p-4 text-sm text-base-content/70 only:block"
                  >
                    {@available_games_empty_message}
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
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Voting Sessions")
     |> assign(:selected_session_id, selected_session_id_param(params))
     |> assign(:subscribed_voting_session_id, nil)
     |> assign(:available_games_filter, "")
     |> refresh()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:selected_session_id, selected_session_id_param(params))
     |> refresh()}
  end

  @impl true
  def handle_event("create_session", _params, socket) do
    {:ok, session} = Voting.create_voting_session(socket.assigns.current_community, %{})

    {:noreply,
     socket
     |> assign(:selected_session_id, session.id)
     |> put_flash(:info, "Voting session created")
     |> refresh()}
  end

  def handle_event(
        "create_session_from_format",
        %{"wheel_format" => %{"wheel_format_id" => wheel_format_id}},
        socket
      ) do
    wheel_format =
      Voting.get_wheel_format!(
        socket.assigns.current_community,
        String.to_integer(wheel_format_id)
      )

    {:ok, session} =
      Voting.create_voting_session_from_wheel_format(
        socket.assigns.current_community,
        wheel_format
      )

    {:noreply,
     socket
     |> assign(:selected_session_id, session.id)
     |> put_flash(:info, "Voting session created from Wheel Format")
     |> refresh()}
  end

  def handle_event("select_session", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/voting?#{[session_id: id]}")}
  end

  def handle_event("set_status", %{"status" => status}, socket) do
    result =
      if status in ["completed", "closed", "cancelled"] do
        Voting.close_voting_session(socket.assigns.selected_session, status)
      else
        Voting.update_voting_session_status(socket.assigns.selected_session, status)
      end

    case result do
      {:ok, session} ->
        {:noreply,
         socket
         |> assign(:selected_session_id, session.id)
         |> put_flash(:info, "Session marked #{status}")
         |> refresh()}

      {:error, {:twitch_reward_cleanup_failed, session, reason}} ->
        {:noreply,
         socket
         |> assign(:selected_session_id, session.id)
         |> put_flash(:error, "Session marked #{status}, but #{twitch_error(reason)}")
         |> refresh()}
    end
  end

  def handle_event("start_twitch_voting", _params, socket) do
    case Voting.start_twitch_voting(socket.assigns.selected_session) do
      {:ok, session} ->
        {:noreply,
         socket
         |> assign(:selected_session_id, session.id)
         |> put_flash(:info, "Twitch voting started")
         |> refresh()}

      {:error, reason} ->
        Logger.warning("Failed to start Twitch voting: #{inspect(reason)}")

        {:noreply,
         socket
         |> put_flash(:error, twitch_error(reason))
         |> refresh()}
    end
  end

  def handle_event("remove_twitch_rewards", _params, socket) do
    case Voting.remove_twitch_rewards(socket.assigns.selected_session) do
      {:ok, session} ->
        {:noreply,
         socket
         |> assign(:selected_session_id, session.id)
         |> put_flash(:info, "Twitch rewards removed; voting status unchanged")
         |> refresh()}

      {:error, reason} ->
        Logger.warning("Failed to remove Twitch rewards: #{inspect(reason)}")

        {:noreply,
         socket
         |> put_flash(:error, twitch_error(reason))
         |> refresh()}
    end
  end

  def handle_event(
        "filter_available_games",
        %{"available_games_filter" => %{"query" => query}},
        socket
      ) do
    {:noreply, socket |> assign(:available_games_filter, query) |> refresh()}
  end

  def handle_event("populate_pool", _params, socket) do
    {:ok, pool_items} =
      Voting.populate_session_from_wheel_candidates(socket.assigns.selected_session)

    {:noreply,
     socket
     |> put_flash(:info, "Added #{length(pool_items)} wheel games")
     |> refresh()}
  end

  def handle_event("add_pool_game", %{"id" => id}, socket) do
    game = Backlog.get_game!(socket.assigns.current_community, id)
    {:ok, _pool_item} = Voting.add_game_to_session(socket.assigns.selected_session, game)

    {:noreply, refresh(socket)}
  end

  def handle_event("remove_pool_game", %{"id" => id}, socket) do
    pool_item = Enum.find(socket.assigns.pool_items, &(&1.id == String.to_integer(id)))
    {:ok, _pool_item} = Voting.remove_game_from_session(pool_item)

    {:noreply, refresh(socket)}
  end

  def handle_event("vote_pool_game", %{"id" => id}, socket) do
    pool_item = Enum.find(socket.assigns.pool_items, &(&1.id == String.to_integer(id)))
    {:ok, _vote} = Voting.record_vote(pool_item, %{strength: 1, source: "local"})

    {:noreply, refresh(socket)}
  end

  @impl true
  def handle_info({:voting_session_changed, id}, socket) do
    if socket.assigns.selected_session_id == id do
      {:noreply, refresh(socket)}
    else
      {:noreply, socket}
    end
  end

  defp refresh(socket) do
    {:ok, _formats} = Voting.ensure_default_wheel_formats(socket.assigns.current_community)

    sessions = Voting.list_voting_sessions(socket.assigns.current_community)
    wheel_formats = Voting.list_wheel_formats(socket.assigns.current_community)
    selected_session = selected_session(sessions, socket.assigns.selected_session_id)
    pool_items = if selected_session, do: selected_session.voting_session_games, else: []

    unfiltered_available_games =
      if selected_session, do: Voting.list_available_games_for_session(selected_session), else: []

    available_games =
      filter_available_games(unfiltered_available_games, socket.assigns.available_games_filter)

    socket
    |> assign(:wheel_format_options, wheel_format_options(wheel_formats))
    |> assign(:wheel_format_form, wheel_format_form(wheel_formats))
    |> assign(:selected_session, selected_session)
    |> assign(:selected_session_id, selected_session && selected_session.id)
    |> assign(:pool_items, pool_items)
    |> assign(:pool_size, length(pool_items))
    |> assign(
      :available_games_filter_form,
      available_games_filter_form(socket.assigns.available_games_filter)
    )
    |> assign(
      :available_games_empty_message,
      available_games_empty_message(
        unfiltered_available_games,
        available_games,
        socket.assigns.available_games_filter
      )
    )
    |> assign(:has_twitch_rewards?, has_twitch_rewards?(pool_items))
    |> assign(:failed_twitch_reward_deletions, failed_twitch_reward_deletions(pool_items))
    |> assign(:twitch_connected?, Twitch.credential_configured?())
    |> assign_twitch_voting_state(pool_items)
    |> assign_lifecycle_actions()
    |> stream(:voting_sessions, sessions, reset: true)
    |> stream(:voting_session_pool, pool_items, reset: true)
    |> stream(:available_games, available_games, reset: true)
    |> subscribe_to_selected_session()
  end

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

  defp selected_session([], _selected_session_id), do: nil

  defp selected_session(sessions, nil), do: hd(sessions)

  defp selected_session(sessions, selected_session_id) do
    Enum.find(sessions, &(&1.id == selected_session_id)) || hd(sessions)
  end

  defp selected_session_id_param(%{"session_id" => session_id}) do
    case Integer.parse(session_id) do
      {id, ""} -> id
      _invalid -> nil
    end
  end

  defp selected_session_id_param(_params), do: nil

  defp session_button_class(%VotingSession{} = session, selected_session) do
    [
      "flex w-full items-center justify-between gap-2 rounded-xl border p-3 text-left transition hover:-translate-y-0.5 hover:shadow-md",
      selected_session && session.id == selected_session.id && "border-primary bg-primary/10",
      (!selected_session || session.id != selected_session.id) && "border-base-300 bg-base-200"
    ]
  end

  defp filter_available_games(available_games, filter) do
    normalized_filter = filter |> String.trim() |> String.downcase()

    if normalized_filter == "" do
      available_games
    else
      Enum.filter(available_games, fn game ->
        game.title
        |> String.downcase()
        |> String.contains?(normalized_filter)
      end)
    end
  end

  defp available_games_filter_form(filter) do
    to_form(%{"query" => filter}, as: :available_games_filter)
  end

  defp wheel_format_form([]), do: to_form(%{"wheel_format_id" => ""}, as: :wheel_format)

  defp wheel_format_form([wheel_format | _wheel_formats]) do
    to_form(%{"wheel_format_id" => wheel_format.id}, as: :wheel_format)
  end

  defp wheel_format_options(wheel_formats) do
    Enum.map(wheel_formats, &{&1.name, &1.id})
  end

  defp available_games_empty_message([], _available_games, _filter),
    do: "Every game is already in this vote."

  defp available_games_empty_message(_unfiltered_available_games, [], filter) do
    if String.trim(filter) == "" do
      "Every game is already in this vote."
    else
      "No available games match this search."
    end
  end

  defp available_games_empty_message(_unfiltered_available_games, _available_games, _filter),
    do: "Every game is already in this vote."

  defp has_twitch_rewards?(pool_items) do
    Enum.any?(pool_items, fn pool_item ->
      pool_item.twitch_reward_id not in [nil, ""] and
        pool_item.twitch_reward_deletion_status != "deleted"
    end)
  end

  defp failed_twitch_reward_deletions(pool_items) do
    Enum.count(pool_items, &(&1.twitch_reward_deletion_status == "failed"))
  end

  defp assign_twitch_voting_state(socket, pool_items) do
    hint =
      twitch_voting_hint(
        socket.assigns.twitch_connected?,
        socket.assigns.selected_session,
        pool_items
      )

    socket
    |> assign(:twitch_voting_hint, hint)
    |> assign(:can_start_twitch_voting?, is_nil(hint))
  end

  defp twitch_voting_hint(_connected?, nil, _pool_items), do: nil

  defp twitch_voting_hint(false, _selected_session, _pool_items),
    do: "Connect Twitch before starting Twitch voting."

  defp twitch_voting_hint(_connected?, _selected_session, []),
    do: "Add games to this vote before starting Twitch voting."

  defp twitch_voting_hint(_connected?, selected_session, pool_items) do
    if Enum.all?(pool_items, fn pool_item ->
         pool_item.twitch_reward_id not in [nil, ""] and
           pool_item.twitch_reward_deletion_status != "deleted"
       end) do
      "Twitch voting rewards are already created for this session."
    else
      case Voting.validate_twitch_reward_creation(selected_session) do
        :ok -> nil
        {:error, reason} -> twitch_error(reason)
      end
    end
  end

  defp assign_lifecycle_actions(%{assigns: %{selected_session: nil}} = socket) do
    socket
    |> assign(:lifecycle, nil)
    |> assign(:secondary_actions, [])
    |> assign(:advanced_actions, [])
    |> assign(:destructive_actions, [])
  end

  defp assign_lifecycle_actions(socket) do
    lifecycle = lifecycle(socket.assigns)

    socket
    |> assign(:lifecycle, lifecycle)
    |> assign(:secondary_actions, secondary_actions(socket.assigns, lifecycle.primary_action))
    |> assign(:advanced_actions, advanced_actions(socket.assigns))
    |> assign(:destructive_actions, destructive_actions(socket.assigns))
  end

  defp lifecycle(%{selected_session: %{status: "draft"}, pool_size: 0}) do
    %{
      state_label: "Draft",
      state_description:
        "The streamer is preparing the vote. The pool can be edited freely and viewers cannot vote yet.",
      next_action_copy: "Add games to this vote.",
      blocking_issue: nil,
      primary_action: :populate_pool
    }
  end

  defp lifecycle(%{selected_session: %{status: "draft"}}) do
    %{
      state_label: "Draft",
      state_description:
        "The streamer is preparing the vote. The pool can be edited freely and viewers cannot vote yet.",
      next_action_copy: "Open voting when the pool is ready.",
      blocking_issue: nil,
      primary_action: :open_voting
    }
  end

  defp lifecycle(%{selected_session: %{status: "open"}, twitch_voting_hint: hint} = assigns)
       when is_binary(hint) do
    %{
      state_label: "Open",
      state_description: "This is the active vote. Viewers can vote or influence it.",
      next_action_copy: open_blocked_next_action(hint),
      blocking_issue: hint,
      primary_action: open_blocked_primary_action(assigns)
    }
  end

  defp lifecycle(%{selected_session: %{status: "open"}, has_twitch_rewards?: true}) do
    %{
      state_label: "Open",
      state_description: "This is the active vote. Twitch voting rewards are collecting votes.",
      next_action_copy: "Mark voting ready to spin when voting is finished.",
      blocking_issue: nil,
      primary_action: :ready_to_spin
    }
  end

  defp lifecycle(%{selected_session: %{status: "open"}}) do
    %{
      state_label: "Open",
      state_description: "This is the active vote. Viewers can vote or influence it.",
      next_action_copy: "Start Twitch voting or keep collecting manual votes.",
      blocking_issue: nil,
      primary_action: :start_twitch_voting
    }
  end

  defp lifecycle(%{selected_session: %{status: "locked"}}) do
    %{
      state_label: "Ready to Spin",
      state_description:
        "Voting is frozen and the streamer is ready to spin. No new viewer votes should be collected.",
      next_action_copy: "Spin the wheel.",
      blocking_issue: nil,
      primary_action: :spin
    }
  end

  defp lifecycle(%{selected_session: %{status: status}}) when status in ["completed", "closed"] do
    %{
      state_label: "Completed",
      state_description: "The wheel has been spun and a result was recorded.",
      next_action_copy: "View the recap or create another session.",
      blocking_issue: nil,
      primary_action: :view_recap
    }
  end

  defp lifecycle(%{selected_session: %{status: "cancelled"}}) do
    %{
      state_label: "Cancelled",
      state_description: "This session was abandoned without a winner.",
      next_action_copy: "Create a new session when ready.",
      blocking_issue: nil,
      primary_action: :create_session
    }
  end

  defp open_blocked_next_action("Connect Twitch" <> _rest),
    do: "Connect Twitch to start Twitch voting."

  defp open_blocked_next_action("Add games" <> _rest),
    do: "Add games before starting Twitch voting."

  defp open_blocked_next_action("Twitch voting rewards are already created" <> _rest),
    do: "Mark voting ready to spin when voting is finished."

  defp open_blocked_next_action(_hint),
    do: "Fix the blocking issue before starting Twitch voting."

  defp open_blocked_primary_action(%{has_twitch_rewards?: true}), do: :ready_to_spin
  defp open_blocked_primary_action(%{pool_size: 0}), do: :populate_pool
  defp open_blocked_primary_action(%{twitch_connected?: false}), do: :manage_twitch
  defp open_blocked_primary_action(_assigns), do: nil

  defp secondary_actions(assigns, primary_action) do
    assigns
    |> available_secondary_actions()
    |> Enum.reject(&(&1 == primary_action))
  end

  defp available_secondary_actions(%{selected_session: %{status: "draft"}}), do: [:populate_pool]

  defp available_secondary_actions(%{selected_session: %{status: "open"}} = assigns) do
    []
    |> maybe_add(:populate_pool, true)
    |> maybe_add(:start_twitch_voting, assigns.can_start_twitch_voting?)
    |> maybe_add(:remove_twitch_rewards, assigns.twitch_connected? && assigns.has_twitch_rewards?)
    |> maybe_add(:ready_to_spin, assigns.pool_size > 0)
    |> maybe_add(:spin_manually, assigns.pool_size > 0)
  end

  defp available_secondary_actions(%{selected_session: %{status: "locked"}}),
    do: [:reopen_voting]

  defp available_secondary_actions(%{selected_session: %{status: status}} = assigns)
       when status in ["completed", "closed", "cancelled"] do
    []
    |> maybe_add(:remove_twitch_rewards, assigns.twitch_connected? && assigns.has_twitch_rewards?)
    |> maybe_add(:create_session, status in ["completed", "closed"])
  end

  defp advanced_actions(%{selected_session: %{status: status}}) when status != "draft",
    do: [:back_to_draft]

  defp advanced_actions(_assigns), do: []

  defp destructive_actions(%{selected_session: %{status: status}})
       when status in ["draft", "open", "locked"],
       do: [:cancel]

  defp destructive_actions(_assigns), do: []

  defp maybe_add(actions, action, true), do: [action | actions]
  defp maybe_add(actions, _action, false), do: actions

  defp status_label("locked"), do: "Ready to Spin"
  defp status_label("completed"), do: "Completed"
  defp status_label("closed"), do: "Completed"
  defp status_label(status), do: String.capitalize(status)

  defp twitch_error({:missing_config, missing}),
    do: "Missing Twitch config: #{Enum.join(missing, ", ")}"

  defp twitch_error(:missing_twitch_credential),
    do: "Connect Twitch before starting Twitch voting"

  defp twitch_error(:missing_twitch_refresh_token),
    do: "Reconnect Twitch before starting Twitch voting"

  defp twitch_error(:empty_pool), do: "Add games to this vote before starting Twitch voting"
  defp twitch_error(:no_twitch_rewards), do: "No Twitch rewards to remove"

  defp twitch_error({:twitch_reward_pool_too_large, count, max_count}),
    do:
      "Twitch can create at most #{max_count} reward titles for one vote; this vote has #{count} games."

  defp twitch_error({:twitch_reward_title_too_long, title, max_length}),
    do: "Twitch reward title is too long (max #{max_length} characters): #{title}"

  defp twitch_error({:duplicate_twitch_reward_titles, [title | _titles]}),
    do: "Twitch reward titles must be unique; duplicate title: #{title}"

  defp twitch_error({:twitch_reward_deletion_failed, count}),
    do: "#{count} Twitch reward cleanup failed"

  defp twitch_error({:twitch_http_error, status, body}) do
    message = twitch_http_error_message(body)

    if message do
      "Twitch API error #{status}: #{message}"
    else
      "Twitch API error #{status}"
    end
  end

  defp twitch_error({:error, reason}), do: twitch_error(reason)

  defp twitch_error(_reason), do: "Could not complete Twitch action"

  defp twitch_http_error_message(%{"message" => message}) when is_binary(message), do: message
  defp twitch_http_error_message(%{message: message}) when is_binary(message), do: message
  defp twitch_http_error_message(body) when is_binary(body) and body != "", do: body
  defp twitch_http_error_message(_body), do: nil
end
