defmodule BacklogWheelWeb.TwitchLive do
  use BacklogWheelWeb, :live_view

  alias BacklogWheel.Communities
  alias BacklogWheel.Twitch

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_community={@current_community}>
      <div class="grid gap-6 lg:grid-cols-[14rem_minmax(0,1fr)]">
        <Layouts.settings_nav active={:twitch} />

        <section class="max-w-5xl rounded-[2rem] border border-base-300 bg-base-100 p-6 shadow-xl sm:p-8">
          <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <p class="text-sm font-semibold uppercase tracking-[0.24em] text-primary">
                Twitch
              </p>
              <h1 class="mt-2 text-4xl font-black tracking-tight">Twitch integration</h1>
              <p class="mt-3 max-w-3xl text-base-content/70">
                Connect Twitch so Backlog Wheel can create and remove temporary channel point rewards for voting sessions.
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

          <section
            id="twitch-connected-account"
            class="mt-8 rounded-3xl bg-base-200/60 p-5 sm:p-6"
          >
            <h2 class="text-lg font-bold">Connected account</h2>
            <dl class="mt-4 grid gap-4 sm:grid-cols-[10rem_1fr] sm:items-start">
              <dt class="text-sm font-semibold text-base-content/60">Connection status</dt>
              <dd id="twitch-settings-account-status" class="font-semibold">
                {if @twitch_connected?, do: "Connected", else: "Not connected"}
              </dd>

              <dt class="text-sm font-semibold text-base-content/60">Channel</dt>
              <dd id="twitch-settings-channel-name" class="font-semibold">
                {channel_label(@current_community)}
              </dd>

              <dt class="text-sm font-semibold text-base-content/60">Broadcaster ID</dt>
              <dd
                id="twitch-settings-broadcaster-id"
                class="break-words font-mono text-sm text-base-content/70 [overflow-wrap:anywhere]"
              >
                {@current_community.twitch_broadcaster_id || "Available after connecting Twitch"}
              </dd>
            </dl>
            <p id="twitch-settings-capability" class="mt-4 text-sm leading-6 text-base-content/70">
              Backlog Wheel can manage temporary custom rewards for game-voting sessions.
            </p>
          </section>

          <p
            :if={@missing_config != []}
            id="twitch-settings-missing-config"
            class="mt-4 rounded-2xl border border-warning/30 bg-warning/10 p-4 text-sm"
          >
            Missing Twitch config: {Enum.join(@missing_config, ", ")}
          </p>

          <section class="mt-8 border-t border-base-300 pt-8">
            <h2 class="text-xl font-bold">Channel point rewards</h2>
            <.form
              for={@form}
              id="twitch-settings-form"
              class="mt-5 grid max-w-xl gap-4"
              phx-change="validate"
              phx-submit="save"
            >
              <p id="twitch-settings-reward-cost-help" class="text-sm leading-6 text-base-content/70">
                The number of channel points viewers spend for each temporary game-voting reward.
              </p>
              <.input
                field={@form[:twitch_reward_cost]}
                type="number"
                label="Reward cost"
                min="1"
              />

              <div>
                <.button id="save-twitch-settings" variant="primary">Save changes</.button>
              </div>
            </.form>
          </section>

          <section class="mt-8 border-t border-base-300 pt-8">
            <h2 class="text-xl font-bold">Connection management</h2>
            <div class="mt-4 flex flex-col gap-3 sm:flex-row sm:flex-wrap">
              <.button
                id="connect-twitch"
                href={~p"/twitch/oauth/start"}
                class="btn btn-secondary btn-soft"
                disabled={!@twitch_configured?}
              >
                {if @twitch_connected?, do: "Reconnect Twitch", else: "Connect Twitch"}
              </.button>
              <.button
                id="disconnect-twitch"
                phx-click="disconnect"
                class="btn btn-error btn-soft"
                disabled={!@twitch_connected?}
                data-confirm="Disconnect Twitch? Backlog Wheel will stop using this connection for future voting sessions. Existing channel point rewards are not removed."
              >
                Disconnect Twitch
              </.button>
            </div>
          </section>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Twitch integration") |> refresh()}
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

  defp refresh(socket) do
    community = socket.assigns.current_community
    oauth_config = Twitch.oauth_config()

    socket
    |> assign(:form, to_form(Communities.change_community_twitch_settings(community)))
    |> assign(:twitch_connected?, Twitch.credential_configured?())
    |> assign(:twitch_configured?, match?({:ok, _config}, oauth_config))
    |> assign(:missing_config, missing_config(oauth_config))
  end

  defp missing_config({:error, {:missing_config, missing}}), do: missing
  defp missing_config(_config), do: []

  defp channel_label(%{twitch_broadcaster_display_name: display_name})
       when is_binary(display_name) and display_name != "",
       do: display_name

  defp channel_label(%{twitch_broadcaster_login: login}) when is_binary(login) and login != "",
    do: login

  defp channel_label(%{twitch_broadcaster_id: broadcaster_id})
       when is_binary(broadcaster_id) and broadcaster_id != "",
       do: "Name unavailable"

  defp channel_label(_community), do: "Connect Twitch to choose a channel"
end
