defmodule JidoHubWeb.Plugs.RateLimit do
  @moduledoc """
  Rate limiting plug using PlugAttack and ExRated.

  Protects endpoints from abuse with configurable limits per route type:
  - Auth endpoints: 5 requests/minute per IP (default)
  - API endpoints: 100 requests/minute per IP (default)
  - LiveView websocket upgrades: 20 requests/minute per IP (default)
  - Static assets and health checks: bypass rate limiting

  ## Configuration

  Rate limits can be configured per environment in config files:

      config :jido_hub, JidoHubWeb.Plugs.RateLimit,
        enabled: true,
        auth_limit: 5,
        api_limit: 100,
        liveview_limit: 20

  Set `enabled: false` to disable rate limiting entirely (e.g., in test environment).
  """

  use PlugAttack

  import Plug.Conn

  require Logger

  defp rate_limit_config do
    Application.get_env(:jido_hub, __MODULE__, [])
  end

  defp enabled? do
    Keyword.get(rate_limit_config(), :enabled, true)
  end

  defp auth_limit do
    Keyword.get(rate_limit_config(), :auth_limit, 5)
  end

  defp api_limit do
    Keyword.get(rate_limit_config(), :api_limit, 100)
  end

  defp liveview_limit do
    Keyword.get(rate_limit_config(), :liveview_limit, 20)
  end

  rule "allow static assets and health checks", conn do
    case conn.request_path do
      "/assets/" <> _ -> {:allow, conn}
      "/health" -> {:allow, conn}
      "/favicon.ico" -> {:allow, conn}
      _ -> nil
    end
  end

  rule "auth endpoints rate limit", conn do
    if enabled?() do
      case conn do
        %{method: "POST", request_path: path}
        when path in [
               "/auth/user/password/sign_in",
               "/auth/user/password/register",
               "/reset",
               "/confirm",
               "/magic_link"
             ] ->
          check_rate(conn, "auth:#{remote_ip(conn)}", auth_limit(), 60_000)

        _ ->
          nil
      end
    end
  end

  rule "liveview websocket rate limit", conn do
    if enabled?() do
      case {conn.request_path, get_req_header(conn, "upgrade")} do
        {"/live" <> _, ["websocket" | _]} ->
          check_rate(conn, "liveview:#{remote_ip(conn)}", liveview_limit(), 60_000)

        _ ->
          nil
      end
    end
  end

  rule "api endpoints rate limit", conn do
    if enabled?() do
      case conn.request_path do
        "/api/" <> _ ->
          check_rate(conn, "api:#{remote_ip(conn)}", api_limit(), 60_000)

        _ ->
          nil
      end
    end
  end

  def allow_action(conn, _data, _opts) do
    conn
  end

  def block_action(conn, _data, _opts) do
    Logger.warning("Rate limit exceeded for #{remote_ip(conn)} on #{conn.request_path}")

    conn
    |> put_resp_header("retry-after", "60")
    |> send_resp(429, "Too many requests")
    |> halt()
  end

  defp check_rate(conn, key, max_requests, time_window) do
    case ExRated.check_rate(key, time_window, max_requests) do
      {:ok, _count} ->
        nil

      {:error, _limit} ->
        {:block, conn}
    end
  end

  defp remote_ip(conn) do
    conn.remote_ip
    |> :inet.ntoa()
    |> to_string()
  end
end
