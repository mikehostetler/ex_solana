defmodule ExSolana.Program.IDLMacros.GenerateEventDecoders do
  @moduledoc false
  alias ExSolana.Program.IDLMacros.Helpers

  defmacro generate_event_decoders(idl, log_prefix) do
    quote bind_quoted: [idl: idl, log_prefix: log_prefix], location: :keep do
      use ExSolana.Util.DebugTools, debug_enabled: false

      if Enum.empty?(idl.events || []) do
        nil
      else
        @events for event <- idl.events || [],
                    into: %{},
                    do: {event.discriminator, String.to_atom(Macro.underscore(event.name))}

        @doc """
        Returns a map of event discriminants to their corresponding atom names.

        ## Example

            iex> #{__MODULE__}.events()
            %{0 => :transfer, 1 => :mint, ...}
        """
        def events, do: @events

        @doc """
        Decodes events from a list of logs.

        ## Parameters

          * `logs` - List of log strings

        ## Returns

          * List of tuples `{event_type, params}` where:
            * `event_type` is an atom representing the type of event
            * `params` is a map of decoded parameters for the event

        ## Example

            iex> #{__MODULE__}.decode_events(["Program log: ...", "Program data: ..."])
            [{:transfer, %{...}}, ...]
        """
        def decode_events(logs) do
          debug("Decoding events", logs: logs)

          result =
            logs
            |> Enum.map(&decode_event/1)
            |> Enum.filter(&(&1 != nil))

          debug("Events decoded", result: result)
          result
        end

        @doc """
        Decodes a single event from a log string.

        ## Parameters

          * `log` - Log string

        ## Returns

          * `{event_type, params}` where:
            * `event_type` is an atom representing the type of event
            * `params` is a map of decoded parameters for the event
          * `nil` if the log is not a valid event log

        ## Example

            iex> #{__MODULE__}.decode_event("Program data: ...")
            {:transfer, %{...}}
        """
        def decode_event(log) do
          debug("Decoding event", log: log)

          result =
            if String.starts_with?(log, unquote(log_prefix)) do
              log_data = String.trim_leading(log, unquote(log_prefix))

              case Base.decode64(log_data) do
                {:ok, decoded_data} ->
                  case decoded_data do
                    <<discriminator::binary-size(8), rest::binary>> ->
                      discriminator_list = :binary.bin_to_list(discriminator)
                      event_type = @events[discriminator_list]
                      debug("Identified event type", type: event_type, discriminator: discriminator_list)

                      if event_type do
                        apply(__MODULE__, String.to_atom("decode_event_#{event_type}"), [rest])
                      else
                        debug("Unknown event discriminator", discriminator: discriminator_list)
                        nil
                      end

                    _ ->
                      debug("Unknown event format - insufficient data for discriminator", data: Base.encode16(decoded_data))
                      nil
                  end

                :error ->
                  error("Invalid Base64 in event log", log: log)
                  {:error, :invalid_base64}
              end
            end

          debug("Event decoded", result: result)
          result
        end

        defoverridable decode_event: 1

        # Generate decode_event_$name functions for each event
        for event <- idl.events || [] do
          event_name = String.to_atom(Macro.underscore(event.name))

          if event.fields do
            field_pattern = Helpers.generate_field_pattern(event.fields)

            @doc """
            Decodes a #{event.name} event.

            ## Parameters

              * `data` - Binary data of the event

            ## Returns

              * `{:#{event_name}, decoded_fields}` on success
              * `{:error, :decode_failed}` on failure

            ## Fields

            #{Enum.map_join(event.fields, "\n", fn field -> "  * `#{field.name}` - #{inspect(field.type)}" end)}

            ## Example

                iex> #{__MODULE__}.decode_event_#{event_name}(<<...>>)
                {:#{event_name}, %{...}}
            """
            def unquote(:"decode_event_#{event_name}")(data) do
              debug("Decoding #{unquote(event_name)} event", data: Base.encode16(data))

              try do
                {decoded_fields, _rest} =
                  ExSolana.BinaryDecoder.decode(data, unquote(Macro.escape(field_pattern)))

                result = {unquote(event_name), decoded_fields}
                debug("Successfully decoded #{unquote(event_name)} event", result: result)
                result
              rescue
                e ->
                  error("Failed to decode #{unquote(event_name)} event",
                    event: unquote(event_name),
                    data: Base.encode16(data),
                    error: inspect(e)
                  )

                  nil
              end
            end
          else
            @doc """
            Event #{event.name} has no field definition in the IDL.
            This function returns the discriminator-based detection only.
            """
            def unquote(:"decode_event_#{event_name}")(_data) do
              {:error, :no_field_definition}
            end
          end

          defoverridable [{:"decode_event_#{event_name}", 1}]
        end
      end
    end
  end
end
