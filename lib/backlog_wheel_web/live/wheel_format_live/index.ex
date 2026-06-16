defmodule BacklogWheelWeb.WheelFormatLive.Index do
  use BacklogWheelWeb, :live_view

  alias BacklogWheel.Voting
  alias BacklogWheel.Voting.WheelFormat

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_community={@current_community}>
      <div class="grid gap-6 lg:grid-cols-[14rem_1fr]">
        <Layouts.settings_nav active={:formats} />

        <section id="wheel-format-management" class="space-y-8">
          <div class="relative overflow-hidden rounded-[2rem] bg-base-200 p-6 shadow-xl md:p-8">
            <div class="max-w-3xl">
              <p class="text-sm font-black uppercase tracking-[0.22em] text-accent">Settings</p>
              <h1 class="mt-2 text-4xl font-black tracking-tight md:text-5xl">Wheel Formats</h1>
              <p class="mt-4 text-base leading-7 text-base-content/70">
                Create reusable starting points for community voting sessions. Each Wheel Format keeps the session copy and simple game-pool rules together.
              </p>
            </div>
            <div class="mt-6 flex flex-wrap gap-2">
              <.link
                id="wheel-formats-back-to-voting"
                navigate={~p"/voting"}
                class="btn btn-ghost hover-lift"
              >
                Voting Sessions
              </.link>
            </div>
          </div>

          <div class="grid gap-6 xl:grid-cols-[1fr_25rem]">
            <section id="wheel-formats-list" class="space-y-4">
              <article
                :for={format <- @wheel_formats}
                id={"wheel-format-#{format.id}"}
                class="rounded-[2rem] border border-base-300 bg-base-100 p-5 shadow-lg transition hover:-translate-y-0.5 hover:shadow-xl"
              >
                <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                  <div class="min-w-0">
                    <div class="flex flex-wrap items-center gap-2">
                      <h2 class="text-2xl font-black tracking-tight">{format.name}</h2>
                      <span :if={format.is_default} class="badge badge-primary">Default</span>
                      <span class={
                        if(format.is_enabled, do: "badge badge-success", else: "badge badge-ghost")
                      }>
                        {if(format.is_enabled, do: "Enabled", else: "Disabled")}
                      </span>
                    </div>
                    <p class="mt-2 text-sm leading-6 text-base-content/70">
                      {format.description || "No description yet."}
                    </p>
                    <p class="mt-4 text-sm font-bold text-base-content/80">
                      Starts voting sessions as: {format.default_session_title}
                    </p>
                    <p
                      :if={format.default_session_description}
                      class="mt-1 text-sm leading-6 text-base-content/60"
                    >
                      {format.default_session_description}
                    </p>
                    <div class="mt-4 flex flex-wrap gap-2 text-xs font-bold uppercase tracking-[0.16em] text-base-content/50">
                      <span>{format_rule_label(format)}</span>
                      <span>Base weight {format_base_weight(format)}</span>
                    </div>
                  </div>

                  <div class="flex shrink-0 flex-wrap gap-2 lg:justify-end">
                    <.link
                      :if={format.is_enabled}
                      id={"start-wheel-format-#{format.id}"}
                      navigate={~p"/voting?#{[wheel_format_id: format.id]}"}
                      class="btn btn-accent btn-sm hover-lift"
                    >
                      Start Vote
                    </.link>
                    <.button
                      id={"edit-wheel-format-#{format.id}"}
                      phx-click="edit"
                      phx-value-id={format.id}
                      class="btn btn-primary btn-soft btn-sm hover-lift"
                    >
                      Edit
                    </.button>
                    <.button
                      id={"toggle-wheel-format-#{format.id}"}
                      phx-click="toggle_enabled"
                      phx-value-id={format.id}
                      class="btn btn-secondary btn-sm hover-lift"
                    >
                      {if(format.is_enabled, do: "Disable", else: "Enable")}
                    </.button>
                    <.button
                      :if={!format.is_default}
                      id={"delete-wheel-format-#{format.id}"}
                      phx-click="delete"
                      phx-value-id={format.id}
                      data-confirm="Remove this custom Wheel Format? Existing voting sessions keep their history."
                      class="btn btn-error btn-soft btn-sm hover-lift"
                    >
                      Remove
                    </.button>
                    <span
                      :if={format.is_default}
                      id={"protected-wheel-format-#{format.id}"}
                      title="Can't delete the default formats"
                      class="cursor-help rounded-full bg-base-200 px-3 py-2 text-xs font-bold text-base-content/60 underline decoration-dashed underline-offset-4"
                    >
                      Removal protected
                    </span>
                  </div>
                </div>
              </article>
            </section>

            <aside class="rounded-[2rem] border border-base-300 bg-base-100 p-5 shadow-xl xl:sticky xl:top-6 xl:self-start">
              <div class="flex items-start justify-between gap-3">
                <div>
                  <p class="text-xs font-black uppercase tracking-[0.2em] text-accent">
                    Wheel Format
                  </p>
                  <h2 id="wheel-format-form-title" class="mt-2 text-2xl font-black">
                    {if(@editing_format, do: "Edit Format", else: "Create Format")}
                  </h2>
                </div>
                <.button
                  :if={@editing_format}
                  id="new-wheel-format"
                  phx-click="new"
                  class="btn btn-ghost btn-sm hover-lift"
                >
                  New
                </.button>
              </div>

              <.form
                for={@form}
                id="wheel-format-form"
                phx-change="validate"
                phx-submit="save"
                class="mt-5 space-y-3"
              >
                <.input field={@form[:name]} type="text" label="Name" required maxlength="120" />
                <.input field={@form[:description]} type="textarea" label="Description" rows="3" />
                <.input
                  field={@form[:default_session_title]}
                  type="text"
                  label="Default voting session title"
                  required
                  maxlength="160"
                />
                <.input
                  field={@form[:default_session_description]}
                  type="textarea"
                  label="Default voting session description"
                  rows="3"
                />
                <div class="rounded-3xl bg-base-200 p-4">
                  <p class="mb-2 text-sm font-black uppercase tracking-[0.16em] text-base-content/60">
                    Simple Rules
                  </p>
                  <.input field={@form[:is_enabled]} type="checkbox" label="Enabled" />
                  <.input
                    field={@form[:include_in_wheel]}
                    type="checkbox"
                    label="Include only wheel-eligible games"
                  />
                  <.input
                    field={@form[:unplayed_only]}
                    type="checkbox"
                    label="Include only unplayed games"
                  />
                  <.input field={@form[:base_weight]} type="number" label="Base weight" min="1" />
                </div>
                <.button id="save-wheel-format" class="btn btn-accent w-full hover-lift">
                  {if(@editing_format, do: "Save Wheel Format", else: "Create Wheel Format")}
                </.button>
              </.form>
            </aside>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    community = socket.assigns.current_community
    {:ok, _formats} = Voting.ensure_default_wheel_formats(community)

    {:ok,
     socket
     |> assign(:page_title, "Wheel Formats")
     |> assign(:editing_format, nil)
     |> assign_formats()
     |> assign_form(%WheelFormat{community_id: community.id, is_enabled: true})}
  end

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_format, nil)
     |> assign_form(%WheelFormat{
       community_id: socket.assigns.current_community.id,
       is_enabled: true
     })}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    format = Voting.get_wheel_format!(socket.assigns.current_community, id)

    {:noreply,
     socket
     |> assign(:editing_format, format)
     |> assign_form(format)}
  end

  def handle_event("validate", %{"wheel_format" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :wheel_format))}
  end

  def handle_event("save", %{"wheel_format" => params}, socket) do
    attrs = wheel_format_attrs(params)

    result =
      if format = socket.assigns.editing_format do
        Voting.update_wheel_format(socket.assigns.current_community, format, attrs)
      else
        Voting.create_wheel_format(socket.assigns.current_community, attrs)
      end

    case result do
      {:ok, _format} ->
        {:noreply,
         socket
         |> put_flash(:info, "Wheel Format saved")
         |> assign(:editing_format, nil)
         |> assign_formats()
         |> assign_form(%WheelFormat{
           community_id: socket.assigns.current_community.id,
           is_enabled: true
         })}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(form_attrs(changeset), as: :wheel_format))}
    end
  end

  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    format = Voting.get_wheel_format!(socket.assigns.current_community, id)

    {:ok, _format} =
      Voting.update_wheel_format(socket.assigns.current_community, format, %{
        is_enabled: !format.is_enabled
      })

    {:noreply,
     socket
     |> put_flash(:info, "Wheel Format updated")
     |> assign_formats()}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    format = Voting.get_wheel_format!(socket.assigns.current_community, id)

    case Voting.delete_wheel_format(socket.assigns.current_community, format) do
      {:ok, _format} ->
        {:noreply,
         socket
         |> put_flash(:info, "Wheel Format removed")
         |> assign(:editing_format, nil)
         |> assign_formats()
         |> assign_form(%WheelFormat{
           community_id: socket.assigns.current_community.id,
           is_enabled: true
         })}

      {:error, :default_wheel_format_protected} ->
        {:noreply, put_flash(socket, :error, "Default Wheel Formats cannot be removed")}
    end
  end

  defp assign_formats(socket) do
    assign(
      socket,
      :wheel_formats,
      Voting.list_all_wheel_formats(socket.assigns.current_community)
    )
  end

  defp assign_form(socket, %WheelFormat{} = format) do
    form_attrs = form_attrs(format)

    assign(socket, :form, to_form(form_attrs, as: :wheel_format))
  end

  defp form_attrs(%Ecto.Changeset{} = changeset) do
    changes = changeset.changes
    data = changeset.data

    form_attrs(%{
      data
      | name: Map.get(changes, :name, data.name),
        description: Map.get(changes, :description, data.description),
        default_session_title:
          Map.get(changes, :default_session_title, data.default_session_title),
        default_session_description:
          Map.get(changes, :default_session_description, data.default_session_description),
        is_enabled: Map.get(changes, :is_enabled, data.is_enabled),
        candidate_rules: Map.get(changes, :candidate_rules, data.candidate_rules),
        weighting_rules: Map.get(changes, :weighting_rules, data.weighting_rules)
    })
  end

  defp form_attrs(%WheelFormat{} = format) do
    %{
      "name" => format.name,
      "description" => format.description,
      "default_session_title" => format.default_session_title,
      "default_session_description" => format.default_session_description,
      "is_enabled" => format.is_enabled,
      "include_in_wheel" => Map.get(format.candidate_rules || %{}, "include_in_wheel", true),
      "unplayed_only" => Map.get(format.candidate_rules || %{}, "played_on_stream") == false,
      "base_weight" => format_base_weight(format)
    }
  end

  defp wheel_format_attrs(params) do
    include_in_wheel? =
      truthy?(Map.get(params, "include_in_wheel", Map.get(params, :include_in_wheel, true)))

    unplayed_only? =
      truthy?(Map.get(params, "unplayed_only", Map.get(params, :unplayed_only, false)))

    base_weight =
      positive_integer(Map.get(params, "base_weight", Map.get(params, :base_weight, 1)))

    candidate_rules =
      %{}
      |> maybe_put_rule("include_in_wheel", include_in_wheel?)
      |> maybe_put_rule("played_on_stream", false, unplayed_only?)

    %{
      name: Map.get(params, "name", Map.get(params, :name)),
      description: Map.get(params, "description", Map.get(params, :description)),
      default_session_title:
        Map.get(params, "default_session_title", Map.get(params, :default_session_title)),
      default_session_description:
        Map.get(
          params,
          "default_session_description",
          Map.get(params, :default_session_description)
        ),
      is_enabled: truthy?(Map.get(params, "is_enabled", Map.get(params, :is_enabled, true))),
      candidate_rules: candidate_rules,
      weighting_rules: %{"base_weight" => base_weight}
    }
  end

  defp maybe_put_rule(rules, _key, false), do: rules
  defp maybe_put_rule(rules, key, true), do: Map.put(rules, key, true)
  defp maybe_put_rule(rules, key, value, true), do: Map.put(rules, key, value)
  defp maybe_put_rule(rules, _key, _value, false), do: rules

  defp truthy?(value) when value in [true, "true", "1", 1], do: true
  defp truthy?(_value), do: false

  defp positive_integer(value) when is_integer(value) and value > 0, do: value

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _invalid -> 1
    end
  end

  defp positive_integer(_value), do: 1

  defp format_rule_label(%WheelFormat{candidate_rules: %{"played_on_stream" => false}}),
    do: "Unplayed games only"

  defp format_rule_label(%WheelFormat{candidate_rules: %{"include_in_wheel" => true}}),
    do: "Wheel-eligible games"

  defp format_rule_label(_format), do: "Broad game pool"

  defp format_base_weight(%WheelFormat{weighting_rules: %{"base_weight" => weight}})
       when is_integer(weight),
       do: weight

  defp format_base_weight(_format), do: 1
end
