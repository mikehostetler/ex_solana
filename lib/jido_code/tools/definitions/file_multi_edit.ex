defmodule JidoCode.Tools.Definitions.FileMultiEdit do
  @moduledoc """
  Tool definition for atomic batch file editing with multiple search/replace operations.

  This module defines the `multi_edit_file` tool which performs multiple targeted
  string replacements within a single file atomically. All edits succeed or all
  fail - there are no partial modifications.

  ## Execution Flow

  Tool Executor → Handler → FileSystem.MultiEdit.execute/2 → validate all → apply all → atomic write

  ## Features

  - Multiple edits applied atomically (all-or-nothing)
  - Pre-validation of all edits before any modifications
  - Reuses multi-strategy matching from EditFile
  - Sequential edit application with position preservation
  - Read-before-write requirement for safety
  - Project boundary enforcement

  ## Atomicity Guarantee

  All edits are validated before any modifications occur:
  1. Read file content once
  2. Validate each edit can be applied (string found, unique unless replace_all)
  3. Apply all edits sequentially in memory
  4. Write modified content via single atomic write operation

  If any validation fails, the operation returns an error identifying which
  edit failed, and the file remains unchanged.

  ## Edit Order and Position Sensitivity

  Edits are applied sequentially, so earlier edits may affect the positions
  of later matches. The handler sorts edits by position (end-to-start) when
  necessary to avoid position shifting issues.

  ## Read-Before-Write Requirement

  The file must be read in the current session before it can be edited. This
  ensures the agent has seen the current content and understands the context
  of the modifications.

  ## Usage

      # Register the tool
      :ok = Registry.register(FileMultiEdit.multi_edit_file())

      # Get LLM-compatible format
      Tool.to_llm_function(FileMultiEdit.multi_edit_file())

  ## See Also

  - `JidoCode.Tools.Handlers.FileSystem.MultiEdit` - Handler implementation
  - `JidoCode.Tools.Definitions.FileEdit` - Single edit tool
  - `JidoCode.Tools.Definitions.FileRead` - Read tool (must be called first)
  """

  alias JidoCode.Tools.Tool

  @doc """
  Returns the multi_edit_file tool definition.

  Performs multiple search/replace operations within a single file atomically.
  All edits must succeed or none are applied.

  ## Parameters

  - `path` (required, string) - Path to the file to edit (relative to project root)
  - `edits` (required, array) - Array of edit objects, each containing:
    - `old_string` (required, string) - Exact text to find and replace
    - `new_string` (required, string) - Replacement text (can be empty to delete)

  ## Returns

  On success:
  - `{:ok, "Successfully applied N edit(s) to <path>"}`

  On error:
  - `{:error, "Edit 1 failed: String not found in file"}` - Edit validation failed
  - `{:error, "Edit 2 failed: Found N occurrences..."}` - Ambiguous match
  - `{:error, "File must be read before editing: <path>"}` - Read-before-write violation
  - `{:error, "Security error: path escapes project boundary: <path>"}` - Security violation
  - `{:error, "edits array cannot be empty"}` - No edits provided

  ## Atomic Behavior

  All edits are validated before any modifications occur. This means:
  - If edit 3 of 5 would fail, edits 1 and 2 are NOT applied
  - The file remains completely unchanged on any error
  - You can safely retry after fixing the failing edit

  ## Examples

      # Multiple independent edits
      %{
        "path" => "lib/myapp.ex",
        "edits" => [
          %{"old_string" => "def foo, do: :old", "new_string" => "def foo, do: :new"},
          %{"old_string" => "def bar, do: :old", "new_string" => "def bar, do: :new"}
        ]
      }

      # Rename a function and update all calls
      %{
        "path" => "lib/module.ex",
        "edits" => [
          %{"old_string" => "def old_name(", "new_string" => "def new_name("},
          %{"old_string" => "old_name(arg)", "new_string" => "new_name(arg)"},
          %{"old_string" => "old_name(other)", "new_string" => "new_name(other)"}
        ]
      }

      # Delete multiple TODO comments
      %{
        "path" => "lib/myapp.ex",
        "edits" => [
          %{"old_string" => "# TODO: fix this\\n", "new_string" => ""},
          %{"old_string" => "# TODO: clean up\\n", "new_string" => ""}
        ]
      }

  ## Best Practices

  1. **Order matters** - Edits are applied sequentially; earlier edits affect later positions
  2. **Be specific** - Include enough context in each old_string to ensure uniqueness
  3. **Read first** - Always read the file before editing to see current state
  4. **Fewer is better** - Prefer fewer, more targeted edits over many small ones
  5. **Test incrementally** - For complex changes, consider multiple tool calls
  """
  @spec multi_edit_file() :: Tool.t()
  def multi_edit_file do
    Tool.new!(%{
      name: "multi_edit_file",
      description:
        "Apply multiple edits to a file atomically (all succeed or all fail). " <>
          "Each edit replaces old_string with new_string. " <>
          "IMPORTANT: The file must be read first before editing. " <>
          "All edits are validated before any changes are applied.",
      handler: JidoCode.Tools.Handlers.FileSystem.MultiEdit,
      parameters: [
        %{
          name: "path",
          type: :string,
          description: "Path to the file to edit (relative to project root)",
          required: true
        },
        %{
          name: "edits",
          type: :array,
          description:
            "Array of edit objects. Each object must have 'old_string' (text to find) and " <>
              "'new_string' (replacement text) fields. Edits are applied sequentially - " <>
              "earlier edits may affect positions of later matches.",
          required: true,
          items: :object
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
    [multi_edit_file()]
  end
end
