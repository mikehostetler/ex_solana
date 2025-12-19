defmodule JidoCode.TestHelpers.EnvIsolation do
  @moduledoc """
  Test helper for isolating environment variable state during tests.

  This module provides functions to save, restore, and clear environment
  variables in test setup/teardown to ensure tests don't leak state.

  ## Usage

      setup do
        env_keys = ["JIDO_CODE_PROVIDER", "JIDO_CODE_MODEL", "ANTHROPIC_API_KEY"]
        app_keys = [{:jido_code, :llm}]

        original = JidoCode.TestHelpers.EnvIsolation.save(env_keys, app_keys)

        on_exit(fn ->
          JidoCode.TestHelpers.EnvIsolation.restore(original)
        end)

        JidoCode.TestHelpers.EnvIsolation.clear(env_keys, app_keys)

        :ok
      end

  Or use the convenience function that does all three:

      setup do
        env_keys = ["JIDO_CODE_PROVIDER", "JIDO_CODE_MODEL"]
        app_keys = [{:jido_code, :llm}]

        JidoCode.TestHelpers.EnvIsolation.isolate(env_keys, app_keys)
      end
  """

  @type env_key :: String.t()
  @type app_key :: {atom(), atom()}
  @type saved_state :: %{
          env: %{String.t() => String.t() | nil},
          app: %{{atom(), atom()} => term() | nil}
        }

  @doc """
  Saves the current values of environment variables and application config.

  Returns a map that can be passed to `restore/1` to restore the original state.
  """
  @spec save([env_key()], [app_key()]) :: saved_state()
  def save(env_keys, app_keys \\ []) do
    env_state =
      env_keys
      |> Enum.map(fn key -> {key, System.get_env(key)} end)
      |> Map.new()

    app_state =
      app_keys
      |> Enum.map(fn {app, key} -> {{app, key}, Application.get_env(app, key)} end)
      |> Map.new()

    %{env: env_state, app: app_state}
  end

  @doc """
  Restores environment variables and application config to their saved state.
  """
  @spec restore(saved_state()) :: :ok
  def restore(%{env: env_state, app: app_state}) do
    # Restore env vars
    Enum.each(env_state, fn
      {key, nil} -> System.delete_env(key)
      {key, value} -> System.put_env(key, value)
    end)

    # Restore app config
    Enum.each(app_state, fn
      {{app, key}, nil} -> Application.delete_env(app, key)
      {{app, key}, value} -> Application.put_env(app, key, value)
    end)

    :ok
  end

  @doc """
  Clears the specified environment variables and application config.

  This ensures tests start with a clean state.
  """
  @spec clear([env_key()], [app_key()]) :: :ok
  def clear(env_keys, app_keys \\ []) do
    Enum.each(env_keys, &System.delete_env/1)
    Enum.each(app_keys, fn {app, key} -> Application.delete_env(app, key) end)
    :ok
  end

  @doc """
  Convenience function that saves state, registers cleanup on exit, and clears state.

  This is the most common pattern for test isolation. Returns :ok.

  ## Example

      setup do
        JidoCode.TestHelpers.EnvIsolation.isolate(
          ["JIDO_CODE_PROVIDER", "ANTHROPIC_API_KEY"],
          [{:jido_code, :llm}]
        )
      end
  """
  @spec isolate([env_key()], [app_key()]) :: :ok
  def isolate(env_keys, app_keys \\ []) do
    original = save(env_keys, app_keys)

    ExUnit.Callbacks.on_exit(fn ->
      restore(original)
    end)

    clear(env_keys, app_keys)
  end
end
