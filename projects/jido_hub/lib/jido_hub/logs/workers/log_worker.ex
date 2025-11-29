defmodule JidoHub.Logs.Workers.LogWorker do
  use Oban.Worker, queue: :logs, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"attrs" => attrs, "opts" => opts}}) do
    JidoHub.Logs.log(attrs, opts)
  end
end
