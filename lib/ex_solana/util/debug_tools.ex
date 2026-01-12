defmodule ExSolana.Util.DebugTools do
  @moduledoc false
  require Logger

  defmacro __using__(opts \\ []) do
    quote do
      import ExSolana.Util.DebugTools

      require ExSolana.Util.DebugTools

      @debug_opts unquote(opts)
      @debug_enabled Keyword.get(unquote(opts), :debug_enabled, true)
    end
  end

  defmacro debug(message, metadata \\ []) do
    quote do
      if @debug_enabled do
        caller = "#{__MODULE__}.#{elem(__ENV__.function, 0)}"
        prefixed_message = "[#{caller}] #{unquote(message)}"
        ExSolana.Util.DebugTools.log(:debug, prefixed_message, unquote(metadata), @debug_opts)
      end
    end
  end

  defmacro error(message, metadata \\ []) do
    quote do
      if @debug_enabled do
        caller = "#{__MODULE__}.#{elem(__ENV__.function, 0)}"
        prefixed_message = "[#{caller}] #{unquote(message)}"
        ExSolana.Util.DebugTools.log(:error, prefixed_message, unquote(metadata), @debug_opts)
      end
    end
  end

  def log(level, message, metadata, opts) do
    if should_log?(level, opts) do
      formatted_metadata = format_metadata(metadata, opts)
      log_message = "#{message} #{formatted_metadata}"

      case level do
        :debug -> Logger.debug(log_message)
        :error -> Logger.error(log_message)
      end
    end
  end

  defp should_log?(level, opts) do
    config = Application.get_env(:ex_solana, ExSolana.Util.DebugTools, [])
    env = Application.get_env(:ex_solana, :env, :prod)

    debug_levels = opts[:levels] || config[:levels] || [:debug, :error]
    env_whitelist = opts[:env] || config[:env] || [:dev, :test]

    level in debug_levels and env in env_whitelist
  end

  defp format_metadata(metadata, opts) do
    max_length = opts[:max_length] || 500
    truncate_threshold = opts[:truncate_threshold] || 100

    Enum.map_join(metadata, ", ", fn {key, value} ->
      formatted_value = format_value(value, max_length, truncate_threshold)
      "#{key}: #{formatted_value}"
    end)
  end

  defp format_value(value, max_length, truncate_threshold) do
    formatted = inspect(value, limit: :infinity, pretty: false)

    if String.length(formatted) > truncate_threshold do
      truncated = String.slice(formatted, 0, max_length)
      "#{truncated}... (truncated)"
    else
      formatted
    end
  end
end
