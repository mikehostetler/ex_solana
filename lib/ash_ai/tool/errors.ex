# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Tool.Errors do
  @moduledoc false

  require Logger

  alias Ash.Error.{Forbidden, Framework, Invalid, Unknown}

  @doc """
  Converts Ash errors to JSON:API error format.
  """
  @spec to_json_api_errors(module(), module(), list() | struct(), atom()) :: list()
  def to_json_api_errors(domain, resource, errors, type) when is_list(errors) do
    Enum.flat_map(errors, &to_json_api_errors(domain, resource, &1, type))
  end

  def to_json_api_errors(domain, resource, %mod{errors: errors}, type)
      when mod in [Forbidden, Framework, Invalid, Unknown] do
    Enum.flat_map(errors, &to_json_api_errors(domain, resource, &1, type))
  end

  def to_json_api_errors(_domain, _resource, %AshJsonApi.Error{} = error, _type) do
    [error]
  end

  def to_json_api_errors(domain, _resource, %{class: :invalid} = error, _type) do
    if AshJsonApi.ToJsonApiError.impl_for(error) do
      error
      |> AshJsonApi.ToJsonApiError.to_json_api_error()
      |> List.wrap()
      |> Enum.flat_map(&with_source_pointer(&1, error))
    else
      uuid = Ash.UUID.generate()

      stacktrace =
        case error do
          %{stacktrace: %{stacktrace: v}} ->
            v

          _ ->
            nil
        end

      Logger.warning(
        "`#{uuid}`: AshJsonApi.Error not implemented for error:\n\n#{Exception.format(:error, error, stacktrace)}"
      )

      if AshJsonApi.Domain.Info.show_raised_errors?(domain) do
        [
          %AshJsonApi.Error{
            id: uuid,
            status_code: class_to_status(error.class),
            code: "something_went_wrong",
            title: "SomethingWentWrong",
            detail: """
            Raised error: #{uuid}

            #{Exception.format(:error, error, stacktrace)}"
            """
          }
        ]
      else
        [
          %AshJsonApi.Error{
            id: uuid,
            status_code: class_to_status(error.class),
            code: "something_went_wrong",
            title: "SomethingWentWrong",
            detail: "Something went wrong. Error id: #{uuid}"
          }
        ]
      end
    end
  end

  def to_json_api_errors(_domain, _resource, %{class: :forbidden} = error, _type) do
    [
      %AshJsonApi.Error{
        id: Ash.UUID.generate(),
        status_code: class_to_status(error.class),
        code: "forbidden",
        title: "Forbidden",
        detail: "forbidden"
      }
    ]
  end

  def to_json_api_errors(_domain, _resource, error, _type) do
    uuid = Ash.UUID.generate()

    stacktrace =
      case error do
        %{stacktrace: %{stacktrace: v}} ->
          v

        _ ->
          nil
      end

    Logger.warning(
      "`#{uuid}`: AshJsonApi.Error not implemented for error:\n\n#{Exception.format(:error, error, stacktrace)}"
    )

    [
      %AshJsonApi.Error{
        id: uuid,
        status_code: class_to_status(error.class),
        code: "something_went_wrong",
        title: "SomethingWentWrong",
        detail: "Something went wrong. Error id: #{uuid}"
      }
    ]
  end

  @doc "Turns an error class into an HTTP status code"
  @spec class_to_status(atom()) :: integer()
  def class_to_status(:forbidden), do: 403
  def class_to_status(:invalid), do: 400
  def class_to_status(_), do: 500

  @doc """
  Serializes errors to JSON format.
  """
  @spec serialize_errors(list() | struct()) :: list()
  def serialize_errors(errors) do
    errors
    |> List.wrap()
    |> Enum.map(fn error ->
      %{}
      |> add_if_defined(:id, error.id)
      |> add_if_defined(:status, to_string(error.status_code))
      |> add_if_defined(:code, error.code)
      |> add_if_defined(:title, error.title)
      |> add_if_defined(:detail, error.detail)
      |> add_if_defined([:source, :pointer], error.source_pointer)
      |> add_if_defined([:source, :parameter], error.source_parameter)
      |> add_if_defined(:meta, parse_error(error.meta))
    end)
  end

  @doc """
  Adds source pointer information to error.
  """
  @spec with_source_pointer(map(), map()) :: list()
  def with_source_pointer(%{source_pointer: source_pointer} = built_error, _)
      when source_pointer not in [nil, :undefined] do
    [built_error]
  end

  def with_source_pointer(built_error, %{fields: fields, path: path})
      when is_list(fields) and fields != [] do
    Enum.map(fields, fn field ->
      %{built_error | source_pointer: source_pointer(field, path)}
    end)
  end

  def with_source_pointer(built_error, %{field: field, path: path})
      when not is_nil(field) do
    [
      %{built_error | source_pointer: source_pointer(field, path)}
    ]
  end

  def with_source_pointer(built_error, _) do
    [built_error]
  end

  @doc """
  Constructs a JSON pointer for the error source.
  """
  @spec source_pointer(atom() | String.t(), list() | nil) :: String.t()
  def source_pointer(field, path) do
    "/input/#{Enum.join(List.wrap(path) ++ [field], "/")}"
  end

  @spec add_if_defined(map(), atom() | list(), any()) :: map()
  defp add_if_defined(params, _, :undefined) do
    params
  end

  defp add_if_defined(params, [key1, key2], value) do
    params
    |> Map.put_new(key1, %{})
    |> Map.update!(key1, &Map.put(&1, key2, value))
  end

  defp add_if_defined(params, key, value) do
    Map.put(params, key, value)
  end

  @spec parse_error(any()) :: any()
  defp parse_error(%{match: %Regex{} = match} = error) do
    %{error | match: Regex.source(match)}
  end

  defp parse_error(error), do: error
end
