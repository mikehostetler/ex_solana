#!/usr/bin/env elixir
# Run with: mix run examples/code_mapper/simple_runner.exs [path]
#
# Jido CodeMapper v0.1 - Simple single-process demo
#
# This is a simplified version that demonstrates the core functionality:
# - File discovery with gitignore support
# - AST parsing for Elixir files
# - Result aggregation and report generation
#
# Later iterations will add:
# - Multi-agent hierarchy (Root → Folder → File)
# - LLM summarization
# - Embedding generation

Logger.configure(level: :info)

defmodule CodeMapper.Simple do
  @moduledoc """
  Simple codebase mapper - single process, no agents.
  Demonstrates core functionality before adding agent hierarchy.
  """

  require Logger

  @default_extensions [".ex", ".exs"]
  @default_ignore ["_build", "deps", ".elixir_ls", ".git", "node_modules", "test"]

  def map(root_path, opts \\ []) do
    extensions = Keyword.get(opts, :extensions, @default_extensions)
    ignore = Keyword.get(opts, :ignore, @default_ignore)

    IO.puts("\n")
    IO.puts(String.duplicate("=", 70))
    IO.puts("  🗺️  JIDO CODEMAPPER v0.1 - Simple Mode")
    IO.puts(String.duplicate("=", 70))
    IO.puts("\n📂 Target: #{root_path}")

    start_time = System.monotonic_time(:millisecond)

    # Step 1: Discover files
    IO.puts("\n[1/3] Discovering files...")
    files = discover_files(root_path, extensions, ignore)
    IO.puts("      Found #{length(files)} files")

    # Step 2: Parse each file
    IO.puts("\n[2/3] Parsing files...")
    results = parse_all_files(files, root_path)

    # Step 3: Aggregate and report
    IO.puts("\n[3/3] Generating report...")
    report = generate_report(root_path, results, start_time)

    IO.puts("\n")
    IO.puts(report)

    {:ok, results}
  end

  # ============================================================================
  # File Discovery
  # ============================================================================

  defp discover_files(root_path, extensions, ignore_patterns) do
    case git_tracked_files(root_path) do
      {:ok, files} ->
        files
        |> Enum.filter(fn f -> Enum.any?(extensions, &String.ends_with?(f, &1)) end)
        |> Enum.reject(fn f -> should_ignore?(f, ignore_patterns) end)

      :error ->
        manual_discover(root_path, extensions, ignore_patterns)
    end
  end

  defp git_tracked_files(root_path) do
    case System.cmd("git", ["ls-files", "--cached", "--others", "--exclude-standard"],
           cd: root_path,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        files =
          output
          |> String.split("\n", trim: true)
          |> Enum.map(&Path.join(root_path, &1))
          |> Enum.filter(&File.regular?/1)

        {:ok, files}

      _ ->
        :error
    end
  end

  defp manual_discover(root_path, extensions, ignore_patterns) do
    pattern = Path.join([root_path, "**", "*"])

    Path.wildcard(pattern)
    |> Enum.filter(&File.regular?/1)
    |> Enum.filter(fn f -> Enum.any?(extensions, &String.ends_with?(f, &1)) end)
    |> Enum.reject(fn f -> should_ignore?(f, ignore_patterns) end)
  end

  defp should_ignore?(path, patterns) do
    Enum.any?(patterns, fn pattern ->
      String.contains?(path, "/#{pattern}/") or String.contains?(path, "/#{pattern}")
    end)
  end

  # ============================================================================
  # AST Parsing
  # ============================================================================

  defp parse_all_files(files, root_path) do
    total = length(files)

    files
    |> Enum.with_index(1)
    |> Enum.map(fn {file, idx} ->
      relative = Path.relative_to(file, root_path)
      IO.write("\r      [#{idx}/#{total}] #{String.slice(relative, 0, 50)}#{String.duplicate(" ", 30)}")

      result = parse_file(file)
      Map.put(result, :path, file)
    end)
    |> tap(fn _ -> IO.puts("") end)
  end

  defp parse_file(path) do
    case File.read(path) do
      {:ok, source} ->
        case Code.string_to_quoted(source, file: path) do
          {:ok, ast} ->
            extract_from_ast(ast)

          {:error, {line, error, _}} ->
            %{parse_error: "#{error} at line #{line}", modules: [], functions: [], refs: []}
        end

      {:error, reason} ->
        %{read_error: reason, modules: [], functions: [], refs: []}
    end
  end

  defp extract_from_ast(ast) do
    acc = %{modules: [], functions: [], imports: [], aliases: [], uses: []}
    result = walk_ast(ast, acc)

    public_fns =
      result.functions
      |> Enum.filter(fn f -> f.visibility == :public end)

    refs =
      Enum.map(result.imports, fn mod -> %{to: mod, type: :import} end) ++
        Enum.map(result.aliases, fn mod -> %{to: mod, type: :alias} end) ++
        Enum.map(result.uses, fn mod -> %{to: mod, type: :use} end)

    %{
      modules: result.modules,
      functions: public_fns,
      refs: refs,
      imports: result.imports,
      aliases: result.aliases,
      uses: result.uses
    }
  end

  defp walk_ast(ast, acc) do
    {_, acc} =
      Macro.prewalk(ast, acc, fn
        {:defmodule, _, [{:__aliases__, _, parts} | _]} = node, acc ->
          mod_name = Enum.join(parts, ".")
          {node, %{acc | modules: [mod_name | acc.modules]}}

        {:def, _, [{name, _, args} | _]} = node, acc when is_atom(name) ->
          arity = if is_list(args), do: length(args), else: 0
          func = %{name: name, arity: arity, visibility: :public}
          {node, %{acc | functions: [func | acc.functions]}}

        {:defp, _, [{name, _, args} | _]} = node, acc when is_atom(name) ->
          arity = if is_list(args), do: length(args), else: 0
          func = %{name: name, arity: arity, visibility: :private}
          {node, %{acc | functions: [func | acc.functions]}}

        {:import, _, [{:__aliases__, _, parts} | _]} = node, acc ->
          mod_name = Enum.join(parts, ".")
          {node, %{acc | imports: [mod_name | acc.imports]}}

        {:alias, _, [{:__aliases__, _, parts} | _]} = node, acc ->
          mod_name = Enum.join(parts, ".")
          {node, %{acc | aliases: [mod_name | acc.aliases]}}

        {:use, _, [{:__aliases__, _, parts} | _]} = node, acc ->
          mod_name = Enum.join(parts, ".")
          {node, %{acc | uses: [mod_name | acc.uses]}}

        node, acc ->
          {node, acc}
      end)

    acc
  end

  # ============================================================================
  # Report Generation
  # ============================================================================

  defp generate_report(root_path, results, start_time) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    all_modules =
      results
      |> Enum.flat_map(fn r -> r[:modules] || [] end)
      |> Enum.uniq()
      |> Enum.sort()

    all_functions =
      results
      |> Enum.flat_map(fn r -> r[:functions] || [] end)

    all_refs =
      results
      |> Enum.flat_map(fn r -> r[:refs] || [] end)
      |> Enum.uniq()

    # Group by folder
    by_folder =
      results
      |> Enum.group_by(fn r ->
        r.path
        |> Path.dirname()
        |> Path.relative_to(root_path)
      end)

    """
    ================================================================================
    JIDO CODEBASE MAP
    ================================================================================

    Root: #{root_path}
    Files: #{length(results)}
    Time: #{elapsed}ms

    --------------------------------------------------------------------------------
    MODULES (#{length(all_modules)})
    --------------------------------------------------------------------------------
    #{all_modules |> Enum.map(&"  • #{&1}") |> Enum.join("\n")}

    --------------------------------------------------------------------------------
    PUBLIC FUNCTIONS (#{length(all_functions)})
    --------------------------------------------------------------------------------
    #{all_functions |> Enum.take(30) |> Enum.map(&format_fn/1) |> Enum.join("\n")}
    #{if length(all_functions) > 30, do: "  ... and #{length(all_functions) - 30} more", else: ""}

    --------------------------------------------------------------------------------
    DEPENDENCIES (#{length(all_refs)})
    --------------------------------------------------------------------------------
    #{all_refs |> Enum.take(20) |> Enum.map(&format_ref/1) |> Enum.join("\n")}
    #{if length(all_refs) > 20, do: "  ... and #{length(all_refs) - 20} more", else: ""}

    --------------------------------------------------------------------------------
    FOLDERS (#{map_size(by_folder)})
    --------------------------------------------------------------------------------
    #{by_folder |> Enum.map(&format_folder/1) |> Enum.join("\n")}

    ================================================================================
    """
  end

  defp format_fn(f) do
    "  • #{f.name}/#{f.arity}"
  end

  defp format_ref(ref) do
    "  • #{ref.type}: #{ref.to}"
  end

  defp format_folder({folder, files}) do
    modules =
      files
      |> Enum.flat_map(fn r -> r[:modules] || [] end)
      |> Enum.uniq()

    """
    📁 #{folder}
       Files: #{length(files)}
       Modules: #{Enum.join(modules, ", ")}
    """
  end
end

# Main
args = System.argv()

target_path =
  case args do
    [path | _] -> Path.expand(path)
    [] ->
      project_root = Path.dirname(Path.dirname(__DIR__))
      Path.join(project_root, "lib/jido")
  end

CodeMapper.Simple.map(target_path)
