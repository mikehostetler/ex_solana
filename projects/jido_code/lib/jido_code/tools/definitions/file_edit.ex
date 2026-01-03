defmodule JidoCode.Tools.Definitions.FileEdit do
  @moduledoc """
  Tool definition for editing file contents with search/replace.

  This module defines the `edit_file` tool which performs targeted string
  replacement within files. Unlike `write_file` which overwrites entire files,
  `edit_file` allows surgical modifications to specific sections.

  ## Execution Flow

  Tool Executor → Handler → FileSystem.EditFile.execute/2 → File.read → replace → File.write

  ## Features

  - Exact string matching with multi-strategy fallback
  - Uniqueness validation (old_string must appear exactly once by default)
  - Optional replace_all mode for multiple occurrences
  - Project boundary enforcement
  - Read-before-write requirement for safety

  ## Uniqueness Requirement

  By default, the `old_string` must appear **exactly once** in the file. This
  prevents accidental modifications when the search string is ambiguous. If
  the string appears multiple times, the operation fails with a clear error
  message indicating the number of occurrences found.

  To replace all occurrences, set `replace_all: true`.

  ## Multi-Strategy Matching

  The handler implements multi-strategy matching for robustness:

  1. **Exact match** (primary) - Literal string comparison
  2. **Line-trimmed match** - Ignores leading/trailing whitespace per line
  3. **Whitespace-normalized match** - Collapses multiple spaces/tabs
  4. **Indentation-flexible match** - Allows different indentation levels

  Strategies are tried in order until one succeeds. The success message
  indicates which strategy matched (e.g., "matched via line_trimmed").

  ## Read-Before-Write Requirement

  The file must be read in the current session before it can be edited. This
  ensures the agent has seen the current content and understands the context
  of the modification.

  ## Usage

      # Register the tool
      :ok = Registry.register(FileEdit.edit_file())

      # Get LLM-compatible format
      Tool.to_llm_function(FileEdit.edit_file())

  ## See Also

  - `JidoCode.Tools.Handlers.FileSystem.EditFile` - Handler implementation
  - `JidoCode.Tools.Definitions.FileRead` - Read tool (must be called first)
  - `JidoCode.Tools.Definitions.FileWrite` - Full file overwrite tool
  """

  alias JidoCode.Tools.Tool

  @doc """
  Returns the edit_file tool definition.

  Performs search/replace within a file. The old_string must be unique in the
  file unless replace_all is set to true.

  ## Parameters

  - `path` (required, string) - Path to the file to edit (relative to project root)
  - `old_string` (required, string) - Exact text to find and replace
  - `new_string` (required, string) - Replacement text (can be empty to delete)
  - `replace_all` (optional, boolean, default: false) - Replace all occurrences

  ## Returns

  On success:
  - `{:ok, "Successfully replaced N occurrence(s) in <path>"}`

  On error:
  - `{:error, "String not found in file: <path>"}` - old_string not in file
  - `{:error, "Found N occurrences of the string in <path>. Use replace_all: true..."}` - Ambiguous match
  - `{:error, "File must be read before editing: <path>"}` - Read-before-write violation
  - `{:error, "Security error: path escapes project boundary: <path>"}` - Security violation

  ## Uniqueness Requirement

  By default, `old_string` must appear exactly once in the file. This prevents
  unintended modifications when the search string is ambiguous. If multiple
  occurrences exist:

  1. The operation fails with an error showing the count
  2. User can either provide a more specific `old_string`
  3. Or set `replace_all: true` to replace all occurrences

  ## Examples

      # Simple replacement (old_string must be unique)
      %{
        "path" => "lib/myapp.ex",
        "old_string" => "def hello, do: :world",
        "new_string" => "def hello, do: :elixir"
      }

      # Replace all occurrences
      %{
        "path" => "README.md",
        "old_string" => "old_name",
        "new_string" => "new_name",
        "replace_all" => true
      }

      # Delete text (empty new_string)
      %{
        "path" => "config.exs",
        "old_string" => "# TODO: remove this\\n",
        "new_string" => ""
      }

      # Multi-line replacement
      %{
        "path" => "lib/module.ex",
        "old_string" => "def old_function do\\n    :old\\n  end",
        "new_string" => "def new_function do\\n    :new\\n  end"
      }

  ## Best Practices

  1. **Be specific** - Include enough context in old_string to ensure uniqueness
  2. **Include surrounding code** - Add a line before/after to disambiguate
  3. **Match exact formatting** - Preserve indentation and line endings
  4. **Read first** - Always read the file before editing to see current state
  """
  @spec edit_file() :: Tool.t()
  def edit_file do
    Tool.new!(%{
      name: "edit_file",
      description:
        "Edit a file by replacing old_string with new_string. " <>
          "The old_string must be unique in the file (appear exactly once) unless replace_all is true. " <>
          "IMPORTANT: The file must be read first before editing. " <>
          "Include enough context in old_string to ensure it matches exactly one location.",
      handler: JidoCode.Tools.Handlers.FileSystem.EditFile,
      parameters: [
        %{
          name: "path",
          type: :string,
          description: "Path to the file to edit (relative to project root)",
          required: true
        },
        %{
          name: "old_string",
          type: :string,
          description:
            "Exact text to find and replace. Must be unique in the file unless replace_all is true. " <>
              "Include surrounding context (lines before/after) to ensure uniqueness.",
          required: true
        },
        %{
          name: "new_string",
          type: :string,
          description: "Replacement text. Can be empty string to delete the old_string.",
          required: true
        },
        %{
          name: "replace_all",
          type: :boolean,
          description:
            "If true, replace all occurrences of old_string. " <>
              "If false (default), old_string must appear exactly once.",
          required: false,
          default: false
        }
      ]
    })
  end

  @doc """
  Returns all tools defined in this module.

  ## Returns

  List of `%Tool{}` structs ready for registration.
  """
  @spec all() :: [Tool.t()]
  def all do
    [edit_file()]
  end
end
