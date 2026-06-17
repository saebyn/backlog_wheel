defmodule BacklogWheelWeb.Router do
  use BacklogWheelWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BacklogWheelWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug BacklogWheelWeb.UserAuth, :fetch_current_user
  end

  pipeline :authenticated_browser do
    plug BacklogWheelWeb.UserAuth, :require_authenticated_user
    plug BacklogWheelWeb.UserAuth, :require_admin_community
  end

  pipeline :authenticated_user_browser do
    plug BacklogWheelWeb.UserAuth, :require_authenticated_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BacklogWheelWeb do
    get "/health", PageController, :health
  end

  scope "/", BacklogWheelWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/login", DiscordOAuthController, :login
    get "/access-not-enabled", DiscordOAuthController, :access_not_enabled
    get "/auth/discord/start", DiscordOAuthController, :start
    get "/auth/discord/callback", DiscordOAuthController, :callback
    delete "/logout", DiscordOAuthController, :logout
  end

  scope "/", BacklogWheelWeb do
    pipe_through [:browser, :authenticated_user_browser]

    live_session :onboarding do
      live "/onboarding", OnboardingLive, :new
    end
  end

  scope "/", BacklogWheelWeb do
    pipe_through [:browser, :authenticated_browser]

    get "/twitch/oauth/start", TwitchOAuthController, :start
    get "/twitch/oauth/callback", TwitchOAuthController, :callback

    live_session :authenticated,
      on_mount: [{BacklogWheelWeb.UserAuth, :require_authenticated_user}] do
      live "/settings", SettingsLive.General, :edit
      live "/dashboard", DashboardLive, :show
      live "/settings/twitch", TwitchLive, :index
      live "/wheel", WheelLive, :show
      live "/history", SpinHistoryLive, :index
      live "/history/:id", SpinRecapLive, :show
      live "/voting", VotingSessionLive.Index, :index
      live "/games", GameLive.Index, :index
      live "/games/import/steam", GameLive.SteamImport, :index
      live "/games/new", GameLive.Form, :new
      live "/games/:id", GameLive.Show, :show
      live "/games/:id/edit", GameLive.Form, :edit
      live "/settings/formats", WheelFormatLive.Index, :index
      live "/settings/theme", SettingsLive.Theme, :edit
    end
  end

  scope "/", BacklogWheelWeb do
    pipe_through :api

    post "/twitch/eventsub", TwitchEventSubController, :webhook
  end

  # Other scopes may use custom stacks.
  # scope "/api", BacklogWheelWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:backlog_wheel, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BacklogWheelWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
