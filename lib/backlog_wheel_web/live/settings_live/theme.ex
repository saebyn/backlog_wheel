defmodule BacklogWheelWeb.SettingsLive.Theme do
  use BacklogWheelWeb, :live_view

  alias BacklogWheel.Communities

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_community={@current_community}>
      <div class="grid gap-6 lg:grid-cols-[14rem_1fr]">
        <aside class="h-fit rounded-2xl border border-base-300 bg-base-100/85 p-3 shadow-sm backdrop-blur">
          <p class="px-3 py-2 text-xs font-black uppercase tracking-[0.22em] text-base-content/50">
            Settings
          </p>
          <.link
            navigate={~p"/settings/theme"}
            class="flex items-center gap-2 rounded-xl bg-primary/10 px-3 py-2 text-sm font-bold text-primary"
          >
            <.icon name="hero-swatch" class="size-4" /> Theme
          </.link>
          <.link
            id="settings-nav-twitch"
            navigate={~p"/settings/twitch"}
            class="mt-1 flex items-center gap-2 rounded-xl px-3 py-2 text-sm font-bold text-base-content/70 transition hover:bg-base-200 hover:text-base-content"
          >
            <.icon name="hero-signal" class="size-4" /> Twitch
          </.link>
        </aside>

        <section class="space-y-6">
          <.header>
            Theme Settings
            <:subtitle>
              Customize stream-friendly colors for this community.
            </:subtitle>
          </.header>

          <.form for={@form} id="theme-form" phx-change="validate" phx-submit="save">
            <div class="grid gap-4 xl:grid-cols-2">
              <section class="rounded-[2rem] border border-base-300 bg-base-100/85 p-5 shadow-sm backdrop-blur">
                <div class="mb-4 flex items-center gap-3">
                  <div class="flex size-10 items-center justify-center rounded-full bg-warning/15 text-warning">
                    <.icon name="hero-sun" class="size-5" />
                  </div>
                  <div>
                    <h2 class="text-xl font-black">Light Mode</h2>
                    <p class="text-sm text-base-content/60">
                      Used when the theme switch is light, or system mode resolves light.
                    </p>
                  </div>
                </div>

                <div class="grid gap-3 sm:grid-cols-3">
                  <.color_field
                    field={@form[:light_primary_color]}
                    label="Primary"
                    fallback={@resolved_theme.light.primary}
                    placeholder="#f97316"
                  />
                  <.color_field
                    field={@form[:light_accent_color]}
                    label="Accent"
                    fallback={@resolved_theme.light.accent}
                    placeholder="#c026d3"
                  />
                  <.color_field
                    field={@form[:light_background_color]}
                    label="Background"
                    fallback={@resolved_theme.light.background}
                    placeholder="#fafafa"
                  />
                </div>
              </section>

              <section class="rounded-[2rem] border border-base-300 bg-base-100/85 p-5 shadow-sm backdrop-blur">
                <div class="mb-4 flex items-center gap-3">
                  <div class="flex size-10 items-center justify-center rounded-full bg-primary/15 text-primary">
                    <.icon name="hero-moon" class="size-5" />
                  </div>
                  <div>
                    <h2 class="text-xl font-black">Dark Mode</h2>
                    <p class="text-sm text-base-content/60">
                      Leave blank to automatically derive values from light mode.
                    </p>
                  </div>
                </div>

                <div class="grid gap-3 sm:grid-cols-3">
                  <.color_field
                    field={@form[:dark_primary_color]}
                    label="Primary"
                    fallback={@resolved_theme.dark.primary}
                    placeholder="Derived"
                  />
                  <.color_field
                    field={@form[:dark_accent_color]}
                    label="Accent"
                    fallback={@resolved_theme.dark.accent}
                    placeholder="Derived"
                  />
                  <.color_field
                    field={@form[:dark_background_color]}
                    label="Background"
                    fallback={@resolved_theme.dark.background}
                    placeholder="Derived"
                  />
                </div>
              </section>
            </div>

            <section
              id="theme-preview"
              class="mt-6 overflow-hidden rounded-[2rem] border border-base-300 bg-base-100 shadow-xl"
            >
              <div class="grid gap-0 lg:grid-cols-2">
                <.theme_preview
                  id="light-theme-preview"
                  label="Light Preview"
                  theme={@resolved_theme.light}
                />
                <.theme_preview
                  id="dark-theme-preview"
                  label="Dark Preview"
                  theme={@resolved_theme.dark}
                />
              </div>
            </section>

            <footer class="mt-6 flex flex-wrap gap-3">
              <.button id="save-theme-button" phx-disable-with="Saving..." variant="primary">
                Save Theme
              </.button>
              <button
                id="reset-theme-button"
                type="button"
                phx-click="reset"
                data-confirm="Reset theme colors to defaults?"
                class="btn btn-error btn-soft"
              >
                Reset to Default
              </button>
              <.button navigate={~p"/"}>Cancel</.button>
            </footer>
          </.form>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :fallback, :string, required: true
  attr :placeholder, :string, required: true

  defp color_field(assigns) do
    ~H"""
    <div class="space-y-1">
      <div class="flex items-end gap-2">
        <div class="min-w-0 flex-1">
          <.input
            field={@field}
            type="text"
            label={@label}
            placeholder={@placeholder}
            class="w-full input font-mono uppercase placeholder:font-sans placeholder:normal-case placeholder:text-base-content/35"
          />
        </div>
        <input
          id={"#{@field.id}-picker"}
          type="color"
          value={color_picker_value(@field.value, @fallback)}
          aria-label={"Pick #{@label} color"}
          phx-hook="ThemeColorPicker"
          data-target={@field.id}
          class="mb-2 h-10 w-12 cursor-pointer rounded-lg border border-base-300 bg-base-100 p-1 shadow-sm"
        />
      </div>
      <p class="text-xs text-base-content/60">
        Type a hex value or use the color picker. Leave blank to use the derived/default color.
      </p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :theme, :map, required: true

  defp theme_preview(assigns) do
    ~H"""
    <div
      id={@id}
      class="min-h-80 p-6"
      style={preview_style(@theme)}
    >
      <div
        class="rounded-[1.5rem] border border-white/20 p-5 shadow-2xl backdrop-blur"
        style={preview_card_style(@theme)}
      >
        <p class="text-xs font-black uppercase tracking-[0.25em] opacity-70">{@label}</p>
        <h3 class="mt-3 text-3xl font-black tracking-tight">Backlog Wheel</h3>
        <p class="mt-2 max-w-md text-sm leading-6 opacity-75">
          This preview uses the resolved colors, including generated opposite-mode values when fields are blank.
        </p>
        <div class="mt-5 flex flex-wrap gap-2">
          <span
            class="rounded-full px-4 py-2 text-sm font-bold"
            style={pill_style(@theme.primary, @theme.primary_content)}
          >
            Primary
          </span>
          <span
            class="rounded-full px-4 py-2 text-sm font-bold"
            style={pill_style(@theme.accent, @theme.accent_content)}
          >
            Accent
          </span>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    community = socket.assigns.current_community

    {:ok,
     socket
     |> assign(:page_title, "Theme Settings")
     |> assign(:community, community)
     |> assign_theme_form(community)}
  end

  @impl true
  def handle_event("validate", %{"community" => community_params}, socket) do
    changeset = Communities.change_community_theme(socket.assigns.community, community_params)
    preview = preview_community(changeset, socket.assigns.community)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, action: :validate))
     |> assign(:resolved_theme, Communities.resolved_theme(preview))}
  end

  @impl true
  def handle_event("save", %{"community" => community_params}, socket) do
    case Communities.update_community_theme(socket.assigns.community, community_params) do
      {:ok, community} ->
        {:noreply,
         socket
         |> put_flash(:info, "Theme updated successfully")
         |> assign(:community, community)
         |> assign_theme_form(community)}

      {:error, changeset} ->
        preview = preview_community(changeset, socket.assigns.community)

        {:noreply,
         socket
         |> assign(:form, to_form(changeset))
         |> assign(:resolved_theme, Communities.resolved_theme(preview))}
    end
  end

  @impl true
  def handle_event("reset", _params, socket) do
    case Communities.reset_community_theme(socket.assigns.community) do
      {:ok, community} ->
        {:noreply,
         socket
         |> put_flash(:info, "Theme reset to defaults")
         |> assign(:community, community)
         |> assign_theme_form(community)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp assign_theme_form(socket, community) do
    socket
    |> assign(:form, to_form(Communities.change_community_theme(community)))
    |> assign(:resolved_theme, Communities.resolved_theme(community))
  end

  defp preview_community(%Ecto.Changeset{valid?: true} = changeset, _community) do
    Ecto.Changeset.apply_changes(changeset)
  end

  defp preview_community(_changeset, community), do: community

  defp color_picker_value(value, fallback) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" -> color_picker_value(fallback, "#000000")
      Regex.match?(~r/^#[0-9a-fA-F]{6}$/, value) -> value
      Regex.match?(~r/^#[0-9a-fA-F]{3}$/, value) -> expand_short_hex(value)
      true -> "#000000"
    end
  end

  defp color_picker_value(_value, fallback), do: color_picker_value(fallback, "#000000")

  defp expand_short_hex("#" <> hex) do
    [r, g, b] = String.graphemes(hex)
    "##{r}#{r}#{g}#{g}#{b}#{b}"
  end

  defp preview_style(theme) do
    "color: #{theme.background_content}; background: linear-gradient(135deg, #{theme.background}, #{theme.primary}); background-size: cover;"
  end

  defp preview_card_style(theme) do
    "background: color-mix(in oklch, #{theme.background} 82%, transparent); color: #{theme.background_content};"
  end

  defp pill_style(background, color), do: "background: #{background}; color: #{color};"
end
