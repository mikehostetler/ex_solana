defmodule JidoMessaging.Application do
  @moduledoc """
  OTP Application supervisor for JidoMessaging.

  Manages the supervision tree for the messaging system.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Add child processes and supervisors here
    ]

    opts = [strategy: :one_for_one, name: JidoMessaging.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
