defmodule Mix.Tasks.Sprite do
  @shortdoc "Manage Fly.io Sprites (code containers)"
  @moduledoc """
  Manage Fly.io Sprites (code containers).

  ## Commands

      mix sprite.list              # List all sprites
      mix sprite.create NAME       # Create a new sprite (dev environment)
      mix sprite.destroy NAME      # Destroy a sprite
      mix sprite.status NAME       # Show sprite status and git info
      mix sprite.exec NAME -- CMD  # Execute command in sprite
      mix sprite.checkpoint NAME   # Create a checkpoint
      mix sprite.checkpoints NAME  # List checkpoints
      mix sprite.restore NAME ID   # Restore from checkpoint
      mix sprite.git.status NAME   # Show git status in sprite
      mix sprite.git.push NAME     # Push changes from sprite

  ## Environment Variables

      SPRITE_TOKEN         - Sprites API token (required)
      SPRITE_SSH_KEY_PATH  - Default SSH key for private repos
      ANTHROPIC_API_KEY    - Default Claude API key
      SPRITE_DEFAULT_REPO  - Default git repository URL
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    case args do
      ["list" | rest] -> Mix.Tasks.Sprite.List.run(rest)
      ["create" | rest] -> Mix.Tasks.Sprite.Create.run(rest)
      ["destroy" | rest] -> Mix.Tasks.Sprite.Destroy.run(rest)
      ["status" | rest] -> Mix.Tasks.Sprite.Status.run(rest)
      ["exec" | rest] -> Mix.Tasks.Sprite.Exec.run(rest)
      ["checkpoint" | rest] -> Mix.Tasks.Sprite.Checkpoint.run(rest)
      ["checkpoints" | rest] -> Mix.Tasks.Sprite.Checkpoints.run(rest)
      ["restore" | rest] -> Mix.Tasks.Sprite.Restore.run(rest)
      ["git.status" | rest] -> Mix.Tasks.Sprite.Git.Status.run(rest)
      ["git.push" | rest] -> Mix.Tasks.Sprite.Git.Push.run(rest)
      _ -> Mix.shell().info(@moduledoc)
    end
  end
end

defmodule Mix.Tasks.Sprite.Helpers do
  @moduledoc false

  @default_repo "git@github.com:agentjido/jido_workspace.git"
  @project_dir "/home/sprite/workspace"

  def load_env! do
    env_paths = [Path.expand(".env")]

    Enum.find(env_paths, &File.exists?/1)
    |> case do
      nil -> :ok
      path -> Dotenv.load!(path)
    end
  end

  def get_token! do
    load_env!()

    case System.get_env("SPRITE_TOKEN") do
      nil -> Mix.raise("SPRITE_TOKEN environment variable required")
      token -> token
    end
  end

  def build_client do
    Sprites.new(get_token!())
  end

  def default_repo, do: System.get_env("SPRITE_DEFAULT_REPO", @default_repo)
  def project_dir, do: @project_dir

  def run!(sprite, cmd, args, opts \\ []) do
    opts = Keyword.put_new(opts, :stderr_to_stdout, true)

    case Sprites.cmd(sprite, cmd, args, opts) do
      {output, 0} ->
        output

      {output, code} ->
        Mix.raise("Command failed (exit #{code}): #{cmd} #{Enum.join(args, " ")}\n#{output}")
    end
  end

  def stream_cmd(sprite, cmd, args, opts \\ []) do
    sprite
    |> Sprites.stream(cmd, args, opts)
    |> Stream.each(&IO.write/1)
    |> Stream.run()
  end
end

defmodule Mix.Tasks.Sprite.Dev do
  @moduledoc """
  Helper functions for setting up development environments on Sprites.
  """
  alias Mix.Tasks.Sprite.Helpers
  require Logger

  def setup(sprite, opts) do
    Mix.shell().info("\nSetting up development environment...")

    if opts[:ssh_key] do
      setup_ssh(sprite, opts)
    end

    unless opts[:no_repo] do
      clone_repo(sprite, opts)
      run_startup_script(sprite, opts)
    end

    if opts[:claude_key] do
      configure_claude(sprite, opts)
      verify_claude(sprite, opts)
    end

    create_initial_checkpoint(sprite, opts)

    Mix.shell().info("\nDevelopment environment ready!")
  end

  def setup_ssh(sprite, opts) do
    Mix.shell().info("  Configuring SSH for private repo access...")

    key_path = opts[:ssh_key]

    unless File.exists?(key_path) do
      Mix.raise("SSH key not found: #{key_path}")
    end

    key = File.read!(key_path)

    cmd = """
    set -e
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    cat > ~/.ssh/id_ed25519 << 'SSHKEYEOF'
    #{String.trim(key)}
    SSHKEYEOF
    chmod 600 ~/.ssh/id_ed25519
    ssh-keyscan -H github.com >> ~/.ssh/known_hosts 2>/dev/null
    """

    Helpers.run!(sprite, "bash", ["-lc", cmd])
    Mix.shell().info("  [ok] SSH configured")
  end

  def clone_repo(sprite, opts) do
    repo = opts[:repo] || Helpers.default_repo()
    branch = opts[:branch] || opts[:name]
    project_dir = Helpers.project_dir()

    Mix.shell().info("  Cloning repository...")
    Mix.shell().info("     Repo: #{repo}")
    Mix.shell().info("     Branch: #{branch}")

    Helpers.run!(sprite, "mkdir", ["-p", Path.dirname(project_dir)])
    Helpers.run!(sprite, "rm", ["-rf", project_dir])
    Helpers.run!(sprite, "git", ["clone", repo, project_dir])

    Helpers.run!(sprite, "git", ["fetch", "origin"], dir: project_dir)

    {_, code} =
      Sprites.cmd(sprite, "git", ["checkout", branch],
        dir: project_dir,
        stderr_to_stdout: true
      )

    if code != 0 do
      Mix.shell().info("     Branch '#{branch}' not found, creating from origin/main...")

      Helpers.run!(sprite, "git", ["checkout", "-b", branch, "origin/main"],
        dir: project_dir
      )
    end

    git_user = opts[:git_user] || "Sprite Dev"
    git_email = opts[:git_email] || "sprite@jido.dev"

    Helpers.run!(sprite, "git", ["config", "--global", "user.name", git_user])
    Helpers.run!(sprite, "git", ["config", "--global", "user.email", git_email])

    Mix.shell().info("  [ok] Repository cloned and configured")
  end

  def run_startup_script(sprite, opts) do
    Mix.shell().info("  Running startup script (mix deps.get)...")

    startup_cmd = opts[:startup] || "mix deps.get"
    project_dir = Helpers.project_dir()

    Helpers.stream_cmd(
      sprite,
      "bash",
      ["-lc", "cd #{project_dir} && #{startup_cmd}"],
      env: [{"MIX_ENV", "dev"}]
    )

    Mix.shell().info("  [ok] Dependencies installed")
  end

  def configure_claude(sprite, opts) do
    Mix.shell().info("  Configuring Claude Code...")

    key = resolve_claude_key(opts)

    cmd = """
    set -e
    mkdir -p ~/.config/claude

    # Write env file for Claude CLI
    cat > ~/.config/claude/env.sh << 'CLAUDEKEYEOF'
    export ANTHROPIC_API_KEY=#{String.trim(key)}
    CLAUDEKEYEOF

    # Add to shell profile for interactive sessions
    if ! grep -q 'claude/env.sh' ~/.bashrc 2>/dev/null; then
      echo 'source ~/.config/claude/env.sh 2>/dev/null || true' >> ~/.bashrc
    fi

    # Also set up for non-interactive commands
    cat > ~/.profile.d/claude.sh << 'PROFILEEOF' 2>/dev/null || true
    source ~/.config/claude/env.sh
    PROFILEEOF
    """

    Helpers.run!(sprite, "bash", ["-lc", cmd])
    Mix.shell().info("  [ok] Claude configured")
  end

  defp resolve_claude_key(opts) do
    cond do
      opts[:claude_key] ->
        opts[:claude_key]

      opts[:claude_key_env] ->
        case System.get_env(opts[:claude_key_env]) do
          nil -> Mix.raise("Environment variable #{opts[:claude_key_env]} not set")
          key -> key
        end

      true ->
        case System.get_env("ANTHROPIC_API_KEY") do
          nil -> Mix.raise("No Claude API key provided. Use --claude-key or set ANTHROPIC_API_KEY")
          key -> key
        end
    end
  end

  def verify_claude(sprite, _opts) do
    Mix.shell().info("  Verifying Claude CLI...")

    {output, code} =
      Sprites.cmd(
        sprite,
        "bash",
        ["-lc", "source ~/.config/claude/env.sh && claude --version"],
        timeout: 30_000,
        stderr_to_stdout: true
      )

    if code != 0 do
      Mix.shell().error("  [warn] Claude CLI check failed: #{output}")
    else
      Mix.shell().info("  [ok] Claude CLI verified: #{String.trim(output)}")
    end
  end

  def create_initial_checkpoint(sprite, opts) do
    unless opts[:no_checkpoint] do
      Mix.shell().info("  Creating initial checkpoint...")

      comment = "setup: repo clone + deps + claude configured"

      case Sprites.create_checkpoint(sprite, comment: comment) do
        {:ok, _} ->
          Mix.shell().info("  [ok] Checkpoint created")

        {:error, reason} ->
          Mix.shell().error("  [warn] Failed to create checkpoint: #{inspect(reason)}")
      end
    end
  end

  def run_claude_prompt(sprite, prompt) do
    Mix.shell().info("\nRunning Claude prompt: #{prompt}")

    project_dir = Helpers.project_dir()

    Helpers.stream_cmd(
      sprite,
      "bash",
      ["-lc", "source ~/.config/claude/env.sh && cd #{project_dir} && claude -p \"#{prompt}\""],
      tty: true
    )
  end
end

defmodule Mix.Tasks.Sprite.List do
  @shortdoc "List all sprites"
  use Mix.Task
  alias Mix.Tasks.Sprite.Helpers

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start", [])
    client = Helpers.build_client()

    Mix.shell().info("Fetching sprites...\n")

    case Sprites.list(client) do
      {:ok, sprites} ->
        show_sprites(sprites)

      {:error, error} ->
        Mix.shell().error("Failed to list sprites: #{inspect(error)}")
    end
  end

  defp show_sprites([]) do
    Mix.shell().info("No sprites found.")
  end

  defp show_sprites(sprites) do
    for sprite <- sprites do
      name = sprite["name"]
      url = sprite["url"] || "no url"
      created = sprite["created_at"]

      Mix.shell().info("#{name} - #{url} (created: #{created})")
    end
  end
end

defmodule Mix.Tasks.Sprite.Create do
  @shortdoc "Create a new sprite dev environment"
  @moduledoc """
  Create a new Fly.io Sprite with development environment.

  ## Usage

      mix sprite.create NAME [options]

  ## Options

      --repo URL           Git repository URL (default: jido_workspace)
      --branch BRANCH      Git branch to checkout (default: NAME)
      --no-repo            Don't clone any repository
      --ssh-key PATH       Path to SSH private key for private repos
      --claude-key KEY     Claude API key (or use ANTHROPIC_API_KEY env)
      --claude-key-env VAR Environment variable containing Claude key
      --startup CMD        Startup command (default: "mix deps.get")
      --no-checkpoint      Skip creating initial checkpoint
      --test-claude        Run a test Claude prompt after setup

  ## Examples

      mix sprite.create myfeature
      mix sprite.create myfeature --branch main --claude-key sk-ant-...
      mix sprite.create myfeature --ssh-key ~/.ssh/deploy_key
      mix sprite.create blank --no-repo
  """

  use Mix.Task
  alias Mix.Tasks.Sprite.{Helpers, Dev}

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start", [])

    {opts, args, _} =
      OptionParser.parse(args,
        strict: [
          repo: :string,
          branch: :string,
          no_repo: :boolean,
          ssh_key: :string,
          claude_key: :string,
          claude_key_env: :string,
          startup: :string,
          no_checkpoint: :boolean,
          test_claude: :boolean,
          git_user: :string,
          git_email: :string
        ]
      )

    case args do
      [name | _] -> create_sprite(name, opts)
      [] -> Mix.raise("Usage: mix sprite.create NAME [options]")
    end
  end

  defp create_sprite(name, opts) do
    client = Helpers.build_client()

    opts = Keyword.put(opts, :name, name)

    opts =
      if opts[:ssh_key] == nil do
        case System.get_env("SPRITE_SSH_KEY_PATH") do
          nil -> opts
          path -> Keyword.put(opts, :ssh_key, path)
        end
      else
        opts
      end

    Mix.shell().info("Creating sprite '#{name}'...")

    case Sprites.create(client, name) do
      {:ok, sprite} ->
        Mix.shell().info("[ok] Sprite created: #{sprite.name}")

        case Sprites.get_sprite(client, name) do
          {:ok, details} ->
            Mix.shell().info("  URL: #{details["url"]}")

          _ ->
            :ok
        end

        Dev.setup(sprite, opts)

        if opts[:test_claude] do
          Dev.run_claude_prompt(sprite, "Say hello world")
        end

        print_summary(name, opts)

      {:error, error} ->
        Mix.raise("Failed to create sprite: #{inspect(error)}")
    end
  end

  defp print_summary(name, opts) do
    branch = opts[:branch] || name
    project_dir = Helpers.project_dir()

    Mix.shell().info("""

    ----------------------------------------------------------------
    Sprite '#{name}' is ready
    ----------------------------------------------------------------

    Quick commands:
      mix sprite.status #{name}         # Check status
      mix sprite.exec #{name} -- ls     # Run command
      mix sprite.git.status #{name}     # Check git status
      mix sprite.git.push #{name}       # Push changes to GitHub

    To get your changes back locally:
      git fetch origin && git checkout #{branch} && git pull

    Working directory: #{project_dir}
    ----------------------------------------------------------------
    """)
  end
end

defmodule Mix.Tasks.Sprite.Destroy do
  @shortdoc "Destroy a sprite"
  @moduledoc """
  Destroy a Fly.io Sprite.

  ## Usage

      mix sprite.destroy NAME [--force]
  """

  use Mix.Task
  alias Mix.Tasks.Sprite.Helpers

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start", [])

    {opts, args, _} = OptionParser.parse(args, strict: [force: :boolean])

    case args do
      [name] -> destroy_sprite(name, opts)
      [] -> Mix.raise("Usage: mix sprite.destroy NAME [--force]")
      _ -> Mix.raise("Too many arguments")
    end
  end

  defp destroy_sprite(name, opts) do
    client = Helpers.build_client()
    sprite = Sprites.sprite(client, name)

    unless opts[:force] do
      unless Mix.shell().yes?("Destroy sprite #{name}?") do
        Mix.raise("Aborted")
      end
    end

    Mix.shell().info("Destroying sprite '#{name}'...")

    case Sprites.destroy(sprite) do
      :ok ->
        Mix.shell().info("[ok] Sprite #{name} destroyed")

      {:error, error} ->
        Mix.raise("Failed to destroy sprite: #{inspect(error)}")
    end
  end
end

defmodule Mix.Tasks.Sprite.Status do
  @shortdoc "Show sprite status"
  @moduledoc """
  Show sprite status and git info.

  ## Usage

      mix sprite.status NAME
  """

  use Mix.Task
  alias Mix.Tasks.Sprite.Helpers

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start", [])

    case args do
      [name] -> show_status(name)
      [] -> Mix.raise("Usage: mix sprite.status NAME")
      _ -> Mix.raise("Too many arguments")
    end
  end

  defp show_status(name) do
    client = Helpers.build_client()

    case Sprites.get_sprite(client, name) do
      {:ok, info} ->
        sprite = Sprites.sprite(client, name)
        project_dir = Helpers.project_dir()

        Mix.shell().info("Sprite: #{name}")
        Mix.shell().info("URL: #{info["url"]}")
        Mix.shell().info("")

        {git_branch, _} =
          Sprites.cmd(sprite, "git", ["branch", "--show-current"],
            dir: project_dir,
            stderr_to_stdout: true
          )

        Mix.shell().info("Git branch: #{String.trim(git_branch)}")

        {git_status, _} =
          Sprites.cmd(sprite, "git", ["status", "--short"],
            dir: project_dir,
            stderr_to_stdout: true
          )

        if String.trim(git_status) == "" do
          Mix.shell().info("Git status: Clean")
        else
          Mix.shell().info("Git status:")
          Mix.shell().info(git_status)
        end

        case Sprites.list_checkpoints(sprite) do
          {:ok, checkpoints} when checkpoints != [] ->
            Mix.shell().info("")
            Mix.shell().info("Recent checkpoints:")

            checkpoints
            |> Enum.take(3)
            |> Enum.each(fn cp ->
              Mix.shell().info("  #{cp["id"]} - #{cp["comment"] || "no comment"}")
            end)

          _ ->
            :ok
        end

      {:error, {:not_found, _}} ->
        Mix.raise("Sprite '#{name}' not found")

      {:error, error} ->
        Mix.raise("Failed to get sprite status: #{inspect(error)}")
    end
  end
end

defmodule Mix.Tasks.Sprite.Exec do
  @shortdoc "Execute command in sprite"
  @moduledoc """
  Execute a command in a sprite.

  ## Usage

      mix sprite.exec NAME -- COMMAND [ARGS...]
      mix sprite.exec NAME --shell   # Start interactive shell

  ## Examples

      mix sprite.exec mysprite -- ls -la
      mix sprite.exec mysprite -- mix test
      mix sprite.exec mysprite --shell
  """

  use Mix.Task
  alias Mix.Tasks.Sprite.Helpers

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start", [])

    {opts, args, _} = OptionParser.parse(args, strict: [shell: :boolean])

    case {args, opts[:shell]} do
      {[name, "--" | cmd_args], _} when cmd_args != [] ->
        exec_command(name, cmd_args, opts)

      {[name], true} ->
        exec_shell(name)

      _ ->
        Mix.raise("Usage: mix sprite.exec NAME -- COMMAND [ARGS...]")
    end
  end

  defp exec_command(name, [cmd | args], _opts) do
    client = Helpers.build_client()
    sprite = Sprites.sprite(client, name)
    project_dir = Helpers.project_dir()

    Helpers.stream_cmd(sprite, cmd, args, dir: project_dir)
  end

  defp exec_shell(name) do
    client = Helpers.build_client()
    sprite = Sprites.sprite(client, name)
    project_dir = Helpers.project_dir()

    Mix.shell().info("Starting shell in #{project_dir}...")
    Mix.shell().info("(Note: Interactive shell support is limited)")

    Helpers.stream_cmd(
      sprite,
      "bash",
      ["-lc", "cd #{project_dir} && exec bash"],
      tty: true
    )
  end
end

defmodule Mix.Tasks.Sprite.Checkpoint do
  @shortdoc "Create a checkpoint"
  @moduledoc """
  Create a checkpoint of the sprite state.

  ## Usage

      mix sprite.checkpoint NAME [--comment "message"]
  """

  use Mix.Task
  alias Mix.Tasks.Sprite.Helpers

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start", [])

    {opts, args, _} = OptionParser.parse(args, strict: [comment: :string])

    case args do
      [name] -> create_checkpoint(name, opts)
      [] -> Mix.raise("Usage: mix sprite.checkpoint NAME [--comment \"message\"]")
      _ -> Mix.raise("Too many arguments")
    end
  end

  defp create_checkpoint(name, opts) do
    client = Helpers.build_client()
    sprite = Sprites.sprite(client, name)

    comment = opts[:comment] || "Manual checkpoint"

    Mix.shell().info("Creating checkpoint...")

    case Sprites.create_checkpoint(sprite, comment: comment) do
      {:ok, _} ->
        Mix.shell().info("[ok] Checkpoint created: #{comment}")

      {:error, error} ->
        Mix.raise("Failed to create checkpoint: #{inspect(error)}")
    end
  end
end

defmodule Mix.Tasks.Sprite.Checkpoints do
  @shortdoc "List checkpoints"
  @moduledoc """
  List checkpoints for a sprite.

  ## Usage

      mix sprite.checkpoints NAME
  """

  use Mix.Task
  alias Mix.Tasks.Sprite.Helpers

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start", [])

    case args do
      [name] -> list_checkpoints(name)
      [] -> Mix.raise("Usage: mix sprite.checkpoints NAME")
      _ -> Mix.raise("Too many arguments")
    end
  end

  defp list_checkpoints(name) do
    client = Helpers.build_client()
    sprite = Sprites.sprite(client, name)

    case Sprites.list_checkpoints(sprite) do
      {:ok, []} ->
        Mix.shell().info("No checkpoints found.")

      {:ok, checkpoints} ->
        Mix.shell().info("Checkpoints for #{name}:\n")

        for cp <- checkpoints do
          id = cp["id"]
          comment = cp["comment"] || "no comment"
          created = cp["created_at"]
          Mix.shell().info("  #{id} - #{comment} (#{created})")
        end

      {:error, error} ->
        Mix.raise("Failed to list checkpoints: #{inspect(error)}")
    end
  end
end

defmodule Mix.Tasks.Sprite.Restore do
  @shortdoc "Restore from checkpoint"
  @moduledoc """
  Restore a sprite from a checkpoint.

  ## Usage

      mix sprite.restore NAME CHECKPOINT_ID
  """

  use Mix.Task
  alias Mix.Tasks.Sprite.Helpers

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start", [])

    case args do
      [name, checkpoint_id] -> restore_checkpoint(name, checkpoint_id)
      [_] -> Mix.raise("Usage: mix sprite.restore NAME CHECKPOINT_ID")
      [] -> Mix.raise("Usage: mix sprite.restore NAME CHECKPOINT_ID")
      _ -> Mix.raise("Too many arguments")
    end
  end

  defp restore_checkpoint(name, checkpoint_id) do
    client = Helpers.build_client()
    sprite = Sprites.sprite(client, name)

    Mix.shell().info("Restoring checkpoint #{checkpoint_id}...")
    Mix.shell().info("Note: This will restore filesystem state but NOT running processes.")
    Mix.shell().info("Note: Use Git for code history - checkpoints are for environment state.")

    case Sprites.restore_checkpoint(sprite, checkpoint_id) do
      {:ok, _} ->
        Mix.shell().info("[ok] Checkpoint restored")

      {:error, error} ->
        Mix.raise("Failed to restore checkpoint: #{inspect(error)}")
    end
  end
end

defmodule Mix.Tasks.Sprite.Git.Status do
  @shortdoc "Show git status in sprite"
  @moduledoc """
  Show git status in the sprite's project directory.

  ## Usage

      mix sprite.git.status NAME
  """

  use Mix.Task
  alias Mix.Tasks.Sprite.Helpers

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start", [])

    case args do
      [name] -> show_git_status(name)
      [] -> Mix.raise("Usage: mix sprite.git.status NAME")
      _ -> Mix.raise("Too many arguments")
    end
  end

  defp show_git_status(name) do
    client = Helpers.build_client()
    sprite = Sprites.sprite(client, name)
    project_dir = Helpers.project_dir()

    {branch, _} =
      Sprites.cmd(sprite, "git", ["branch", "--show-current"],
        dir: project_dir,
        stderr_to_stdout: true
      )

    Mix.shell().info("Branch: #{String.trim(branch)}")
    Mix.shell().info("")

    Helpers.stream_cmd(sprite, "git", ["status"], dir: project_dir)
  end
end

defmodule Mix.Tasks.Sprite.Git.Push do
  @shortdoc "Push changes from sprite to GitHub"
  @moduledoc """
  Commit and push changes from the sprite to GitHub.

  ## Usage

      mix sprite.git.push NAME [--message "commit message"]
      mix sprite.git.push NAME --push-only   # Just push, don't commit

  ## Examples

      mix sprite.git.push mysprite --message "Fix bug"
      mix sprite.git.push mysprite --push-only
  """

  use Mix.Task
  alias Mix.Tasks.Sprite.Helpers

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start", [])

    {opts, args, _} =
      OptionParser.parse(args,
        strict: [
          message: :string,
          push_only: :boolean
        ]
      )

    case args do
      [name] -> push_changes(name, opts)
      [] -> Mix.raise("Usage: mix sprite.git.push NAME [--message \"msg\"]")
      _ -> Mix.raise("Too many arguments")
    end
  end

  defp push_changes(name, opts) do
    client = Helpers.build_client()
    sprite = Sprites.sprite(client, name)
    project_dir = Helpers.project_dir()

    {branch, _} =
      Sprites.cmd(sprite, "git", ["branch", "--show-current"],
        dir: project_dir,
        stderr_to_stdout: true
      )

    branch = String.trim(branch)

    unless opts[:push_only] do
      {status, _} =
        Sprites.cmd(sprite, "git", ["status", "--porcelain"],
          dir: project_dir,
          stderr_to_stdout: true
        )

      if String.trim(status) != "" do
        message = opts[:message] || "Changes from Sprite dev"

        Mix.shell().info("Staging changes...")
        Helpers.run!(sprite, "git", ["add", "-A"], dir: project_dir)

        Mix.shell().info("Committing: #{message}")
        Helpers.run!(sprite, "git", ["commit", "-m", message], dir: project_dir)
      else
        Mix.shell().info("No changes to commit")
      end
    end

    Mix.shell().info("Pushing to origin/#{branch}...")
    Helpers.stream_cmd(sprite, "git", ["push", "origin", branch], dir: project_dir)

    Mix.shell().info("")
    Mix.shell().info("[ok] Changes pushed")
    Mix.shell().info("To pull locally: git fetch origin && git checkout #{branch} && git pull")
  end
end
