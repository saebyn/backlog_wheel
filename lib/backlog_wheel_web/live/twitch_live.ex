defmodule BacklogWheelWeb.TwitchLive do
  use BacklogWheelWeb, :live_view

  alias BacklogWheel.Communities
  alias BacklogWheel.Twitch

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_community={@current_community}>
      <div class="grid gap-6 lg:grid-cols-[14rem_1fr]">
        <Layouts.settings_nav active={:twitch} />

        <section class="rounded-[2rem] border border-base-300 bg-base-100 p-6 shadow-xl">
          <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <p class="text-sm font-semibold uppercase tracking-[0.24em] text-primary">
                Twitch
              </p>
              <h1 class="mt-2 text-4xl font-black tracking-tight">Connection</h1>
              <p class="mt-3 text-base-content/70">
                Authorize this local app to create and remove temporary channel point rewards.
              </p>
            </div>

            <span
              id="twitch-settings-connection-status"
              class={[
                "badge badge-lg",
                @twitch_connected? && "badge-success",
                !@twitch_connected? && "badge-warning"
              ]}
            >
              {if @twitch_connected?, do: "Connected", else: "Not connected"}
            </span>
          </div>

          <div class="mt-6 grid gap-3 sm:grid-cols-4">
            <div class="rounded-2xl bg-base-200 p-4">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                App config
              </p>
              <p id="twitch-settings-config-status" class="mt-1 font-bold">
                {if @twitch_configured?, do: "Configured", else: "Missing values"}
              </p>
            </div>
            <div class="rounded-2xl bg-base-200 p-4">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                Reward cost
              </p>
              <p id="twitch-settings-reward-cost" class="mt-1 font-bold">
                {@reward_cost || "Not configured"}
              </p>
            </div>
            <div class="min-w-0 rounded-2xl bg-base-200 p-4">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                Scope
              </p>
              <p class="mt-1 break-words font-bold leading-snug [overflow-wrap:anywhere]">
                channel:manage:redemptions
              </p>
            </div>
            <div class="rounded-2xl bg-base-200 p-4">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                Webhook events
              </p>
              <p id="twitch-settings-eventsub-status" class="mt-1 font-bold">
                {if @eventsub_configured?, do: "Configured", else: "Missing secret"}
              </p>
            </div>
          </div>

          <p
            :if={@missing_config != []}
            id="twitch-settings-missing-config"
            class="mt-4 rounded-2xl border border-warning/30 bg-warning/10 p-4 text-sm"
          >
            Missing Twitch config: {Enum.join(@missing_config, ", ")}
          </p>

          <p
            :if={!@eventsub_configured?}
            id="twitch-settings-eventsub-warning"
            class="mt-4 rounded-2xl border border-warning/30 bg-warning/10 p-4 text-sm"
          >
            Twitch EventSub is not configured. Channel point rewards can be created, but redemptions
            will not be delivered as votes until an EventSub secret is saved and Twitch is reconnected.
          </p>

          <.form
            for={@form}
            id="twitch-settings-form"
            class="mt-6 grid gap-4 rounded-3xl border border-base-300 bg-base-200/60 p-5"
            phx-change="validate"
            phx-submit="save"
          >
            <div class="grid gap-4 md:grid-cols-2">
              <.input
                field={@form[:twitch_broadcaster_id]}
                type="text"
                label="Twitch broadcaster ID"
                placeholder="28728577"
              />
              <.input
                field={@form[:twitch_reward_cost]}
                type="number"
                label="Reward cost"
                min="1"
              />
            </div>

            <div class="rounded-2xl border border-base-300 bg-base-100 p-4">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                EventSub secret
              </p>
              <p id="twitch-settings-eventsub-secret-status" class="mt-1 font-bold">
                {if @eventsub_configured?, do: "Configured", else: "Missing"}
              </p>
              <p class="mt-2 text-sm text-base-content/70">
                The secret is generated and stored by Backlog Wheel. Rotate it if it may have been
                exposed, then reconnect Twitch to refresh the webhook subscription.
              </p>
            </div>

            <div class="flex flex-wrap gap-2">
              <.button id="save-twitch-settings">Save Twitch settings</.button>
              <.button id="rotate-eventsub-secret" type="button" phx-click="rotate_secret">
                {if @eventsub_configured?,
                  do: "Rotate EventSub secret",
                  else: "Generate EventSub secret"}
              </.button>
            </div>
          </.form>

          <div class="mt-6 flex flex-wrap gap-2">
            <.button
              id="connect-twitch"
              href={~p"/twitch/oauth/start"}
              disabled={!@twitch_configured?}
            >
              {if @twitch_connected?, do: "Reconnect Twitch", else: "Connect Twitch"}
            </.button>
            <.button
              id="disconnect-twitch"
              phx-click="disconnect"
              disabled={!@twitch_connected?}
              data-confirm="Disconnect Twitch from this local app? Existing channel point rewards are not removed."
            >
              Disconnect
            </.button>
            <.button id="back-to-voting" href={~p"/voting"}>Back to voting</.button>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Twitch Connection") |> refresh()}
  end

  @impl true
  def handle_event("disconnect", _params, socket) do
    :ok = Twitch.delete_credential()

    {:noreply,
     socket
     |> put_flash(:info, "Twitch disconnected")
     |> refresh()}
  end

  @impl true
  def handle_event("validate", %{"community" => params}, socket) do
    form =
      socket.assigns.current_community
      |> Communities.change_community_twitch_settings(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event("save", %{"community" => params}, socket) do
    case Communities.update_community_twitch_settings(socket.assigns.current_community, params) do
      {:ok, community} ->
        {:noreply,
         socket
         |> assign(:current_community, community)
         |> put_flash(:info, "Twitch settings updated successfully")
         |> refresh()}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(%{changeset | action: :insert}))}
    end
  end

  @impl true
  def handle_event("rotate_secret", _params, socket) do
    params = %{
      "twitch_broadcaster_id" => socket.assigns.current_community.twitch_broadcaster_id,
      "twitch_reward_cost" => socket.assigns.current_community.twitch_reward_cost,
      "twitch_eventsub_secret" => Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    }

    case Communities.update_community_twitch_settings(socket.assigns.current_community, params) do
      {:ok, community} ->
        {:noreply,
         socket
         |> assign(:current_community, community)
         |> put_flash(:info, "EventSub secret rotated. Reconnect Twitch to update the webhook.")
         |> refresh()}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(%{changeset | action: :insert}))}
    end
  end

  defp refresh(socket) do
    community = socket.assigns.current_community
    config = Twitch.config(community)

    socket
    |> assign(:form, to_form(Communities.change_community_twitch_settings(community)))
    |> assign(:twitch_connected?, Twitch.credential_configured?())
    |> assign(:twitch_configured?, match?({:ok, _config}, config))
    |> assign(:missing_config, missing_config(config))
    |> assign(:reward_cost, reward_cost(config))
    |> assign(:eventsub_configured?, eventsub_configured?(config))
  end

  defp missing_config({:error, {:missing_config, missing}}), do: missing
  defp missing_config(_config), do: []

  defp reward_cost({:ok, config}), do: config.reward_cost
  defp reward_cost(_config), do: nil

  defp eventsub_configured?({:ok, config}),
    do: match?({:ok, _secret}, Twitch.eventsub_secret(config))

  defp eventsub_configured?(_config), do: false
end
