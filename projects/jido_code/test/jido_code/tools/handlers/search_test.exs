defmodule JidoCode.Tools.Handlers.SearchTest do
  # async: false because we're modifying the shared Manager state
  use ExUnit.Case, async: false

  alias JidoCode.Tools.Handlers.Search.{FindFiles, Grep}

  @moduletag :tmp_dir

  # Set up Manager with tmp_dir as project root for sandboxed operations
  setup %{tmp_dir: tmp_dir} do
    JidoCode.TestHelpers.ManagerIsolation.set_project_root(tmp_dir)
    :ok
  end

  # ============================================================================
  # Session Context Tests
  # ============================================================================

  describe "session-aware context" do
    setup %{tmp_dir: tmp_dir} do
      # Set dummy API key for test
      System.put_env("ANTHROPIC_API_KEY", "test-key-search-handler")

      on_exit(fn ->
        System.delete_env("ANTHROPIC_API_KEY")
      end)

      # Start required registries if not already started
      unless Process.whereis(JidoCode.SessionProcessRegistry) do
        start_supervised!({Registry, keys: :unique, name: JidoCode.SessionProcessRegistry})
      end

      # Create a session
      {:ok, session} = JidoCode.Session.new(project_path: tmp_dir, name: "search-session-test")

      {:ok, supervisor_pid} =
        JidoCode.Session.Supervisor.start_link(
          session: session,
          name: {:via, Registry, {JidoCode.Registry, {:search_session_test_sup, session.id}}}
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

    test "Grep uses session_id for path validation", %{tmp_dir: tmp_dir, session: session} do
      # Create test file
      File.write!(Path.join(tmp_dir, "session_grep.ex"), "defmodule Test do\nend")

      # Use session_id context
      context = %{session_id: session.id}
      {:ok, json} = Grep.execute(%{"pattern" => "defmodule", "path" => ""}, context)

      results = Jason.decode!(json)
      assert length(results) == 1
      assert hd(results)["file"] == "session_grep.ex"
    end

    test "FindFiles uses session_id for path validation", %{tmp_dir: tmp_dir, session: session} do
      # Create test file
      File.write!(Path.join(tmp_dir, "session_find.ex"), "")

      # Use session_id context
      context = %{session_id: session.id}
      {:ok, json} = FindFiles.execute(%{"pattern" => "session_find.ex"}, context)

      results = Jason.decode!(json)
      assert results == ["session_find.ex"]
    end

    test "session_id context rejects path traversal in Grep", %{session: session} do
      context = %{session_id: session.id}

      {:error, error} = Grep.execute(%{"pattern" => "test", "path" => "../../../etc"}, context)
      assert error =~ "Security error"
    end

    test "session_id context rejects path traversal in FindFiles", %{session: session} do
      context = %{session_id: session.id}

      {:error, error} =
        FindFiles.execute(%{"pattern" => "*.ex", "path" => "../../../etc"}, context)

      assert error =~ "Security error"
    end

    test "invalid session_id returns error in Grep" do
      context = %{session_id: "not-a-valid-uuid"}
      {:error, error} = Grep.execute(%{"pattern" => "test", "path" => ""}, context)
      assert error =~ "invalid_session_id" or error =~ "Invalid session ID"
    end

    test "invalid session_id returns error in FindFiles" do
      context = %{session_id: "not-a-valid-uuid"}
      {:error, error} = FindFiles.execute(%{"pattern" => "*.ex"}, context)
      assert error =~ "invalid_session_id" or error =~ "Invalid session ID"
    end
  end

  # ============================================================================
  # Grep Tests
  # ============================================================================

  describe "Grep.execute/2" do
    test "finds pattern in file", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "test.ex"), """
      defmodule Test do
        def hello do
          :world
        end

        def hello_world do
          :ok
        end
      end
      """)

      context = %{project_root: tmp_dir}
      {:ok, json} = Grep.execute(%{"pattern" => "def hello", "path" => ""}, context)

      results = Jason.decode!(json)
      assert length(results) == 2
      assert Enum.any?(results, &(&1["line"] == 2 && &1["content"] =~ "def hello do"))
      assert Enum.any?(results, &(&1["line"] == 6 && &1["content"] =~ "def hello_world"))
    end

    test "returns file path and line number", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "lib"))
      File.write!(Path.join(tmp_dir, "lib/main.ex"), "defmodule Main do\nend")

      context = %{project_root: tmp_dir}
      {:ok, json} = Grep.execute(%{"pattern" => "defmodule", "path" => "lib"}, context)

      results = Jason.decode!(json)
      assert [result] = results
      assert result["file"] == "lib/main.ex"
      assert result["line"] == 1
      assert result["content"] =~ "defmodule Main"
    end

    test "searches recursively by default", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "a/b/c"))
      File.write!(Path.join(tmp_dir, "a/b/c/deep.ex"), "# TODO: fix this")

      context = %{project_root: tmp_dir}
      {:ok, json} = Grep.execute(%{"pattern" => "TODO", "path" => "a"}, context)

      results = Jason.decode!(json)
      assert length(results) == 1
      assert hd(results)["file"] == "a/b/c/deep.ex"
    end

    test "respects recursive=false", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "lib/sub"))
      File.write!(Path.join(tmp_dir, "lib/top.ex"), "# MARKER")
      File.write!(Path.join(tmp_dir, "lib/sub/nested.ex"), "# MARKER")

      context = %{project_root: tmp_dir}

      {:ok, json} =
        Grep.execute(%{"pattern" => "MARKER", "path" => "lib", "recursive" => false}, context)

      results = Jason.decode!(json)
      assert length(results) == 1
      assert hd(results)["file"] == "lib/top.ex"
    end

    test "respects max_results limit", %{tmp_dir: tmp_dir} do
      # Create file with many matches
      content = Enum.map_join(1..50, "\n", fn i -> "line #{i} match" end)
      File.write!(Path.join(tmp_dir, "many.txt"), content)

      context = %{project_root: tmp_dir}

      {:ok, json} =
        Grep.execute(%{"pattern" => "match", "path" => "", "max_results" => 10}, context)

      results = Jason.decode!(json)
      assert length(results) == 10
    end

    test "searches single file", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "single.ex"), "def foo\ndef bar")

      context = %{project_root: tmp_dir}
      {:ok, json} = Grep.execute(%{"pattern" => "def", "path" => "single.ex"}, context)

      results = Jason.decode!(json)
      assert length(results) == 2
    end

    test "returns empty array when no matches", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "empty.ex"), "nothing here")

      context = %{project_root: tmp_dir}
      {:ok, json} = Grep.execute(%{"pattern" => "notfound", "path" => ""}, context)

      assert Jason.decode!(json) == []
    end

    test "supports regex patterns", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "regex.ex"), """
      def hello_world
      def hello_there
      def goodbye
      """)

      context = %{project_root: tmp_dir}
      {:ok, json} = Grep.execute(%{"pattern" => "def hello_\\w+", "path" => ""}, context)

      results = Jason.decode!(json)
      assert length(results) == 2
    end

    test "returns error for invalid regex", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      {:error, error} = Grep.execute(%{"pattern" => "[invalid", "path" => ""}, context)
      assert error =~ "Invalid regex"
    end

    test "returns error for path traversal", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      {:error, error} = Grep.execute(%{"pattern" => "test", "path" => "../../../etc"}, context)
      assert error =~ "Security error"
    end

    test "returns error for missing arguments", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      {:error, error} = Grep.execute(%{"pattern" => "test"}, context)
      assert error =~ "requires pattern and path"
    end
  end

  # ============================================================================
  # FindFiles Tests
  # ============================================================================

  describe "FindFiles.execute/2" do
    test "finds files by exact name", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "lib"))
      File.write!(Path.join(tmp_dir, "lib/main.ex"), "")
      File.write!(Path.join(tmp_dir, "mix.exs"), "")

      context = %{project_root: tmp_dir}
      {:ok, json} = FindFiles.execute(%{"pattern" => "mix.exs"}, context)

      results = Jason.decode!(json)
      assert results == ["mix.exs"]
    end

    test "finds files by glob pattern", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "lib"))
      File.write!(Path.join(tmp_dir, "lib/a.ex"), "")
      File.write!(Path.join(tmp_dir, "lib/b.ex"), "")
      File.write!(Path.join(tmp_dir, "lib/c.txt"), "")

      context = %{project_root: tmp_dir}
      {:ok, json} = FindFiles.execute(%{"pattern" => "*.ex"}, context)

      results = Jason.decode!(json)
      assert length(results) == 2
      assert "lib/a.ex" in results
      assert "lib/b.ex" in results
    end

    test "finds files recursively", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "a/b/c"))
      File.write!(Path.join(tmp_dir, "top.ex"), "")
      File.write!(Path.join(tmp_dir, "a/level1.ex"), "")
      File.write!(Path.join(tmp_dir, "a/b/c/deep.ex"), "")

      context = %{project_root: tmp_dir}
      {:ok, json} = FindFiles.execute(%{"pattern" => "*.ex"}, context)

      results = Jason.decode!(json)
      assert length(results) == 3
    end

    test "searches within specified path", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "lib"))
      File.mkdir_p!(Path.join(tmp_dir, "test"))
      File.write!(Path.join(tmp_dir, "lib/code.ex"), "")
      File.write!(Path.join(tmp_dir, "test/code_test.ex"), "")

      context = %{project_root: tmp_dir}
      {:ok, json} = FindFiles.execute(%{"pattern" => "*.ex", "path" => "lib"}, context)

      results = Jason.decode!(json)
      assert results == ["lib/code.ex"]
    end

    test "respects max_results limit", %{tmp_dir: tmp_dir} do
      # Create many files
      Enum.each(1..20, fn i ->
        File.write!(Path.join(tmp_dir, "file#{i}.ex"), "")
      end)

      context = %{project_root: tmp_dir}
      {:ok, json} = FindFiles.execute(%{"pattern" => "*.ex", "max_results" => 5}, context)

      results = Jason.decode!(json)
      assert length(results) == 5
    end

    test "returns empty array when no matches", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "file.txt"), "")

      context = %{project_root: tmp_dir}
      {:ok, json} = FindFiles.execute(%{"pattern" => "*.ex"}, context)

      assert Jason.decode!(json) == []
    end

    test "supports complex glob patterns", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "test"))
      File.write!(Path.join(tmp_dir, "test/foo_test.exs"), "")
      File.write!(Path.join(tmp_dir, "test/bar_test.exs"), "")
      File.write!(Path.join(tmp_dir, "test/helper.ex"), "")

      context = %{project_root: tmp_dir}
      {:ok, json} = FindFiles.execute(%{"pattern" => "*_test.exs"}, context)

      results = Jason.decode!(json)
      assert length(results) == 2
      assert Enum.all?(results, &String.ends_with?(&1, "_test.exs"))
    end

    test "returns error for path traversal", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      {:error, error} =
        FindFiles.execute(%{"pattern" => "*.ex", "path" => "../../../etc"}, context)

      assert error =~ "Security error"
    end

    test "returns error for missing pattern", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      {:error, error} = FindFiles.execute(%{}, context)
      assert error =~ "requires a pattern"
    end

    test "finds files with path in pattern", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "src/components"))
      File.write!(Path.join(tmp_dir, "src/components/button.ex"), "")

      context = %{project_root: tmp_dir}
      {:ok, json} = FindFiles.execute(%{"pattern" => "src/**/*.ex"}, context)

      results = Jason.decode!(json)
      assert "src/components/button.ex" in results
    end
  end
end
