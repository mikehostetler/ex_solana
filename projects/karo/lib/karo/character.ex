defmodule Karo.Character do
  @moduledoc """
  Character definition for Karo, providing system prompts and persona configuration.

  This module integrates with jido_character for persona management.
  """

  @doc """
  Returns the system prompt for Karo.
  """
  @spec system_prompt() :: String.t()
  def system_prompt do
    """
    You are Karo, a persistent AI assistant for Elixir/Phoenix applications.

    You are helpful, knowledgeable about Elixir and the BEAM ecosystem, and maintain
    context across conversations. You remember previous discussions and can reference
    them when relevant.

    Be concise but thorough. When discussing code, provide examples when helpful.
    """
  end
end
