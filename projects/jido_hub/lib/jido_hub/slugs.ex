defmodule JidoHub.Slugs do
  @moduledoc """
  Utilities for validating and working with slugs.
  Prevents use of reserved route names and enforces slug format rules.
  """

  @reserved_slugs ~w(
    login signup reset confirm logout magic_link auth
    admin dashboard settings
    api dev rpc ash-typescript
    privacy terms features pricing faq about contact
    storybook
  )

  @doc """
  Returns the list of reserved slugs that cannot be used for users or organizations.
  """
  def reserved_slugs, do: @reserved_slugs

  @doc """
  Validates a slug for format and reserved keywords.

  Returns `:ok` if valid, or `{:error, reason}` if invalid.

  ## Rules
  - Must be 3-39 characters
  - Lowercase letters, numbers, and hyphens only
  - Cannot be a reserved keyword
  - Cannot start or end with a hyphen
  - Cannot contain consecutive hyphens

  ## Examples

      iex> JidoHub.Slugs.validate_slug("valid-slug-123")
      :ok

      iex> JidoHub.Slugs.validate_slug("admin")
      {:error, "admin is a reserved slug"}

      iex> JidoHub.Slugs.validate_slug("AB")
      {:error, "must be between 3 and 39 characters"}
  """
  def validate_slug(slug) when is_binary(slug) do
    cond do
      String.length(slug) < 3 or String.length(slug) > 39 ->
        {:error, "must be between 3 and 39 characters"}

      slug in @reserved_slugs ->
        {:error, "#{slug} is a reserved slug"}

      not valid_format?(slug) ->
        {:error, "must contain only lowercase letters, numbers, and hyphens"}

      String.starts_with?(slug, "-") or String.ends_with?(slug, "-") ->
        {:error, "cannot start or end with a hyphen"}

      String.contains?(slug, "--") ->
        {:error, "cannot contain consecutive hyphens"}

      true ->
        :ok
    end
  end

  def validate_slug(_), do: {:error, "must be a string"}

  defp valid_format?(slug) do
    Regex.match?(~r/^[a-z0-9-]+$/, slug)
  end

  @doc """
  Resolves a slug to either a User or Organization.
  This is a stub for future implementation.
  """
  @spec resolve(String.t()) ::
          {:ok, {:user, map()} | {:org, map()}} | {:error, :not_found}
  def resolve(slug) when is_binary(slug) do
    # TODO: Implement actual resolution in a later step
    # Conditional to satisfy gradual typing until implementation
    if false do
      {:ok, {:user, %{}}}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Resolves owner and pod slugs.
  This is a stub for future implementation.
  """
  @spec resolve_owner_and_pod(String.t(), String.t()) ::
          {:ok, %{owner: map(), pod: map()}} | {:error, :not_found}
  def resolve_owner_and_pod(owner_slug, pod_slug)
      when is_binary(owner_slug) and is_binary(pod_slug) do
    # TODO: Implement actual resolution in a later step
    # Conditional to satisfy gradual typing until implementation
    if false do
      {:ok, %{owner: %{}, pod: %{}}}
    else
      {:error, :not_found}
    end
  end
end
