#!/usr/bin/env elixir
# Run with: mix run examples/code_mapper/runner.exs [path]
#
# Jido CodeMapper - Multi-Agent Codebase Analysis Demo
#
# This demonstrates:
# - Hierarchical agents (Root → Folder → File)
# - Maximum BEAM scheduler utilization
# - Signal-based coordination with emit_to_parent
# - AST parsing for Elixir files
# - DETS-based caching to avoid repeated work
#
# Examples:
#   mix run examples/code_mapper/runner.exs                    # Map current project (fast!)
#   mix run examples/code_mapper/runner.exs /path/to/project   # Map custom path
#   CLEAR_CACHE=1 mix run examples/code_mapper/runner.exs      # Clear cache first
#   CODEMAPPER_DEMO=1 mix run examples/code_mapper/runner.exs  # Slow spawn for visual effect
#
# Options (via env vars):
#   CLEAR_CACHE=1     - Clear the cache before running
#   MAX_FOLDERS=N     - Override max concurrent folders
#   MAX_FILES=N       - Override max files per folder batch
#   SEQUENTIAL=1      - Process folders sequentially (1 at a time)
#   SAFE_MODE=1       - Alias for SEQUENTIAL=1 with conservative settings
#   CODEMAPPER_DEMO=1 - Enable spawn delays for dramatic demo effect

Logger.configure(level: :error)

# Load modules
Code.require_file("cache.ex", __DIR__)
Code.require_file("strategy/mapper_strategy.ex", __DIR__)
Code.require_file("agents/file_agent.ex", __DIR__)
Code.require_file("agents/folder_agent.ex", __DIR__)
Code.require_file("agents/root_coordinator.ex", __DIR__)

alias Jido.AgentServer

defmodule CodeMapperRunner do
  @moduledoc """
  Runner for the CodeMapper demo.
  Maximizes BEAM scheduler utilization for fastest possible analysis.
  """

  alias Jido.Signal
  alias CodeMapper.Cache

  @banner """

  ╔═══════════════════════════════════════════════════════════════════╗
  ║                                                                   ║
  ║     ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░    ║
  ║     ░░      ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░    ║
  ║     ▒▒      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒    ║
  ║     ▒▒      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒    ║
  ║     ▓▓      ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓    ║
  ║     ██████████████████████████████████████████████████████████    ║
  ║                                                                   ║
  ║            J I D O   C O D E M A P P E R                         ║
  ║                                                                   ║
  ║         Multi-Agent Codebase Analysis System                      ║
  ║                                                                   ║
  ╚═══════════════════════════════════════════════════════════════════╝
  """

  def run(args \\ []) do
    IO.puts(@banner)

    # BEAM scheduler info
    schedulers_online = :erlang.system_info(:schedulers_online)
    total_schedulers = :erlang.system_info(:schedulers)
    logical_cores = :erlang.system_info(:logical_processors_available)

    IO.puts("   🧠 BEAM: #{schedulers_online}/#{total_schedulers} schedulers online (#{logical_cores} logical cores)")

    # Enable scheduler wall-time tracking
    :erlang.system_flag(:scheduler_wall_time, true)
    sched_start = :erlang.statistics(:scheduler_wall_time)

    # Determine target path
    target_path = determine_target_path(args)

    # Mode detection
    safe_mode = System.get_env("SAFE_MODE") != nil or System.get_env("SEQUENTIAL") != nil
    demo_mode = System.get_env("CODEMAPPER_DEMO") in ["1", "true", "TRUE"]

    # Calculate optimal concurrency based on schedulers
    {max_folders, max_files} = calculate_concurrency(schedulers_online, safe_mode)

    IO.puts("   🎯 Target: #{target_path}")
    
    cond do
      safe_mode ->
        IO.puts("   ⚠️  Mode: SEQUENTIAL (safe mode for large codebases)")
      demo_mode ->
        IO.puts("   🎬 Mode: DEMO (spawn delays enabled for visual effect)")
      true ->
        IO.puts("   🚀 Mode: MAXIMUM PERFORMANCE")
    end
    
    IO.puts("   ⚙️  Config: #{max_folders} concurrent folders, #{max_files} files/batch")

    # Start cache
    {:ok, _} = Cache.start_link(cache_dir: target_path)

    if System.get_env("CLEAR_CACHE") do
      IO.puts("   🗑️  Clearing cache...")
      Cache.clear()
    else
      cache_stats = Cache.stats()
      if cache_stats.entries > 0 do
        IO.puts("   💾 Cache: #{cache_stats.entries} entries available")
      end
    end

    # Start Jido instance
    {:ok, _} = Jido.start_link(name: CodeMapperRunner.Jido)

    # Start RootCoordinator
    {:ok, root_pid} =
      Jido.start_agent(CodeMapperRunner.Jido, CodeMapper.RootCoordinator, id: "root-coordinator")

    IO.puts("   🤖 RootCoordinator: #{inspect(root_pid)}")

    # Send start signal
    start_signal =
      Signal.new!(
        "root.start",
        %{
          path: target_path,
          extensions: [".ex", ".exs"],
          ignore: [
            "_build", "deps", ".elixir_ls", ".git", "node_modules",
            "test", ".code_mapper_cache", "priv", "cover", ".github", "tmp"
          ],
          max_folders: max_folders,
          max_files: max_files,
          sequential: safe_mode,
          demo_mode: demo_mode
        },
        source: "/runner"
      )

    AgentServer.cast(root_pid, start_signal)

    # Wait for completion with live status updates
    case wait_for_completion(root_pid, 300_000) do
      {:ok, report, stats} ->
        IO.puts(report)

        # Get scheduler stats at end
        sched_end = :erlang.statistics(:scheduler_wall_time)

        total_agents = stats[:total_agents] || (1 + (stats[:folder_agents_spawned] || 0) + (stats[:file_agents_spawned] || 0))

        IO.puts("╔═══════════════════════════════════════════════════════════════════╗")
        IO.puts("║  ✅ MAPPING COMPLETE                                              ║")
        IO.puts("╠═══════════════════════════════════════════════════════════════════╣")
        IO.puts("║                                                                   ║")
        IO.puts("║   📄 Files:     #{String.pad_trailing("#{stats[:total_files]}", 46)}║")
        IO.puts("║   📁 Folders:   #{String.pad_trailing("#{stats[:total_folders]}", 46)}║")
        IO.puts("║   📦 Modules:   #{String.pad_trailing("#{stats[:total_modules]}", 46)}║")
        IO.puts("║   ⏱️  Time:      #{String.pad_trailing("#{stats[:elapsed_ms]}ms", 46)}║")
        IO.puts("║   💾 Cache:     #{String.pad_trailing("#{stats[:cache_hits] || 0} hits / #{stats[:cache_misses] || 0} misses", 46)}║")
        IO.puts("║                                                                   ║")
        IO.puts("╠═══════════════════════════════════════════════════════════════════╣")
        IO.puts("║  🤖 AGENTS SPAWNED                                                ║")
        IO.puts("╠═══════════════════════════════════════════════════════════════════╣")
        IO.puts("║   🎯 Root:      #{String.pad_trailing("1", 46)}║")
        IO.puts("║   📁 Folder:    #{String.pad_trailing("#{stats[:folder_agents_spawned] || 0}", 46)}║")
        IO.puts("║   📄 File:      #{String.pad_trailing("#{stats[:file_agents_spawned] || 0}", 46)}║")
        IO.puts("║   ─────────────────────────────────────────────────────────────   ║")
        IO.puts("║   🤖 TOTAL:     #{String.pad_trailing("#{total_agents} agents", 46)}║")
        IO.puts("║                                                                   ║")
        IO.puts("╚═══════════════════════════════════════════════════════════════════╝")

        # Print scheduler utilization
        print_scheduler_utilization(sched_start, sched_end)

      {:error, :timeout} ->
        IO.puts("\n\n❌ TIMEOUT: Mapping did not complete in time")

      {:error, reason} ->
        IO.puts("\n\n❌ ERROR: #{inspect(reason)}")
    end

    # Cleanup
    Cache.stop()
    GenServer.stop(root_pid, :normal)
    IO.puts("\n   [DONE] CodeMapper finished\n")
  end

  defp calculate_concurrency(schedulers_online, safe_mode) do
    if safe_mode do
      {1, 5}
    else
      # Target ~3x schedulers worth of concurrent file agents total
      target_parallelism = 3 * schedulers_online

      default_folders =
        schedulers_online
        |> min(12)
        |> max(2)

      default_files_per_folder =
        target_parallelism
        |> div(default_folders)
        |> max(4)

      {
        get_env_int("MAX_FOLDERS", default_folders),
        get_env_int("MAX_FILES", default_files_per_folder)
      }
    end
  end

  defp print_scheduler_utilization(start_stats, end_stats) do
    end_map = Map.new(end_stats, fn {id, active, total} -> {id, {active, total}} end)

    utilizations =
      for {id, active0, total0} <- start_stats,
          {active1, total1} = Map.fetch!(end_map, id),
          do: {id, busy_pct(active1 - active0, total1 - total0)}

    avg =
      utilizations
      |> Enum.map(fn {_id, pct} -> pct end)
      |> case do
        [] -> 0.0
        list -> Enum.sum(list) / length(list)
      end

    IO.puts("\n┌─────────────────────────────────────────────────────────────────┐")
    IO.puts("│  🧮 SCHEDULER UTILIZATION                                       │")
    IO.puts("└─────────────────────────────────────────────────────────────────┘")

    # Show per-scheduler utilization as a bar chart
    utilizations
    |> Enum.sort_by(fn {id, _} -> id end)
    |> Enum.each(fn {id, pct} ->
      bar_len = round(pct / 5)
      bar = String.duplicate("█", bar_len) <> String.duplicate("░", 20 - bar_len)
      IO.puts("   Scheduler #{String.pad_leading("#{id}", 2)}: #{bar} #{Float.round(pct, 1)}%")
    end)

    IO.puts("   ─────────────────────────────────────────────────────────────")
    IO.puts("   Average:      #{Float.round(avg, 1)}% busy")
  end

  defp busy_pct(_active, 0), do: 0.0
  defp busy_pct(active, total), do: 100.0 * active / total

  defp determine_target_path(args) do
    case args do
      [path | _] ->
        Path.expand(path, File.cwd!())

      [] ->
        __DIR__
        |> Path.dirname()
        |> Path.dirname()
    end
  end

  defp get_env_int(name, default) do
    case System.get_env(name) do
      nil -> default
      val -> String.to_integer(val)
    end
  end

  defp wait_for_completion(pid, timeout) do
    start = System.monotonic_time(:millisecond)

    result =
      Stream.repeatedly(fn ->
        Process.sleep(500)

        try do
          {:ok, state} = GenServer.call(pid, :get_state, 30_000)

          case state do
            %{agent: %{state: %{status: :completed, report: report, stats: stats}}} ->
              {:done, report, stats}

            _ ->
              elapsed = System.monotonic_time(:millisecond) - start

              if elapsed > timeout do
                {:timeout}
              else
                {:continue}
              end
          end
        catch
          :exit, {:timeout, _} ->
            elapsed = System.monotonic_time(:millisecond) - start
            IO.write(".")

            if elapsed > timeout do
              {:timeout}
            else
              {:continue}
            end
        end
      end)
      |> Enum.reduce_while(nil, fn
        {:done, report, stats}, _acc ->
          {:halt, {:ok, report, stats}}

        {:timeout}, _acc ->
          {:halt, {:error, :timeout}}

        {:continue}, _acc ->
          {:cont, nil}
      end)

    case result do
      {:ok, report, stats} -> {:ok, report, stats}
      {:error, reason} -> {:error, reason}
    end
  end
end

# Parse command line args and run
args = System.argv()
CodeMapperRunner.run(args)
