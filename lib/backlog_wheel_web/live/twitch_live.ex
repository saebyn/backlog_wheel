defmodule BacklogWheelWeb.TwitchLive do
  use BacklogWheelWeb, :live_view

  alias BacklogWheel.Twitch

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-3xl space-y-6">
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

          <div class="mt-6 grid gap-3 sm:grid-cols-3">
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
          </div>

          <p
            :if={@missing_config != []}
            id="twitch-settings-missing-config"
            class="mt-4 rounded-2xl border border-warning/30 bg-warning/10 p-4 text-sm"
          >
            Missing Twitch config: {Enum.join(@missing_config, ", ")}
          </p>

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

  defp refresh(socket) do
    config = Twitch.config()

    socket
    |> assign(:twitch_connected?, Twitch.credential_configured?())
    |> assign(:twitch_configured?, match?({:ok, _config}, config))
    |> assign(:missing_config, missing_config(config))
    |> assign(:reward_cost, reward_cost(config))
  end

  defp missing_config({:error, {:missing_config, missing}}), do: missing
  defp missing_config(_config), do: []

  defp reward_cost({:ok, config}), do: config.reward_cost
  defp reward_cost(_config), do: nil
end
