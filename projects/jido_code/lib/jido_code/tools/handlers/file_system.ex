defmodule JidoCode.Tools.Handlers.FileSystem do
  @moduledoc """
  Handler modules for file system tools.

  This module contains sub-modules that implement the execute/2 callback
  for file system operations with session-aware path validation.

  ## Handler Modules

  - `EditFile` - Edit file with string replacement
  - `ReadFile` - Read file contents
  - `WriteFile` - Write/overwrite file
  - `ListDirectory` - List directory contents
  - `FileInfo` - Get file metadata
  - `CreateDirectory` - Create directory
  - `DeleteFile` - Delete file (with confirmation)

  ## Session Context

  Handlers use `HandlerHelpers.validate_path/2` for session-aware path validation:

  1. `session_id` present → Uses `Session.Manager.validate_path/2`
  2. `project_root` present → Uses `Security.validate_path/3`
  3. Neither → Falls back to global `Tools.Manager` (deprecated)

  ## Usage

  These handlers are invoked by the Executor when the LLM calls file tools:

      # Via Executor with session context
      {:ok, context} = Executor.build_context(session_id)
      Executor.execute(%{
        id: "call_123",
        name: "read_file",
        arguments: %{"path" => "src/main.ex"}
      }, context: context)
  """

  require Logger

  alias JidoCode.Tools.HandlerHelpers
  alias JidoCode.Tools.Security

  # ============================================================================
  # Shared Helpers
  # ============================================================================

  @doc false
  defdelegate get_project_root(context), to: HandlerHelpers

  @doc false
  defdelegate validate_path(path, context), to: HandlerHelpers

  @doc """
  Normalizes a path for consistent tracking across read and write operations.

  This ensures both ReadFile and WriteFile use the same path format when
  tracking file operations for read-before-write validation. The normalized
  path is always an absolute, expanded path.

  ## Parameters

  - `path` - The relative or absolute path
  - `project_root` - The project root directory

  ## Returns

  The normalized absolute path.
  """
  @spec normalize_path_for_tracking(String.t(), String.t()) :: String.t()
  def normalize_path_for_tracking(path, project_root) do
    # For consistent tracking, always:
    # 1. Join with project_root if relative
    # 2. Expand to resolve .. and .
    # 3. This matches what Security.validate_path returns
    if Path.type(path) == :absolute do
      Path.expand(path)
    else
      Path.join(project_root, path) |> Path.expand()
    end
  end

  @doc """
  Emits telemetry for file operations.

  Used by both ReadFile and WriteFile handlers to emit consistent telemetry.

  ## Parameters

  - `operation` - The operation name (`:read` or `:write`)
  - `start_time` - The start time from `System.monotonic_time()`
  - `path` - The file path (will be sanitized to basename only)
  - `context` - The execution context containing session_id
  - `status` - The operation status (`:ok`, `:error`, `:read_before_write_required`)
  - `bytes` - The number of bytes read/written
  """
  @spec emit_file_telemetry(atom(), integer(), String.t(), map(), atom(), non_neg_integer()) ::
          :ok
  def emit_file_telemetry(operation, start_time, path, context, status, bytes) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:jido_code, :file_system, operation],
      %{duration: duration, bytes: bytes},
      %{
        path: sanitize_path_for_telemetry(path),
        status: status,
        session_id: Map.get(context, :session_id)
      }
    )
  end

  @doc """
  Sanitizes a path for safe inclusion in telemetry.

  Only includes the filename (basename) to prevent leaking sensitive
  directory structure information.
  """
  @spec sanitize_path_for_telemetry(String.t()) :: String.t()
  def sanitize_path_for_telemetry(path) do
    Path.basename(path)
  end

  @doc false
  def format_error(:enoent, path), do: "File not found: #{path}"
  def format_error(:eacces, path), do: "Permission denied: #{path}"
  def format_error(:eisdir, path), do: "Is a directory: #{path}"
  def format_error(:enotdir, path), do: "Not a directory: #{path}"
  def format_error(:enospc, _path), do: "No space left on device"

  def format_error(:content_too_large, _path),
    do: "Content exceeds maximum file size (10MB)"

  def format_error(:path_escapes_boundary, path),
    do: "Security error: path escapes project boundary: #{path}"

  def format_error(:path_outside_boundary, path),
    do: "Security error: path is outside project: #{path}"

  def format_error(:symlink_escapes_boundary, path),
    do: "Security error: symlink points outside project: #{path}"

  def format_error(reason, path) when is_atom(reason), do: "File error (#{reason}): #{path}"
  def format_error(reason, _path) when is_binary(reason), do: reason
  def format_error(reason, path), do: "Error (#{inspect(reason)}): #{path}"

  @doc """
  Tracks a file write in session state.

  Used by both EditFile and WriteFile handlers to record file modifications
  for read-before-write validation. In legacy mode (no session_id), this is a no-op.

  ## Parameters

  - `normalized_path` - The normalized absolute path of the file
  - `context` - The execution context containing session_id
  - `operation` - Atom identifying the calling handler (for logging)

  ## Returns

  Always returns `:ok` (logs warning if session not found).
  """
  @spec track_file_write(String.t(), map(), atom()) :: :ok
  def track_file_write(normalized_path, context, operation \\ :file_system) do
    alias JidoCode.Session.State, as: SessionState

    case Map.get(context, :session_id) do
      nil ->
        # No session context - skip tracking (legacy mode)
        :ok

      session_id ->
        case SessionState.track_file_write(session_id, normalized_path) do
          {:ok, _timestamp} ->
            :ok

          {:error, :not_found} ->
            Logger.warning(
              "#{operation}: Session #{session_id} not found when tracking file write for #{Path.basename(normalized_path)}"
            )

            :ok
        end
    end
  end

  # ============================================================================
  # EditFile Handler
  # ============================================================================

  defmodule EditFile do
    @moduledoc """
    Handler for the edit_file tool.

    Performs string replacement within files using multi-strategy matching.
    Unlike write_file which overwrites entire files, edit_file allows targeted
    modifications to specific sections.

    Uses session-aware path validation via `HandlerHelpers.validate_path/2`.

    ## Read-Before-Write Requirement

    The file must be read in the current session before it can be edited.
    This ensures the agent has seen the current content and understands
    the context of the modification.

    ## Multi-Strategy Matching

    When the exact `old_string` is not found, the handler tries fallback
    strategies to handle common LLM formatting variations:

    1. **Exact match** (primary) - Literal string comparison
    2. **Line-trimmed match** - Ignores leading/trailing whitespace per line
    3. **Whitespace-normalized match** - Collapses multiple spaces/tabs to single space
    4. **Indentation-flexible match** - Allows different indentation levels

    ## Configuration

    Tab width for indentation matching can be configured:

        config :jido_code, :tools,
          edit_file: [tab_width: 4]  # default is 4 spaces per tab

    This follows patterns from OpenCode and other coding assistants.

    ## Path Normalization

    File paths are normalized using `FileSystem.normalize_path_for_tracking/2`
    to ensure consistent tracking between read and edit operations.

    ## Security

    Uses `Security.atomic_write/4` for TOCTOU-safe file writing after edits.

    ## Legacy Mode (project_root context)

    When no `session_id` is provided (only `project_root`), the handler operates
    in "legacy mode":

    - Read-before-write check is bypassed with a debug log
    - File tracking is skipped
    - This mode exists for backward compatibility and direct testing

    **Note**: Legacy mode provides weaker safety guarantees. Prefer using
    `session_id` context in production to enforce read-before-write validation.
    """

    alias JidoCode.Session.State, as: SessionState
    alias JidoCode.Tools.HandlerHelpers
    alias JidoCode.Tools.Handlers.FileSystem
    alias JidoCode.Tools.Security

    require Logger

    # Tab width for indentation-flexible matching (configurable via application config)
    # Default of 4 matches common editor defaults
    @tab_width Application.compile_env(:jido_code, [:tools, :edit_file, :tab_width], 4)

    @doc """
    Edits a file by replacing old_string with new_string.

    ## Arguments

    - `"path"` - Path to the file (relative to project root)
    - `"old_string"` - Text to find and replace (multi-strategy matching)
    - `"new_string"` - Replacement string
    - `"replace_all"` - If true, replace all occurrences; if false (default),
      require exactly one match

    ## Context

    - `:session_id` - Session ID for path validation and read-before-write check
    - `:project_root` - Direct project root path (legacy, skips read-before-write)

    ## Returns

    - `{:ok, message}` - Success message with replacement count and match strategy used
    - `{:error, reason}` - Error message

    ## Errors

    - Returns error if old_string is not found (after trying all strategies)
    - Returns error if old_string appears multiple times and replace_all is false
    - Returns error if file was not read first (read-before-write violation)
    """
    def execute(
          %{"path" => path, "old_string" => old_string, "new_string" => new_string} = args,
          context
        )
        when is_binary(path) and is_binary(old_string) and is_binary(new_string) do
      start_time = System.monotonic_time()
      replace_all = Map.get(args, "replace_all", false)

      # Validate old_string is not empty (would match at every position)
      if old_string == "" do
        FileSystem.emit_file_telemetry(:edit, start_time, path, context, :error, 0)
        {:error, "old_string cannot be empty"}
      else
        execute_edit(path, old_string, new_string, replace_all, context, start_time)
      end
    end

    def execute(_args, _context) do
      {:error, "edit_file requires path, old_string, and new_string arguments"}
    end

    # Internal function to perform the actual edit after validation
    defp execute_edit(path, old_string, new_string, replace_all, context, start_time) do
      result =
        with {:ok, project_root} <- HandlerHelpers.get_project_root(context),
             {:ok, safe_path} <- Security.validate_path(path, project_root, log_violations: true),
             normalized_path <- FileSystem.normalize_path_for_tracking(path, project_root),
             :ok <- check_read_before_edit(normalized_path, context),
             {:ok, content} <- File.read(safe_path),
             {:ok, new_content, count, strategy} <-
               do_replace_with_strategies(content, old_string, new_string, replace_all),
             :ok <- Security.atomic_write(path, new_content, project_root, log_violations: true),
             :ok <- FileSystem.track_file_write(normalized_path, context, :edit_file) do
          strategy_note = if strategy != :exact, do: " (matched via #{strategy})", else: ""
          {:ok, "Successfully replaced #{count} occurrence(s) in #{path}#{strategy_note}"}
        end

      # Emit telemetry and return result
      case result do
        {:ok, _} = success ->
          FileSystem.emit_file_telemetry(:edit, start_time, path, context, :ok, 0)
          success

        {:error, :read_before_write_required} ->
          FileSystem.emit_file_telemetry(:edit, start_time, path, context, :read_before_write_required, 0)
          {:error, "File must be read before editing: #{path}"}

        {:error, :session_state_unavailable} ->
          FileSystem.emit_file_telemetry(:edit, start_time, path, context, :error, 0)
          {:error, "Session state unavailable - cannot verify read-before-write requirement"}

        {:error, :not_found} ->
          FileSystem.emit_file_telemetry(:edit, start_time, path, context, :not_found, 0)
          {:error, "String not found in file (tried exact, line-trimmed, whitespace-normalized, and indentation-flexible matching): #{path}"}

        {:error, :ambiguous_match, count} ->
          FileSystem.emit_file_telemetry(:edit, start_time, path, context, :ambiguous_match, 0)
          {:error, "Found #{count} occurrences of the string in #{path}. Use replace_all: true to replace all, or provide a more specific string."}

        {:error, reason} ->
          FileSystem.emit_file_telemetry(:edit, start_time, path, context, :error, 0)
          {:error, FileSystem.format_error(reason, path)}
      end
    end

    # ============================================================================
    # Read-Before-Write Check
    # ============================================================================

    # Check read-before-write requirement
    # Files must be read in the current session before they can be edited
    @spec check_read_before_edit(String.t(), map()) ::
            :ok | {:error, :read_before_write_required | :session_state_unavailable}
    defp check_read_before_edit(normalized_path, context) do
      case Map.get(context, :session_id) do
        nil ->
          # No session context (legacy mode) - skip check but log
          Logger.debug("EditFile: Skipping read-before-edit check - no session context (legacy mode)")
          :ok

        session_id ->
          case SessionState.file_was_read?(session_id, normalized_path) do
            {:ok, true} ->
              :ok

            {:ok, false} ->
              {:error, :read_before_write_required}

            {:error, :not_found} ->
              # Fail-closed: Session not found is a security concern
              Logger.warning(
                "EditFile: Session #{session_id} not found during read-before-edit check - failing closed"
              )
              {:error, :session_state_unavailable}
          end
      end
    end

    # ============================================================================
    # Multi-Strategy Matching
    # ============================================================================

    # Try multiple matching strategies in order of preference
    @spec do_replace_with_strategies(String.t(), String.t(), String.t(), boolean()) ::
            {:ok, String.t(), pos_integer(), atom()} | {:error, :not_found} | {:error, :ambiguous_match, pos_integer()}
    defp do_replace_with_strategies(content, old_string, new_string, replace_all) do
      strategies = [
        {:exact, &exact_match/2},
        {:line_trimmed, &line_trimmed_match/2},
        {:whitespace_normalized, &whitespace_normalized_match/2},
        {:indentation_flexible, &indentation_flexible_match/2}
      ]

      Enum.reduce_while(strategies, {:error, :not_found}, fn {strategy_name, match_fn}, _acc ->
        case try_replace(content, old_string, new_string, replace_all, match_fn) do
          {:ok, new_content, count} ->
            # Log when using fallback strategy for observability
            if strategy_name != :exact do
              Logger.debug(
                "EditFile: Used #{strategy_name} matching strategy (exact match failed)"
              )
            end

            {:halt, {:ok, new_content, count, strategy_name}}

          {:error, :ambiguous_match, count} ->
            # Stop on ambiguous match - user needs to fix this
            {:halt, {:error, :ambiguous_match, count}}

          {:error, :not_found} ->
            # Try next strategy
            {:cont, {:error, :not_found}}
        end
      end)
    end

    # Try to replace using a specific match function
    @spec try_replace(String.t(), String.t(), String.t(), boolean(), (String.t(), String.t() -> [non_neg_integer()])) ::
            {:ok, String.t(), pos_integer()} | {:error, :not_found} | {:error, :ambiguous_match, pos_integer()}
    defp try_replace(content, old_string, new_string, replace_all, match_fn) do
      # Find all match positions using the strategy
      positions = match_fn.(content, old_string)
      count = length(positions)

      cond do
        count == 0 ->
          {:error, :not_found}

        count > 1 and not replace_all ->
          {:error, :ambiguous_match, count}

        true ->
          # Apply replacements from end to start to maintain position validity
          new_content = apply_replacements(content, old_string, new_string, positions, replace_all)
          replaced_count = if replace_all, do: count, else: 1
          {:ok, new_content, replaced_count}
      end
    end

    # Apply replacements at the given positions (from end to start)
    # Positions can be either integers (for exact match) or {pos, len} tuples (for fuzzy match)
    @spec apply_replacements(String.t(), String.t(), String.t(), [non_neg_integer() | {non_neg_integer(), non_neg_integer()}], boolean()) :: String.t()
    defp apply_replacements(content, old_string, new_string, positions, replace_all) do
      default_len = String.length(old_string)
      positions_to_use = if replace_all, do: positions, else: [hd(positions)]

      # Normalize positions to {pos, len} tuples
      normalized_positions = Enum.map(positions_to_use, fn
        {pos, len} -> {pos, len}
        pos when is_integer(pos) -> {pos, default_len}
      end)

      # Sort positions in reverse order to apply from end to start
      # Using a large constant for suffix slice avoids expensive String.length calls in the reduce
      # String.slice handles lengths beyond the string end gracefully
      normalized_positions
      |> Enum.sort_by(fn {pos, _len} -> pos end, :desc)
      |> Enum.reduce(content, fn {pos, len}, acc ->
        prefix = String.slice(acc, 0, pos)
        # Use :infinity-like large value - String.slice returns rest of string if length exceeds available
        suffix = String.slice(acc, pos + len, 0x7FFFFFFF)
        prefix <> new_string <> suffix
      end)
    end

    # ============================================================================
    # Match Strategy Implementations
    # ============================================================================

    # Strategy 1: Exact match - find literal occurrences
    @spec exact_match(String.t(), String.t()) :: [non_neg_integer()]
    defp exact_match(content, pattern) do
      find_all_positions(content, pattern)
    end

    # Strategy 2: Line-trimmed match - trim leading/trailing whitespace from each line
    @spec line_trimmed_match(String.t(), String.t()) :: [non_neg_integer()]
    defp line_trimmed_match(content, pattern) do
      trimmed_pattern = trim_lines(pattern)
      if trimmed_pattern == pattern do
        # No change from trimming, skip this strategy
        []
      else
        # Find positions in the original content where trimmed pattern matches
        find_fuzzy_positions(content, pattern, &trim_lines/1)
      end
    end

    # Strategy 3: Whitespace-normalized match - collapse multiple spaces/tabs
    @spec whitespace_normalized_match(String.t(), String.t()) :: [non_neg_integer()]
    defp whitespace_normalized_match(content, pattern) do
      normalized_pattern = normalize_whitespace(pattern)
      if normalized_pattern == pattern do
        []
      else
        find_fuzzy_positions(content, pattern, &normalize_whitespace/1)
      end
    end

    # Strategy 4: Indentation-flexible match - allow different indentation levels
    @spec indentation_flexible_match(String.t(), String.t()) :: [non_neg_integer()]
    defp indentation_flexible_match(content, pattern) do
      # Remove leading indentation from each line of the pattern
      dedented_pattern = dedent(pattern)
      if dedented_pattern == pattern do
        []
      else
        find_fuzzy_positions(content, pattern, &dedent/1)
      end
    end

    # ============================================================================
    # Helper Functions
    # ============================================================================

    # Find all positions of exact pattern in content (grapheme-safe)
    # Uses String functions instead of :binary.match for correct UTF-8 handling
    @spec find_all_positions(String.t(), String.t()) :: [non_neg_integer()]
    defp find_all_positions(content, pattern) do
      pattern_len = String.length(pattern)
      do_find_positions(content, pattern, pattern_len, 0, [])
    end

    defp do_find_positions(content, pattern, pattern_len, offset, acc) do
      case find_grapheme_position(content, pattern) do
        {:found, pos} ->
          absolute_pos = offset + pos
          rest = String.slice(content, pos + pattern_len, String.length(content))
          do_find_positions(rest, pattern, pattern_len, absolute_pos + pattern_len, [absolute_pos | acc])

        :not_found ->
          Enum.reverse(acc)
      end
    end

    # Find the grapheme position of pattern in content
    # Returns {:found, position} or :not_found
    @spec find_grapheme_position(String.t(), String.t()) :: {:found, non_neg_integer()} | :not_found
    defp find_grapheme_position(content, pattern) do
      case String.split(content, pattern, parts: 2) do
        [before, _rest] -> {:found, String.length(before)}
        [_no_match] -> :not_found
      end
    end

    # Find positions where normalized content matches normalized pattern
    # Returns {position, length} tuples in the ORIGINAL content
    # The length is the actual length of matched content (not pattern length)
    @spec find_fuzzy_positions(String.t(), String.t(), (String.t() -> String.t())) :: [{non_neg_integer(), non_neg_integer()}]
    defp find_fuzzy_positions(content, pattern, normalize_fn) do
      # Split content into lines and try to find matching sequences
      content_lines = String.split(content, "\n")
      pattern_lines = String.split(pattern, "\n")
      pattern_line_count = length(pattern_lines)

      normalized_pattern_lines = Enum.map(pattern_lines, normalize_fn)

      # Slide through content lines looking for matches
      find_matching_line_sequences(content_lines, normalized_pattern_lines, pattern_line_count, normalize_fn, 0, 0, [])
    end

    defp find_matching_line_sequences(content_lines, normalized_pattern_lines, pattern_line_count, normalize_fn, line_idx, char_offset, acc) do
      if line_idx + pattern_line_count > length(content_lines) do
        Enum.reverse(acc)
      else
        # Get the candidate lines from content
        candidate_lines = Enum.slice(content_lines, line_idx, pattern_line_count)
        normalized_candidates = Enum.map(candidate_lines, normalize_fn)

        # Check if normalized versions match
        new_acc =
          if normalized_candidates == normalized_pattern_lines do
            # Calculate actual length of matched content in original file
            matched_content = Enum.join(candidate_lines, "\n")
            matched_len = String.length(matched_content)
            [{char_offset, matched_len} | acc]
          else
            acc
          end

        # Calculate next character offset (add length of current line + newline)
        current_line = Enum.at(content_lines, line_idx, "")
        next_char_offset = char_offset + String.length(current_line) + 1

        find_matching_line_sequences(
          content_lines,
          normalized_pattern_lines,
          pattern_line_count,
          normalize_fn,
          line_idx + 1,
          next_char_offset,
          new_acc
        )
      end
    end

    # Trim leading/trailing whitespace from each line
    @spec trim_lines(String.t()) :: String.t()
    defp trim_lines(text) do
      text
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.join("\n")
    end

    # Collapse multiple whitespace characters to single space
    @spec normalize_whitespace(String.t()) :: String.t()
    defp normalize_whitespace(text) do
      text
      |> String.replace(~r/[ \t]+/, " ")
      |> String.replace(~r/ ?\n ?/, "\n")
    end

    # Remove common leading indentation from all lines
    @spec dedent(String.t()) :: String.t()
    defp dedent(text) do
      lines = String.split(text, "\n")

      # Find minimum indentation (ignoring empty lines)
      min_indent =
        lines
        |> Enum.filter(&(String.trim(&1) != ""))
        |> Enum.map(&count_leading_spaces/1)
        |> Enum.min(fn -> 0 end)

      # Remove that many spaces from each line
      lines
      |> Enum.map(fn line ->
        if String.trim(line) == "" do
          line
        else
          String.slice(line, min_indent, String.length(line))
        end
      end)
      |> Enum.join("\n")
    end

    # Count leading spaces/tabs (tabs count as @tab_width spaces)
    @spec count_leading_spaces(String.t()) :: non_neg_integer()
    defp count_leading_spaces(line) do
      tab_width = @tab_width

      line
      |> String.graphemes()
      |> Enum.take_while(&(&1 == " " or &1 == "\t"))
      |> Enum.reduce(0, fn char, acc ->
        case char do
          " " -> acc + 1
          "\t" -> acc + tab_width
        end
      end)
    end
  end

  # ============================================================================
  # MultiEdit Handler
  # ============================================================================

  defmodule MultiEdit do
    @moduledoc """
    Handler for the multi_edit_file tool.

    Applies multiple search/replace edits to a single file atomically.
    All edits succeed or all fail - the file remains unchanged if any
    validation fails.

    ## Execution Flow

    1. Validate path and read-before-write requirement
    2. Read file content once
    3. Validate ALL edits can be applied (pre-flight check)
    4. Apply all edits sequentially in memory
    5. Write result via single atomic write
    6. Track file write and emit telemetry

    ## Atomicity Guarantee

    If any edit fails validation (string not found, ambiguous match),
    the operation returns an error and no file is modified. This is
    achieved by validating all edits before applying any.

    ## Edit Order

    Edits are applied sequentially in the order provided. Each edit
    operates on the content as modified by previous edits. This means
    earlier edits may affect positions of later matches.

    ## Multi-Strategy Matching

    Each edit uses the same multi-strategy matching as EditFile:
    1. Exact match (primary)
    2. Line-trimmed match (fallback)
    3. Whitespace-normalized match (fallback)
    4. Indentation-flexible match (fallback)

    ## Read-Before-Write Requirement

    The file must be read in the current session before it can be edited.
    In legacy mode (no session_id), this check is skipped.
    """

    alias JidoCode.Session.State, as: SessionState
    alias JidoCode.Tools.HandlerHelpers
    alias JidoCode.Tools.Handlers.FileSystem
    alias JidoCode.Tools.Security

    require Logger

    @tab_width Application.compile_env(:jido_code, [:tools, :edit_file, :tab_width], 4)

    @doc """
    Applies multiple edits to a file atomically.

    ## Arguments

    - `"path"` - Path to the file (relative to project root)
    - `"edits"` - Array of edit objects, each with:
      - `"old_string"` - Text to find and replace
      - `"new_string"` - Replacement text

    ## Context

    - `:session_id` - Session ID for path validation and read-before-write check
    - `:project_root` - Direct project root path (legacy, skips read-before-write)

    ## Returns

    - `{:ok, message}` - Success message with edit count
    - `{:error, reason}` - Error message identifying which edit failed
    """
    @spec execute(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
    def execute(%{"path" => path, "edits" => edits} = _args, context)
        when is_binary(path) and is_list(edits) do
      start_time = System.monotonic_time()

      # Validate edits array is not empty
      if edits == [] do
        FileSystem.emit_file_telemetry(:multi_edit, start_time, path, context, :error, 0)
        {:error, "edits array cannot be empty"}
      else
        execute_multi_edit(path, edits, context, start_time)
      end
    end

    def execute(_args, _context) do
      {:error, "multi_edit_file requires path and edits arguments"}
    end

    # ============================================================================
    # Main Execution Logic
    # ============================================================================

    defp execute_multi_edit(path, edits, context, start_time) do
      result =
        with {:ok, project_root} <- HandlerHelpers.get_project_root(context),
             {:ok, safe_path} <- Security.validate_path(path, project_root, log_violations: true),
             normalized_path = FileSystem.normalize_path_for_tracking(path, project_root),
             :ok <- check_read_before_edit(normalized_path, context),
             {:ok, content} <- File.read(safe_path),
             {:ok, parsed_edits} <- parse_and_validate_edits(edits),
             {:ok, new_content, count} <- apply_all_edits(content, parsed_edits),
             :ok <- Security.atomic_write(path, new_content, project_root, log_violations: true),
             :ok <- FileSystem.track_file_write(normalized_path, context, :multi_edit_file) do
          {:ok, "Successfully applied #{count} edit(s) to #{path}"}
        end

      # Emit telemetry and return result
      case result do
        {:ok, _} = success ->
          FileSystem.emit_file_telemetry(:multi_edit, start_time, path, context, :ok, 0)
          success

        {:error, :read_before_write_required} ->
          FileSystem.emit_file_telemetry(:multi_edit, start_time, path, context, :read_before_write_required, 0)
          {:error, "File must be read before editing: #{path}"}

        {:error, :session_state_unavailable} ->
          FileSystem.emit_file_telemetry(:multi_edit, start_time, path, context, :error, 0)
          {:error, "Session state unavailable - cannot verify read-before-write requirement"}

        {:error, {:edit_failed, index, reason}} ->
          FileSystem.emit_file_telemetry(:multi_edit, start_time, path, context, :edit_failed, 0)
          {:error, "Edit #{index + 1} failed: #{reason}"}

        {:error, {:invalid_edit, index, reason}} ->
          FileSystem.emit_file_telemetry(:multi_edit, start_time, path, context, :invalid_edit, 0)
          {:error, "Edit #{index + 1} invalid: #{reason}"}

        {:error, reason} ->
          FileSystem.emit_file_telemetry(:multi_edit, start_time, path, context, :error, 0)
          {:error, FileSystem.format_error(reason, path)}
      end
    end

    # ============================================================================
    # Read-Before-Write Check
    # ============================================================================

    @spec check_read_before_edit(String.t(), map()) ::
            :ok | {:error, :read_before_write_required | :session_state_unavailable}
    defp check_read_before_edit(normalized_path, context) do
      case Map.get(context, :session_id) do
        nil ->
          # No session context (legacy mode) - skip check but log
          Logger.debug("MultiEdit: Skipping read-before-edit check - no session context (legacy mode)")
          :ok

        session_id ->
          case SessionState.file_was_read?(session_id, normalized_path) do
            {:ok, true} ->
              :ok

            {:ok, false} ->
              {:error, :read_before_write_required}

            {:error, :not_found} ->
              Logger.warning(
                "MultiEdit: Session #{session_id} not found during read-before-edit check - failing closed"
              )
              {:error, :session_state_unavailable}
          end
      end
    end

    # ============================================================================
    # Edit Parsing and Validation
    # ============================================================================

    @spec parse_and_validate_edits([map()]) :: {:ok, [{String.t(), String.t()}]} | {:error, {:invalid_edit, non_neg_integer(), String.t()}}
    defp parse_and_validate_edits(edits) do
      edits
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {edit, index}, {:ok, acc} ->
        case parse_edit(edit) do
          {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
          {:error, reason} -> {:halt, {:error, {:invalid_edit, index, reason}}}
        end
      end)
      |> case do
        {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
        error -> error
      end
    end

    defp parse_edit(%{"old_string" => old_string, "new_string" => new_string})
         when is_binary(old_string) and is_binary(new_string) do
      cond do
        old_string == "" ->
          {:error, "old_string cannot be empty"}

        true ->
          {:ok, {old_string, new_string}}
      end
    end

    defp parse_edit(%{old_string: old_string, new_string: new_string})
         when is_binary(old_string) and is_binary(new_string) do
      parse_edit(%{"old_string" => old_string, "new_string" => new_string})
    end

    defp parse_edit(_), do: {:error, "must have old_string and new_string fields"}

    # ============================================================================
    # Batch Edit Application
    # ============================================================================

    @spec apply_all_edits(String.t(), [{String.t(), String.t()}]) ::
            {:ok, String.t(), pos_integer()} | {:error, {:edit_failed, non_neg_integer(), String.t()}}
    defp apply_all_edits(content, edits) do
      edits
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, content, 0}, fn {{old_string, new_string}, index}, {:ok, current_content, count} ->
        case apply_single_edit(current_content, old_string, new_string) do
          {:ok, new_content} ->
            {:cont, {:ok, new_content, count + 1}}

          {:error, reason} ->
            {:halt, {:error, {:edit_failed, index, reason}}}
        end
      end)
    end

    # Apply a single edit using multi-strategy matching
    @spec apply_single_edit(String.t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
    defp apply_single_edit(content, old_string, new_string) do
      strategies = [
        {:exact, &exact_match/2},
        {:line_trimmed, &line_trimmed_match/2},
        {:whitespace_normalized, &whitespace_normalized_match/2},
        {:indentation_flexible, &indentation_flexible_match/2}
      ]

      result =
        Enum.reduce_while(strategies, {:error, :not_found}, fn {strategy_name, match_fn}, _acc ->
          case try_single_replace(content, old_string, new_string, match_fn) do
            {:ok, new_content} ->
              if strategy_name != :exact do
                Logger.debug("MultiEdit: Used #{strategy_name} matching strategy for edit")
              end
              {:halt, {:ok, new_content}}

            {:error, :ambiguous_match, count} ->
              {:halt, {:error, {:ambiguous, count}}}

            {:error, :not_found} ->
              {:cont, {:error, :not_found}}
          end
        end)

      case result do
        {:ok, _} = success ->
          success

        {:error, :not_found} ->
          {:error, "String not found in file"}

        {:error, {:ambiguous, count}} ->
          {:error, "Found #{count} occurrences - provide more specific old_string"}
      end
    end

    # Try to replace using a specific match function (single occurrence only)
    defp try_single_replace(content, old_string, new_string, match_fn) do
      positions = match_fn.(content, old_string)
      count = length(positions)

      cond do
        count == 0 ->
          {:error, :not_found}

        count > 1 ->
          {:error, :ambiguous_match, count}

        true ->
          # Apply single replacement
          {pos, len} = normalize_position(hd(positions), old_string)
          prefix = String.slice(content, 0, pos)
          suffix = String.slice(content, pos + len, 0x7FFFFFFF)
          {:ok, prefix <> new_string <> suffix}
      end
    end

    # Normalize position to {pos, len} tuple
    defp normalize_position({pos, len}, _old_string), do: {pos, len}
    defp normalize_position(pos, old_string) when is_integer(pos), do: {pos, String.length(old_string)}

    # ============================================================================
    # Match Strategy Implementations
    # (Mirrors EditFile strategies for consistency)
    # ============================================================================

    # Strategy 1: Exact match
    defp exact_match(content, pattern), do: find_all_positions(content, pattern)

    # Strategy 2: Line-trimmed match
    defp line_trimmed_match(content, pattern) do
      trimmed_pattern = trim_lines(pattern)
      if trimmed_pattern == pattern do
        []
      else
        find_fuzzy_positions(content, pattern, &trim_lines/1)
      end
    end

    # Strategy 3: Whitespace-normalized match
    defp whitespace_normalized_match(content, pattern) do
      normalized_pattern = normalize_whitespace(pattern)
      if normalized_pattern == pattern do
        []
      else
        find_fuzzy_positions(content, pattern, &normalize_whitespace/1)
      end
    end

    # Strategy 4: Indentation-flexible match
    defp indentation_flexible_match(content, pattern) do
      dedented_pattern = dedent(pattern)
      if dedented_pattern == pattern do
        []
      else
        find_fuzzy_positions(content, pattern, &dedent/1)
      end
    end

    # ============================================================================
    # Position Finding Helpers
    # ============================================================================

    defp find_all_positions(content, pattern) do
      pattern_len = String.length(pattern)
      do_find_positions(content, pattern, pattern_len, 0, [])
    end

    defp do_find_positions(content, pattern, pattern_len, offset, acc) do
      case find_grapheme_position(content, pattern) do
        {:found, pos} ->
          absolute_pos = offset + pos
          rest = String.slice(content, pos + pattern_len, String.length(content))
          do_find_positions(rest, pattern, pattern_len, absolute_pos + pattern_len, [absolute_pos | acc])

        :not_found ->
          Enum.reverse(acc)
      end
    end

    defp find_grapheme_position(content, pattern) do
      case String.split(content, pattern, parts: 2) do
        [before, _rest] -> {:found, String.length(before)}
        [_no_match] -> :not_found
      end
    end

    defp find_fuzzy_positions(content, pattern, normalize_fn) do
      content_lines = String.split(content, "\n")
      pattern_lines = String.split(pattern, "\n")
      pattern_line_count = length(pattern_lines)
      normalized_pattern_lines = Enum.map(pattern_lines, normalize_fn)

      find_matching_line_sequences(content_lines, normalized_pattern_lines, pattern_line_count, normalize_fn, 0, 0, [])
    end

    defp find_matching_line_sequences(content_lines, normalized_pattern_lines, pattern_line_count, normalize_fn, line_idx, char_offset, acc) do
      if line_idx + pattern_line_count > length(content_lines) do
        Enum.reverse(acc)
      else
        candidate_lines = Enum.slice(content_lines, line_idx, pattern_line_count)
        normalized_candidates = Enum.map(candidate_lines, normalize_fn)

        new_acc =
          if normalized_candidates == normalized_pattern_lines do
            matched_content = Enum.join(candidate_lines, "\n")
            matched_len = String.length(matched_content)
            [{char_offset, matched_len} | acc]
          else
            acc
          end

        current_line = Enum.at(content_lines, line_idx, "")
        next_char_offset = char_offset + String.length(current_line) + 1

        find_matching_line_sequences(
          content_lines,
          normalized_pattern_lines,
          pattern_line_count,
          normalize_fn,
          line_idx + 1,
          next_char_offset,
          new_acc
        )
      end
    end

    # ============================================================================
    # Normalization Helpers
    # ============================================================================

    defp trim_lines(text) do
      text
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.join("\n")
    end

    defp normalize_whitespace(text) do
      text
      |> String.replace(~r/[ \t]+/, " ")
      |> String.replace(~r/ ?\n ?/, "\n")
    end

    defp dedent(text) do
      lines = String.split(text, "\n")

      min_indent =
        lines
        |> Enum.filter(&(String.trim(&1) != ""))
        |> Enum.map(&count_leading_spaces/1)
        |> Enum.min(fn -> 0 end)

      lines
      |> Enum.map(fn line ->
        if String.trim(line) == "" do
          line
        else
          String.slice(line, min_indent, String.length(line))
        end
      end)
      |> Enum.join("\n")
    end

    # Count leading spaces/tabs (tabs count as @tab_width spaces)
    defp count_leading_spaces(line) do
      tab_width = @tab_width

      line
      |> String.graphemes()
      |> Enum.take_while(&(&1 == " " or &1 == "\t"))
      |> Enum.reduce(0, fn char, acc ->
        case char do
          " " -> acc + 1
          "\t" -> acc + tab_width
        end
      end)
    end
  end

  # ============================================================================
  # ReadFile Handler
  # ============================================================================

  defmodule ReadFile do
    @moduledoc """
    Handler for the read_file tool.

    Reads the contents of a file within the project boundary using TOCTOU-safe
    atomic operations via `Security.atomic_read/3`.

    Uses session-aware path validation via `HandlerHelpers.validate_path/2`.

    ## File Tracking

    Successful reads are tracked in the session state to support the
    read-before-write safety check. This ensures that files must be read
    before they can be overwritten.

    ## Path Normalization

    File paths are normalized using `FileSystem.normalize_path_for_tracking/2`
    to ensure consistent tracking between read and write operations. This
    prevents bypass attacks where different path formats could refer to the
    same file.
    """

    alias JidoCode.Session.State, as: SessionState
    alias JidoCode.Tools.HandlerHelpers
    alias JidoCode.Tools.Handlers.FileSystem
    alias JidoCode.Tools.Security

    @doc """
    Reads the contents of a file.

    ## Arguments

    - `"path"` - Path to the file (relative to project root)

    ## Context

    - `:session_id` - Session ID for path validation and read tracking
    - `:project_root` - Direct project root path (legacy)

    ## Returns

    - `{:ok, content}` - File contents as string
    - `{:error, reason}` - Error message

    ## Security

    Uses `Security.atomic_read/3` for TOCTOU-safe file reading:
    - Validates path before read
    - Re-validates realpath after read
    - Detects symlink attacks during operation

    ## Side Effects

    On successful read, tracks the file path and timestamp in session state
    to enable read-before-write validation for subsequent write operations.
    """
    def execute(%{"path" => path}, context) when is_binary(path) do
      start_time = System.monotonic_time()

      case HandlerHelpers.get_project_root(context) do
        {:ok, project_root} ->
          # Use atomic_read for TOCTOU-safe reading
          case Security.atomic_read(path, project_root, log_violations: true) do
            {:ok, content} ->
              # Track the read in session state for read-before-write validation
              # Use normalized path for consistent tracking with WriteFile
              normalized_path = FileSystem.normalize_path_for_tracking(path, project_root)
              track_file_read(normalized_path, context)

              # Emit success telemetry using shared helper
              FileSystem.emit_file_telemetry(:read, start_time, path, context, :ok, byte_size(content))

              {:ok, content}

            {:error, reason} ->
              FileSystem.emit_file_telemetry(:read, start_time, path, context, :error, 0)
              {:error, FileSystem.format_error(reason, path)}
          end

        {:error, reason} ->
          FileSystem.emit_file_telemetry(:read, start_time, path, context, :error, 0)
          {:error, FileSystem.format_error(reason, path)}
      end
    end

    def execute(_args, _context) do
      {:error, "read_file requires a path argument"}
    end

    # Track the file read in session state
    # Returns :ok on success, logs warning on session not found
    @spec track_file_read(String.t(), map()) :: :ok
    defp track_file_read(normalized_path, context) do
      case Map.get(context, :session_id) do
        nil ->
          # No session context - skip tracking (legacy mode)
          :ok

        session_id ->
          case SessionState.track_file_read(session_id, normalized_path) do
            {:ok, _timestamp} ->
              :ok

            {:error, :not_found} ->
              # Log warning for debugging - session should exist
              Logger.warning(
                "ReadFile: Session #{session_id} not found when tracking file read for #{Path.basename(normalized_path)}"
              )

              :ok
          end
      end
    end
  end

  # ============================================================================
  # WriteFile Handler
  # ============================================================================

  defmodule WriteFile do
    @moduledoc """
    Handler for the write_file tool.

    Writes content to a file, creating parent directories if needed.
    Uses session-aware path validation via `HandlerHelpers.validate_path/2`.

    ## Read-Before-Write Requirement

    For existing files, the file must be read in the current session before
    it can be overwritten. This prevents accidental overwrites and ensures
    the agent has seen the current file contents. New files can be created
    without prior reading.

    ## Path Normalization

    File paths are normalized using `FileSystem.normalize_path_for_tracking/2`
    to ensure consistent tracking between read and write operations. This
    prevents bypass attacks where different path formats could refer to the
    same file.

    ## Security

    Uses `Security.atomic_write/4` for TOCTOU-safe file writing:
    - Validates path before write
    - Creates parent directories atomically
    - Re-validates realpath after write
    - Detects symlink attacks during operation

    ## File Write Tracking

    After successful writes, the file path and timestamp are recorded in
    session state (`file_writes` map). This tracking is used for:
    - Detecting concurrent modification conflicts (future feature)
    - Auditing which files were modified in a session
    - Enabling session persistence and replay

    Note: The `file_writes` map is currently populated but not actively used
    for conflict detection. This is intentional infrastructure for planned
    features. See Session.State for the tracking implementation.

    ## TOCTOU Limitation

    The atomic_write implementation has a known TOCTOU window between
    `File.mkdir_p` and `File.write`. An attacker could theoretically create
    a symlink at the target path during this window. The post-write validation
    (`Security.validate_realpath/3`) detects this attack but cannot prevent
    the write from occurring. This is logged as a security event for incident
    response. Full prevention would require OS-level support (O_EXCL, etc.)
    which is not reliably available in Elixir/Erlang's file APIs.
    """

    alias JidoCode.Session.State, as: SessionState
    alias JidoCode.Tools.HandlerHelpers
    alias JidoCode.Tools.Handlers.FileSystem
    alias JidoCode.Tools.Security

    # Maximum file size: 10MB
    @max_file_size 10 * 1024 * 1024

    @doc """
    Returns the maximum file size in bytes.
    """
    @spec max_file_size() :: pos_integer()
    def max_file_size, do: @max_file_size

    @doc """
    Writes content to a file.

    ## Arguments

    - `"path"` - Path to the file (relative to project root)
    - `"content"` - Content to write (max 10MB)

    ## Context

    - `:session_id` - Session ID for path validation and read-before-write check
    - `:project_root` - Direct project root path (legacy, skips read-before-write)

    ## Returns

    - `{:ok, message}` - Success message (e.g., "File written successfully: path"
      for new files, "File updated successfully: path" for overwrites)
    - `{:error, reason}` - Error message

    ## Security

    - Content size limited to 10MB
    - Existing files require prior read in session (read-before-write check)
    - Uses atomic_write for TOCTOU protection
    """
    def execute(%{"path" => path, "content" => content}, context)
        when is_binary(path) and is_binary(content) do
      start_time = System.monotonic_time()
      content_size = byte_size(content)

      result =
        with :ok <- validate_content_size(content),
             {:ok, project_root} <- HandlerHelpers.get_project_root(context),
             {:ok, safe_path} <- Security.validate_path(path, project_root, log_violations: true),
             # Check file existence once and pass to check_read_before_write
             file_existed <- File.exists?(safe_path),
             # Use normalized path for consistent tracking with ReadFile
             normalized_path <- FileSystem.normalize_path_for_tracking(path, project_root),
             :ok <- check_read_before_write(normalized_path, file_existed, context),
             :ok <- Security.atomic_write(path, content, project_root, log_violations: true),
             :ok <- FileSystem.track_file_write(normalized_path, context, :write_file) do
          file_status = if file_existed, do: "updated", else: "written"
          {:ok, "File #{file_status} successfully: #{path}"}
        end

      # Emit telemetry and return result
      case result do
        {:ok, _} = success ->
          FileSystem.emit_file_telemetry(:write, start_time, path, context, :ok, content_size)
          success

        {:error, :read_before_write_required} ->
          FileSystem.emit_file_telemetry(:write, start_time, path, context, :read_before_write_required, content_size)
          {:error, "File must be read before overwriting: #{path}"}

        {:error, :session_state_unavailable} ->
          FileSystem.emit_file_telemetry(:write, start_time, path, context, :error, content_size)
          {:error, "Session state unavailable - cannot verify read-before-write requirement"}

        {:error, reason} ->
          FileSystem.emit_file_telemetry(:write, start_time, path, context, :error, content_size)
          {:error, FileSystem.format_error(reason, path)}
      end
    end

    def execute(_args, _context) do
      {:error, "write_file requires path and content arguments"}
    end

    # Private functions for WriteFile

    @spec validate_content_size(binary()) :: :ok | {:error, :content_too_large}
    defp validate_content_size(content) when byte_size(content) > @max_file_size do
      {:error, :content_too_large}
    end

    defp validate_content_size(_content), do: :ok

    # Check read-before-write requirement for existing files
    # This ensures the agent has seen the file content before overwriting
    # Now takes file_existed as parameter to avoid double File.exists? call
    @spec check_read_before_write(String.t(), boolean(), map()) ::
            :ok | {:error, :read_before_write_required | :session_state_unavailable}
    defp check_read_before_write(_normalized_path, false, _context) do
      # New file - no read required
      :ok
    end

    defp check_read_before_write(normalized_path, true, context) do
      # Existing file - check if it was read in this session
      case Map.get(context, :session_id) do
        nil ->
          # No session context (legacy mode) - skip check but log
          Logger.debug("WriteFile: Skipping read-before-write check - no session context (legacy mode)")
          :ok

        session_id ->
          case SessionState.file_was_read?(session_id, normalized_path) do
            {:ok, true} ->
              :ok

            {:ok, false} ->
              {:error, :read_before_write_required}

            {:error, :not_found} ->
              # Fail-closed: Session not found is a security concern
              Logger.warning(
                "WriteFile: Session #{session_id} not found during read-before-write check - failing closed"
              )

              {:error, :session_state_unavailable}
          end
      end
    end
  end

  # ============================================================================
  # ListDirectory Handler
  # ============================================================================

  defmodule ListDirectory do
    @moduledoc """
    Handler for the list_directory tool.

    Lists the contents of a directory with optional recursive listing.
    Uses session-aware path validation via `HandlerHelpers.validate_path/2`.
    """

    alias JidoCode.Tools.Handlers.FileSystem

    @doc """
    Lists directory contents.

    ## Arguments

    - `"path"` - Path to the directory (relative to project root)
    - `"recursive"` - Whether to list recursively (optional, default false)

    ## Context

    - `:session_id` - Session ID for path validation (preferred)
    - `:project_root` - Direct project root path (legacy)

    ## Returns

    - `{:ok, entries}` - JSON-encoded list of entries
    - `{:error, reason}` - Error message
    """
    def execute(%{"path" => path} = args, context) when is_binary(path) do
      recursive = Map.get(args, "recursive", false)

      case FileSystem.validate_path(path, context) do
        {:ok, safe_path} ->
          list_entries(path, safe_path, recursive)

        {:error, reason} ->
          {:error, FileSystem.format_error(reason, path)}
      end
    end

    def execute(_args, _context) do
      {:error, "list_directory requires a path argument"}
    end

    defp list_entries(original_path, safe_path, false) do
      case File.ls(safe_path) do
        {:ok, entries} when is_list(entries) ->
          result = entries |> Enum.sort() |> Enum.map(&entry_info(safe_path, &1))
          {:ok, Jason.encode!(result)}

        {:error, reason} ->
          {:error, FileSystem.format_error(reason, original_path)}
      end
    end

    defp list_entries(original_path, safe_path, true) do
      case list_recursive(safe_path, safe_path) do
        {:ok, entries} ->
          {:ok, Jason.encode!(entries)}

        {:error, reason} ->
          {:error, FileSystem.format_error(reason, original_path)}
      end
    end

    defp entry_info(parent_path, entry) do
      full_path = Path.join(parent_path, entry)
      type = if File.dir?(full_path), do: "directory", else: "file"
      %{name: entry, type: type}
    end

    # Recursive listing - base_path is the root for relative name calculation
    defp list_recursive(path, base_path) do
      case File.ls(path) do
        {:ok, entries} when is_list(entries) ->
          results = entries |> Enum.sort() |> Enum.flat_map(&expand_entry(path, &1, base_path))
          {:ok, results}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp expand_entry(parent_path, entry, base_path) do
      full_path = Path.join(parent_path, entry)
      # Calculate relative path from base
      relative_name = Path.relative_to(full_path, base_path)

      if File.dir?(full_path) do
        expand_directory(full_path, relative_name, base_path)
      else
        [%{name: relative_name, type: "file"}]
      end
    end

    defp expand_directory(full_path, relative_name, base_path) do
      case list_recursive(full_path, base_path) do
        {:ok, children} ->
          [%{name: relative_name, type: "directory"} | children]

        {:error, _} ->
          [%{name: relative_name, type: "directory", error: "unreadable"}]
      end
    end
  end

  # ============================================================================
  # ListDir Handler
  # ============================================================================

  defmodule ListDir do
    @moduledoc """
    Handler for the list_dir tool.

    Lists the contents of a directory with optional filtering via glob patterns.
    Uses session-aware path validation via `HandlerHelpers.validate_path/2`.

    This handler extends ListDirectory with support for ignore_patterns,
    allowing files and directories matching specified glob patterns to be
    excluded from the listing.

    ## Ignore Patterns

    Patterns follow standard glob syntax:
    - `*` - Match any sequence of characters
    - `?` - Match any single character
    - `*.log` - Match all .log files
    - `node_modules` - Match exact directory name

    ### Limitations

    The following advanced glob features are NOT supported:
    - `**` for recursive directory matching (treated as `*`)
    - `[abc]` character classes
    - `{a,b}` brace expansion
    - `!pattern` negation

    ## Security

    All paths are validated against the project boundary before access.
    Glob patterns are properly escaped to prevent regex injection attacks.

    ## See Also

    - `JidoCode.Tools.Definitions.ListDir` - Tool definition
    - `JidoCode.Tools.Handlers.FileSystem.ListDirectory` - Base handler
    - `JidoCode.Tools.Helpers.GlobMatcher` - Glob pattern matching utilities
    """

    alias JidoCode.Tools.Handlers.FileSystem
    alias JidoCode.Tools.Helpers.GlobMatcher

    @doc """
    Lists directory contents with optional filtering.

    ## Arguments

    - `"path"` - Path to the directory (relative to project root)
    - `"ignore_patterns"` - Array of glob patterns to exclude (optional)

    ## Context

    - `:session_id` - Session ID for path validation (preferred)
    - `:project_root` - Direct project root path (legacy)

    ## Returns

    - `{:ok, entries}` - JSON-encoded list of entries with name and type
    - `{:error, reason}` - Error message
    """
    @spec execute(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
    def execute(%{"path" => path} = args, context) when is_binary(path) do
      ignore_patterns = Map.get(args, "ignore_patterns", [])

      case FileSystem.validate_path(path, context) do
        {:ok, safe_path} ->
          list_entries(path, safe_path, ignore_patterns)

        {:error, reason} ->
          {:error, FileSystem.format_error(reason, path)}
      end
    end

    def execute(_args, _context) do
      {:error, "list_dir requires a path argument"}
    end

    @spec list_entries(String.t(), String.t(), list(String.t())) ::
            {:ok, String.t()} | {:error, String.t()}
    defp list_entries(original_path, safe_path, ignore_patterns) do
      case File.ls(safe_path) do
        {:ok, entries} when is_list(entries) ->
          result =
            entries
            |> Enum.reject(&GlobMatcher.matches_any?(&1, ignore_patterns))
            |> GlobMatcher.sort_directories_first(safe_path)
            |> Enum.map(&GlobMatcher.entry_info(safe_path, &1))

          {:ok, Jason.encode!(result)}

        {:error, reason} ->
          {:error, FileSystem.format_error(reason, original_path)}
      end
    end
  end

  # ============================================================================
  # FileInfo Handler
  # ============================================================================

  defmodule FileInfo do
    @moduledoc """
    Handler for the file_info tool.

    Gets metadata about a file or directory.
    Uses session-aware path validation via `HandlerHelpers.validate_path/2`.
    """

    alias JidoCode.Tools.Handlers.FileSystem

    @doc """
    Gets file metadata.

    ## Arguments

    - `"path"` - Path to the file/directory (relative to project root)

    ## Context

    - `:session_id` - Session ID for path validation (preferred)
    - `:project_root` - Direct project root path (legacy)

    ## Returns

    - `{:ok, info}` - JSON-encoded metadata map
    - `{:error, reason}` - Error message
    """
    def execute(%{"path" => path}, context) when is_binary(path) do
      case FileSystem.validate_path(path, context) do
        {:ok, safe_path} ->
          case File.stat(safe_path) do
            {:ok, stat} ->
              info = %{
                path: path,
                size: stat.size,
                type: Atom.to_string(stat.type),
                access: Atom.to_string(stat.access),
                mtime: format_mtime(stat.mtime)
              }

              {:ok, Jason.encode!(info)}

            {:error, reason} ->
              {:error, FileSystem.format_error(reason, path)}
          end

        {:error, reason} ->
          {:error, FileSystem.format_error(reason, path)}
      end
    end

    def execute(_args, _context) do
      {:error, "file_info requires a path argument"}
    end

    defp format_mtime({{year, month, day}, {hour, minute, second}}) do
      :io_lib.format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B", [
        year,
        month,
        day,
        hour,
        minute,
        second
      ])
      |> IO.iodata_to_binary()
    end

    defp format_mtime(_), do: ""
  end

  # ============================================================================
  # CreateDirectory Handler
  # ============================================================================

  defmodule CreateDirectory do
    @moduledoc """
    Handler for the create_directory tool.

    Creates a directory, including parent directories.
    Uses session-aware path validation via `HandlerHelpers.validate_path/2`.
    """

    alias JidoCode.Tools.Handlers.FileSystem

    @doc """
    Creates a directory.

    ## Arguments

    - `"path"` - Path to the directory to create (relative to project root)

    ## Context

    - `:session_id` - Session ID for path validation (preferred)
    - `:project_root` - Direct project root path (legacy)

    ## Returns

    - `{:ok, message}` - Success message
    - `{:error, reason}` - Error message
    """
    def execute(%{"path" => path}, context) when is_binary(path) do
      case FileSystem.validate_path(path, context) do
        {:ok, safe_path} ->
          case File.mkdir_p(safe_path) do
            :ok -> {:ok, "Directory created successfully: #{path}"}
            {:error, reason} -> {:error, FileSystem.format_error(reason, path)}
          end

        {:error, reason} ->
          {:error, FileSystem.format_error(reason, path)}
      end
    end

    def execute(_args, _context) do
      {:error, "create_directory requires a path argument"}
    end
  end

  # ============================================================================
  # DeleteFile Handler
  # ============================================================================

  defmodule DeleteFile do
    @moduledoc """
    Handler for the delete_file tool.

    Deletes a file with confirmation requirement for safety.
    Uses session-aware path validation via `HandlerHelpers.validate_path/2`.
    """

    alias JidoCode.Tools.Handlers.FileSystem

    @doc """
    Deletes a file.

    ## Arguments

    - `"path"` - Path to the file to delete (relative to project root)
    - `"confirm"` - Must be true to actually delete

    ## Context

    - `:session_id` - Session ID for path validation (preferred)
    - `:project_root` - Direct project root path (legacy)

    ## Returns

    - `{:ok, message}` - Success message
    - `{:error, reason}` - Error message
    """
    def execute(%{"path" => path, "confirm" => true}, context) when is_binary(path) do
      case FileSystem.validate_path(path, context) do
        {:ok, safe_path} ->
          case File.rm(safe_path) do
            :ok -> {:ok, "File deleted successfully: #{path}"}
            {:error, reason} -> {:error, FileSystem.format_error(reason, path)}
          end

        {:error, reason} ->
          {:error, FileSystem.format_error(reason, path)}
      end
    end

    def execute(%{"path" => _path, "confirm" => false}, _context) do
      {:error, "Delete operation requires confirm=true"}
    end

    def execute(%{"path" => _path}, _context) do
      {:error, "delete_file requires confirm parameter set to true"}
    end

    def execute(_args, _context) do
      {:error, "delete_file requires path and confirm arguments"}
    end
  end

  # ============================================================================
  # GlobSearch Handler
  # ============================================================================

  defmodule GlobSearch do
    @moduledoc """
    Handler for the glob_search tool.

    Finds files matching a glob pattern within the project boundary.
    Uses Elixir's `Path.wildcard/2` for robust pattern matching.

    ## Supported Patterns

    - `*` - Match any sequence of characters (not including path separator)
    - `**` - Match any sequence of characters including path separators (recursive)
    - `?` - Match any single character
    - `{a,b}` - Match either pattern a or pattern b (brace expansion)
    - `[abc]` - Match any character in the set

    ## Security

    All matched paths are validated against the project boundary.
    Paths outside the boundary are automatically filtered out.
    Symlinks are followed to ensure their targets stay within the boundary.

    ## See Also

    - `JidoCode.Tools.Definitions.GlobSearch` - Tool definition
    - `JidoCode.Tools.Helpers.GlobMatcher` - Shared helper functions
    - `Path.wildcard/2` - Underlying pattern matching
    """

    alias JidoCode.Tools.Handlers.FileSystem
    alias JidoCode.Tools.Helpers.GlobMatcher

    @doc """
    Finds files matching a glob pattern.

    ## Arguments

    - `"pattern"` (required) - Glob pattern to match files against
    - `"path"` (optional) - Base directory to search from (defaults to project root)

    ## Context

    - `:session_id` - Session ID for path validation (preferred)
    - `:project_root` - Direct project root path (legacy)

    ## Returns

    - `{:ok, paths}` - JSON-encoded array of relative file paths, sorted by mtime
    - `{:error, reason}` - Error message
    """
    @spec execute(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
    def execute(%{"pattern" => pattern} = args, context) when is_binary(pattern) do
      base_path = Map.get(args, "path", ".")

      case FileSystem.validate_path(base_path, context) do
        {:ok, safe_base} ->
          if File.exists?(safe_base) do
            search_files(pattern, safe_base, context)
          else
            {:error, FileSystem.format_error(:enoent, base_path)}
          end

        {:error, reason} ->
          {:error, FileSystem.format_error(reason, base_path)}
      end
    end

    # Fallback clause for missing or invalid pattern argument
    def execute(_args, _context) do
      {:error, "glob_search requires a pattern argument"}
    end

    @spec search_files(String.t(), String.t(), map()) ::
            {:ok, String.t()} | {:error, String.t()}
    defp search_files(pattern, safe_base, context) do
      case FileSystem.get_project_root(context) do
        {:ok, project_root} ->
          # Build full pattern path
          full_pattern = Path.join(safe_base, pattern)

          # Use Path.wildcard to find matching files
          # Note: Path.wildcard may raise for invalid patterns, hence the rescue
          matches =
            full_pattern
            |> Path.wildcard(match_dot: false)
            |> GlobMatcher.filter_within_boundary(project_root)
            |> GlobMatcher.sort_by_mtime_desc()
            |> GlobMatcher.make_relative(project_root)

          {:ok, Jason.encode!(matches)}

        {:error, reason} ->
          {:error, FileSystem.format_error(reason, "context")}
      end
    rescue
      # Path.wildcard/2 can raise for malformed patterns
      e in ArgumentError ->
        {:error, "Invalid glob pattern: #{Exception.message(e)}"}

      e in Jason.EncodeError ->
        {:error, "Failed to encode results: #{Exception.message(e)}"}
    end
  end
end
