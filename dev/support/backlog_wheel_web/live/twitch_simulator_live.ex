defmodule BacklogWheelWeb.TwitchSimulatorLive do
  use BacklogWheelWeb, :live_view

  alias BacklogWheel.Twitch
  alias BacklogWheel.Twitch.SimulatorClient
  alias BacklogWheel.Voting.TwitchRedemptions
  alias BacklogWheel.Voting

  @impl true
  def mount(_params, _session, socket) do
    if Application.get_env(:backlog_wheel, :twitch_simulator, false) do
      if connected?(socket), do: SimulatorClient.subscribe(socket.assigns.current_community)

      {:ok,
       socket
       |> assign(
         :simulator_connected?,
         Twitch.credential_configured?(socket.assigns.current_community)
       )
       |> assign(:sample_session_id, nil)
       |> assign(
         :redeem_form,
         to_form(%{"user_login" => "viewer", "user_input" => "", "delay" => "false"},
           as: :simulator
         )
       )
       |> stream_configure(:simulator_rewards,
         dom_id: &"simulator-reward-#{&1.voting_session_id}"
       )
       |> stream_configure(:deleted_rewards, dom_id: &"simulator-deleted-#{&1.id}")
       |> stream_configure(:simulator_redemptions, dom_id: &"simulator-redemption-#{&1.id}")
       |> stream_configure(:simulator_messages, dom_id: &"simulator-message-#{&1.id}")
       |> refresh_simulator()}
    else
      {:ok, redirect(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_info(:simulator_updated, socket), do: {:noreply, refresh_simulator(socket)}

  defp refresh_simulator(socket) do
    community = socket.assigns.current_community

    socket
    |> assign(:failures, SimulatorClient.failures(community))
    |> stream(:simulator_rewards, SimulatorClient.rewards(community), reset: true)
    |> stream(:deleted_rewards, SimulatorClient.deleted_rewards(community), reset: true)
    |> stream(:simulator_redemptions, SimulatorClient.redemptions(community), reset: true)
    |> stream(:simulator_messages, SimulatorClient.messages(community), reset: true)
  end

  @impl true
  def handle_event("connect", _params, socket) do
    case SimulatorClient.connect(socket.assigns.current_community) do
      {:ok, community} ->
        {:noreply,
         socket |> assign(:current_community, community) |> assign(:simulator_connected?, true)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not connect the simulated channel.")}
    end
  end

  def handle_event("redeem", %{"reward_id" => reward_id, "simulator" => params}, socket) do
    user_login = Map.get(params, "user_login", "viewer")
    user_input = Map.get(params, "user_input", "")
    delay? = Map.get(params, "delay") == "true"

    case SimulatorClient.redeem(
           socket.assigns.current_community,
           reward_id,
           user_login,
           user_input,
           delay?
         ) do
      {:ok, _redemption} ->
        if not delay?, do: TwitchRedemptions.process_pending(SimulatorClient)
        {:noreply, refresh_simulator(socket)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not redeem the simulated reward.")
         |> refresh_simulator()}
    end
  end

  def handle_event("deliver", %{"id" => id}, socket) do
    case SimulatorClient.deliver(socket.assigns.current_community, id) do
      {:ok, _} ->
        TwitchRedemptions.process_pending(SimulatorClient)
        {:noreply, refresh_simulator(socket)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not deliver the simulated webhook.")
         |> refresh_simulator()}
    end
  end

  def handle_event("toggle_failure", %{"kind" => kind}, socket)
      when kind in ["resolution", "reconciliation", "chat", "deletion", "disable", "creation"] do
    :ok = SimulatorClient.toggle_failure(socket.assigns.current_community, kind)
    {:noreply, refresh_simulator(socket)}
  end

  def handle_event("retry", _params, socket) do
    TwitchRedemptions.reconcile_rewards(SimulatorClient)
    TwitchRedemptions.process_pending(SimulatorClient)
    Voting.cleanup_finished_twitch_rewards(client: SimulatorClient)
    {:noreply, refresh_simulator(socket)}
  end

  def handle_event("create_sample", _params, socket) do
    case SimulatorClient.create_sample_vote(socket.assigns.current_community) do
      {:ok, session} -> {:noreply, assign(socket, :sample_session_id, session.id)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not create the sample vote.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_community={@current_community}>
      <section
        id="twitch-simulator"
        class="mx-auto max-w-4xl rounded-3xl border border-base-300 bg-base-100 p-8 shadow-xl"
      >
        <p class="text-sm font-bold uppercase tracking-widest text-primary">Development simulator</p>
        <h1 class="mt-3 text-3xl font-black">Twitch simulator</h1>
        <p class="mt-3 text-base-content/70">Connect a simulated channel to test voting locally.</p>
        <p
          :if={@simulator_connected?}
          id="simulator-connected"
          class="mt-5 font-semibold text-success"
        >
          Simulated channel connected
        </p>
        <.button
          :if={!@simulator_connected?}
          id="simulator-connect"
          phx-click="connect"
          class="mt-5 btn btn-primary"
        >Connect simulated channel</.button>
        <div :if={@simulator_connected?} class="mt-4 flex flex-wrap items-center gap-3">
          <.button id="simulator-create-sample" phx-click="create_sample">Create sample vote</.button>
          <.link
            :if={@sample_session_id}
            id="simulator-sample-vote-link"
            navigate={~p"/voting?#{[session_id: @sample_session_id]}"}
            class="font-semibold text-primary underline"
          >Open sample vote</.link>
        </div>
        <div id="simulator-rewards" phx-update="stream" class="mt-6 grid gap-3">
          <p id="simulator-rewards-empty" class="hidden text-base-content/60 only:block">
            No simulated rewards yet. Start Twitch voting from a session.
          </p>
          <article
            :for={{id, reward} <- @streams.simulator_rewards}
            id={id}
            class="rounded-2xl border border-base-300 bg-base-200 p-4"
          >
            <h2 class="font-bold">{reward.title}</h2>
            <p class="text-sm text-base-content/70">
              {reward.cost} points · {if reward.enabled, do: "enabled", else: "disabled"}
            </p>
            <.form
              :if={reward.enabled}
              for={@redeem_form}
              id={"simulator-redeem-form-#{reward.voting_session_id}"}
              phx-submit="redeem"
              class="mt-4 grid gap-3 sm:grid-cols-2"
            >
              <.input type="hidden" name="reward_id" value={reward.id} />
              <.input
                field={@redeem_form[:user_login]}
                id={"simulator-viewer-#{reward.id}"}
                label="Viewer login"
              />
              <.input
                field={@redeem_form[:user_input]}
                id={"simulator-input-#{reward.id}"}
                label="Game number"
              />
              <.input
                field={@redeem_form[:delay]}
                id={"simulator-delay-#{reward.id}"}
                type="checkbox"
                label="Delay webhook delivery"
              />
              <.button id={"simulator-redeem-#{reward.id}"} variant="primary">Redeem</.button>
            </.form>
          </article>
        </div>
        <h2 class="mt-8 text-xl font-bold">Deleted rewards</h2>
        <div id="simulator-deleted-rewards" phx-update="stream" class="mt-3 grid gap-3">
          <p id="simulator-deleted-rewards-empty" class="hidden text-base-content/60 only:block">
            No rewards have been deleted.
          </p>
          <p
            :for={{id, reward} <- @streams.deleted_rewards}
            id={id}
            class="rounded-xl bg-base-200 p-4"
          >
            {reward.title} · deleted
          </p>
        </div>
        <h2 class="mt-8 text-xl font-bold">Redemptions</h2>
        <div id="simulator-redemptions" phx-update="stream" class="mt-3 grid gap-3">
          <p id="simulator-redemptions-empty" class="hidden text-base-content/60 only:block">
            No redemptions yet.
          </p>
          <article
            :for={{id, redemption} <- @streams.simulator_redemptions}
            id={id}
            class="rounded-xl bg-base-200 p-4"
          >
            <p class="font-semibold">@{redemption.user_login} · {redemption.status}</p>
            <p class="text-sm text-base-content/70">Entered: {redemption.user_input}</p>
            <.button
              id={"simulator-deliver-#{redemption.id}"}
              phx-click="deliver"
              phx-value-id={redemption.id}
              class="mt-3 btn btn-sm btn-ghost"
            >
              {if redemption.delivered, do: "Replay webhook", else: "Deliver webhook"}
            </.button>
          </article>
        </div>
        <h2 class="mt-8 text-xl font-bold">Simulated chat</h2>
        <div id="simulator-messages" phx-update="stream" class="mt-3 grid gap-3">
          <p id="simulator-messages-empty" class="hidden text-base-content/60 only:block">
            No chat messages yet.
          </p>
          <p
            :for={{id, message} <- @streams.simulator_messages}
            id={id}
            class="rounded-xl bg-base-200 p-4"
          >
            {message.text}
          </p>
        </div>
        <section
          id="simulator-failures"
          class="mt-8 rounded-2xl border border-base-300 bg-base-200 p-5"
        >
          <h2 class="text-xl font-bold">Failure controls</h2>
          <p class="mt-2 text-sm text-base-content/70">
            Switch a simulated Twitch failure on, then switch it off and run retries.
          </p>
          <div class="mt-4 flex flex-wrap gap-2">
            <.button
              :for={
                {kind, label} <- [
                  {"resolution", "Refund / fulfillment"},
                  {"reconciliation", "Reconciliation"},
                  {"chat", "Chat"},
                  {"creation", "Reward creation"},
                  {"disable", "Reward disabling"},
                  {"deletion", "Reward deletion"}
                ]
              }
              id={"simulator-fail-#{kind}"}
              phx-click="toggle_failure"
              phx-value-kind={kind}
              class="btn btn-sm btn-ghost"
            >
              {label}: {if @failures[kind], do: "FAIL", else: "OK"}
            </.button>
            <.button id="simulator-retry" phx-click="retry" class="btn btn-sm btn-primary">Run retries now</.button>
          </div>
        </section>
      </section>
    </Layouts.app>
    """
  end
end
