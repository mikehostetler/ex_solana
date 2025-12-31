defmodule Jido.Agent.Directive.CronCancel do
  @moduledoc """
  Cancel a previously registered cron job for this agent by job_id.

  ## Fields

  - `job_id` - The logical job id to cancel

  ## Examples

      %CronCancel{job_id: :heartbeat}
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              job_id: Zoi.any(description: "Logical cron job id within the agent")
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema
end
