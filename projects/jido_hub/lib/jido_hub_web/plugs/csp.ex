defmodule JidoHubWeb.Plugs.CSP do
  @moduledoc """
  Content Security Policy plug with LiveView nonce support.

  Generates a cryptographically strong nonce per request and sets
  strict CSP headers that work with Phoenix LiveView's dynamic
  script/style requirements.
  """

  import Plug.Conn

  @doc """
  Generates a nonce and sets the Content-Security-Policy header.
  """
  def init(opts), do: opts

  def call(conn, _opts) do
    nonce = generate_nonce()

    csp_header = build_csp_header(nonce)

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy", csp_header)
  end

  defp generate_nonce do
    Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  end

  defp build_csp_header(nonce) do
    env = JidoHub.config(:env, :prod)

    {script_src, style_src} =
      if env in [:dev, :test] do
        {"script-src 'self' 'unsafe-eval' 'nonce-#{nonce}'",
         "style-src 'self' 'unsafe-inline' 'nonce-#{nonce}'"}
      else
        {"script-src 'self' 'nonce-#{nonce}'", "style-src 'self' 'nonce-#{nonce}'"}
      end

    [
      "default-src 'self'",
      "base-uri 'self'",
      "frame-ancestors 'self'",
      "form-action 'self'",
      "img-src 'self' data: https:",
      "font-src 'self' data:",
      script_src,
      style_src,
      "connect-src 'self' ws: wss:"
    ]
    |> Enum.join("; ")
  end
end
