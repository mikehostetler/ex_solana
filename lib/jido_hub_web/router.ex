defmodule JidoHubWeb.Router do
  use JidoHubWeb, :router
  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers
  import Oban.Web.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {JidoHubWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
    plug JidoHubWeb.Plugs.RateLimit, :browser
  end

  pipeline :api do
    plug :accepts, ["json"]

    plug AshAuthentication.Strategy.ApiKey.Plug,
      resource: JidoHub.Accounts.User,
      required?: true

    plug :load_from_bearer
    plug :set_actor, :user
    plug JidoHubWeb.Plugs.RateLimit, :api
  end

  pipeline :api_flex do
    plug :accepts, ["json"]

    plug AshAuthentication.Strategy.ApiKey.Plug,
      resource: JidoHub.Accounts.User,
      required?: false

    plug :load_from_bearer
    plug :set_actor, :user
  end

  # ----------------------------
  # Public site (landing/static)
  # ----------------------------
  scope "/", JidoHubWeb do
    pipe_through :browser

    # Homepage - controller that gates by auth
    get "/", PageController, :home

    # Static pages
    get "/privacy", PageController, :privacy
    get "/terms", PageController, :terms

    live_session :auth,
      root_layout: {JidoHubWeb.Layouts, :root},
      layout: {JidoHubWeb.Layouts, :auth},
      on_mount: [{JidoHubWeb.LiveUserAuth, :live_user_optional}] do
      # Auth UI routes at root level (per ROUTING_PATTERNS.md)
      live "/login", LoginLive, :index
      live "/signup", RegisterLive, :index
      live "/reset", PasswordResetRequestLive, :index
    end

    # AshAuthentication token routes at root level
    sign_out_route AuthController, "/logout"

    reset_route auth_routes_prefix: "/",
                path: "/reset",
                overrides: [
                  JidoHubWeb.AuthOverrides,
                  Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                ]

    confirm_route JidoHub.Accounts.User, :confirm_new_user,
      path: "/confirm",
      overrides: [JidoHubWeb.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI]

    magic_sign_in_route(JidoHub.Accounts.User, :magic_link,
      path: "/magic_link",
      overrides: [JidoHubWeb.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI]
    )
  end

  # Separate scope for AshAuthentication API endpoints only
  scope "/auth", JidoHubWeb do
    pipe_through :browser

    # Only include the backend auth routes that we need
    post "/user/password/sign_in", AuthController, :password_sign_in
    post "/user/password/register", AuthController, :password_register
  end

  # --------------------------
  # Authenticated web app (UI)
  # --------------------------
  scope "/", JidoHubWeb do
    pipe_through :browser

    live_session :app_required,
      root_layout: {JidoHubWeb.Layouts, :root},
      on_mount: [{JidoHubWeb.LiveUserAuth, :live_user_required}] do
      live "/dashboard", DashboardLive, :index

      live "/settings", Settings.PreferencesLive, :index
      live "/settings/profile", Settings.ProfileLive, :index
      live "/settings/security", Settings.SecurityLive, :index
    end
  end

  # ------------------
  # Admin (restricted)
  # ------------------
  scope "/admin", JidoHubWeb do
    pipe_through :browser

    live_session :admin_required,
      root_layout: {JidoHubWeb.Layouts, :root},
      layout: {JidoHubWeb.Layouts, :admin},
      on_mount: [
        {JidoHubWeb.LiveUserAuth, :live_user_required},
        {JidoHubWeb.OnMount.RequireAdmin, :admin}
      ] do
      live "/", Admin.DashboardLive, :index

      live "/users", Admin.UserLive.Index, :index
      live "/users/new", Admin.UserLive.Index, :new
      live "/users/:user_id/edit", Admin.UserLive.Index, :edit

      live "/organizations", Admin.OrganizationLive.Index, :index
      live "/organizations/:organization_id/edit", Admin.OrganizationLive.Index, :edit

      live "/logs", Admin.LogLive.Index, :index
    end
  end

  # ---------------
  # API (versioned)
  # ---------------
  scope "/api/v1" do
    pipe_through :api

    forward "/swaggerui", OpenApiSpex.Plug.SwaggerUI,
      path: "/api/v1/open_api",
      default_model_expand_depth: 4

    forward "/", JidoHubWeb.AshJsonApiRouter
  end

  scope "/api/v1", JidoHubWeb do
    pipe_through :api_flex

    scope "/rpc" do
      post "/run", AshTypescriptRpcController, :run
      post "/validate", AshTypescriptRpcController, :validate
    end
  end

  # -------------------
  # Legacy compatibility (TODO: Remove after migration)
  # -------------------
  scope "/api/json" do
    pipe_through [:api]

    forward "/swaggerui", OpenApiSpex.Plug.SwaggerUI,
      path: "/api/json/open_api",
      default_model_expand_depth: 4

    forward "/", JidoHubWeb.AshJsonApiRouter
  end

  # -------------------
  # Dev-only dashboards
  # -------------------
  if Application.compile_env(:jido_hub, :dev_routes) do
    import AshAdmin.Router
    import Phoenix.LiveDashboard.Router
    # import PhoenixStorybook.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: JidoHubWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
      oban_dashboard("/oban")
    end

    # scope "/" do
    #   storybook_assets()
    # end

    # scope "/", JidoHubWeb do
    #   pipe_through :browser
    #   live_storybook("/storybook", backend_module: JidoHubWeb.Storybook)
    # end

    scope "/dev/ash_admin" do
      pipe_through :browser
      ash_admin "/"
    end
  end

  # -------------------------------------------------------------------
  # Dynamic GitHub-style routes: /:slug and /:owner_slug/:pod_slug
  # -------------------------------------------------------------------
  # These routes must come LAST to avoid shadowing static routes above.
  # Slug resolution order: User → Organization → Pod (if enabled)
  # See docs/ROUTING_PATTERNS.md for details
  # -------------------------------------------------------------------
  scope "/", JidoHubWeb do
    pipe_through :browser

    # Single slug routes: /:slug → User or Organization profile
    live_session :dynamic_single_slug,
      root_layout: {JidoHubWeb.Layouts, :root},
      on_mount: [
        {JidoHubWeb.LiveUserAuth, :live_user_optional},
        {JidoHubWeb.OnMount.ResolveSlug, :single_slug}
      ] do
      live "/:slug", ProfileLive, :show
      live "/:slug/workflows", ProfileLive, :workflows
      live "/:slug/settings", ProfileLive, :settings
    end

    # Owner + Pod routes: /:owner_slug/:pod_slug → Pod pages
    # TODO: Uncomment when PodLive, PodSettingsLive, PodActionsLive, PodWorkflowsLive are created
    # live_session :dynamic_pods,
    #   root_layout: {JidoHubWeb.Layouts, :root},
    #   on_mount: [
    #     {JidoHubWeb.LiveUserAuth, :live_user_optional},
    #     {JidoHubWeb.OnMount.ResolveSlug, :owner_pod}
    #   ] do
    #   live "/:owner_slug/:pod_slug", PodLive, :show
    #   live "/:owner_slug/:pod_slug/settings", PodSettingsLive, :index
    #   live "/:owner_slug/:pod_slug/actions", PodActionsLive, :index
    #   live "/:owner_slug/:pod_slug/workflows", PodWorkflowsLive, :index
    # end
  end
end
