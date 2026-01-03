defmodule CodeMapper.Strategy.MapperStrategy do
  @moduledoc """
  Custom strategy for CodeMapper agents.

  Handles signal routing for:
  - root.start → Start codebase mapping
  - folder.process → Process a folder
  - file.process → Process a file
  - file.done → File analysis complete
  - folder.done → Folder analysis complete
  - jido.agent.child.started → Child agent ready

  Features:
  - Rate-limited agent spawning for dramatic demo effect
  - DETS-based caching to avoid re-parsing unchanged files
  - Batched folder processing (max concurrent folders)
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Directive
  alias Jido.Signal
  alias CodeMapper.Cache

  require Logger

  @max_concurrent_folders 5
  @demo_spawn_delay_ms 25
  @max_files_per_batch 15

  # ============================================================================
  # Strategy Callbacks
  # ============================================================================

  @impl true
  def cmd(%Agent{} = agent, instructions, ctx) do
    Enum.reduce(instructions, {agent, []}, fn instruction, {acc_agent, acc_directives} ->
      {new_agent, new_directives} = handle_instruction(acc_agent, instruction, ctx)
      {new_agent, acc_directives ++ new_directives}
    end)
  end

  @impl true
  def signal_routes(_ctx) do
    [
      {"root.start", {:strategy_cmd, :root_start}},
      {"root.spawn_batch", {:strategy_cmd, :spawn_folder_batch}},
      {"folder.process", {:strategy_cmd, :folder_process}},
      {"folder.spawn_batch", {:strategy_cmd, :spawn_file_batch}},
      {"file.process", {:strategy_cmd, :file_process}},
      {"file.done", {:strategy_cmd, :file_done}},
      {"folder.done", {:strategy_cmd, :folder_done}},
      {"jido.agent.child.started", {:strategy_cmd, :child_started}}
    ]
  end

  # ============================================================================
  # Command Handlers
  # ============================================================================

  defp handle_instruction(agent, %{action: :root_start, params: params}, _ctx) do
    root_path = params[:path] || params["path"] || File.cwd!()
    extensions = params[:extensions] || [".ex", ".exs"]
    ignore_patterns = params[:ignore] || default_ignore_patterns()
    max_folders = params[:max_folders] || @max_concurrent_folders

    IO.puts("\n┌─────────────────────────────────────────────────────────────────┐")
    IO.puts("│  🔍 DISCOVERING FILES                                           │")
    IO.puts("└─────────────────────────────────────────────────────────────────┘")

    files = discover_files(root_path, extensions, ignore_patterns)
    folders = partition_by_folder(files, root_path)
    folder_paths = Map.keys(folders) |> Enum.sort()
    
    total_files = length(files)
    
    IO.puts("\n   📂 Root: #{root_path}")
    IO.puts("   📄 Files: #{total_files}")
    IO.puts("   📁 Folders: #{length(folder_paths)}")

    # Auto-clamp concurrency based on codebase size to prevent cascade failures
    # Key insight: limit TOTAL concurrent agents, not just per-level
    schedulers = :erlang.system_info(:schedulers_online)

    {max_folders, max_files_per_batch} =
      cond do
        params[:sequential] ->
          {1, 5}

        total_files > 5_000 ->
          IO.puts("   ⚠️  Large codebase detected (#{total_files} files), auto-clamping concurrency")
          {min(max_folders, 5), min(params[:max_files] || @max_files_per_batch, 8)}

        total_files > 1_000 ->
          IO.puts("   ⚡ Medium-large codebase (#{total_files} files), using scheduler-based concurrency")
          {min(max_folders, schedulers), min(params[:max_files] || @max_files_per_batch, 12)}

        total_files > 200 ->
          {min(max_folders, schedulers), min(params[:max_files] || @max_files_per_batch, 15)}

        true ->
          # Small repos: use full concurrency
          {max_folders, params[:max_files] || @max_files_per_batch}
      end

    IO.puts("   ⚙️  Max concurrent: #{max_folders} folders, #{max_files_per_batch} files/batch")

    demo_mode? = params[:demo_mode] || System.get_env("CODEMAPPER_DEMO") in ["1", "true", "TRUE"]
    spawn_delay_ms = if demo_mode?, do: @demo_spawn_delay_ms, else: 0

    agent = %{
      agent
      | state:
          Map.merge(agent.state, %{
            root_path: root_path,
            all_files: files,
            folders: folders,
            pending_folders: folder_paths,
            spawned_folders: [],
            active_folders: 0,
            max_concurrent_folders: max_folders,
            max_files_per_batch: max_files_per_batch,
            sequential: params[:sequential] || false,
            spawn_delay_ms: spawn_delay_ms,
            status: :spawning_folders,
            stats: %{
              total_files: length(files),
              total_folders: length(folder_paths),
              start_time: System.monotonic_time(:millisecond),
              cache_hits: 0,
              cache_misses: 0,
              folder_agents_spawned: 0,
              file_agents_spawned: 0
            }
          })
    }

    IO.puts("\n┌─────────────────────────────────────────────────────────────────┐")
    IO.puts("│  🚀 SPAWNING AGENTS                                             │")
    IO.puts("└─────────────────────────────────────────────────────────────────┘\n")

    spawn_next_folder_batch(agent)
  end

  defp handle_instruction(agent, %{action: :spawn_folder_batch}, _ctx) do
    spawn_next_folder_batch(agent)
  end

  defp handle_instruction(agent, %{action: :folder_process, params: params}, _ctx) do
    folder_path = params[:folder_path] || params["folder_path"]
    files = params[:files] || params["files"] || []
    max_files = params[:max_files] || @max_files_per_batch
    spawn_delay_ms = params[:spawn_delay_ms] || 0

    IO.puts("         └─ Processing #{length(files)} files")

    agent = %{
      agent
      | state:
          Map.merge(agent.state, %{
            folder_path: folder_path,
            files: files,
            pending_files: files,
            spawned_files: [],
            active_files: 0,
            max_files_per_batch: max_files,
            spawn_delay_ms: spawn_delay_ms,
            status: :spawning_workers
          })
    }

    spawn_next_file_batch(agent)
  end

  defp handle_instruction(agent, %{action: :spawn_file_batch}, _ctx) do
    spawn_next_file_batch(agent)
  end

  defp handle_instruction(agent, %{action: :file_process, params: params}, _ctx) do
    path = params[:path] || params["path"]
    
    case Cache.get(path) do
      {:ok, cached_result} ->
        IO.write("·")
        
        agent = %{
          agent
          | state:
              Map.merge(agent.state, %{
                path: path,
                status: :completed,
                file_result: cached_result
              })
        }

        result_signal = Signal.new!("file.done", %{file: cached_result, cached: true}, source: "/file")
        emit_directive = Directive.emit_to_parent(agent, result_signal)

        {agent, List.wrap(emit_directive)}

      nil ->
        IO.write("○")
        
        {ast_meta, refs, public_api} = parse_file(path)

        file_result = %{
          path: path,
          language: "elixir",
          ast_meta: ast_meta,
          refs: refs,
          public_api: public_api,
          summary: "[PARSED] #{Path.basename(path)}"
        }

        Cache.put(path, file_result)

        agent = %{
          agent
          | state:
              Map.merge(agent.state, %{
                path: path,
                status: :completed,
                file_result: file_result
              })
        }

        result_signal = Signal.new!("file.done", %{file: file_result, cached: false}, source: "/file")
        emit_directive = Directive.emit_to_parent(agent, result_signal)

        {agent, List.wrap(emit_directive)}
    end
  end

  defp handle_instruction(agent, %{action: :file_done, params: params}, _ctx) do
    file_result = params[:file] || params["file"]
    file_path = file_result[:path] || file_result["path"]
    cached = params[:cached] || false

    pending = List.delete(agent.state[:pending_files] || [], file_path)
    results = [file_result | (agent.state[:file_results] || [])]
    active = max(0, (agent.state[:active_files] || 1) - 1)
    
    stats = agent.state[:stats] || %{}
    stats = if cached do
      Map.update(stats, :cache_hits, 1, &(&1 + 1))
    else
      Map.update(stats, :cache_misses, 1, &(&1 + 1))
    end

    agent = %{
      agent
      | state:
          Map.merge(agent.state, %{
            pending_files: pending,
            file_results: results,
            active_files: active,
            stats: stats
          })
    }

    cond do
      pending == [] and active == 0 ->
        complete_folder(agent)
        
      agent.state[:pending_files] != [] ->
        spawn_next_file_batch(agent)
        
      true ->
        {agent, []}
    end
  end

  defp handle_instruction(agent, %{action: :folder_done, params: params}, _ctx) do
    folder_result = params[:folder] || params["folder"]
    folder_path = folder_result[:path] || folder_result["path"]

    file_count = folder_result[:file_count] || 0
    short_path = if String.length(folder_path) > 40, do: "..." <> String.slice(folder_path, -37, 37), else: folder_path
    IO.puts(" ✓ #{short_path} (#{file_count})")

    pending = List.delete(agent.state[:pending_folders] || [], folder_path)
    results = [folder_result | (agent.state[:folder_results] || [])]
    active = max(0, (agent.state[:active_folders] || 1) - 1)

    agent = %{
      agent
      | state:
          Map.merge(agent.state, %{
            pending_folders: pending,
            folder_results: results,
            active_folders: active
          })
    }

    cond do
      pending == [] and active == 0 ->
        complete_mapping(agent)
        
      agent.state[:pending_folders] != [] ->
        spawn_next_folder_batch(agent)
        
      true ->
        {agent, []}
    end
  end

  defp handle_instruction(agent, %{action: :child_started, params: data}, _ctx) do
    case data.tag do
      {:folder, folder_path, _idx} ->
        folder_children = Map.put(agent.state[:folder_children] || %{}, folder_path, data.pid)
        files = Map.get(agent.state[:folders] || %{}, folder_path, [])

        work_signal =
          Signal.new!(
            "folder.process",
            %{
              folder_path: folder_path,
              files: files,
              spawn_delay_ms: agent.state[:spawn_delay_ms] || 0,
              max_files: agent.state[:max_files_per_batch] || @max_files_per_batch
            },
            source: "/root"
          )

        agent = %{
          agent
          | state: Map.put(agent.state, :folder_children, folder_children)
        }

        {agent, [Directive.emit_to_pid(work_signal, data.pid)]}

      {:file, file_path, _idx} ->
        file_children = Map.put(agent.state[:file_children] || %{}, file_path, data.pid)

        work_signal =
          Signal.new!(
            "file.process",
            %{path: file_path},
            source: "/folder"
          )

        agent = %{
          agent
          | state: Map.put(agent.state, :file_children, file_children)
        }

        {agent, [Directive.emit_to_pid(work_signal, data.pid)]}

      _ ->
        {agent, []}
    end
  end

  defp handle_instruction(agent, instruction, _ctx) do
    Logger.warning("[MapperStrategy] Unhandled instruction: #{inspect(instruction.action)}")
    {agent, []}
  end

  # ============================================================================
  # Batch Spawning Helpers
  # ============================================================================

  defp spawn_next_folder_batch(%{state: %{status: status}} = agent)
       when status in [:completed, :shutting_down] do
    {agent, []}
  end

  defp spawn_next_folder_batch(agent) do
    state = agent.state
    pending = state[:pending_folders] || []
    active = state[:active_folders] || 0
    max_concurrent = state[:max_concurrent_folders] || @max_concurrent_folders
    spawned = state[:spawned_folders] || []
    spawn_delay_ms = state[:spawn_delay_ms] || 0

    available_slots = max_concurrent - active

    if available_slots > 0 and pending != [] do
      {to_spawn, remaining} = Enum.split(pending, available_slots)

      spawn_directives =
        to_spawn
        |> Enum.with_index(length(spawned))
        |> Enum.flat_map(fn {folder_path, idx} ->
          if spawn_delay_ms > 0, do: Process.sleep(spawn_delay_ms)

          short_path = String.slice(folder_path, -40, 40)
          progress = "#{idx + 1}/#{state[:stats][:total_folders]}"
          IO.puts("   [#{progress}] 📁 #{short_path}")

          tag = {:folder, folder_path, idx}
          folder_id = "folder-#{idx}-#{:erlang.phash2(folder_path)}"
          [Directive.spawn_agent(CodeMapper.FolderAgent, tag, opts: %{id: folder_id})]
        end)

      new_stats =
        Map.update(state[:stats] || %{}, :folder_agents_spawned, length(to_spawn), &(&1 + length(to_spawn)))

      agent = %{
        agent
        | state:
            Map.merge(state, %{
              pending_folders: remaining,
              spawned_folders: spawned ++ to_spawn,
              active_folders: active + length(to_spawn),
              stats: new_stats
            })
      }

      {agent, spawn_directives}
    else
      if pending == [] and active == 0 do
        complete_mapping(agent)
      else
        {agent, []}
      end
    end
  end

  defp spawn_next_file_batch(%{state: %{status: status}} = agent)
       when status in [:completed, :shutting_down] do
    {agent, []}
  end

  defp spawn_next_file_batch(agent) do
    state = agent.state
    pending = state[:pending_files] || []
    active = state[:active_files] || 0
    max_batch = state[:max_files_per_batch] || @max_files_per_batch
    spawned = state[:spawned_files] || []
    spawn_delay_ms = state[:spawn_delay_ms] || 0

    available_slots = max_batch - active

    if available_slots > 0 and pending != [] do
      {to_spawn, remaining} = Enum.split(pending, available_slots)

      spawn_directives =
        to_spawn
        |> Enum.with_index(length(spawned))
        |> Enum.flat_map(fn {file_path, idx} ->
          if spawn_delay_ms > 0, do: Process.sleep(div(spawn_delay_ms, 2))

          tag = {:file, file_path, idx}
          file_id = "file-#{idx}-#{:erlang.phash2(file_path)}"
          [Directive.spawn_agent(CodeMapper.FileAgent, tag, opts: %{id: file_id})]
        end)

      new_stats =
        Map.update(state[:stats] || %{}, :file_agents_spawned, length(to_spawn), &(&1 + length(to_spawn)))

      agent = %{
        agent
        | state:
            Map.merge(state, %{
              pending_files: remaining,
              spawned_files: spawned ++ to_spawn,
              active_files: active + length(to_spawn),
              stats: new_stats
            })
      }

      {agent, spawn_directives}
    else
      if pending == [] and active == 0 do
        complete_folder(agent)
      else
        {agent, []}
      end
    end
  end

  # ============================================================================
  # File Discovery
  # ============================================================================

  defp default_ignore_patterns do
    [
      "_build", "deps", ".elixir_ls", ".git", "node_modules", "test",
      ".code_mapper_cache", "priv", "cover", ".github", "tmp"
    ]
  end

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

  defp partition_by_folder(files, root_path) do
    files
    |> Enum.group_by(fn file ->
      file
      |> Path.dirname()
      |> Path.relative_to(root_path)
    end)
  end

  # ============================================================================
  # AST Parsing
  # ============================================================================

  defp parse_file(path) do
    case File.read(path) do
      {:ok, source} ->
        parse_elixir_source(source, path)

      {:error, reason} ->
        Logger.warning("[FileAgent] Failed to read #{path}: #{reason}")
        {%{error: reason}, [], []}
    end
  end

  defp parse_elixir_source(source, path) do
    case Code.string_to_quoted(source, file: path) do
      {:ok, ast} ->
        extract_from_ast(ast)

      {:error, {line, error, _}} ->
        error_str = if is_binary(error), do: error, else: inspect(error)
        {%{parse_error: error_str, line: line}, [], []}

      {:error, error} ->
        {%{parse_error: inspect(error)}, [], []}
    end
  end

  defp extract_from_ast(ast) do
    acc = %{modules: [], functions: [], imports: [], aliases: [], uses: []}
    result = walk_ast(ast, acc)

    ast_meta = %{
      modules: result.modules,
      functions: result.functions,
      imports: result.imports,
      aliases: result.aliases,
      uses: result.uses
    }

    refs =
      Enum.map(result.imports, fn mod -> %{to: mod, type: :import} end) ++
        Enum.map(result.aliases, fn mod -> %{to: mod, type: :alias} end) ++
        Enum.map(result.uses, fn mod -> %{to: mod, type: :use} end)

    public_api =
      result.functions
      |> Enum.filter(fn f -> f.visibility == :public end)
      |> Enum.map(fn f -> %{name: f.name, arity: f.arity, kind: :function} end)

    {ast_meta, refs, public_api}
  end

  defp walk_ast(ast, acc) do
    try do
      {_, acc} =
        Macro.prewalk(ast, acc, fn
          {:defmodule, _, [{:__aliases__, _, parts} | _]} = node, acc ->
            mod_name = safe_join_parts(parts)
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
            mod_name = safe_join_parts(parts)
            {node, %{acc | imports: [mod_name | acc.imports]}}

          {:alias, _, [{:__aliases__, _, parts} | _]} = node, acc ->
            mod_name = safe_join_parts(parts)
            {node, %{acc | aliases: [mod_name | acc.aliases]}}

          {:use, _, [{:__aliases__, _, parts} | _]} = node, acc ->
            mod_name = safe_join_parts(parts)
            {node, %{acc | uses: [mod_name | acc.uses]}}

          node, acc ->
            {node, acc}
        end)

      acc
    rescue
      _ -> acc
    end
  end

  defp safe_join_parts(parts) when is_list(parts) do
    parts
    |> Enum.map(fn
      atom when is_atom(atom) -> Atom.to_string(atom)
      {:__MODULE__, _, _} -> "__MODULE__"
      {atom, _, _} when is_atom(atom) -> Atom.to_string(atom)
      other -> inspect(other)
    end)
    |> Enum.join(".")
  end

  defp safe_join_parts(other), do: inspect(other)

  # ============================================================================
  # Completion Handlers
  # ============================================================================

  defp complete_folder(%{state: %{status: status}} = agent) when status in [:completed, :shutting_down] do
    {agent, []}
  end

  defp complete_folder(agent) do
    file_results = agent.state[:file_results] || []
    file_agents_spawned = (agent.state[:stats] || %{})[:file_agents_spawned] || length(file_results)

    folder_result = %{
      path: agent.state[:folder_path],
      file_count: length(file_results),
      file_agents_spawned: file_agents_spawned,
      files: Enum.map(file_results, & &1[:path]),
      all_modules:
        file_results
        |> Enum.flat_map(fn f -> (f[:ast_meta] || %{})[:modules] || [] end)
        |> Enum.uniq(),
      all_public_api:
        file_results
        |> Enum.flat_map(fn f -> f[:public_api] || [] end),
      all_refs:
        file_results
        |> Enum.flat_map(fn f -> f[:refs] || [] end)
    }

    agent = %{
      agent
      | state: Map.merge(agent.state, %{status: :shutting_down})
    }

    result_signal = Signal.new!("folder.done", %{folder: folder_result}, source: "/folder")
    emit_directive = Directive.emit_to_parent(agent, result_signal)

    {agent, List.wrap(emit_directive)}
  end

  defp complete_mapping(%{state: %{status: status}} = agent) when status in [:completed, :shutting_down] do
    {agent, []}
  end

  defp complete_mapping(agent) do
    elapsed =
      System.monotonic_time(:millisecond) - (agent.state[:stats][:start_time] || 0)

    folder_results = agent.state[:folder_results] || []

    all_modules =
      folder_results
      |> Enum.flat_map(fn f -> f[:all_modules] || [] end)
      |> Enum.uniq()

    # Aggregate file agent counts from all folder results
    total_file_agents =
      folder_results
      |> Enum.map(fn f -> f[:file_agents_spawned] || f[:file_count] || 0 end)
      |> Enum.sum()

    cache_stats = Cache.stats()
    
    report = build_report(agent, all_modules, elapsed, cache_stats, total_file_agents)

    agent = %{
      agent
      | state:
          Map.merge(agent.state, %{
            status: :completed,
            report: report,
            stats:
            Map.merge(agent.state[:stats] || %{}, %{
              elapsed_ms: elapsed,
              total_modules: length(all_modules),
              cache_hits: cache_stats[:hits],
              cache_misses: cache_stats[:misses],
              file_agents_spawned: total_file_agents,
              total_agents: 1 + (agent.state[:stats][:folder_agents_spawned] || 0) + total_file_agents
            })
          })
    }

    {agent, []}
  end

  defp build_report(agent, all_modules, elapsed, cache_stats, total_file_agents) do
    folder_results = agent.state[:folder_results] || []
    folder_agents = agent.state[:stats][:folder_agents_spawned] || 0
    
    top_folders = 
      folder_results
      |> Enum.sort_by(fn f -> -(f[:file_count] || 0) end)
      |> Enum.take(10)
      |> Enum.map(fn f -> "   📁 #{f[:path]} (#{f[:file_count]} files)" end)
      |> Enum.join("\n")

    """

    ╔═══════════════════════════════════════════════════════════════════╗
    ║                     JIDO CODEBASE MAP                             ║
    ║                   Multi-Agent Analysis                            ║
    ╚═══════════════════════════════════════════════════════════════════╝

    ┌─────────────────────────────────────────────────────────────────┐
    │  📊 STATISTICS                                                  │
    └─────────────────────────────────────────────────────────────────┘

       Root: #{agent.state[:root_path]}
       
       📄 Files:     #{agent.state[:stats][:total_files]}
       📁 Folders:   #{agent.state[:stats][:total_folders]}
       📦 Modules:   #{length(all_modules)}
       ⏱️  Time:      #{elapsed}ms
       
       💾 Cache:     #{cache_stats[:hits]} hits / #{cache_stats[:misses]} misses (#{cache_stats[:hit_rate]}%)

    ┌─────────────────────────────────────────────────────────────────┐
    │  🤖 AGENTS                                                      │
    └─────────────────────────────────────────────────────────────────┘

       🎯 Root:      1 (RootCoordinator)
       📁 Folder:    #{folder_agents} agents
       📄 File:      #{total_file_agents} agents
       ═══════════════════════════════════════════════════════════════
       🤖 Total:     #{1 + folder_agents + total_file_agents} agents

    ┌─────────────────────────────────────────────────────────────────┐
    │  📁 TOP FOLDERS                                                 │
    └─────────────────────────────────────────────────────────────────┘

#{top_folders}

    ┌─────────────────────────────────────────────────────────────────┐
    │  📦 MODULES (#{length(all_modules)} total)                                        │
    └─────────────────────────────────────────────────────────────────┘

#{all_modules |> Enum.sort() |> Enum.take(30) |> Enum.map(&"   • #{&1}") |> Enum.join("\n")}
#{if length(all_modules) > 30, do: "\n   ... and #{length(all_modules) - 30} more", else: ""}

    ╔═══════════════════════════════════════════════════════════════════╗
    """
  end
end
