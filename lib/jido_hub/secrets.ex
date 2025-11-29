defmodule JidoHub.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        JidoHub.Accounts.User,
        _opts,
        _context
      ) do
    case Application.fetch_env(:jido_hub, :token_signing_secret) do
      {:ok, secret} ->
        {:ok, secret}

      :error ->
        raise """
        Token signing secret not configured!
        Add to config/runtime.exs:

          config :jido_hub, :token_signing_secret, System.get_env("TOKEN_SIGNING_SECRET")
        """
    end
  end
end
