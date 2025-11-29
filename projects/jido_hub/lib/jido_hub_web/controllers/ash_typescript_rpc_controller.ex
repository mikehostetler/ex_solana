defmodule JidoHubWeb.AshTypescriptRpcController do
  use JidoHubWeb, :controller

  def run(conn, params) do
    result = AshTypescript.Rpc.run_action(:jido_hub, conn, params)
    json(conn, result)
  end

  def validate(conn, params) do
    result = AshTypescript.Rpc.validate_action(:jido_hub, conn, params)
    json(conn, result)
  end
end
