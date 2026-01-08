defmodule JidoWorkspace.LLM do
  @moduledoc """
  Unified LLM interface for the roadmap workflow system.

  Supports multiple backends:
  - `:claude_code` - Claude Code SDK (default, for agentic workflows)
  - `:req_llm` - ReqLLM for direct API calls (configurable models)

  ## Configuration

      config :jido_workspace, :llm,
        provider: :claude_code,
        model: "claude-sonnet-4-20250514"

  ## Usage

      # Stream with live output
      result = JidoWorkspace.LLM.run("Explain this code")

      # Silent execution (no streaming to stdout)
      result = JidoWorkspace.LLM.run("Generate JSON", stream: false)

      # Custom chunk handler
      result = JidoWorkspace.LLM.run("Explain", on_chunk: &Logger.info/1)
  """

  require Logger

  @default_provider :claude_code

  @doc """
  Run a prompt through the configured LLM provider.

  ## Options

  - `:stream` - Whether to stream output (default: true)
  - `:on_chunk` - Callback for each text chunk (default: `&IO.write/1`)
  - `:provider` - Override the configured provider
  - `:model` - Override the configured model (for req_llm)
  """
  def run(prompt, opts \\ []) do
    provider = opts[:provider] || config(:provider, @default_provider)
    stream = Keyword.get(opts, :stream, true)

    case provider do
      :claude_code -> run_claude_code(prompt, stream, opts)
      :req_llm -> run_req_llm(prompt, stream, opts)
      other -> raise "Unknown LLM provider: #{inspect(other)}"
    end
  end

  @doc """
  Run a prompt and parse the result as JSON.
  Useful for structured LLM outputs like PRDs.
  """
  def run_json(prompt, opts \\ []) do
    result = run(prompt, Keyword.put(opts, :stream, false))

    case extract_json(result) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, reason} -> {:error, reason, result}
    end
  end

  @doc """
  Run a prompt and parse the result as YAML.
  """
  def run_yaml(prompt, opts \\ []) do
    result = run(prompt, Keyword.put(opts, :stream, false))

    case YamlElixir.read_from_string(result) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, reason} -> {:error, reason, result}
    end
  end

  defp run_claude_code(prompt, stream, opts) do
    on_chunk = if stream, do: Keyword.get(opts, :on_chunk, &IO.write/1), else: fn _ -> :ok end

    prompt
    |> ClaudeCodeSDK.query()
    |> Enum.reduce("", fn message, acc ->
      case message do
        %{"type" => "assistant", "message" => %{"content" => content}} ->
          text = extract_text(content)
          on_chunk.(text)
          acc <> text

        %{"type" => "result", "result" => result_text} when is_binary(result_text) ->
          acc <> result_text

        _ ->
          acc
      end
    end)
  end

  defp run_req_llm(prompt, stream, opts) do
    model = opts[:model] || config(:model, "anthropic:claude-sonnet-4-20250514")
    on_chunk = if stream, do: Keyword.get(opts, :on_chunk, &IO.write/1), else: fn _ -> :ok end

    messages = [
      %{role: "user", content: prompt}
    ]

    if stream do
      case ReqLLM.stream_text(model, messages) do
        {:ok, stream_response} ->
          text =
            stream_response.stream
            |> Enum.reduce("", fn chunk, acc ->
              delta = chunk.content || ""
              on_chunk.(delta)
              acc <> delta
            end)

          text

        {:error, reason} ->
          Logger.error("ReqLLM stream error: #{inspect(reason)}")
          ""
      end
    else
      case ReqLLM.generate_text(model, messages) do
        {:ok, response} ->
          text = response.text || ""
          on_chunk.(text)
          text

        {:error, reason} ->
          Logger.error("ReqLLM error: #{inspect(reason)}")
          ""
      end
    end
  end

  defp extract_text(content) when is_list(content) do
    content
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map(& &1["text"])
    |> Enum.join("")
  end

  defp extract_text(_), do: ""

  defp extract_json(text) do
    trimmed = String.trim(text)

    json_text =
      cond do
        String.starts_with?(trimmed, "```json") ->
          trimmed
          |> String.replace_prefix("```json", "")
          |> String.replace_suffix("```", "")
          |> String.trim()

        String.starts_with?(trimmed, "```") ->
          trimmed
          |> String.replace_prefix("```", "")
          |> String.replace_suffix("```", "")
          |> String.trim()

        true ->
          trimmed
      end

    case Jason.decode(json_text) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _} = err -> err
    end
  end

  defp config(key, default) do
    Application.get_env(:jido_workspace, :llm, [])
    |> Keyword.get(key, default)
  end
end
