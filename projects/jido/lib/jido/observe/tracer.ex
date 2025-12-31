defmodule Jido.Observe.Tracer do
  @moduledoc """
  Behaviour for tracing backends.

  Implement this behaviour to integrate OpenTelemetry or other tracing systems.
  The default implementation is `Jido.Observe.NoopTracer` which does nothing.

  ## Example Implementation

  A future `jido_otel` package could implement this:

      defmodule JidoOtel.Tracer do
        @behaviour Jido.Observe.Tracer

        def span_start(event_prefix, metadata) do
          # Create OpenTelemetry span and return context
        end

        def span_stop(tracer_ctx, measurements) do
          # End the span with success status
        end

        def span_exception(tracer_ctx, kind, reason, stacktrace) do
          # End the span with error status
        end
      end
  """

  @type event_prefix :: [atom()]
  @type metadata :: map()
  @type measurements :: map()
  @type tracer_ctx :: term()

  @doc """
  Called when a span starts.

  Returns context to be passed to `span_stop/2` or `span_exception/4`.
  """
  @callback span_start(event_prefix(), metadata()) :: tracer_ctx()

  @doc """
  Called when a span completes successfully.
  """
  @callback span_stop(tracer_ctx(), measurements()) :: :ok

  @doc """
  Called when a span completes with an exception.
  """
  @callback span_exception(tracer_ctx(), kind :: atom(), reason :: term(), stacktrace :: list()) ::
              :ok
end
