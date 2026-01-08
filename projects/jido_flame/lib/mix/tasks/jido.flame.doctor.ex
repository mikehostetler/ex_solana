defmodule Mix.Tasks.Jido.Flame.Doctor do
  @shortdoc "Diagnose FLAME + Jido integration"

  @moduledoc """
  Diagnostic task to verify FLAME + Jido integration is working correctly.

  ## Usage

      $ mix jido.flame.doctor

  ## Checks Performed

  1. **Configuration** - Verifies FLAME pool and backend are configured
  2. **RemoteCall** - Tests a simple FLAME.call/3
  3. **SpawnRemoteAgent** (optional) - Tests remote agent spawning
  4. **Fly.io Backend** - Reports Fly.io configuration status

  ## Options

      --pool NAME      - FLAME pool to test (default: from config or starts temp pool)
      --skip-spawn     - Skip the SpawnRemoteAgent test
      --verbose        - Show detailed output
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [pool: :string, skip_spawn: :boolean, verbose: :boolean],
        aliases: [p: :pool, s: :skip_spawn, v: :verbose]
      )

    verbose = Keyword.get(opts, :verbose, false)
    skip_spawn = Keyword.get(opts, :skip_spawn, false)

    IO.puts("")
    IO.puts(IO.ANSI.cyan() <> "JidoFlame Doctor" <> IO.ANSI.reset())
    IO.puts(String.duplicate("=", 40))
    IO.puts("")

    check_configuration(opts, verbose)

    pool = get_pool(opts)

    if pool do
      check_remote_call(pool, verbose)

      unless skip_spawn do
        check_spawn_remote_agent(pool, verbose)
      end
    end

    check_fly_config(verbose)

    IO.puts("")
    IO.puts(IO.ANSI.green() <> "✔ Doctor checks complete!" <> IO.ANSI.reset())
    IO.puts("")
  end

  defp check_configuration(_opts, verbose) do
    IO.puts(IO.ANSI.yellow() <> "Checking configuration..." <> IO.ANSI.reset())

    default_pool = JidoFlame.default_pool()

    if default_pool do
      success("Default pool configured: #{inspect(default_pool)}")
    else
      info("No default pool configured (set :jido_flame, :default_pool)")
    end

    backend = Application.get_env(:flame, :backend, FLAME.LocalBackend)
    success("FLAME backend: #{inspect(backend)}")

    if verbose do
      flame_config = Application.get_all_env(:flame)
      info("FLAME config: #{inspect(flame_config)}")
    end

    IO.puts("")
  end

  defp get_pool(opts) do
    pool_name = Keyword.get(opts, :pool)

    cond do
      pool_name ->
        String.to_atom(pool_name)

      pool = JidoFlame.default_pool() ->
        pool

      true ->
        start_temp_pool()
    end
  end

  defp start_temp_pool do
    IO.puts(IO.ANSI.yellow() <> "Starting temporary FLAME pool for testing..." <> IO.ANSI.reset())

    pool_name = :"jido_flame_doctor_pool_#{:erlang.unique_integer([:positive])}"

    spec = {FLAME.Pool, name: pool_name, backend: FLAME.LocalBackend, min: 0, max: 2, idle_shutdown_after: 5_000}

    case DynamicSupervisor.start_child(
           {:via, PartitionSupervisor, {Kernel.PartitionSupervisor, self()}},
           spec
         ) do
      {:ok, _pid} ->
        success("Temporary pool started: #{inspect(pool_name)}")
        pool_name

      {:error, {:already_started, _pid}} ->
        pool_name

      {:error, _reason} ->
        case start_pool_simple(spec) do
          {:ok, _} ->
            success("Temporary pool started: #{inspect(pool_name)}")
            pool_name

          {:error, reason} ->
            warning("Could not start temp pool: #{inspect(reason)}")
            nil
        end
    end
  end

  defp start_pool_simple({FLAME.Pool, opts}) do
    children = [{FLAME.Pool, opts}]
    Supervisor.start_link(children, strategy: :one_for_one, name: :"doctor_sup_#{:rand.uniform(10000)}")
  end

  defp check_remote_call(pool, verbose) do
    IO.puts(IO.ANSI.yellow() <> "Testing RemoteCall..." <> IO.ANSI.reset())

    start_time = System.monotonic_time(:millisecond)

    try do
      result =
        FLAME.call(
          pool,
          fn ->
            %{
              node: node(),
              pid: self(),
              flame_parent: FLAME.Parent.get()
            }
          end,
          timeout: 30_000
        )

      elapsed = System.monotonic_time(:millisecond) - start_time

      success("RemoteCall succeeded")
      info("  - Executed on node: #{inspect(result.node)}")
      info("  - Round-trip time: #{elapsed}ms")

      if verbose do
        info("  - Remote PID: #{inspect(result.pid)}")
        info("  - FLAME parent: #{inspect(result.flame_parent)}")
      end
    rescue
      e ->
        error("RemoteCall failed: #{Exception.message(e)}")
    catch
      :exit, reason ->
        error("RemoteCall exited: #{inspect(reason)}")
    end

    IO.puts("")
  end

  defp check_spawn_remote_agent(pool, verbose) do
    IO.puts(IO.ANSI.yellow() <> "Testing SpawnRemoteAgent..." <> IO.ANSI.reset())

    ensure_registries_started()

    test_agent_id = "doctor_test_#{:erlang.unique_integer([:positive])}"
    JidoFlame.AgentRegistry.register(test_agent_id)

    try do
      child_spec =
        {JidoFlame.TestAgent,
         %{
           parent_ref: %{
             logical_agent_id: test_agent_id,
             owner_pid: nil,
             meta: %{test: true}
           }
         }}

      case JidoFlame.Owner.start_child(
             test_agent_id,
             :doctor_test,
             child_spec,
             pool,
             flame_opts: [timeout: 30_000]
           ) do
        {:ok, owner_pid, child_pid} ->
          success("SpawnRemoteAgent succeeded")
          info("  - Owner PID: #{inspect(owner_pid)}")
          info("  - Child PID: #{inspect(child_pid)}")
          info("  - Child node: #{node(child_pid)}")

          :pong = JidoFlame.TestAgent.ping(child_pid)
          success("  - Child responds to ping: :pong")

          JidoFlame.TestAgent.emit_to_parent(child_pid, "doctor.test", %{success: true})

          receive do
            {:remote_child_signal, :doctor_test, signal} ->
              success("  - emit_to_parent verified: received signal")
              if verbose, do: info("    Signal: #{inspect(signal)}")
          after
            2000 ->
              warning("  - emit_to_parent: no signal received within 2s")
          end

          JidoFlame.Owner.stop(owner_pid)
          success("  - Cleanup complete")

        {:error, reason} ->
          error("SpawnRemoteAgent failed: #{inspect(reason)}")
      end
    rescue
      e ->
        error("SpawnRemoteAgent test error: #{Exception.message(e)}")
    after
      JidoFlame.AgentRegistry.unregister(test_agent_id)
    end

    IO.puts("")
  end

  defp ensure_registries_started do
    unless Process.whereis(JidoFlame.AgentRegistry) do
      {:ok, _} = JidoFlame.AgentRegistry.start_link([])
    end

    unless Process.whereis(JidoFlame.ChildRegistry) do
      {:ok, _} = JidoFlame.ChildRegistry.start_link([])
    end

    unless Process.whereis(JidoFlame.OwnerSupervisor) do
      {:ok, _} =
        DynamicSupervisor.start_link(
          name: JidoFlame.OwnerSupervisor,
          strategy: :one_for_one
        )
    end
  end

  defp check_fly_config(verbose) do
    IO.puts(IO.ANSI.yellow() <> "Fly.io Backend Status" <> IO.ANSI.reset())
    IO.puts(String.duplicate("-", 25))

    fly_token = System.get_env("FLY_API_TOKEN")
    fly_app = System.get_env("FLY_APP_NAME")

    cond do
      fly_token && fly_app ->
        success("Fly.io configured")
        info("  - App: #{fly_app}")
        info("  - Token: [REDACTED]")

      fly_app && !fly_token ->
        warning("FLY_APP_NAME set but FLY_API_TOKEN missing")

      true ->
        info("Fly.io not configured (set FLY_API_TOKEN and FLY_APP_NAME)")
    end

    if verbose do
      fly_env =
        for {k, v} <- System.get_env(), String.starts_with?(k, "FLY_") do
          {k, if(String.contains?(k, "TOKEN"), do: "[REDACTED]", else: v)}
        end

      unless Enum.empty?(fly_env) do
        info("  Fly environment: #{inspect(fly_env)}")
      end
    end

    IO.puts("")
  end

  defp success(msg), do: IO.puts(IO.ANSI.green() <> "✔ " <> IO.ANSI.reset() <> msg)
  defp info(msg), do: IO.puts("  " <> msg)
  defp warning(msg), do: IO.puts(IO.ANSI.yellow() <> "⚠ " <> IO.ANSI.reset() <> msg)
  defp error(msg), do: IO.puts(IO.ANSI.red() <> "✘ " <> IO.ANSI.reset() <> msg)
end
