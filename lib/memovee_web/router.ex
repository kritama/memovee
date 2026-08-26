defmodule MemoveeWeb.Router do
  use MemoveeWeb, :router

  import MemoveeWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MemoveeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated_api do
    plug MemoveeWeb.ApiAuth
  end

  scope "/", MemoveeWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/api", MemoveeWeb do
    pipe_through [:api, :authenticated_api]

    get "/principal", ApiPrincipalController, :show
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:memovee, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MemoveeWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", MemoveeWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{MemoveeWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
      live "/console/agents", Console.AgentLive.Index, :index
      live "/console/agents/new", Console.AgentLive.New, :new
      live "/console/agents/:id", Console.AgentLive.Show, :show
    end

    resources "/auth/password", Auth.PasswordController, only: [:update], singleton: true
  end

  scope "/", MemoveeWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{MemoveeWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    resources "/auth/session", Auth.SessionController, only: [:create, :delete], singleton: true
  end
end
