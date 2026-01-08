defmodule JidoFlame.Actions.RemoteCall do
  @moduledoc """
  Action to execute a function on a remote FLAME runner.

  Supports both MFA (module/function/args) and raw function syntax.

  ## Examples

      # With MFA
      params = %{
        pool: MyApp.FlamePool,
        mfa: %{module: MyModule, function: :my_function, args: [1, 2]}
      }

      # With function
      params = %{
        pool: MyApp.FlamePool,
        fun: fn -> expensive_computation() end
      }
  """

  use Jido.Action,
    name: "jido_flame_remote_call",
    description: "Execute a function on a remote FLAME runner",
    category: "flame",
    tags: ["flame", "remote", "execution"],
    vsn: "1.0.0",
    schema: [
      pool: [type: :atom, required: true, doc: "FLAME pool name"],
      mfa: [type: :map, doc: "Map with :module, :function, :args keys"],
      fun: [type: :any, doc: "0-arity function (alternative to mfa)"],
      opts: [type: :keyword_list, default: [], doc: "Options for FLAME.call/3"],
      timeout: [type: :integer, default: 30_000, doc: "Call timeout in milliseconds"],
      result_type: [type: :string, doc: "CloudEvents type for result signal (optional)"],
      result_dispatch: [type: :any, doc: "Dispatch config for result signal (optional)"],
      tag: [type: :any, doc: "Correlation tag (optional)"]
    ]

  alias JidoFlame.Directive.RemoteCall

  @impl true
  def run(params, _context) do
    # Build the function from MFA or use provided function
    fun = build_function(params)

    # Build FLAME options
    opts = Keyword.merge(params[:opts] || [], timeout: params[:timeout] || 30_000)

    # Create the directive
    directive_attrs = %{
      pool: params.pool,
      fun: fun,
      opts: opts,
      result_type: params[:result_type],
      result_dispatch: params[:result_dispatch],
      tag: params[:tag]
    }

    case RemoteCall.new(directive_attrs) do
      {:ok, directive} ->
        {:ok, %{directive_type: :remote_call, pool: params.pool}, [directive]}

      {:error, error} ->
        {:error, error}
    end
  end

  defp build_function(%{fun: fun}) when is_function(fun, 0), do: fun

  defp build_function(%{mfa: %{module: mod, function: func, args: args}}) do
    fn -> apply(mod, func, args) end
  end

  defp build_function(%{mfa: %{module: mod, function: func}}) do
    fn -> apply(mod, func, []) end
  end

  defp build_function(_), do: fn -> :no_function_provided end
end
