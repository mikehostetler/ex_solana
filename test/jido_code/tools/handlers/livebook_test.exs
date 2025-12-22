defmodule JidoCode.Tools.Handlers.LivebookTest do
  # async: false because we're modifying the shared Manager state
  use ExUnit.Case, async: false

  alias JidoCode.Livebook.{Cell, Parser}
  alias JidoCode.Tools.Handlers.Livebook.EditCell

  @moduletag :tmp_dir

  # Set up Manager with tmp_dir as project root for sandboxed operations
  setup %{tmp_dir: tmp_dir} do
    JidoCode.TestHelpers.ManagerIsolation.set_project_root(tmp_dir)
    :ok
  end

  @sample_notebook """
  # Test Notebook

  ```elixir
  x = 1
  ```

  Some text.

  ```elixir
  y = 2
  ```
  """

  # ============================================================================
  # Session Context Tests
  # ============================================================================

  describe "session-aware context" do
    setup %{tmp_dir: tmp_dir} do
      # Start required registries if not already started
      start_supervised!({Registry, keys: :unique, name: JidoCode.SessionProcessRegistry})

      # Create a session
      {:ok, session} = JidoCode.Session.new(project_path: tmp_dir, name: "livebook-session-test")

      {:ok, supervisor_pid} =
        JidoCode.Session.Supervisor.start_link(
          session: session,
          name: {:via, Registry, {JidoCode.Registry, {:livebook_session_test_sup, session.id}}}
        )

      on_exit(fn ->
        try do
          if Process.alive?(supervisor_pid), do: Supervisor.stop(supervisor_pid, :normal, 100)
        catch
          :exit, _ -> :ok
        end
      end)

      %{session: session}
    end

    test "EditCell uses session_id for path validation", %{tmp_dir: tmp_dir, session: session} do
      # Create test notebook
      notebook_path = Path.join(tmp_dir, "session_test.livemd")
      File.write!(notebook_path, @sample_notebook)

      # Use session_id context
      context = %{session_id: session.id}

      assert {:ok, message} =
               EditCell.execute(
                 %{
                   "notebook_path" => "session_test.livemd",
                   "cell_index" => 1,
                   "new_source" => "session_value = 42"
                 },
                 context
               )

      assert message =~ "Successfully replaced"

      # Verify the change
      updated_content = File.read!(notebook_path)
      assert updated_content =~ "session_value = 42"
    end

    test "session_id context rejects path traversal", %{session: session} do
      context = %{session_id: session.id}

      assert {:error, error} =
               EditCell.execute(
                 %{
                   "notebook_path" => "../../../etc/passwd",
                   "cell_index" => 0,
                   "new_source" => "malicious"
                 },
                 context
               )

      assert error =~ "Security error"
    end

    test "invalid session_id returns error" do
      context = %{session_id: "not-a-valid-uuid"}

      assert {:error, error} =
               EditCell.execute(
                 %{
                   "notebook_path" => "test.livemd",
                   "cell_index" => 0,
                   "new_source" => "test"
                 },
                 context
               )

      assert error =~ "invalid_session_id" or error =~ "Invalid session ID"
    end

    test "non-existent session_id returns error" do
      # Valid UUID format but no session exists
      context = %{session_id: "550e8400-e29b-41d4-a716-446655440000"}

      assert {:error, error} =
               EditCell.execute(
                 %{
                   "notebook_path" => "test.livemd",
                   "cell_index" => 0,
                   "new_source" => "test"
                 },
                 context
               )

      assert error =~ "not_found" or error =~ "not found"
    end

    test "delete mode uses session_id for path validation", %{tmp_dir: tmp_dir, session: session} do
      # Create test notebook
      notebook_path = Path.join(tmp_dir, "delete_session_test.livemd")
      File.write!(notebook_path, @sample_notebook)

      # Parse to get code cells before delete
      {:ok, notebook_before} = notebook_path |> File.read!() |> Parser.parse()
      code_cells_before = Enum.filter(notebook_before.cells, &Cell.code_cell?/1)
      code_count_before = length(code_cells_before)

      # Use session_id context
      context = %{session_id: session.id}

      assert {:ok, message} =
               EditCell.execute(
                 %{
                   "notebook_path" => "delete_session_test.livemd",
                   "cell_index" => 1,
                   "edit_mode" => "delete"
                 },
                 context
               )

      assert message =~ "Successfully deleted"

      # Verify code cell was removed
      {:ok, notebook_after} = notebook_path |> File.read!() |> Parser.parse()
      code_cells_after = Enum.filter(notebook_after.cells, &Cell.code_cell?/1)

      assert length(code_cells_after) == code_count_before - 1
    end
  end

  # ============================================================================
  # Replace Mode Tests
  # ============================================================================

  describe "EditCell.execute/2 - replace mode" do
    test "replaces cell at valid index", %{tmp_dir: tmp_dir} do
      notebook_path = Path.join(tmp_dir, "test.livemd")
      File.write!(notebook_path, @sample_notebook)

      context = %{project_root: tmp_dir}

      assert {:ok, message} =
               EditCell.execute(
                 %{
                   "notebook_path" => "test.livemd",
                   "cell_index" => 1,
                   "new_source" => "z = 42"
                 },
                 context
               )

      assert message =~ "Successfully replaced"

      # Verify the change
      updated_content = File.read!(notebook_path)
      {:ok, notebook} = Parser.parse(updated_content)

      code_cells = Enum.filter(notebook.cells, &Cell.code_cell?/1)
      assert hd(code_cells).content =~ "z = 42"
    end

    test "preserves cell type when not specified", %{tmp_dir: tmp_dir} do
      notebook_path = Path.join(tmp_dir, "test.livemd")
      File.write!(notebook_path, @sample_notebook)

      context = %{project_root: tmp_dir}

      EditCell.execute(
        %{
          "notebook_path" => "test.livemd",
          "cell_index" => 1,
          "new_source" => "new_code = true"
        },
        context
      )

      {:ok, notebook} = notebook_path |> File.read!() |> Parser.parse()
      code_cells = Enum.filter(notebook.cells, &Cell.code_cell?/1)
      assert hd(code_cells).type == :elixir
    end

    test "changes cell type when specified", %{tmp_dir: tmp_dir} do
      notebook_path = Path.join(tmp_dir, "test.livemd")
      File.write!(notebook_path, @sample_notebook)

      context = %{project_root: tmp_dir}

      EditCell.execute(
        %{
          "notebook_path" => "test.livemd",
          "cell_index" => 0,
          "new_source" => "## New Header",
          "cell_type" => "markdown"
        },
        context
      )

      {:ok, notebook} = notebook_path |> File.read!() |> Parser.parse()
      first_cell = hd(notebook.cells)
      assert first_cell.type == :markdown
      assert first_cell.content =~ "New Header"
    end

    test "returns error for invalid cell index", %{tmp_dir: tmp_dir} do
      notebook_path = Path.join(tmp_dir, "test.livemd")
      File.write!(notebook_path, @sample_notebook)

      context = %{project_root: tmp_dir}

      assert {:error, error} =
               EditCell.execute(
                 %{
                   "notebook_path" => "test.livemd",
                   "cell_index" => 999,
                   "new_source" => "invalid"
                 },
                 context
               )

      assert error =~ "out of bounds"
    end
  end

  describe "EditCell.execute/2 - insert mode" do
    test "inserts cell after specified index", %{tmp_dir: tmp_dir} do
      notebook_path = Path.join(tmp_dir, "test.livemd")
      File.write!(notebook_path, @sample_notebook)

      context = %{project_root: tmp_dir}

      {:ok, notebook_before} = @sample_notebook |> Parser.parse()
      count_before = length(notebook_before.cells)

      assert {:ok, message} =
               EditCell.execute(
                 %{
                   "notebook_path" => "test.livemd",
                   "cell_index" => 0,
                   "new_source" => "inserted_cell = true",
                   "edit_mode" => "insert"
                 },
                 context
               )

      assert message =~ "Successfully inserted"

      {:ok, notebook_after} = notebook_path |> File.read!() |> Parser.parse()
      assert length(notebook_after.cells) == count_before + 1

      # Verify the inserted cell
      inserted_cell = Enum.at(notebook_after.cells, 1)
      assert inserted_cell.content =~ "inserted_cell"
    end

    test "defaults to elixir cell type for insert", %{tmp_dir: tmp_dir} do
      notebook_path = Path.join(tmp_dir, "test.livemd")
      File.write!(notebook_path, @sample_notebook)

      context = %{project_root: tmp_dir}

      EditCell.execute(
        %{
          "notebook_path" => "test.livemd",
          "cell_index" => 0,
          "new_source" => "new_code()",
          "edit_mode" => "insert"
        },
        context
      )

      {:ok, notebook} = notebook_path |> File.read!() |> Parser.parse()
      inserted_cell = Enum.at(notebook.cells, 1)
      assert inserted_cell.type == :elixir
    end

    test "inserts markdown cell when specified", %{tmp_dir: tmp_dir} do
      notebook_path = Path.join(tmp_dir, "test.livemd")
      File.write!(notebook_path, @sample_notebook)

      context = %{project_root: tmp_dir}

      # Insert markdown after the first code cell (index 1) to avoid merging with header
      assert {:ok, _message} =
               EditCell.execute(
                 %{
                   "notebook_path" => "test.livemd",
                   "cell_index" => 1,
                   "new_source" => "## New Section",
                   "cell_type" => "markdown",
                   "edit_mode" => "insert"
                 },
                 context
               )

      # After serialize/parse, the new markdown content should be present
      content = File.read!(notebook_path)
      assert content =~ "## New Section"

      # Note: Adjacent markdown cells merge in .livemd format during round-trip.
      # The content is preserved but as part of a single markdown block.
    end
  end

  describe "EditCell.execute/2 - delete mode" do
    test "deletes cell at valid index", %{tmp_dir: tmp_dir} do
      notebook_path = Path.join(tmp_dir, "test.livemd")
      File.write!(notebook_path, @sample_notebook)

      context = %{project_root: tmp_dir}

      # Parse to get code cells before delete
      {:ok, notebook_before} = notebook_path |> File.read!() |> Parser.parse()
      code_cells_before = Enum.filter(notebook_before.cells, &Cell.code_cell?/1)
      code_count_before = length(code_cells_before)

      # Cell index 1 is the first elixir code cell (x = 1)
      first_code_content = hd(code_cells_before).content

      assert {:ok, message} =
               EditCell.execute(
                 %{
                   "notebook_path" => "test.livemd",
                   "cell_index" => 1,
                   "edit_mode" => "delete"
                 },
                 context
               )

      assert message =~ "Successfully deleted"

      # Verify code cell was removed by checking code cell count
      # Note: Markdown cells may merge after serialize/parse, but code cells are distinct
      {:ok, notebook_after} = notebook_path |> File.read!() |> Parser.parse()
      code_cells_after = Enum.filter(notebook_after.cells, &Cell.code_cell?/1)

      assert length(code_cells_after) == code_count_before - 1

      # The deleted cell's content should no longer be the first code cell
      if length(code_cells_after) > 0 do
        refute hd(code_cells_after).content == first_code_content
      end
    end

    test "returns error for invalid delete index", %{tmp_dir: tmp_dir} do
      notebook_path = Path.join(tmp_dir, "test.livemd")
      File.write!(notebook_path, @sample_notebook)

      context = %{project_root: tmp_dir}

      assert {:error, error} =
               EditCell.execute(
                 %{
                   "notebook_path" => "test.livemd",
                   "cell_index" => 999,
                   "edit_mode" => "delete"
                 },
                 context
               )

      assert error =~ "out of bounds"
    end
  end

  describe "EditCell.execute/2 - security" do
    test "returns error for non-existent notebook", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      assert {:error, error} =
               EditCell.execute(
                 %{
                   "notebook_path" => "missing.livemd",
                   "cell_index" => 0,
                   "new_source" => "test"
                 },
                 context
               )

      assert error =~ "not found"
    end

    test "returns error for path traversal", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      assert {:error, error} =
               EditCell.execute(
                 %{
                   "notebook_path" => "../../../etc/passwd",
                   "cell_index" => 0,
                   "new_source" => "test"
                 },
                 context
               )

      assert error =~ "Security error"
    end

    test "returns error for missing arguments", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      assert {:error, error} = EditCell.execute(%{"notebook_path" => "test.livemd"}, context)
      assert error =~ "requires"
    end
  end
end
