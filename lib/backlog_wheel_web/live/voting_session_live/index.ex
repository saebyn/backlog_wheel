defmodule BacklogWheelWeb.VotingSessionLive.Index do
  use BacklogWheelWeb, :live_view

  alias BacklogWheel.Backlog
  alias BacklogWheel.Twitch
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
            <:subtitle>Create game lists, collect channel point votes, and spin a winner.</:subtitle>
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
                <h1 class="mt-2 text-4xl font-black tracking-tight">Games In This Vote</h1>
                <div class="mt-3 flex flex-wrap gap-2">
                  <span id="selected-session-status" class="badge badge-primary capitalize">
                    {@selected_session.status}
                  </span>
                  <span id="selected-session-pool-size" class="badge badge-ghost">
                    {@pool_size} games in this vote
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
                <.button id="populate-session-pool" phx-click="populate_pool">
                  Add wheel games
                </.button>
                <.button
                  id="spin-selected-voting-session"
                  navigate={~p"/wheel?#{[voting_session_id: @selected_session.id]}"}
                  disabled={@pool_size == 0}
                >
                  Spin these games
                </.button>
                <.button id="manage-twitch" href={~p"/twitch"}>
                  Manage Twitch
                </.button>
                <.button
                  id="start-twitch-voting"
                  phx-click="start_twitch_voting"
                  disabled={!@can_start_twitch_voting?}
                >
                  Start Twitch Voting
                </.button>
                <.button
                  id="remove-twitch-rewards"
                  phx-click="remove_twitch_rewards"
                  disabled={!@twitch_connected? || !@has_twitch_rewards?}
                  data-confirm="Remove Twitch channel point rewards for this session? Voting stays open."
                >
                  Remove Twitch Rewards
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

            <p
              :if={@twitch_voting_hint}
              id="twitch-voting-hint"
              class="rounded-2xl border border-base-300 bg-base-200 px-4 py-3 text-sm text-base-content/70"
            >
              {@twitch_voting_hint}
            </p>

            <div class="grid gap-6 xl:grid-cols-[1fr_22rem]">
              <section class="space-y-3">
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
                              id={"pool-game-boost-total-#{pool_item.id}"}
                              class="text-lg font-black text-primary"
                            >
                              +{pool_item.boost_total}
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
                        </div>
                      </div>
                      <div class="flex shrink-0 flex-col gap-2">
                        <.button
                          id={"boost-pool-game-#{pool_item.id}"}
                          phx-click="boost_pool_game"
                          phx-value-id={pool_item.id}
                        >
                          +1 Vote
                        </.button>
                        <.button
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

              <section class="space-y-3 rounded-2xl border border-base-300 bg-base-200 p-4">
                <h2 class="text-xl font-bold">Available Games</h2>
                <p class="text-sm text-base-content/70">
                  Add or remove games here without changing whether they appear on the main wheel.
                </p>
                <div id="available-voting-games" phx-update="stream" class="space-y-2">
                  <p
                    id="empty-available-voting-games"
                    class="hidden rounded-xl bg-base-100 p-4 text-sm text-base-content/70 only:block"
                  >
                    Every game is already in this vote.
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
     |> assign(:subscribed_voting_session_id, nil)
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

  def handle_event("start_twitch_voting", _params, socket) do
    case Voting.start_twitch_voting(socket.assigns.selected_session) do
      {:ok, session} ->
        {:noreply,
         socket
         |> assign(:selected_session_id, session.id)
         |> put_flash(:info, "Twitch voting started")
         |> refresh()}

      {:error, reason} ->
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
        {:noreply,
         socket
         |> put_flash(:error, twitch_error(reason))
         |> refresh()}
    end
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

  @impl true
  def handle_info({:voting_session_changed, id}, socket) do
    if socket.assigns.selected_session_id == id do
      {:noreply, refresh(socket)}
    else
      {:noreply, socket}
    end
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
    |> assign(:has_twitch_rewards?, has_twitch_rewards?(pool_items))
    |> assign(:twitch_connected?, Twitch.credential_configured?())
    |> assign_twitch_voting_state(pool_items)
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

  defp session_button_class(%VotingSession{} = session, selected_session) do
    [
      "flex w-full items-center justify-between gap-2 rounded-xl border p-3 text-left transition hover:-translate-y-0.5 hover:shadow-md",
      selected_session && session.id == selected_session.id && "border-primary bg-primary/10",
      (!selected_session || session.id != selected_session.id) && "border-base-300 bg-base-200"
    ]
  end

  defp has_twitch_rewards?(pool_items) do
    Enum.any?(pool_items, &(&1.twitch_reward_id not in [nil, ""]))
  end

  defp assign_twitch_voting_state(socket, pool_items) do
    hint = twitch_voting_hint(socket.assigns.twitch_connected?, pool_items)

    socket
    |> assign(:twitch_voting_hint, hint)
    |> assign(:can_start_twitch_voting?, is_nil(hint))
  end

  defp twitch_voting_hint(false, _pool_items),
    do: "Connect Twitch before starting Twitch voting."

  defp twitch_voting_hint(_connected?, []),
    do: "Add games to this vote before starting Twitch voting."

  defp twitch_voting_hint(_connected?, pool_items) do
    if Enum.all?(pool_items, &(&1.twitch_reward_id not in [nil, ""])) do
      "Twitch voting rewards are already created for this session."
    end
  end

  defp status_label("draft"), do: "Draft"
  defp status_label("open"), do: "Open"
  defp status_label("locked"), do: "Lock"
  defp status_label("closed"), do: "Close"
  defp status_label("cancelled"), do: "Cancel"

  defp twitch_error({:missing_config, missing}),
    do: "Missing Twitch config: #{Enum.join(missing, ", ")}"

  defp twitch_error(:missing_twitch_credential),
    do: "Connect Twitch before starting Twitch voting"

  defp twitch_error(:empty_pool), do: "Add games to this vote before starting Twitch voting"
  defp twitch_error(:no_twitch_rewards), do: "No Twitch rewards to remove"
  defp twitch_error(_reason), do: "Could not start Twitch voting"
end
