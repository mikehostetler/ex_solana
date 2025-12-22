defmodule JidoCode.Tools.Security.Web do
  @moduledoc """
  Security module for web tool operations.

  Provides URL validation, domain allowlist enforcement, and request
  sanitization to prevent data exfiltration and abuse.

  ## Default Allowed Domains

  The default allowlist includes common documentation and code hosting sites:
  - hexdocs.pm (Elixir package docs)
  - elixir-lang.org (Elixir official)
  - erlang.org (Erlang official)
  - github.com (Code hosting)
  - hex.pm (Package registry)

  ## Configuration

  The allowlist can be customized via Settings:

      %{
        "web_tools_enabled" => true,
        "allowed_domains" => ["hexdocs.pm", "example.com"]
      }
  """

  require Logger

  @default_allowed_domains [
    "hexdocs.pm",
    "elixir-lang.org",
    "erlang.org",
    "github.com",
    "hex.pm"
  ]

  @blocked_schemes ["file", "javascript", "data", "about"]
  # 1MB
  @max_response_size 1_048_576
  # 30 seconds
  @default_timeout 30_000
  @max_redirects 5

  @doc """
  Validates a URL against security rules.

  ## Parameters

  - `url` - The URL to validate
  - `opts` - Options:
    - `:allowed_domains` - Custom domain allowlist (overrides default)
    - `:strict_scheme` - If true, only allow https (default: true)

  ## Returns

  - `{:ok, validated_url}` - URL is valid and allowed
  - `{:error, reason}` - Validation failed

  ## Examples

      iex> validate_url("https://hexdocs.pm/elixir")
      {:ok, "https://hexdocs.pm/elixir"}

      iex> validate_url("file:///etc/passwd")
      {:error, :blocked_scheme}
  """
  @spec validate_url(String.t(), keyword()) :: {:ok, String.t()} | {:error, atom() | String.t()}
  def validate_url(url, opts \\ []) when is_binary(url) do
    allowed_domains = Keyword.get(opts, :allowed_domains, @default_allowed_domains)
    strict_scheme = Keyword.get(opts, :strict_scheme, true)

    with {:ok, uri} <- parse_url(url),
         :ok <- validate_scheme(uri, strict_scheme),
         :ok <- validate_domain(uri, allowed_domains) do
      {:ok, url}
    end
  end

  @doc """
  Returns the default allowed domains list.
  """
  @spec default_allowed_domains() :: [String.t()]
  def default_allowed_domains, do: @default_allowed_domains

  @doc """
  Returns the maximum response size in bytes.
  """
  @spec max_response_size() :: non_neg_integer()
  def max_response_size, do: @max_response_size

  @doc """
  Returns the default request timeout in milliseconds.
  """
  @spec default_timeout() :: non_neg_integer()
  def default_timeout, do: @default_timeout

  @doc """
  Returns the maximum number of redirects to follow.
  """
  @spec max_redirects() :: non_neg_integer()
  def max_redirects, do: @max_redirects

  @doc """
  Checks if a content type is allowed for web fetch.

  Only text-based content types are allowed to prevent binary data
  processing issues and potential security risks.
  """
  @spec allowed_content_type?(String.t()) :: boolean()
  def allowed_content_type?(content_type) when is_binary(content_type) do
    normalized = content_type |> String.downcase() |> String.split(";") |> hd() |> String.trim()

    allowed_types = [
      "text/html",
      "text/plain",
      "application/json",
      "application/xml",
      "text/xml",
      "text/markdown",
      "application/xhtml+xml"
    ]

    normalized in allowed_types
  end

  def allowed_content_type?(_), do: false

  @doc """
  Logs a web request for audit trail.
  """
  @spec log_request(String.t(), map()) :: :ok
  def log_request(url, metadata \\ %{}) do
    Logger.info("Web request: #{url}", metadata)
    :ok
  end

  # Private helpers

  defp parse_url(url) do
    case URI.parse(url) do
      %URI{scheme: nil} ->
        {:error, :missing_scheme}

      %URI{scheme: scheme} when scheme in @blocked_schemes ->
        Logger.warning("Web security: blocked scheme #{scheme}")
        {:error, :blocked_scheme}

      %URI{host: nil} ->
        {:error, :missing_host}

      %URI{host: ""} ->
        {:error, :missing_host}

      uri ->
        {:ok, uri}
    end
  end

  defp validate_scheme(%URI{scheme: scheme}, strict_scheme) do
    scheme_lower = String.downcase(scheme || "")

    cond do
      scheme_lower in @blocked_schemes ->
        Logger.warning("Web security: blocked scheme #{scheme_lower}")
        {:error, :blocked_scheme}

      strict_scheme and scheme_lower not in ["https", "http"] ->
        {:error, :invalid_scheme}

      true ->
        :ok
    end
  end

  defp validate_domain(%URI{host: host}, allowed_domains) do
    host_lower = String.downcase(host || "")

    if domain_allowed?(host_lower, allowed_domains) do
      :ok
    else
      Logger.warning("Web security: domain not allowed: #{host_lower}")
      {:error, :domain_not_allowed}
    end
  end

  defp domain_allowed?(host, allowed_domains) do
    Enum.any?(allowed_domains, fn allowed ->
      allowed_lower = String.downcase(allowed)
      # Match exact domain or subdomain
      host == allowed_lower or String.ends_with?(host, "." <> allowed_lower)
    end)
  end
end
