defmodule Karo.LLM do
  @moduledoc """
  LLM integration for Karo using req_llm.

  This module wraps the LLM API calls and handles configuration.
  """

  require Logger

  @doc """
  Send a chat request to the configured LLM.

  Messages should be a list of maps with :role and :content keys.

  ## Options
  - :model - Override the default model
  - :temperature - Override the default temperature
  """
  @spec chat([map()], keyword()) :: {:ok, String.t()} | {:error, term()}
  def chat(messages, opts \\ []) do
    config = Application.get_env(:karo, :llm, [])

    # For now, return a stub response
    # TODO: Integrate with req_llm
    if config[:api_key] do
      do_chat(messages, Keyword.merge(config, opts))
    else
      Logger.debug("LLM API key not configured, using stub response")
      {:ok, generate_stub_response(messages)}
    end
  end

  @spec do_chat([map()], keyword()) :: {:ok, String.t()} | {:error, term()}
  defp do_chat(_messages, _config) do
    # TODO: Implement actual req_llm integration with req_llm
    # provider = Keyword.get(config, :provider, :openai)
    # model = Keyword.get(config, :model, "gpt-4o-mini")
    {:ok, "Hello! I'm Karo, your AI assistant. (LLM integration pending)"}
  end

  defp generate_stub_response(messages) do
    last_message = List.last(messages)
    content = if last_message, do: last_message[:content] || last_message["content"], else: ""

    "Hello! I'm Karo. I received your message: \"#{String.slice(content, 0, 50)}...\" " <>
      "(This is a stub response - configure LLM API key for real responses)"
  end
end
