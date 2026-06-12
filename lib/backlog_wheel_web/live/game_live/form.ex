defmodule BacklogWheelWeb.GameLive.Form do
  use BacklogWheelWeb, :live_view

  alias BacklogWheel.Backlog
  alias BacklogWheel.Backlog.Game

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_community={@current_community}>
      <.header>
        {@page_title}
        <:subtitle>Keep track of games that may appear on the future backlog wheel.</:subtitle>
      </.header>

      <.form for={@form} id="game-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:title]} type="text" label="Title" />
        <.input field={@form[:platform]} type="text" label="Platform" />
        <.input field={@form[:external_id]} type="text" label="External ID" />
        <.input field={@form[:image_url]} type="url" label="Image URL" />
        <section id="game-tag-editor" class="mb-4 rounded-2xl border border-base-300 bg-base-100 p-4">
          <input
            type="text"
            name="game[tag_names]"
            value={tag_names_value(@selected_tags)}
            class="hidden"
            tabindex="-1"
            aria-hidden="true"
          />
          <div class="flex flex-col gap-3">
            <div>
              <label for="tag-name-input" class="block text-sm font-semibold text-base-content">
                Tags
              </label>
              <p class="mt-1 text-sm text-base-content/60">
                Add community tags, remove chips, or pick from tags already used by this community.
              </p>
            </div>

            <div id="selected-game-tags" class="flex min-h-9 flex-wrap gap-2">
              <span :if={@selected_tags == []} class="text-sm text-base-content/60">
                No tags selected.
              </span>
              <button
                :for={tag <- @selected_tags}
                id={"selected-game-tag-#{tag_slug(tag)}"}
                type="button"
                class="group rounded-full bg-primary/10 px-3 py-1 text-sm font-semibold text-primary transition hover:bg-primary hover:text-primary-content"
                phx-click="remove_tag"
                phx-value-tag={tag}
                aria-label={"Remove #{tag}"}
              >
                {tag}
                <span class="ml-1 opacity-60 transition group-hover:opacity-100">x</span>
              </button>
            </div>

            <input
              id="tag-name-input"
              type="text"
              name="tag_name"
              value={@tag_input}
              placeholder="Type a tag and press Enter"
              autocomplete="off"
              phx-keydown="add_tag_from_input"
              class="input w-full rounded-xl border-base-300 bg-base-100"
            />

            <div :if={@available_tags != []} class="space-y-2">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                Existing community tags
              </p>
              <div id="available-game-tags" class="flex flex-wrap gap-2">
                <button
                  :for={tag <- @available_tags}
                  id={"available-game-tag-#{tag.slug}"}
                  type="button"
                  class={available_tag_class(tag.name, @selected_tags)}
                  phx-click="toggle_tag"
                  phx-value-tag={tag.name}
                >
                  {tag.name}
                </button>
              </div>
            </div>
          </div>
        </section>
        <div
          :if={@form[:image_url].value not in [nil, ""]}
          id="game-image-preview"
          class="mb-4 flex items-center gap-3 rounded-2xl border border-base-300 bg-base-100 p-3"
        >
          <img
            src={@form[:image_url].value}
            alt="Game image preview"
            class="size-16 rounded-xl object-cover"
          />
          <p class="text-sm text-base-content/70">Image preview</p>
        </div>
        <.input field={@form[:include_in_wheel]} type="checkbox" label="Include in wheel" />
        <.input field={@form[:played_on_stream]} type="checkbox" label="Played on stream" />
        <.input field={@form[:last_played_at]} type="datetime-local" label="Last played at" />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Game</.button>
          <.button navigate={return_path(@return_to, @game)}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    game = Backlog.get_game!(socket.assigns.current_community, id)

    socket
    |> assign(:page_title, "Edit Game")
    |> assign(:game, game)
    |> assign_tag_editor(game)
    |> assign(:form, to_form(Backlog.change_game(game)))
  end

  defp apply_action(socket, :new, _params) do
    game = %Game{community_id: socket.assigns.current_community.id}

    socket
    |> assign(:page_title, "New Game")
    |> assign(:game, game)
    |> assign_tag_editor(game)
    |> assign(:form, to_form(Backlog.change_game(game)))
  end

  @impl true
  def handle_event("validate", %{"game" => game_params}, socket) do
    changeset = Backlog.change_game(socket.assigns.game, game_params)

    {:noreply,
     socket
     |> assign(:selected_tags, parse_tag_names(Map.get(game_params, "tag_names", "")))
     |> assign(:form, to_form(changeset, action: :validate))}
  end

  def handle_event("add_tag_from_input", %{"key" => "Enter", "value" => tag}, socket) do
    {:noreply,
     socket
     |> update(:selected_tags, &add_tag(&1, tag))
     |> assign(:tag_input, "")}
  end

  def handle_event("add_tag_from_input", %{"value" => tag}, socket) do
    {:noreply, assign(socket, :tag_input, tag)}
  end

  def handle_event("toggle_tag", %{"tag" => tag}, socket) do
    selected_tags =
      if tag_selected?(tag, socket.assigns.selected_tags) do
        remove_tag(socket.assigns.selected_tags, tag)
      else
        add_tag(socket.assigns.selected_tags, tag)
      end

    {:noreply, assign(socket, :selected_tags, selected_tags)}
  end

  def handle_event("remove_tag", %{"tag" => tag}, socket) do
    {:noreply, update(socket, :selected_tags, &remove_tag(&1, tag))}
  end

  def handle_event("save", %{"game" => game_params}, socket) do
    save_game(socket, socket.assigns.live_action, game_params)
  end

  defp save_game(socket, :edit, game_params) do
    case Backlog.update_game(socket.assigns.game, game_params) do
      {:ok, game} ->
        {:noreply,
         socket
         |> put_flash(:info, "Game updated successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, game))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_game(socket, :new, game_params) do
    case Backlog.create_game(socket.assigns.current_community, game_params) do
      {:ok, game} ->
        {:noreply,
         socket
         |> put_flash(:info, "Game created successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, game))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path("index", _game), do: ~p"/games"
  defp return_path("show", game), do: ~p"/games/#{game}"

  defp assign_tag_editor(socket, %Game{} = game) do
    socket
    |> assign(:selected_tags, game_tag_names(game))
    |> assign(:available_tags, Backlog.list_game_tags(socket.assigns.current_community))
    |> assign(:tag_input, "")
  end

  defp game_tag_names(%Game{tags: %Ecto.Association.NotLoaded{}}), do: []

  defp game_tag_names(%Game{tags: tags}) when is_list(tags) do
    tags
    |> Enum.map(& &1.name)
    |> Enum.sort()
  end

  defp tag_names_value(tags), do: Enum.join(tags, ", ")

  defp parse_tag_names(tag_names) when is_binary(tag_names) do
    tag_names
    |> String.split([",", "\n"], trim: true)
    |> Enum.reduce([], &add_tag(&2, &1))
  end

  defp parse_tag_names(_tag_names), do: []

  defp add_tag(tags, tag) when is_binary(tag) do
    tag = String.trim(tag)

    cond do
      tag == "" -> tags
      tag_selected?(tag, tags) -> tags
      true -> Enum.sort([tag | tags])
    end
  end

  defp remove_tag(tags, tag) do
    tag_slug = tag_slug(tag)
    Enum.reject(tags, &(tag_slug(&1) == tag_slug))
  end

  defp tag_selected?(tag, tags) do
    tag_slug = tag_slug(tag)
    Enum.any?(tags, &(tag_slug(&1) == tag_slug))
  end

  defp tag_slug(tag) when is_binary(tag) do
    tag
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  defp available_tag_class(tag, selected_tags) do
    [
      "rounded-full px-3 py-1 text-sm font-semibold transition",
      tag_selected?(tag, selected_tags) && "bg-primary text-primary-content shadow-sm",
      !tag_selected?(tag, selected_tags) && "bg-base-200 text-base-content/70 hover:bg-base-300"
    ]
  end
end
