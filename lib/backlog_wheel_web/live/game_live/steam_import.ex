defmodule BacklogWheelWeb.GameLive.SteamImport do
  use BacklogWheelWeb, :live_view

  alias BacklogWheel.Backlog
  alias BacklogWheel.Communities
  alias BacklogWheel.Steam.Client

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_community={@current_community}>
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
            Save Steam credentials for {@community.name}. They are stored with this community and
            reused across app instances.
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

          <.form
            for={@form}
            id="steam-credential-form"
            phx-change="validate_credentials"
            phx-submit="save_credentials"
            class="mt-6 grid gap-4 lg:grid-cols-2"
          >
            <.input
              field={@form[:steam_api_key]}
              type="password"
              label="Steam API key"
              placeholder="Paste your Steam Web API key"
            />
            <.input
              field={@form[:steam_id64]}
              type="text"
              label="Steam ID64"
              placeholder="76561198000000000"
            />
            <div class="flex flex-wrap gap-3 lg:col-span-2">
              <.button
                id="save-steam-credentials-button"
                phx-disable-with="Saving..."
                variant="primary"
              >
                Save Steam Credentials
              </.button>
            </div>
          </.form>
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
    community = socket.assigns.current_community

    {:ok,
     socket
     |> assign(:page_title, "Import Steam Library")
     |> assign(:community, community)
     |> assign_steam_form(community)
     |> assign(:importing?, false)
     |> assign(:summary, nil)}
  end

  @impl true
  def handle_event("validate_credentials", %{"community" => community_params}, socket) do
    changeset =
      Communities.change_community_steam_credential(socket.assigns.community, community_params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  @impl true
  def handle_event("save_credentials", %{"community" => community_params}, socket) do
    case Communities.update_community_steam_credential(socket.assigns.community, community_params) do
      {:ok, community} ->
        {:noreply,
         socket
         |> put_flash(:info, "Steam credentials saved")
         |> assign(:community, community)
         |> assign_steam_form(community)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("import", _params, socket) do
    socket = assign(socket, :importing?, true)

    case Client.fetch_owned_games(socket.assigns.community) do
      {:ok, steam_games} ->
        {:ok, summary} = Backlog.import_steam_games(socket.assigns.community, steam_games)

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

  defp assign_steam_form(socket, community) do
    socket
    |> assign(:form, to_form(Communities.change_community_steam_credential(community)))
    |> assign(:configured?, Client.configured?(community))
  end
end
