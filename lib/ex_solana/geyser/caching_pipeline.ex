defmodule ExSolana.Geyser.CachingPipeline do
  @moduledoc false
  use Broadway

  alias ExSolana.Config

  require Logger

  def start_link(opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module:
          {ExSolana.Geyser.Producer,
           [
             url: opts[:url],
             token: opts[:token],
             stream_request: opts[:stream_request]
           ]},
        concurrency: 1
      ],
      processors: [
        default: [
          concurrency: opts[:processor_concurrency] || 50
        ]
      ]
    )
  end

  def transform(event, _opts) do
    %Broadway.Message{
      data: event,
      acknowledger: {__MODULE__, :ack_id, :ack_data}
    }
  end

  @impl true
  def handle_message(_, message, _) do
    case process_message(message.data) do
      :ok -> message
      _ -> Broadway.Message.failed(message, "processing_failed")
    end
  end

  defp process_message(data) do
    # Generate a unique filename based on timestamp and random string
    filename =
      "tx_#{DateTime.to_unix(DateTime.utc_now())}_#{4 |> :crypto.strong_rand_bytes() |> Base.encode16()}.binary"

    base_path = Config.get({:geyser, :cache_dir})
    file_path = Path.join(base_path, filename)

    # Ensure the directory exists
    File.mkdir_p!(Path.dirname(file_path))

    # Write the raw binary data to file
    File.write!(file_path, data)

    Logger.debug("Wrote binary message to file: #{file_path}")

    :ok
  end

  def ack(_, _, _), do: :ok
end
