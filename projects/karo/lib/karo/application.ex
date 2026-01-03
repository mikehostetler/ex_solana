defmodule Karo.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {Registry, keys: :unique, name: Karo.ChatRegistry},
        {DynamicSupervisor, strategy: :one_for_one, name: Karo.ChatSupervisor},
        {Karo.Governor, []}
      ]
      |> maybe_add_repo()

    opts = [strategy: :one_for_one, name: Karo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_repo(children) do
    if Application.get_env(:karo, Karo.Repo) do
      [Karo.Repo | children]
    else
      children
    end
  end
end
