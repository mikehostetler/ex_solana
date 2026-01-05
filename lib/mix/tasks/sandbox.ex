defmodule Mix.Tasks.Sandbox do
  @shortdoc "Manage Fly.io development sandboxes"
  @moduledoc """
  Manage Fly.io development sandboxes.

  ## Commands

      mix sandbox.list            # List all sandboxes
      mix sandbox.create NAME     # Create a new sandbox
      mix sandbox.status NAME     # Show sandbox status
      mix sandbox.password NAME   # Show code-server password
      mix sandbox.start NAME      # Start a stopped sandbox
      mix sandbox.stop NAME       # Stop a running sandbox
      mix sandbox.destroy NAME    # Destroy a sandbox
      mix sandbox.build           # Build and push base image

  ## Environment Variables

      FLY_API_TOKEN    - Fly.io API token (required)
      FLY_ORG          - Fly.io org slug (default: personal)
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    case args do
      ["list" | rest] -> Mix.Tasks.Sandbox.List.run(rest)
      ["create" | rest] -> Mix.Tasks.Sandbox.Create.run(rest)
      ["status" | rest] -> Mix.Tasks.Sandbox.Status.run(rest)
      ["password" | rest] -> Mix.Tasks.Sandbox.Password.run(rest)
      ["start" | rest] -> Mix.Tasks.Sandbox.Start.run(rest)
      ["stop" | rest] -> Mix.Tasks.Sandbox.Stop.run(rest)
      ["destroy" | rest] -> Mix.Tasks.Sandbox.Destroy.run(rest)
      ["build" | rest] -> Mix.Tasks.Sandbox.Build.run(rest)
      _ -> Mix.shell().info(@moduledoc)
    end
  end
end

defmodule Mix.Tasks.Sandbox.Helpers do
  @moduledoc false

  @default_org "jido_dev"
  @default_region "ord"
  @default_repo "git@github.com:agentjido/jido_workspace.git"
  @base_app "jido-sandbox-base"
  @app_prefix "jido-sandbox-"

  def load_env! do
    env_paths = [
      Path.expand("fly-sandbox/.env"),
      Path.expand(".env")
    ]

    Enum.find(env_paths, &File.exists?/1)
    |> case do
      nil -> :ok
      path -> Dotenv.load!(path)
    end
  end

  def get_token! do
    load_env!()
    case System.get_env("FLY_API_TOKEN") do
      nil -> Mix.raise("FLY_API_TOKEN environment variable required")
      token -> token
    end
  end

  def get_org, do: System.get_env("FLY_ORG", @default_org)
  def get_region, do: System.get_env("FLY_REGION", @default_region)
  def default_repo, do: System.get_env("SANDBOX_DEFAULT_REPO", @default_repo)
  def base_app, do: @base_app
  def app_prefix, do: @app_prefix

  def app_name(name), do: "#{@app_prefix}#{name}"

  def build_client do
    Req.new() |> ReqFly.attach(token: get_token!())
  end

  def generate_password do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  def get_base_image! do
    req = build_client()

    case ReqFly.Machines.list(req, app_name: @base_app) do
      {:ok, [machine | _]} ->
        machine["config"]["image"]

      _ ->
        Mix.raise("No base image found. Run: mix sandbox build")
    end
  end

  @graphql_url "https://api.fly.io/graphql"

  def allocate_shared_ipv4(app_name) do
    query = """
    mutation ($input: AllocateIPAddressInput!) {
      allocateIpAddress(input: $input) {
        app {
          sharedIpAddress
        }
      }
    }
    """

    case graphql_request(query, %{input: %{appId: app_name, type: "shared_v4"}}) do
      {:ok, %{"data" => %{"allocateIpAddress" => %{"app" => %{"sharedIpAddress" => ip}}}}} ->
        {:ok, ip}

      {:ok, %{"errors" => [%{"message" => msg} | _]}} ->
        {:error, msg}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def allocate_ipv6(app_name) do
    query = """
    mutation ($input: AllocateIPAddressInput!) {
      allocateIpAddress(input: $input) {
        ipAddress {
          id
          address
          type
        }
      }
    }
    """

    case graphql_request(query, %{input: %{appId: app_name, type: "v6"}}) do
      {:ok, %{"data" => %{"allocateIpAddress" => %{"ipAddress" => %{"address" => addr}}}}} ->
        {:ok, addr}

      {:ok, %{"errors" => [%{"message" => msg} | _]}} ->
        {:error, msg}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp graphql_request(query, variables) do
    Req.post(@graphql_url,
      json: %{query: query, variables: variables},
      auth: {:bearer, get_token!()}
    )
    |> case do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, "HTTP #{status}: #{inspect(body)}"}
      {:error, reason} -> {:error, reason}
    end
  end
end

defmodule Mix.Tasks.Sandbox.List do
  @shortdoc "List all sandboxes"
  use Mix.Task
  alias Mix.Tasks.Sandbox.Helpers

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start", [])
    req = Helpers.build_client()

    Mix.shell().info("Fetching sandboxes...\n")

    case ReqFly.Apps.list(req, org_slug: Helpers.get_org()) do
      {:ok, %{"apps" => apps}} ->
        sandboxes =
          apps
          |> Enum.filter(&String.starts_with?(&1["name"], Helpers.app_prefix()))
          |> Enum.reject(&(&1["name"] == Helpers.base_app()))
        show_sandboxes(req, sandboxes)

      {:ok, apps} when is_list(apps) ->
        sandboxes =
          apps
          |> Enum.filter(&String.starts_with?(&1["name"], Helpers.app_prefix()))
          |> Enum.reject(&(&1["name"] == Helpers.base_app()))
        show_sandboxes(req, sandboxes)

      {:error, error} ->
        Mix.shell().error("Failed to list apps: #{inspect(error)}")
    end
  end

  defp show_sandboxes(_req, []) do
    Mix.shell().info("No sandboxes found.")
  end

  defp show_sandboxes(req, sandboxes) do
    for app <- sandboxes do
      name = app["name"]
      short_name = String.replace_prefix(name, Helpers.app_prefix(), "")

      state =
        case ReqFly.Machines.list(req, app_name: name) do
          {:ok, [machine | _]} -> machine["state"]
          _ -> "unknown"
        end

      Mix.shell().info("#{short_name} (#{state}) - https://#{name}.fly.dev")
    end
  end
end

defmodule Mix.Tasks.Sandbox.Create do
  @shortdoc "Create a new sandbox"
  @moduledoc """
  Create a new Fly.io development sandbox.

  ## Usage

      mix sandbox.create NAME [options]

  ## Options

      --region      Fly region (default: ord)
      --branch      Git branch to checkout (default: sandbox name)
      --repo        Git repository URL (default: jido_workspace)
      --no-repo     Don't clone any repository
      --ssh-key     Path to SSH private key
      --password    code-server password (auto-generated if not set)

  ## Examples

      mix sandbox.create myfeature              # Clones jido_workspace, checks out 'myfeature' branch
      mix sandbox.create test --branch main     # Uses 'main' branch instead
      mix sandbox.create blank --no-repo        # No repository cloned
  """

  use Mix.Task
  alias Mix.Tasks.Sandbox.Helpers

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start", [])

    {opts, args, _} =
      OptionParser.parse(args,
        strict: [
          region: :string,
          branch: :string,
          repo: :string,
          no_repo: :boolean,
          ssh_key: :string,
          password: :string
        ]
      )

    case args do
      [name] -> create_sandbox(name, opts)
      [] -> Mix.raise("Usage: mix sandbox.create NAME [options]")
      _ -> Mix.raise("Too many arguments")
    end
  end

  defp create_sandbox(name, opts) do
    req = Helpers.build_client()
    app_name = Helpers.app_name(name)
    org = Helpers.get_org()
    region = opts[:region] || Helpers.get_region()
    password = opts[:password] || Helpers.generate_password()

    Mix.shell().info("Creating sandbox: #{app_name}")
    Mix.shell().info("  Org: #{org}")
    Mix.shell().info("  Region: #{region}\n")

    # 1. Create app
    case ReqFly.Apps.create(req, app_name: app_name, org_slug: org) do
      {:ok, _} -> Mix.shell().info("✓ App created")
      {:error, %ReqFly.Error{status: 422}} -> Mix.shell().info("✓ App exists")
      {:error, error} -> Mix.raise("Failed to create app: #{inspect(error)}")
    end

    # 2. Allocate IP addresses (required for public access)
    case Helpers.allocate_shared_ipv4(app_name) do
      {:ok, ip} -> Mix.shell().info("✓ Shared IPv4 allocated: #{ip}")
      {:error, msg} -> Mix.shell().info("⚠ IPv4 allocation: #{msg}")
    end

    case Helpers.allocate_ipv6(app_name) do
      {:ok, ip} -> Mix.shell().info("✓ IPv6 allocated: #{ip}")
      {:error, msg} -> Mix.shell().info("⚠ IPv6 allocation: #{msg}")
    end

    # 3. Set secrets
    ReqFly.Secrets.create(req, app_name: app_name, label: "PASSWORD", type: "env", value: password)

    if opts[:branch] do
      ReqFly.Secrets.create(req,
        app_name: app_name,
        label: "BRANCH_NAME",
        type: "env",
        value: opts[:branch]
      )
    end

    Mix.shell().info("✓ Secrets set")

    # 4. Get base image and create machine
    image = Helpers.get_base_image!()
    Mix.shell().info("  Using image: #{image}")
    config = build_machine_config(name, opts, image)

    case ReqFly.Machines.create(req, app_name: app_name, config: config, region: region) do
      {:ok, machine} ->
        Mix.shell().info("✓ Machine created: #{machine["id"]}")

        case ReqFly.Machines.wait(req,
               app_name: app_name,
               machine_id: machine["id"],
               state: "started",
               timeout: 60
             ) do
          {:ok, _} -> Mix.shell().info("✓ Machine started")
          {:error, _} -> Mix.shell().info("⚠ Machine may still be starting")
        end

      {:error, error} ->
        Mix.raise("Failed to create machine: #{inspect(error)}")
    end

    Mix.shell().info("")
    Mix.shell().info("========================================")
    Mix.shell().info("  Sandbox Ready!")
    Mix.shell().info("========================================")
    Mix.shell().info("  URL: https://#{app_name}.fly.dev")
    Mix.shell().info("  Password: #{password}")
    Mix.shell().info("========================================")
  end

  defp build_machine_config(name, opts, image) do
    env = %{
      "GIT_USER_NAME" => System.get_env("GIT_USER_NAME", "Developer"),
      "GIT_USER_EMAIL" => System.get_env("GIT_USER_EMAIL", "dev@example.com"),
      "CODE_SERVER_PORT" => "9090"
    }

    env =
      unless opts[:no_repo] do
        repo = opts[:repo] || Helpers.default_repo()
        branch = opts[:branch] || name
        env
        |> Map.put("GIT_REPO", repo)
        |> Map.put("BRANCH_NAME", branch)
      else
        env
      end

    config = %{
      "image" => image,
      "env" => env,
      "guest" => %{
        "cpu_kind" => "performance",
        "cpus" => 2,
        "memory_mb" => 8192
      },
      "services" => [
        %{
          "internal_port" => 9090,
          "protocol" => "tcp",
          "ports" => [%{"port" => 443, "handlers" => ["tls", "http"]}],
          "autostop" => "stop",
          "autostart" => true,
          "min_machines_running" => 0,
          "checks" => [
            %{
              "type" => "http",
              "port" => 9090,
              "path" => "/healthz",
              "interval" => 30_000_000_000,
              "timeout" => 10_000_000_000,
              "grace_period" => 30_000_000_000
            }
          ]
        }
      ],
      "auto_destroy" => false,
      "restart" => %{"policy" => "on-failure", "max_retries" => 3}
    }

    # Inject SSH key if available
    ssh_key = get_ssh_key(opts[:ssh_key])
    if ssh_key do
      Map.put(config, "files", [
        %{"guest_path" => "/run/secrets/ssh_key", "raw_value" => Base.encode64(ssh_key)}
      ])
    else
      config
    end
  end

  defp get_ssh_key(nil) do
    paths = [
      Path.expand("fly-sandbox/sandbox_deploy_key"),
      Path.expand("~/.ssh/id_ed25519")
    ]

    Enum.find_value(paths, fn path ->
      if File.exists?(path), do: File.read!(path)
    end)
  end

  defp get_ssh_key(path) do
    path = Path.expand(path)
    if File.exists?(path), do: File.read!(path)
  end
end

defmodule Mix.Tasks.Sandbox.Status do
  @shortdoc "Show sandbox status"
  use Mix.Task
  alias Mix.Tasks.Sandbox.Helpers

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start", [])

    case args do
      [name] -> show_status(name)
      [] -> Mix.raise("Usage: mix sandbox.status NAME")
      _ -> Mix.raise("Too many arguments")
    end
  end

  defp show_status(name) do
    req = Helpers.build_client()
    app_name = Helpers.app_name(name)

    Mix.shell().info("Sandbox: #{name}")
    Mix.shell().info("URL: https://#{app_name}.fly.dev\n")

    case ReqFly.Machines.list(req, app_name: app_name) do
      {:ok, []} ->
        Mix.shell().info("No machines")

      {:ok, machines} ->
        Mix.shell().info("Machines:")

        for m <- machines do
          Mix.shell().info("  #{m["id"]} - #{m["state"]} (#{m["region"]})")
        end

      {:error, %ReqFly.Error{status: 404}} ->
        Mix.raise("Sandbox not found: #{name}")

      {:error, error} ->
        Mix.raise("Failed: #{inspect(error)}")
    end
  end
end

defmodule Mix.Tasks.Sandbox.Password do
  @shortdoc "Show code-server password for a sandbox"
  use Mix.Task
  alias Mix.Tasks.Sandbox.Helpers

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start", [])

    case args do
      [name] -> show_password(name)
      [] -> Mix.raise("Usage: mix sandbox.password NAME")
      _ -> Mix.raise("Too many arguments")
    end
  end

  defp show_password(name) do
    app_name = Helpers.app_name(name)

    Mix.shell().info("Fetching password for #{name}...")

    {output, code} =
      System.cmd("fly", [
        "ssh", "console",
        "--app", app_name,
        "-C", "cat /root/.config/code-server/config.yaml"
      ], stderr_to_stdout: true)

    if code == 0 do
      case Regex.run(~r/password:\s*(.+)/, output) do
        [_, password] ->
          Mix.shell().info("")
          Mix.shell().info("========================================")
          Mix.shell().info("  Sandbox: #{name}")
          Mix.shell().info("  URL: https://#{app_name}.fly.dev")
          Mix.shell().info("  Password: #{String.trim(password)}")
          Mix.shell().info("========================================")

        _ ->
          Mix.shell().error("Could not parse password from config")
          Mix.shell().info(output)
      end
    else
      Mix.shell().error("Failed to connect. Is the sandbox running?")
      Mix.shell().info("Try: mix sandbox start #{name}")
    end
  end
end

defmodule Mix.Tasks.Sandbox.Start do
  @shortdoc "Start a stopped sandbox"
  use Mix.Task
  alias Mix.Tasks.Sandbox.Helpers

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start", [])

    case args do
      [name] -> start_sandbox(name)
      [] -> Mix.raise("Usage: mix sandbox.start NAME")
      _ -> Mix.raise("Too many arguments")
    end
  end

  defp start_sandbox(name) do
    req = Helpers.build_client()
    app_name = Helpers.app_name(name)

    case ReqFly.Machines.list(req, app_name: app_name) do
      {:ok, [machine | _]} ->
        case ReqFly.Machines.start(req, app_name: app_name, machine_id: machine["id"]) do
          {:ok, _} ->
            Mix.shell().info("✓ Starting #{name}...")
            Mix.shell().info("  URL: https://#{app_name}.fly.dev")

          {:error, error} ->
            Mix.raise("Failed to start: #{inspect(error)}")
        end

      {:ok, []} ->
        Mix.raise("No machines found")

      {:error, error} ->
        Mix.raise("Failed: #{inspect(error)}")
    end
  end
end

defmodule Mix.Tasks.Sandbox.Stop do
  @shortdoc "Stop a running sandbox"
  use Mix.Task
  alias Mix.Tasks.Sandbox.Helpers

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start", [])

    case args do
      [name] -> stop_sandbox(name)
      [] -> Mix.raise("Usage: mix sandbox.stop NAME")
      _ -> Mix.raise("Too many arguments")
    end
  end

  defp stop_sandbox(name) do
    req = Helpers.build_client()
    app_name = Helpers.app_name(name)

    case ReqFly.Machines.list(req, app_name: app_name) do
      {:ok, [machine | _]} ->
        case ReqFly.Machines.stop(req, app_name: app_name, machine_id: machine["id"]) do
          {:ok, _} -> Mix.shell().info("✓ Stopping #{name}...")
          {:error, error} -> Mix.raise("Failed to stop: #{inspect(error)}")
        end

      {:ok, []} ->
        Mix.raise("No machines found")

      {:error, error} ->
        Mix.raise("Failed: #{inspect(error)}")
    end
  end
end

defmodule Mix.Tasks.Sandbox.Destroy do
  @shortdoc "Destroy a sandbox"
  @moduledoc """
  Destroy a Fly.io development sandbox.

  ## Usage

      mix sandbox.destroy NAME [--force]
  """

  use Mix.Task
  alias Mix.Tasks.Sandbox.Helpers

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start", [])

    {opts, args, _} = OptionParser.parse(args, strict: [force: :boolean])

    case args do
      [name] -> destroy_sandbox(name, opts)
      [] -> Mix.raise("Usage: mix sandbox.destroy NAME [--force]")
      _ -> Mix.raise("Too many arguments")
    end
  end

  defp destroy_sandbox(name, opts) do
    req = Helpers.build_client()
    app_name = Helpers.app_name(name)

    unless opts[:force] do
      unless Mix.shell().yes?("Destroy sandbox #{name}?") do
        Mix.raise("Aborted")
      end
    end

    # Destroy machines first
    case ReqFly.Machines.list(req, app_name: app_name) do
      {:ok, machines} ->
        for m <- machines do
          ReqFly.Machines.destroy(req, app_name: app_name, machine_id: m["id"], force: true)
        end

      _ ->
        :ok
    end

    # Destroy app
    case ReqFly.Apps.destroy(req, app_name) do
      {:ok, _} -> Mix.shell().info("✓ Sandbox #{name} destroyed")
      {:error, error} -> Mix.raise("Failed: #{inspect(error)}")
    end
  end
end

defmodule Mix.Tasks.Sandbox.Build do
  @shortdoc "Build and push base image"
  @moduledoc """
  Build and push the sandbox base image.

  ## Usage

      mix sandbox build [options]

  ## Options

      --no-push     Build locally only, don't push to Fly
      --local       Use local Docker daemon instead of Depot (remote builder)
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args,
      strict: [no_push: :boolean, local: :boolean]
    )

    sandbox_dir = Path.expand("fly-sandbox")

    unless File.exists?(Path.join(sandbox_dir, "Dockerfile")) do
      Mix.raise("fly-sandbox/Dockerfile not found")
    end

    Mix.shell().info("Building jido-sandbox-base image...")

    if opts[:no_push] do
      {_, code} = System.cmd("docker", ["build", "-t", "jido-sandbox-base", "."],
        cd: sandbox_dir,
        into: IO.stream(:stdio, :line)
      )
      if code == 0 do
        Mix.shell().info("\n✓ Image built locally")
      else
        Mix.raise("Docker build failed")
      end
    else
      fly_args = [
        "deploy",
        "-c", "fly-build.toml",
        "--ha=false"
      ]

      fly_args = if opts[:local] do
        Mix.shell().info("Using local Docker daemon...")
        fly_args ++ ["--local-only"]
      else
        fly_args
      end

      {_, code} = System.cmd("fly", fly_args,
        cd: sandbox_dir,
        into: IO.stream(:stdio, :line)
      )
      if code == 0 do
        Mix.shell().info("\n✓ Image built and deployed")
        Mix.shell().info("  Stopping base machine (only used for image)")
        System.cmd("fly", ["machine", "stop", "--app", "jido-sandbox-base", "--select"],
          cd: sandbox_dir,
          into: IO.stream(:stdio, :line)
        )
      else
        Mix.raise("Fly deploy failed")
      end
    end
  end
end
