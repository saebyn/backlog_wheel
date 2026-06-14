defmodule BacklogWheelWeb.OnboardingLive do
  use BacklogWheelWeb, :live_view

  alias BacklogWheel.{Accounts, Communities}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_community={@current_community}>
      <section id="onboarding-page" class="mx-auto grid max-w-4xl gap-6 lg:grid-cols-[0.9fr_1.1fr]">
        <div class="brand-panel relative overflow-hidden rounded-[2rem] p-6 shadow-xl sm:p-8">
          <div
            class="absolute -left-20 -top-20 size-64 rounded-full bg-primary/25 blur-3xl"
            aria-hidden="true"
          />
          <div class="relative space-y-5">
            <p class="text-sm font-black uppercase tracking-[0.25em] text-primary">
              First Run Setup
            </p>
            <h1 class="text-4xl font-black tracking-tight text-base-content sm:text-5xl">
              Create your community hub.
            </h1>
            <p class="text-base leading-7 text-base-content/70">
              This connects your Discord login to an owner community, seeds starter Wheel Formats,
              and gives the rest of Backlog Wheel a place to save your stream data.
            </p>
          </div>
        </div>

        <div class="rounded-[2rem] border border-base-300 bg-base-100 p-6 shadow-xl sm:p-8">
          <div class="mb-6">
            <p class="text-sm font-black uppercase tracking-[0.22em] text-secondary">
              Community Details
            </p>
            <h2 class="mt-2 text-3xl font-black tracking-tight">What should we call it?</h2>
          </div>

          <.form
            for={@form}
            id="onboarding-form"
            phx-change="validate"
            phx-submit="save"
            class="space-y-5"
          >
            <.input
              field={@form[:name]}
              type="text"
              label="Community display name"
              placeholder="Saebyn's Stream"
              autocomplete="organization"
              required
            />

            <div class="rounded-3xl bg-base-200 p-5 text-sm leading-6 text-base-content/70">
              <p class="font-bold text-base-content">After setup we will create:</p>
              <ul class="mt-2 list-disc space-y-1 pl-5">
                <li>An owned community for your account</li>
                <li>Your owner membership</li>
                <li>Starter Wheel Formats for voting sessions</li>
              </ul>
            </div>

            <button id="onboarding-submit" type="submit" class="btn btn-primary w-full hover-lift">
              Finish Setup
            </button>
          </.form>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    user = Accounts.get_user(Map.get(session, "user_id"))
    community = Communities.current_admin_community_for_user(user)

    cond do
      is_nil(user) ->
        {:ok,
         socket
         |> put_flash(:error, "Sign in with Discord to continue")
         |> redirect(to: ~p"/login")}

      community ->
        {:ok, redirect(socket, to: ~p"/dashboard")}

      not Accounts.signup_allowed?(user) ->
        {:ok, redirect(socket, to: ~p"/access-not-enabled")}

      true ->
        {:ok,
         socket
         |> assign(:page_title, "Create Community")
         |> assign(:current_user, user)
         |> assign(:current_community, nil)
         |> assign_form(Communities.change_initial_community())}
    end
  end

  @impl true
  def handle_event("validate", %{"community" => params}, socket) do
    changeset =
      params
      |> Communities.change_initial_community()
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"community" => params}, socket) do
    case Communities.create_initial_community(socket.assigns.current_user, params) do
      {:ok, _community} ->
        {:noreply,
         socket
         |> put_flash(:info, "Community created")
         |> push_navigate(to: ~p"/dashboard")}

      {:error, :signup_not_allowed} ->
        {:noreply, push_navigate(socket, to: ~p"/access-not-enabled")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
