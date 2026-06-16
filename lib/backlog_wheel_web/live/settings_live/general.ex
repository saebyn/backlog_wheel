defmodule BacklogWheelWeb.SettingsLive.General do
  use BacklogWheelWeb, :live_view

  alias BacklogWheel.Communities

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_community={@current_community}>
      <div class="grid gap-6 lg:grid-cols-[14rem_1fr]">
        <Layouts.settings_nav active={:general} />

        <section class="space-y-6">
          <.header>
            General Settings
            <:subtitle>
              Manage the public identity for this community.
            </:subtitle>
          </.header>

          <section class="rounded-[2rem] border border-base-300 bg-base-100/85 p-5 shadow-sm backdrop-blur">
            <div class="mb-5 flex items-center gap-3">
              <div class="flex size-10 items-center justify-center rounded-full bg-primary/15 text-primary">
                <.icon name="hero-cog-6-tooth" class="size-5" />
              </div>
              <div>
                <h2 class="text-xl font-black">Community Details</h2>
                <p class="text-sm text-base-content/60">
                  The slug appears in shareable community URLs and must be unique.
                </p>
              </div>
            </div>

            <.form for={@form} id="general-settings-form" phx-change="validate" phx-submit="save">
              <div class="grid gap-4 md:grid-cols-2">
                <.input
                  field={@form[:name]}
                  type="text"
                  label="Community name"
                  placeholder="Backlog Wheel"
                />
                <.input
                  field={@form[:slug]}
                  type="text"
                  label="Community slug"
                  placeholder="backlog-wheel"
                />
              </div>

              <div class="mt-4 rounded-2xl border border-base-300 bg-base-200/60 p-4 text-sm text-base-content/70">
                <p class="font-bold text-base-content">Slug format</p>
                <p class="mt-1">
                  Use lowercase letters, numbers, and hyphens. Spaces and punctuation are converted to hyphens as you save.
                </p>
              </div>

              <footer class="mt-6 flex flex-wrap gap-3">
                <.button
                  id="save-general-settings-button"
                  phx-disable-with="Saving..."
                  variant="primary"
                >
                  Save Settings
                </.button>
                <.button navigate={~p"/dashboard"}>Cancel</.button>
              </footer>
            </.form>
          </section>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    community = socket.assigns.current_community

    {:ok,
     socket
     |> assign(:page_title, "General Settings")
     |> assign(:community, community)
     |> assign_form(community)}
  end

  @impl true
  def handle_event("validate", %{"community" => community_params}, socket) do
    changeset =
      socket.assigns.community
      |> Communities.change_community_general_settings(community_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"community" => community_params}, socket) do
    case Communities.update_community_general_settings(socket.assigns.community, community_params) do
      {:ok, community} ->
        {:noreply,
         socket
         |> put_flash(:info, "General settings updated successfully")
         |> assign(:community, community)
         |> assign(:current_community, community)
         |> assign_form(community)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp assign_form(socket, community) do
    assign(socket, :form, to_form(Communities.change_community_general_settings(community)))
  end
end
