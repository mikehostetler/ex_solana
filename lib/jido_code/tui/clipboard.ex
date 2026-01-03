defmodule JidoCode.TUI.Clipboard do
  @moduledoc """
  Cross-platform clipboard support for the TUI.

  Provides multiple methods for copying text to the system clipboard:

  1. **OSC 52** - Modern terminals support this escape sequence for clipboard access.
     Works in: iTerm2, kitty, alacritty, WezTerm, Windows Terminal, etc.

  2. **System commands** - Fallback to platform-specific clipboard commands:
     - macOS: `pbcopy`
     - Linux (X11): `xclip` or `xsel`
     - Linux (Wayland): `wl-copy`
     - Windows/WSL: `clip.exe`

  ## Usage

      # Copy text to clipboard
      Clipboard.copy("Hello, world!")

      # Check if clipboard is available
      Clipboard.available?()

  ## OSC 52

  The OSC 52 escape sequence allows terminal applications to access the
  system clipboard without needing external tools. Format:

      \\e]52;c;<base64-encoded-text>\\a

  Not all terminals support this, and some require explicit configuration.
  """

  # Cache key for detected clipboard command
  @cache_key :jido_code_clipboard_command

  @doc """
  Copies text to the system clipboard.

  Tries OSC 52 first, then falls back to system commands.
  Returns `:ok` on success, `{:error, reason}` on failure.
  """
  @spec copy(String.t()) :: :ok | {:error, String.t() | atom()}
  def copy(text) when is_binary(text) do
    # Try OSC 52 first (works in many modern terminals)
    copy_osc52(text)

    # Also try system command for terminals that don't support OSC 52
    case copy_system(text) do
      :ok -> :ok
      {:error, _} = error -> error
    end
  end

  def copy(_text), do: {:error, :invalid_text}

  @doc """
  Copies text using OSC 52 escape sequence.

  This writes directly to the terminal. The terminal must support OSC 52
  for this to work. Most modern terminals do.
  """
  @spec copy_osc52(String.t()) :: :ok
  def copy_osc52(text) when is_binary(text) do
    encoded = Base.encode64(text)
    # OSC 52: \e]52;c;<base64>\a
    # c = clipboard (could also be p for primary selection on X11)
    IO.write("\e]52;c;#{encoded}\a")
    :ok
  end

  @doc """
  Copies text using system clipboard commands.

  Automatically detects the platform and uses the appropriate command.
  """
  @spec copy_system(String.t()) :: :ok | {:error, atom() | String.t()}
  def copy_system(text) when is_binary(text) do
    case detect_clipboard_command() do
      nil ->
        {:error, :clipboard_unavailable}

      {cmd, args} ->
        # Use Port to pipe stdin to the clipboard command
        port =
          Port.open({:spawn_executable, System.find_executable(cmd)}, [
            :binary,
            :exit_status,
            args: args
          ])

        Port.command(port, text)
        Port.close(port)

        # Give the command a moment to process
        receive do
          {^port, {:exit_status, 0}} -> :ok
          {^port, {:exit_status, status}} -> {:error, "Clipboard command exited with status #{status}"}
        after
          1000 -> :ok
        end
    end
  end

  @doc """
  Checks if clipboard functionality is available.

  Returns true if either OSC 52 or a system command is available.
  Note: OSC 52 availability depends on terminal support which can't be
  reliably detected, so we assume it's available and rely on the system
  command fallback.
  """
  @spec available?() :: boolean()
  def available? do
    detect_clipboard_command() != nil
  end

  @doc """
  Returns the detected clipboard command and arguments.

  Returns `nil` if no clipboard command is found.
  Results are cached after first detection.
  """
  @spec detect_clipboard_command() :: {String.t(), [String.t()]} | nil
  def detect_clipboard_command do
    case :persistent_term.get(@cache_key, :not_cached) do
      :not_cached ->
        result = do_detect_clipboard_command()
        :persistent_term.put(@cache_key, result)
        result

      cached ->
        cached
    end
  end

  @doc """
  Clears the cached clipboard command.

  Forces re-detection on the next call to `detect_clipboard_command/0`.
  """
  @spec clear_cache() :: :ok
  def clear_cache do
    try do
      :persistent_term.erase(@cache_key)
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  # Actually detect the clipboard command
  defp do_detect_clipboard_command do
    cond do
      # macOS
      command_available?("pbcopy") ->
        {"pbcopy", []}

      # Linux with Wayland
      command_available?("wl-copy") ->
        {"wl-copy", []}

      # Linux with X11 (xclip)
      command_available?("xclip") ->
        {"xclip", ["-selection", "clipboard"]}

      # Linux with X11 (xsel)
      command_available?("xsel") ->
        {"xsel", ["--clipboard", "--input"]}

      # Windows/WSL
      command_available?("clip.exe") ->
        {"clip.exe", []}

      # No clipboard command found
      true ->
        nil
    end
  end

  # Check if a command is available in PATH
  defp command_available?(command) do
    case System.find_executable(command) do
      nil -> false
      _ -> true
    end
  end

  # ============================================================================
  # Compatibility aliases (used by TUI)
  # ============================================================================

  @doc """
  Alias for `copy/1` for compatibility with TUI.

  Copies text to the system clipboard.
  """
  @spec copy_to_clipboard(String.t()) :: :ok | {:error, atom() | String.t()}
  def copy_to_clipboard(text) when is_binary(text), do: copy(text)
  def copy_to_clipboard(_text), do: {:error, :invalid_text}

  @doc """
  Pastes text from the system clipboard.

  Returns `{:ok, text}` on success, `{:error, reason}` on failure.
  """
  @spec paste_from_clipboard() :: {:ok, String.t()} | {:error, String.t()}
  def paste_from_clipboard do
    case detect_paste_command() do
      nil ->
        {:error, "No clipboard command available"}

      {cmd, args} ->
        case System.cmd(cmd, args, stderr_to_stdout: true) do
          {output, 0} -> {:ok, output}
          {output, _} -> {:error, "Clipboard command failed: #{output}"}
        end
    end
  end

  @doc """
  Returns the detected paste command and arguments.

  Returns `nil` if no paste command is found.
  """
  @spec detect_paste_command() :: {String.t(), [String.t()]} | nil
  def detect_paste_command do
    cond do
      # macOS
      command_available?("pbpaste") ->
        {"pbpaste", []}

      # Linux with Wayland
      command_available?("wl-paste") ->
        {"wl-paste", []}

      # Linux with X11 (xclip)
      command_available?("xclip") ->
        {"xclip", ["-selection", "clipboard", "-o"]}

      # Linux with X11 (xsel)
      command_available?("xsel") ->
        {"xsel", ["--clipboard", "--output"]}

      # Windows/WSL - PowerShell
      command_available?("powershell.exe") ->
        {"powershell.exe", ["-command", "Get-Clipboard"]}

      # No paste command found
      true ->
        nil
    end
  end
end
