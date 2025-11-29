defmodule Jido.HTN.Domain.Builder.Validator do
  @moduledoc """
  Behaviour for custom domain validators.

  Custom validators can be implemented to extend domain validation beyond the
  default validation rules. Validators receive the domain structure and return
  either `:ok`, `{:ok, domain}`, or `{:error, reason}`.

  ## Example

      defmodule MyApp.CustomValidator do
        @behaviour Jido.HTN.Domain.Builder.Validator

        @impl true
        def validate(%Jido.HTN.Domain{} = domain) do
          if meets_custom_criteria?(domain) do
            {:ok, domain}
          else
            {:error, "Custom validation failed"}
          end
        end

        defp meets_custom_criteria?(_domain), do: true
      end

      # Use the custom validator
      domain =
        Domain.new("my_domain")
        |> Domain.compound("task1", methods: [...])
        |> Domain.root("task1")
        |> Domain.build(custom_validators: [&MyApp.CustomValidator.validate/1])
  """

  alias Jido.HTN.Domain

  @doc """
  Validates a domain and returns a validation result.

  ## Return Values

  - `:ok` - Domain is valid, continue with original domain
  - `{:ok, domain}` - Domain is valid, use returned domain (allows transformation)
  - `{:error, reason}` - Validation failed with reason (string or list of strings)
  """
  @callback validate(Domain.t()) :: :ok | {:ok, Domain.t()} | {:error, String.t() | [String.t()]}
end
