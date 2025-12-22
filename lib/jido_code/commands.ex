defmodule JidoCode.Commands do
  @moduledoc """
  Parses and executes slash commands from user input.

  Commands allow users to configure the LLM provider and model at runtime
  without restarting the application.

  ## Available Commands

  | Command | Description |
  |---------|-------------|
  | `/help` | List available commands |
  | `/config` | Display current configuration |
  | `/provider <name>` | Set LLM provider (clears model) |
  | `/model <provider>:<model>` | Set both provider and model |
  | `/model <model>` | Set model for current provider |
  | `/models` | List models for current provider (pending) |
  | `/models <provider>` | List models for provider (pending) |
  | `/providers` | List available providers (pending) |
  | `/resume` | List resumable sessions |
  | `/resume <target>` | Resume session by index or ID |
  | `/resume delete <target>` | Delete session by index or ID |
  | `/resume clear` | Delete all persisted sessions |

  ## Usage

      alias JidoCode.Commands

      config = %{provider: "anthropic", model: "claude-3-5-sonnet"}

      Commands.execute("/help", config)
      #=> {:ok, "Available commands:\\n...", %{}}

      Commands.execute("/model openai:gpt-4o", config)
      #=> {:ok, "Model set to openai:gpt-4o", %{provider: "openai", model: "gpt-4o"}}

      Commands.execute("/unknown", config)
      #=> {:error, "Unknown command: /unknown. Type /help for available commands."}
  """

  alias Jido.AI.Keyring
  alias Jido.AI.Model.Registry.Adapter, as: RegistryAdapter
  alias JidoCode.Agents.LLMAgent
  alias JidoCode.AgentSupervisor
  alias JidoCode.PubSubTopics
  alias JidoCode.Settings
  alias JidoCode.Tools.Manager

  @pubsub JidoCode.PubSub

  # Session index constants
  # Ctrl+0 maps to session 10 (keyboard shortcut convention)
  @ctrl_0_maps_to_index 10

  @type config :: %{provider: String.t() | nil, model: String.t() | nil}
  @type result :: {:ok, String.t(), config()} | {:error, String.t()}

  @help_text """
  Available commands:

    Configuration:
    /help                    - Show this help message
    /config                  - Display current configuration
    /provider <name>         - Set LLM provider (clears model)
    /model <provider>:<model> - Set both provider and model
    /model <model>           - Set model for current provider
    /models                  - List models for current provider
    /models <provider>       - List models for a specific provider
    /providers               - List available providers
    /theme                   - List available themes
    /theme <name>            - Switch to a theme (dark, light, high_contrast)

    Session Management:
    /session                 - Show session command help
    /session new [path]      - Create new session (--name=NAME for custom name)
    /session list            - List all sessions
    /session switch <target> - Switch to session by index, ID, or name
    /session close [target]  - Close session (default: active)
    /session rename <name>   - Rename current session
    /session save [target]   - Save session to disk (default: active)
    /resume                  - List resumable sessions
    /resume <target>         - Resume session by index or ID
    /resume delete <target>  - Delete session by index or ID
    /resume clear            - Delete all persisted sessions

    Development:
    /sandbox-test            - Test the Luerl sandbox security (dev/test only)
    /shell <command> [args]  - Run a shell command (e.g., /shell ls -la)

  Keyboard Shortcuts:
    Ctrl+M                   - Model selection menu
    Ctrl+1 to Ctrl+0         - Switch to session 1-10 (Ctrl+0 = session 10)
    Ctrl+Tab                 - Next session
    Ctrl+Shift+Tab           - Previous session
    Ctrl+W                   - Close current session
    Ctrl+N                   - New session dialog
    Ctrl+R                   - Toggle reasoning panel

  Examples:
    /model anthropic:claude-3-5-sonnet-20241022
    /session new ~/projects/myapp --name="My App"
    /session switch 2
    /resume 1
    /shell mix test
  """

  @doc """
  Executes a slash command and returns the result.

  ## Parameters

  - `command` - The command string starting with `/`
  - `config` - Current configuration map with :provider and :model keys

  ## Returns

  - `{:ok, message, new_config}` - Command executed successfully
  - `{:error, message}` - Command failed

  ## Examples

      iex> Commands.execute("/help", %{provider: nil, model: nil})
      {:ok, "Available commands:...", %{}}

      iex> Commands.execute("/config", %{provider: "anthropic", model: "claude-3-5-sonnet"})
      {:ok, "Provider: anthropic\\nModel: claude-3-5-sonnet", %{}}
  """
  @spec execute(String.t(), config()) :: result()
  def execute(command, config) when is_binary(command) and is_map(config) do
    command
    |> String.trim()
    |> parse_and_execute(config)
  end

  # ============================================================================
  # Command Parsing
  # ============================================================================

  defp parse_and_execute("/help" <> _, _config) do
    {:ok, String.trim(@help_text), %{}}
  end

  defp parse_and_execute("/config" <> _, config) do
    provider = config[:provider] || config["provider"] || "(not set)"
    model = config[:model] || config["model"] || "(not set)"

    message = "Provider: #{provider}\nModel: #{model}"
    {:ok, message, %{}}
  end

  defp parse_and_execute("/provider " <> rest, _config) do
    provider = String.trim(rest)
    execute_provider_command(provider)
  end

  defp parse_and_execute("/provider", _config) do
    {:error, "Usage: /provider <name>\n\nExample: /provider anthropic"}
  end

  defp parse_and_execute("/model " <> rest, config) do
    model_spec = String.trim(rest)
    execute_model_command(model_spec, config)
  end

  defp parse_and_execute("/model", _config) do
    {:error,
     "Usage: /model <provider>:<model> or /model <model>\n\nExamples:\n  /model anthropic:claude-3-5-sonnet\n  /model gpt-4o"}
  end

  defp parse_and_execute("/models " <> rest, _config) do
    provider = String.trim(rest)
    execute_models_command(provider)
  end

  defp parse_and_execute("/models", config) do
    provider = config[:provider] || config["provider"]

    if provider do
      execute_models_command(provider)
    else
      {:error, "No provider set. Use /provider <name> first, or /models <provider>"}
    end
  end

  defp parse_and_execute("/providers" <> _, _config) do
    execute_providers_command()
  end

  defp parse_and_execute("/theme " <> rest, _config) do
    theme_name = String.trim(rest)
    execute_theme_command(theme_name)
  end

  defp parse_and_execute("/theme", _config) do
    execute_theme_list_command()
  end

  defp parse_and_execute("/sandbox-test" <> _, _config) do
    if Mix.env() in [:dev, :test] do
      execute_sandbox_test()
    else
      {:error, "Command /sandbox-test is only available in dev and test environments"}
    end
  end

  defp parse_and_execute("/session " <> rest, _config) do
    {:session, parse_session_args(String.trim(rest))}
  end

  defp parse_and_execute("/session", _config) do
    {:session, :help}
  end

  defp parse_and_execute("/resume delete " <> rest, _config) do
    {:resume, {:delete, String.trim(rest)}}
  end

  defp parse_and_execute("/resume clear", _config) do
    {:resume, :clear}
  end

  defp parse_and_execute("/resume " <> rest, _config) do
    {:resume, {:restore, String.trim(rest)}}
  end

  defp parse_and_execute("/resume", _config) do
    {:resume, :list}
  end

  defp parse_and_execute("/shell " <> rest, _config) do
    execute_shell_command(String.trim(rest))
  end

  defp parse_and_execute("/shell", _config) do
    {:error,
     "Usage: /shell <command> [args]\n\nExamples:\n  /shell ls -la\n  /shell mix test\n  /shell git status"}
  end

  defp parse_and_execute("/" <> command, _config) do
    # Extract just the command name for error message
    command_name = command |> String.split() |> List.first() || command
    {:error, "Unknown command: /#{command_name}. Type /help for available commands."}
  end

  defp parse_and_execute(text, _config) do
    {:error, "Not a command: #{text}. Commands start with /"}
  end

  # ============================================================================
  # Session Command Parsing
  # ============================================================================

  # Parse session subcommand arguments
  # Returns a tuple that the TUI will handle for execution
  defp parse_session_args("new" <> rest) do
    {:new, parse_new_session_args(String.trim(rest))}
  end

  defp parse_session_args("list"), do: :list

  defp parse_session_args("save" <> rest) do
    case String.trim(rest) do
      "" -> {:save, nil}
      target -> {:save, target}
    end
  end

  defp parse_session_args("switch " <> target) do
    {:switch, String.trim(target)}
  end

  defp parse_session_args("switch"), do: {:error, "Usage: /session switch <index|id|name>"}

  defp parse_session_args("close" <> rest) do
    case String.trim(rest) do
      "" -> {:close, nil}
      target -> {:close, target}
    end
  end

  defp parse_session_args("rename " <> name) do
    {:rename, String.trim(name)}
  end

  defp parse_session_args("rename"), do: {:error, "Usage: /session rename <name>"}

  defp parse_session_args(_), do: :help

  # Parse arguments for /session new [path] [--name=NAME]
  defp parse_new_session_args("") do
    %{path: nil, name: nil}
  end

  defp parse_new_session_args(args_string) do
    parts = String.split(args_string, ~r/\s+/)
    parse_new_session_parts(parts, %{path: nil, name: nil})
  end

  defp parse_new_session_parts([], acc), do: acc

  defp parse_new_session_parts(["--name=" <> name | rest], acc) do
    parse_new_session_parts(rest, %{acc | name: name})
  end

  defp parse_new_session_parts(["-n" <> name | rest], acc) when name != "" do
    # Handle -nNAME (no space)
    parse_new_session_parts(rest, %{acc | name: name})
  end

  defp parse_new_session_parts(["-n", name | rest], acc) do
    # Handle -n NAME (with space)
    parse_new_session_parts(rest, %{acc | name: name})
  end

  defp parse_new_session_parts(["--name", name | rest], acc) do
    # Handle --name NAME (with space)
    parse_new_session_parts(rest, %{acc | name: name})
  end

  defp parse_new_session_parts([part | rest], acc) do
    # First non-flag argument is the path
    if acc.path == nil and not String.starts_with?(part, "-") do
      parse_new_session_parts(rest, %{acc | path: part})
    else
      # Ignore unknown flags
      parse_new_session_parts(rest, acc)
    end
  end

  # ============================================================================
  # Path Resolution
  # ============================================================================

  @doc """
  Resolves a path string to an absolute path.

  Handles:
  - `~` expansion to home directory
  - `.` for current working directory
  - `..` for parent directory
  - Relative paths resolved against CWD
  - Absolute paths passed through unchanged

  Returns `{:ok, absolute_path}` or `{:error, reason}`.

  ## Examples

      iex> Commands.resolve_session_path("~/projects")
      {:ok, "/home/user/projects"}

      iex> Commands.resolve_session_path(".")
      {:ok, "/current/working/dir"}

      iex> Commands.resolve_session_path("/absolute/path")
      {:ok, "/absolute/path"}
  """
  @spec resolve_session_path(String.t() | nil) :: {:ok, String.t()} | {:error, String.t()}
  def resolve_session_path(nil) do
    # Default to current working directory
    {:ok, File.cwd!()}
  end

  def resolve_session_path("") do
    {:ok, File.cwd!()}
  end

  def resolve_session_path("~") do
    {:ok, System.user_home!()}
  end

  def resolve_session_path("~/" <> rest) do
    path = Path.join(System.user_home!(), rest)
    {:ok, Path.expand(path)}
  end

  def resolve_session_path("." <> _ = path) do
    # Handles "." and "./something" and "../something"
    {:ok, Path.expand(path)}
  end

  def resolve_session_path("/" <> _ = path) do
    # Absolute path - just expand to resolve any . or .. within
    {:ok, Path.expand(path)}
  end

  def resolve_session_path(path) do
    # Relative path - resolve against CWD
    {:ok, Path.expand(path)}
  end

  @doc """
  Validates that a resolved path exists and is a directory.

  Returns `{:ok, path}` if valid, `{:error, reason}` otherwise.
  """
  # Forbidden paths that should not be used as session directories
  # These are system directories that could pose security risks
  @forbidden_session_paths [
    "/etc",
    "/root",
    "/boot",
    "/sys",
    "/proc",
    "/dev",
    "/var/log",
    "/var/run",
    "/run",
    "/sbin",
    "/bin",
    "/usr/sbin",
    "/usr/bin"
  ]

  @spec validate_session_path(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def validate_session_path(path) do
    cond do
      not File.exists?(path) ->
        {:error, "Path does not exist: #{path}"}

      not File.dir?(path) ->
        {:error, "Path is not a directory: #{path}"}

      forbidden_path?(path) ->
        {:error, "Cannot create session in system directory: #{path}"}

      true ->
        {:ok, path}
    end
  end

  defp forbidden_path?(path) do
    Enum.any?(@forbidden_session_paths, fn forbidden ->
      path == forbidden or String.starts_with?(path, forbidden <> "/")
    end)
  end

  # ============================================================================
  # Session Command Execution
  # ============================================================================

  @doc """
  Executes a parsed session command.

  Called by the TUI when a `/session` command is parsed. Returns a result
  tuple that the TUI will handle.

  ## Parameters

  - `subcommand` - The parsed session subcommand from `parse_session_args/1`
  - `model` - The TUI model (used for context like active session)

  ## Returns

  - `{:session_action, action}` - Action for TUI to perform
  - `{:ok, message}` - Success message to display
  - `{:error, message}` - Error message to display

  ## Examples

      iex> Commands.execute_session({:new, %{path: "/tmp/project", name: nil}}, model)
      {:session_action, {:add_session, %Session{...}}}

      iex> Commands.execute_session(:list, model)
      {:ok, "1. project-a\\n2. project-b"}
  """
  @spec execute_session(term(), map()) ::
          {:session_action, term()}
          | {:ok, String.t()}
          | {:error, String.t()}

  def execute_session(:help, _model) do
    help = """
    Session Commands:
      /session new [path] [--name=NAME]   - Create new session (defaults to cwd)
      /session list                       - List all sessions with indices
      /session switch <index|id|name>     - Switch to session by index, ID, or name
      /session close [index|id]           - Close session (defaults to current)
      /session rename <name>              - Rename current session
      /session save [index|id|name]       - Save session to disk (defaults to current)

    Keyboard Shortcuts:
      Ctrl+1 to Ctrl+0                    - Switch to session 1-10 (Ctrl+0 = session 10)
      Ctrl+Tab                            - Next session
      Ctrl+Shift+Tab                      - Previous session
      Ctrl+W                              - Close current session
      Ctrl+N                              - New session dialog

    Examples:
      /session new ~/projects/myapp --name="My App"
      /session new                        (uses current directory)
      /session switch 2
      /session switch my-app
      /session rename "Backend API"
      /session close 3

    Notes:
      - Maximum 10 sessions can be open simultaneously
      - Sessions are automatically saved when closed
      - Use /resume to restore closed sessions
      - Session names must be 50 characters or less
    """

    {:ok, String.trim(help)}
  end

  def execute_session({:new, opts}, _model) do
    path = opts[:path] || opts.path
    name = opts[:name] || opts.name

    with {:ok, resolved_path} <- resolve_session_path(path),
         {:ok, validated_path} <- validate_session_path(resolved_path),
         {:ok, session} <- create_new_session(validated_path, name) do
      {:session_action, {:add_session, session}}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, :session_limit_reached} ->
        {:error, "Maximum 10 sessions reached. Close a session first."}

      {:error, {:session_limit_reached, current, max}} ->
        {:error, "Maximum sessions reached (#{current}/#{max} sessions open). Close a session first."}

      {:error, :project_already_open} ->
        {:error, "Project already open in another session."}

      {:error, :path_not_found} ->
        {:error, "Path does not exist: #{path}"}

      {:error, :path_not_directory} ->
        {:error, "Path is not a directory: #{path}"}

      {:error, reason} ->
        {:error, "Failed to create session: #{inspect(reason)}"}
    end
  end

  def execute_session(:list, model) do
    # Get sessions in order from the model
    sessions = get_sessions_in_order(model)

    if sessions == [] do
      {:ok, "No sessions. Use /session new to create one."}
    else
      active_id = Map.get(model, :active_session_id)
      output = format_session_list(sessions, active_id)
      {:ok, output}
    end
  end

  def execute_session({:switch, target}, model) do
    case resolve_session_target(target, model) do
      {:ok, session_id} ->
        {:session_action, {:switch_session, session_id}}

      {:error, reason} ->
        format_resolution_error(reason, target)
    end
  end

  def execute_session({:close, target}, model) do
    # Determine which session to close
    session_order = Map.get(model, :session_order, [])
    active_id = Map.get(model, :active_session_id)

    # If no target, close active session
    effective_target = target || active_id

    cond do
      session_order == [] ->
        {:error, "No sessions to close."}

      effective_target == nil ->
        {:error, "No active session to close. Specify a session to close."}

      true ->
        case resolve_session_target(effective_target, model) do
          {:ok, session_id} ->
            sessions = Map.get(model, :sessions, %{})
            session = Map.get(sessions, session_id)
            session_name = if session, do: Map.get(session, :name, session_id), else: session_id
            {:session_action, {:close_session, session_id, session_name}}

          {:error, reason} ->
            format_resolution_error(reason, target)
        end
    end
  end

  @max_session_name_length 50

  def execute_session({:rename, name}, model) do
    active_id = Map.get(model, :active_session_id)

    if is_nil(active_id) do
      {:error, "No active session to rename. Create a session first with /session new."}
    else
      case validate_session_name(name) do
        :ok ->
          {:session_action, {:rename_session, active_id, name}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def execute_session({:save, target}, model) do
    alias JidoCode.Session.Persistence

    # Determine which session to save
    session_order = Map.get(model, :session_order, [])
    active_id = Map.get(model, :active_session_id)

    # If no target, save active session
    effective_target = target || active_id

    cond do
      session_order == [] ->
        {:error, "No sessions to save."}

      effective_target == nil ->
        {:error, "No active session to save. Specify a session to save."}

      true ->
        # Resolve target to session ID
        case resolve_session_target(effective_target, model) do
          {:ok, session_id} ->
            # Attempt to save the session
            case Persistence.save(session_id) do
              {:ok, path} ->
                sessions = Map.get(model, :sessions, %{})
                session = Map.get(sessions, session_id)

                session_name =
                  if session, do: Map.get(session, :name, session_id), else: session_id

                {:ok, "Session '#{session_name}' saved to:\n#{path}"}

              {:error, :not_found} ->
                {:error, "Session not found. It may have been closed."}

              {:error, :save_in_progress} ->
                {:error, "Session is currently being saved. Please try again."}

              {:error, reason} when is_binary(reason) ->
                {:error, "Failed to save session: #{reason}"}

              {:error, reason} ->
                {:error, "Failed to save session: #{inspect(reason)}"}
            end

          {:error, reason} ->
            format_resolution_error(reason, target)
        end
    end
  end

  def execute_session(_, _model) do
    execute_session(:help, nil)
  end

  # ============================================================================
  # Resume Command Execution
  # ============================================================================

  @doc """
  Executes a resume command.

  ## Parameters

  - `subcommand` - The resume subcommand (`:list`, `{:restore, target}`, `{:delete, target}`, or `:clear`)
  - `model` - The TUI model (used for context like active sessions)

  ## Returns

  - `{:session_action, action}` - Action for TUI to perform (when resuming a session)
  - `{:ok, message}` - Informational message (when listing sessions, deleting, or clearing)
  - `{:error, message}` - Error message
  """
  @spec execute_resume(atom() | tuple(), map()) ::
          {:session_action, tuple()} | {:ok, String.t()} | {:error, String.t()}
  def execute_resume(:list, _model) do
    alias JidoCode.Session.Persistence
    alias JidoCode.Commands.ErrorSanitizer

    case Persistence.list_resumable() do
      {:ok, sessions} ->
        message = format_resumable_list(sessions)
        {:ok, message}

      {:error, :eacces} ->
        {:error, "Permission denied: Unable to access sessions directory."}

      {:error, reason} ->
        # Log detailed error internally, return sanitized message to user
        sanitized = ErrorSanitizer.log_and_sanitize(reason, "list sessions")
        {:error, "Failed to list sessions: #{sanitized}"}
    end
  end

  def execute_resume({:restore, target}, _model) do
    alias JidoCode.Session.Persistence
    alias JidoCode.Commands.ErrorSanitizer

    with {:ok, sessions} <- Persistence.list_resumable(),
         {:ok, session_id} <- resolve_resume_target(target, sessions) do
      # Attempt to resume the session
      case Persistence.resume(session_id) do
        {:ok, session} ->
          {:session_action, {:add_session, session}}

        {:error, :project_path_not_found} ->
          {:error, "Project path no longer exists."}

        {:error, :project_path_not_directory} ->
          {:error, "Project path is not a directory."}

        {:error, :project_already_open} ->
          {:error, "Project already open in another session."}

        {:error, :session_limit_reached} ->
          {:error, "Maximum 10 sessions reached. Close a session first."}

        {:error, {:session_limit_reached, current, max}} ->
          {:error, "Maximum sessions reached (#{current}/#{max} sessions open). Close a session first."}

        {:error, {:rate_limit_exceeded, retry_after}} ->
          {:error, "Rate limit exceeded. Try again in #{retry_after} seconds."}

        {:error, :not_found} ->
          {:error, "Session file not found."}

        {:error, reason} ->
          # Log detailed error internally, return sanitized message to user
          sanitized = ErrorSanitizer.log_and_sanitize(reason, "resume session")
          {:error, "Failed to resume session: #{sanitized}"}
      end
    else
      {:error, :eacces} ->
        {:error, "Permission denied: Unable to access sessions directory."}

      {:error, error_message} when is_binary(error_message) ->
        {:error, error_message}

      {:error, reason} ->
        # Log detailed error internally, return sanitized message to user
        sanitized = ErrorSanitizer.log_and_sanitize(reason, "list sessions")
        {:error, "Failed to list sessions: #{sanitized}"}
    end
  end

  def execute_resume({:delete, target}, _model) do
    alias JidoCode.Session.Persistence
    alias JidoCode.Commands.ErrorSanitizer

    with {:ok, sessions} <- Persistence.list_resumable(),
         {:ok, session_id} <- resolve_resume_target(target, sessions) do
      # Attempt to delete the session
      case Persistence.delete_persisted(session_id) do
        :ok ->
          {:ok, "Deleted saved session."}

        {:error, reason} ->
          # Log detailed error internally, return sanitized message to user
          sanitized = ErrorSanitizer.log_and_sanitize(reason, "delete session")
          {:error, "Failed to delete session: #{sanitized}"}
      end
    else
      {:error, :eacces} ->
        {:error, "Permission denied: Unable to access sessions directory."}

      {:error, error_message} when is_binary(error_message) ->
        {:error, error_message}

      {:error, reason} ->
        # Log detailed error internally, return sanitized message to user
        sanitized = ErrorSanitizer.log_and_sanitize(reason, "list sessions")
        {:error, "Failed to list sessions: #{sanitized}"}
    end
  end

  def execute_resume(:clear, _model) do
    alias JidoCode.Session.Persistence
    alias JidoCode.Commands.ErrorSanitizer

    case Persistence.list_persisted() do
      {:ok, sessions} ->
        count = length(sessions)

        if count > 0 do
          # Delete all sessions
          Enum.each(sessions, fn session ->
            Persistence.delete_persisted(session.id)
          end)

          {:ok, "Cleared #{count} saved session(s)."}
        else
          {:ok, "No saved sessions to clear."}
        end

      {:error, :eacces} ->
        {:error, "Permission denied: Unable to access sessions directory."}

      {:error, reason} ->
        # Log detailed error internally, return sanitized message to user
        sanitized = ErrorSanitizer.log_and_sanitize(reason, "list sessions")
        {:error, "Failed to clear sessions: #{sanitized}"}
    end
  end

  # Private helpers for resume command

  # Formats the list of resumable sessions for display
  defp format_resumable_list([]) do
    "No resumable sessions available."
  end

  defp format_resumable_list(sessions) do
    header = "Resumable sessions:\n\n"

    list =
      sessions
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {session, idx} ->
        time_ago = format_ago(session.closed_at)
        "  #{idx}. #{session.name} (#{session.project_path}) - closed #{time_ago}"
      end)

    footer = "\n\nUse /resume <number> to restore a session."

    header <> list <> footer
  end

  # Formats a timestamp as relative time (e.g., "5 min ago", "2 hours ago")
  defp format_ago(iso_timestamp) when is_binary(iso_timestamp) do
    case DateTime.from_iso8601(iso_timestamp) do
      {:ok, dt, _} ->
        diff = DateTime.diff(DateTime.utc_now(), dt, :second)

        cond do
          diff < 60 ->
            "just now"

          diff < 3600 ->
            minutes = div(diff, 60)
            "#{minutes} min ago"

          diff < 86400 ->
            hours = div(diff, 3600)
            "#{hours} #{if hours == 1, do: "hour", else: "hours"} ago"

          diff < 172_800 ->
            # Less than 2 days
            "yesterday"

          diff < 604_800 ->
            # Less than 7 days
            days = div(diff, 86400)
            "#{days} days ago"

          true ->
            # More than a week, show date
            dt |> DateTime.to_date() |> Date.to_string()
        end

      {:error, _} ->
        # Fallback if parsing fails
        "unknown"
    end
  end

  # Resolves a resume target (numeric index or UUID) to a session ID
  defp resolve_resume_target(target, sessions) do
    # Try parsing as integer (1-based index)
    case Integer.parse(target) do
      {index, ""} when index > 0 and index <= length(sessions) ->
        session = Enum.at(sessions, index - 1)
        {:ok, session.id}

      {index, ""} ->
        {:error, "Invalid index: #{index}. Valid range is 1-#{length(sessions)}."}

      {_number, _remaining} ->
        # Partial parse (e.g., "5abc") - treat as UUID/string
        target_trimmed = String.trim(target)

        if Enum.any?(sessions, fn s -> s.id == target_trimmed end) do
          {:ok, target_trimmed}
        else
          {:error, "Session not found: #{target_trimmed}"}
        end

      :error ->
        # Not an integer at all, try as UUID
        target_trimmed = String.trim(target)

        if Enum.any?(sessions, fn s -> s.id == target_trimmed end) do
          {:ok, target_trimmed}
        else
          {:error, "Session not found: #{target_trimmed}"}
        end
    end
  end

  # Private helpers for session name validation
  defp validate_session_name(name) when is_binary(name) do
    trimmed = String.trim(name)

    cond do
      trimmed == "" ->
        {:error, "Session name cannot be empty."}

      String.length(trimmed) > @max_session_name_length ->
        {:error, "Session name too long (max #{@max_session_name_length} characters)."}

      not valid_session_name_chars?(trimmed) ->
        {:error,
         "Session name contains invalid characters. Use letters, numbers, spaces, hyphens, and underscores only."}

      true ->
        :ok
    end
  end

  defp validate_session_name(_), do: {:error, "Session name must be a string."}

  # Validate session name contains only safe characters:
  # - Letters (a-z, A-Z, including Unicode letters)
  # - Numbers (0-9)
  # - Spaces
  # - Hyphens (-)
  # - Underscores (_)
  # Rejects: control characters, path separators, ANSI escape codes, etc.
  defp valid_session_name_chars?(name) do
    # Match only safe characters
    Regex.match?(~r/^[\p{L}\p{N} _-]+$/u, name)
  end

  # Helper to create a new session via SessionSupervisor
  defp create_new_session(path, name) do
    opts = [project_path: path]
    opts = if name, do: Keyword.put(opts, :name, name), else: opts
    JidoCode.SessionSupervisor.create_session(opts)
  end

  # Get sessions in order from the model
  defp get_sessions_in_order(model) do
    session_order = Map.get(model, :session_order, [])
    sessions = Map.get(model, :sessions, %{})

    session_order
    |> Enum.map(&Map.get(sessions, &1))
    |> Enum.reject(&is_nil/1)
  end

  # Format session list for display
  # Shows index (1-10), active marker (*), name, and truncated path
  defp format_session_list(sessions, active_id) do
    sessions
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {session, idx} ->
      format_session_line(session, idx, active_id)
    end)
  end

  defp format_session_line(session, idx, active_id) do
    marker = if session.id == active_id, do: "*", else: " "
    name = Map.get(session, :name, "unnamed")
    path = Map.get(session, :project_path, "")
    truncated = truncate_path(path)

    "#{marker}#{idx}. #{name} (#{truncated})"
  end

  # Format session resolution errors consistently
  defp format_resolution_error(:not_found, target) do
    {:error, "Session not found: #{target}. Use /session list to see available sessions."}
  end

  defp format_resolution_error(:no_sessions, _target) do
    {:error, "No sessions available. Use /session new to create one."}
  end

  defp format_resolution_error({:ambiguous, names}, target) do
    options = Enum.join(names, ", ")
    {:error, "Ambiguous session name '#{target}'. Did you mean: #{options}?"}
  end

  # Truncate long paths to fit display
  # Replaces home directory with ~ and truncates middle if needed
  @max_path_length 40

  defp truncate_path(nil), do: ""
  defp truncate_path(""), do: ""

  defp truncate_path(path) do
    path
    |> replace_home_with_tilde()
    |> truncate_if_long(@max_path_length)
  end

  # Replace home directory with ~ for shorter display
  defp replace_home_with_tilde(path) do
    home = System.user_home!()

    if String.starts_with?(path, home) do
      "~" <> String.replace_prefix(path, home, "")
    else
      path
    end
  end

  # Truncate path if longer than max_length, keeping the end (most relevant)
  defp truncate_if_long(path, max_length) when is_binary(path) do
    if String.length(path) > max_length do
      suffix_length = min(max_length - 3, String.length(path) - 1)
      "..." <> String.slice(path, -suffix_length..-1//1)
    else
      path
    end
  end

  # Resolve a session target (index, ID, or name) to a session ID
  defp resolve_session_target(target, model) do
    session_order = Map.get(model, :session_order, [])
    sessions = Map.get(model, :sessions, %{})

    if session_order == [] do
      {:error, :no_sessions}
    else
      cond do
        # Try as index (1-10, with "0" meaning 10)
        numeric_target?(target) ->
          resolve_by_index(target, session_order)

        # Try as session ID
        Map.has_key?(sessions, target) ->
          {:ok, target}

        # Try as session name
        true ->
          find_session_by_name(target, sessions)
      end
    end
  end

  defp numeric_target?(target) do
    match?({_, ""}, Integer.parse(target))
  end

  defp resolve_by_index(target, session_order) do
    {index, ""} = Integer.parse(target)

    # Handle "0" as index 10 (for Ctrl+0 keyboard shortcut)
    index = if index == 0, do: @ctrl_0_maps_to_index, else: index

    case Enum.at(session_order, index - 1) do
      nil -> {:error, :not_found}
      session_id -> {:ok, session_id}
    end
  end

  defp find_session_by_name("", _sessions) do
    # Empty string should not match anything
    {:error, :not_found}
  end

  defp find_session_by_name(name, sessions) do
    name_lower = String.downcase(name)

    # First try exact match (case-insensitive)
    exact_match =
      Enum.find(sessions, fn {_id, session} ->
        session_name = Map.get(session, :name, "")
        String.downcase(session_name) == name_lower
      end)

    case exact_match do
      {id, _session} ->
        {:ok, id}

      nil ->
        # Fall back to prefix match (case-insensitive)
        find_session_by_prefix(name_lower, sessions)
    end
  end

  defp find_session_by_prefix(prefix, sessions) do
    matches =
      Enum.filter(sessions, fn {_id, session} ->
        session_name = Map.get(session, :name, "")
        String.starts_with?(String.downcase(session_name), prefix)
      end)

    case matches do
      [] ->
        {:error, :not_found}

      [{id, _session}] ->
        {:ok, id}

      multiple ->
        # Multiple matches - return error with options
        names = Enum.map(multiple, fn {_id, s} -> Map.get(s, :name) end)
        {:error, {:ambiguous, names}}
    end
  end

  # ============================================================================
  # Command Execution
  # ============================================================================

  defp execute_provider_command(provider) do
    with :ok <- validate_provider(provider),
         :ok <- validate_api_key(provider) do
      # Save to settings
      Settings.set(:local, "provider", provider)
      Settings.set(:local, "model", nil)

      new_config = %{provider: provider, model: nil}
      {:ok, "Provider set to #{provider}. Use /models to see available models.", new_config}
    end
  end

  defp execute_model_command(model_spec, config) do
    # Format: provider:model
    if String.contains?(model_spec, ":") do
      [provider | rest] = String.split(model_spec, ":", parts: 2)
      model = Enum.join(rest, ":")
      set_provider_and_model(provider, model)
    else
      # Format: model only (requires provider to be set)
      provider = config[:provider] || config["provider"]

      if provider do
        set_model_for_provider(provider, model_spec)
      else
        {:error,
         "No provider set. Use /model <provider>:<model> or set provider first with /provider <name>"}
      end
    end
  end

  defp set_provider_and_model(provider, model) do
    with :ok <- validate_provider(provider),
         :ok <- validate_model(provider, model),
         :ok <- validate_api_key(provider) do
      # Save to settings
      Settings.set(:local, "provider", provider)
      Settings.set(:local, "model", model)

      new_config = %{provider: provider, model: model}

      # Configure running agent if available
      configure_agent(new_config)

      # Broadcast config change
      broadcast_config_change(new_config)

      {:ok, "Model set to #{provider}:#{model}", new_config}
    end
  end

  defp set_model_for_provider(provider, model) do
    with :ok <- validate_model(provider, model),
         :ok <- validate_api_key(provider) do
      Settings.set(:local, "model", model)

      new_config = %{provider: provider, model: model}

      # Configure running agent if available
      configure_agent(new_config)

      # Broadcast config change
      broadcast_config_change(new_config)

      {:ok, "Model set to #{model}", new_config}
    end
  end

  defp execute_models_command(provider) do
    case validate_provider(provider) do
      :ok ->
        models = Settings.get_models(provider)

        if models == [] do
          {:ok, "No models found for provider: #{provider}", %{}}
        else
          # Return pick_list tuple to show interactive model picker
          {:pick_list, provider, models, "Select Model (#{provider})"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_providers_command do
    providers = Settings.get_providers()

    if providers == [] do
      {:ok, "No providers available", %{}}
    else
      # Return pick_list tuple to show interactive provider picker
      # Use :provider as the type to distinguish from model selection
      {:pick_list, :provider, providers, "Select Provider"}
    end
  end

  defp execute_theme_list_command do
    themes = TermUI.Theme.list_builtin()
    current = TermUI.Theme.get_theme()
    current_name = current.name

    theme_list =
      Enum.map_join(themes, "\n  ", fn name ->
        if name == current_name, do: "#{name} (current)", else: "#{name}"
      end)

    {:ok, "Available themes:\n  #{theme_list}", %{}}
  end

  defp execute_theme_command(theme_name) do
    # Convert string to atom safely (only for known themes)
    theme_atom = string_to_theme_atom(theme_name)

    if theme_atom do
      case TermUI.Theme.set_theme(theme_atom) do
        :ok ->
          # Save to settings for persistence
          Settings.set(:local, "theme", theme_name)
          {:ok, "Theme set to #{theme_name}", %{}}

        {:error, :not_found} ->
          available = TermUI.Theme.list_builtin() |> Enum.join(", ")
          {:error, "Unknown theme: #{theme_name}\n\nAvailable themes: #{available}"}

        {:error, reason} ->
          {:error, "Failed to set theme: #{inspect(reason)}"}
      end
    else
      available = TermUI.Theme.list_builtin() |> Enum.join(", ")
      {:error, "Unknown theme: #{theme_name}\n\nAvailable themes: #{available}"}
    end
  end

  # Safe string to theme atom conversion (only allow known themes)
  defp string_to_theme_atom("dark"), do: :dark
  defp string_to_theme_atom("light"), do: :light
  defp string_to_theme_atom("high_contrast"), do: :high_contrast
  defp string_to_theme_atom(_), do: nil

  # ============================================================================
  # Validation
  # ============================================================================

  defp validate_provider(provider) do
    case RegistryAdapter.list_providers() do
      {:ok, providers} ->
        # Use String.to_existing_atom/1 to avoid atom exhaustion from user input
        # Fall back to checking if the string matches a known provider atom
        provider_in_list? =
          Enum.any?(providers, fn p -> Atom.to_string(p) == provider end)

        if provider_in_list? do
          :ok
        else
          # Build helpful error message
          similar = find_similar_providers(provider, providers)

          suggestion =
            if similar != [] do
              "\n\nDid you mean: #{Enum.join(similar, ", ")}?"
            else
              "\n\nUse /providers to see available providers."
            end

          {:error, "Unknown provider: #{provider}#{suggestion}"}
        end

      {:error, _} ->
        # If registry is unavailable, allow any provider
        :ok
    end
  end

  defp validate_model(_provider, _model) do
    # Skip model validation for now - the registry may not have complete model lists
    # and users should be able to use any model their API key supports.
    # The actual validation will happen when the LLM call is made.
    :ok
  end

  # Use shared provider keys module
  alias JidoCode.Config.ProviderKeys

  defp validate_api_key(provider) do
    if ProviderKeys.local_provider?(provider) do
      # Local providers don't require API keys
      :ok
    else
      key_name = ProviderKeys.to_key_name(provider)

      case Keyring.get(key_name) do
        nil ->
          # Use generic message - don't expose env var names
          {:error, "Provider #{provider} is not configured. Please set up API credentials."}

        "" ->
          # Use generic message - don't expose env var names
          {:error,
           "Provider #{provider} has empty credentials. Please configure API credentials."}

        _key ->
          :ok
      end
    end
  end

  # Simple substring matching for suggestions
  defp find_similar_providers(input, providers) do
    input_lower = String.downcase(input)

    providers
    |> Enum.map(&Atom.to_string/1)
    |> Enum.filter(fn p ->
      p_lower = String.downcase(p)
      String.contains?(p_lower, input_lower) or String.contains?(input_lower, p_lower)
    end)
    |> Enum.take(3)
  end

  # ============================================================================
  # Agent Configuration
  # ============================================================================

  defp configure_agent(config) do
    case AgentSupervisor.lookup_agent(:llm_agent) do
      {:ok, pid} ->
        # Configure the running agent with new settings
        LLMAgent.configure(pid,
          provider: config.provider,
          model: config.model
        )

      {:error, :not_found} ->
        # Agent not running - that's OK, it will use settings when started
        :ok
    end
  end

  defp broadcast_config_change(config) do
    Phoenix.PubSub.broadcast(@pubsub, PubSubTopics.tui_events(), {:config_changed, config})
  end

  # ============================================================================
  # Shell Command Execution
  # ============================================================================

  defp execute_shell_command(command_line) do
    case parse_shell_command(command_line) do
      {command, args} ->
        case Manager.shell(command, args) do
          {:ok, %{"exit_code" => 0, "stdout" => stdout, "stderr" => stderr}} ->
            output = format_shell_output(stdout, stderr)
            {:shell_output, command_line, output}

          {:ok, %{"exit_code" => code, "stdout" => stdout, "stderr" => stderr}} ->
            output = format_shell_output(stdout, stderr)
            {:shell_output, command_line, "#{output}\n\n[Exit code: #{code}]"}

          {:error, reason} when is_binary(reason) ->
            {:error, reason}

          {:error, reason} ->
            {:error, "Shell error: #{inspect(reason)}"}
        end

      :error ->
        {:error, "Invalid command format"}
    end
  end

  defp parse_shell_command(command_line) do
    case String.split(command_line, ~r/\s+/, parts: :infinity) do
      [command | args] when command != "" -> {command, args}
      _ -> :error
    end
  end

  defp format_shell_output(stdout, stderr) do
    stdout = String.trim(stdout)
    stderr = String.trim(stderr)

    cond do
      stdout != "" and stderr != "" -> "#{stdout}\n\n[stderr]\n#{stderr}"
      stdout != "" -> stdout
      stderr != "" -> "[stderr]\n#{stderr}"
      true -> "(no output)"
    end
  end

  # ============================================================================
  # Sandbox Testing
  # ============================================================================

  defp execute_sandbox_test do
    results = [
      test_sandbox_read_file(),
      test_sandbox_list_dir(),
      test_sandbox_shell(),
      test_sandbox_lua_script(),
      test_sandbox_security_block()
    ]

    passed = Enum.count(results, fn {status, _, _} -> status == :pass end)
    failed = Enum.count(results, fn {status, _, _} -> status == :fail end)

    output =
      Enum.map_join(results, "\n\n", fn {status, name, detail} ->
        icon = if status == :pass, do: "[OK]", else: "[FAIL]"
        "#{icon} #{name}\n    #{detail}"
      end)

    summary = "\n\nSandbox Test Results: #{passed} passed, #{failed} failed"
    {:ok, output <> summary, %{}}
  end

  defp test_sandbox_read_file do
    case Manager.read_file("mix.exs") do
      {:ok, content} when byte_size(content) > 0 ->
        {:pass, "Read file via sandbox",
         "Successfully read mix.exs (#{byte_size(content)} bytes)"}

      {:ok, _} ->
        {:fail, "Read file via sandbox", "File was empty"}

      {:error, reason} ->
        {:fail, "Read file via sandbox", "Error: #{inspect(reason)}"}
    end
  end

  defp test_sandbox_list_dir do
    case Manager.list_dir("lib") do
      {:ok, entries} when is_list(entries) and length(entries) > 0 ->
        {:pass, "List directory via sandbox", "Found #{length(entries)} entries in lib/"}

      {:ok, []} ->
        {:fail, "List directory via sandbox", "Directory was empty"}

      {:error, reason} ->
        {:fail, "List directory via sandbox", "Error: #{inspect(reason)}"}
    end
  end

  defp test_sandbox_shell do
    case Manager.shell("echo", ["sandbox test"]) do
      {:ok, %{"exit_code" => 0, "stdout" => stdout}} ->
        {:pass, "Shell command via sandbox", "echo returned: #{String.trim(stdout)}"}

      {:ok, %{"exit_code" => code}} ->
        {:fail, "Shell command via sandbox", "Exit code: #{code}"}

      {:ok, result} ->
        {:fail, "Shell command via sandbox", "Unexpected result: #{inspect(result)}"}

      {:error, reason} ->
        {:fail, "Shell command via sandbox", "Error: #{inspect(reason)}"}
    end
  end

  defp test_sandbox_lua_script do
    lua_script = """
    local content = jido.read_file("mix.exs")
    if content then
      return string.sub(content, 1, 20)
    else
      return nil
    end
    """

    case Manager.execute(lua_script) do
      {:ok, result} when is_binary(result) and byte_size(result) > 0 ->
        {:pass, "Execute Lua script", "Lua read file prefix: #{inspect(result)}"}

      {:ok, result} ->
        {:fail, "Execute Lua script", "Unexpected result: #{inspect(result)}"}

      {:error, reason} ->
        {:fail, "Execute Lua script", "Error: #{inspect(reason)}"}
    end
  end

  defp test_sandbox_security_block do
    case Manager.read_file("../../../etc/passwd") do
      {:error, reason} when is_binary(reason) ->
        if String.contains?(reason, "Security") or String.contains?(reason, "escapes") do
          {:pass, "Security boundary enforced", "Blocked path traversal: #{reason}"}
        else
          {:pass, "Security boundary enforced", "Blocked with: #{reason}"}
        end

      {:error, reason} ->
        {:pass, "Security boundary enforced", "Blocked with: #{inspect(reason)}"}

      {:ok, _} ->
        {:fail, "Security boundary enforced", "DANGER: Path traversal was NOT blocked!"}
    end
  end
end
