defmodule JidoHub.Organizations.Organization.Validations.ValidateSlug do
  @moduledoc """
  Validates that an organization slug is not a reserved slug and meets format requirements.
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    slug = Ash.Changeset.get_attribute(changeset, :slug)

    if slug do
      case JidoHub.Slugs.validate_slug(slug) do
        :ok ->
          :ok

        {:error, reason} ->
          {:error, field: :slug, message: reason}
      end
    else
      :ok
    end
  end
end
