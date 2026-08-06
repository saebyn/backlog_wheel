defmodule BacklogWheelWeb.SiteAdminLive do
  use BacklogWheelWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_community={@current_community}>
      <section id="site-admin-page" class="space-y-6">
        <div class="brand-panel relative overflow-hidden rounded-[2rem] p-6 shadow-xl sm:p-8">
          <div
            class="absolute -right-20 -top-24 size-72 rounded-full bg-warning/20 blur-3xl"
            aria-hidden="true"
          />
          <div class="relative max-w-3xl">
            <p class="flex items-center gap-2 text-sm font-black uppercase tracking-[0.25em] text-warning">
              <.icon name="hero-shield-check" class="size-5" /> Site Admin
            </p>
            <h1 class="mt-3 text-4xl font-black tracking-tight text-base-content sm:text-6xl">
              Backlog Wheel operations
            </h1>
            <p class="mt-4 text-base leading-7 text-base-content/70 sm:text-lg">
              This area is reserved for site-wide administration tools. We will add operational controls here as they are built.
            </p>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Site Admin")}
  end
end
