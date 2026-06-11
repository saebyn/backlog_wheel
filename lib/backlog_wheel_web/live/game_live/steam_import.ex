defmodule BacklogWheelWeb.GameLive.SteamImport do
  use BacklogWheelWeb, :live_view

  alias BacklogWheel.Backlog
  alias BacklogWheel.Steam.Client

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        Import Steam Library
        <:subtitle>
          Import owned Steam games into your backlog. Existing Steam games are skipped so local edits are preserved.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/games"}>
            <.icon name="hero-arrow-left" /> Back to games
          </.button>
        </:actions>
      </.header>

      <section id="steam-import" class="space-y-6">
        <div class="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm">
          <h2 class="text-lg font-semibold">Configuration</h2>
          <p class="mt-2 text-sm text-base-content/70">
            Set <code>STEAM_API_KEY</code>
            and <code>STEAM_ID64</code>
            in your local environment, then reload the dev shell.
          </p>

          <div class="mt-4">
            <span
              id="steam-config-status"
              class={[
                "badge",
                @configured? && "badge-success",
                !@configured? && "badge-warning"
              ]}
            >
              {if @configured?, do: "Steam configured", else: "Steam config missing"}
            </span>
          </div>
        </div>

        <div class="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm">
          <h2 class="text-lg font-semibold">Import behavior</h2>
          <ul class="mt-3 list-disc space-y-2 pl-5 text-sm text-base-content/70">
            <li>New Steam games are added with platform <code>steam</code>.</li>
            <li>Imported games are included on the wheel by default.</li>
            <li>Last played time is saved only when Steam returns <code>rtime_last_played</code>.</li>
            <li>Re-imports refresh last played times from Steam.</li>
            <li>Existing Steam games are skipped, preserving local edits.</li>
          </ul>
        </div>

        <div :if={@summary} id="steam-import-summary" class="alert alert-info">
          <.icon name="hero-information-circle" class="size-5" />
          <div>
            Imported {@summary.imported} games, refreshed {@summary.updated} last played times,
            and skipped {@summary.skipped} existing games.
          </div>
        </div>

        <.button
          id="steam-import-button"
          variant="primary"
          phx-click="import"
          disabled={!@configured? || @importing?}
        >
          {if @importing?, do: "Importing...", else: "Import Steam Library"}
        </.button>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Import Steam Library")
     |> assign(:configured?, Client.configured?())
     |> assign(:importing?, false)
     |> assign(:summary, nil)}
  end

  @impl true
  def handle_event("import", _params, socket) do
    socket = assign(socket, :importing?, true)

    case Client.fetch_owned_games() do
      {:ok, steam_games} ->
        {:ok, summary} = Backlog.import_steam_games(steam_games)

        {:noreply,
         socket
         |> assign(:importing?, false)
         |> assign(:summary, summary)
         |> put_flash(:info, "Steam library import complete")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:importing?, false)
         |> put_flash(:error, "Steam import failed: #{format_error(reason)}")}
    end
  end

  defp format_error({:missing_config, :api_key}), do: "STEAM_API_KEY is missing"
  defp format_error({:missing_config, :steam_id64}), do: "STEAM_ID64 is missing"
  defp format_error({:steam_http_error, status}), do: "Steam returned HTTP #{status}"
  defp format_error(reason), do: inspect(reason)
end
