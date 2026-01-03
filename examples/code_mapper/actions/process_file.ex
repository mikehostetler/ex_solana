defmodule CodeMapper.Actions.ProcessFile do
  @moduledoc """
  Action to process a single file - parse AST and emit result.
  """

  use Jido.Action,
    name: "process_file",
    description: "Parse a file's AST and extract metadata",
    schema: [
      path: [type: :string, required: true, doc: "Path to the file to process"]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  require Logger

  @impl true
  def run(params, context) do
    path = params.path
    agent = context.state

    Logger.info("[ProcessFile] Analyzing: #{path}")

    # Step 1: Parse AST (synchronous)
    {ast_meta, refs, public_api} = parse_file(path)

    # Build result
    file_result = %{
      path: path,
      language: "elixir",
      ast_meta: ast_meta,
      refs: refs,
      public_api: public_api,
      summary: "[DRY_RUN] Summary for #{Path.basename(path)}"
    }

    # Emit result to parent
    result_signal = Signal.new!("file.done", %{file: file_result}, source: "/file")

    # Check if agent has a parent
    directives =
      case agent do
        %{__parent__: %{pid: pid}} when is_pid(pid) ->
          [Directive.emit_to_pid(result_signal, pid)]

        _ ->
          Logger.warning("[ProcessFile] No parent to send result to")
          []
      end

    {:ok, %{file_result: file_result}, directives}
  end

  defp parse_file(path) do
    case File.read(path) do
      {:ok, source} ->
        parse_elixir_source(source, path)

      {:error, reason} ->
        Logger.warning("[ProcessFile] Failed to read #{path}: #{reason}")
        {%{error: reason}, [], []}
    end
  end

  defp parse_elixir_source(source, path) do
    case Code.string_to_quoted(source, file: path) do
      {:ok, ast} ->
        extract_from_ast(ast)

      {:error, {line, error, _}} ->
        Logger.warning("[ProcessFile] Parse error in #{path}:#{line}: #{inspect(error)}")
        {%{parse_error: error, line: line}, [], []}
    end
  end

  defp extract_from_ast(ast) do
    acc = %{modules: [], functions: [], imports: [], aliases: [], uses: []}
    result = walk_ast(ast, acc)

    ast_meta = %{
      modules: result.modules,
      functions: result.functions,
      imports: result.imports,
      aliases: result.aliases,
      uses: result.uses
    }

    refs =
      Enum.map(result.imports, fn mod -> %{to: mod, type: :import} end) ++
        Enum.map(result.aliases, fn mod -> %{to: mod, type: :alias} end) ++
        Enum.map(result.uses, fn mod -> %{to: mod, type: :use} end)

    public_api =
      result.functions
      |> Enum.filter(fn f -> f.visibility == :public end)
      |> Enum.map(fn f -> %{name: f.name, arity: f.arity, kind: :function} end)

    {ast_meta, refs, public_api}
  end

  defp walk_ast(ast, acc) do
    {_, acc} =
      Macro.prewalk(ast, acc, fn
        {:defmodule, _, [{:__aliases__, _, parts} | _]} = node, acc ->
          mod_name = Enum.join(parts, ".")
          {node, %{acc | modules: [mod_name | acc.modules]}}

        {:def, _, [{name, _, args} | _]} = node, acc when is_atom(name) ->
          arity = if is_list(args), do: length(args), else: 0
          func = %{name: name, arity: arity, visibility: :public}
          {node, %{acc | functions: [func | acc.functions]}}

        {:defp, _, [{name, _, args} | _]} = node, acc when is_atom(name) ->
          arity = if is_list(args), do: length(args), else: 0
          func = %{name: name, arity: arity, visibility: :private}
          {node, %{acc | functions: [func | acc.functions]}}

        {:import, _, [{:__aliases__, _, parts} | _]} = node, acc ->
          mod_name = Enum.join(parts, ".")
          {node, %{acc | imports: [mod_name | acc.imports]}}

        {:alias, _, [{:__aliases__, _, parts} | _]} = node, acc ->
          mod_name = Enum.join(parts, ".")
          {node, %{acc | aliases: [mod_name | acc.aliases]}}

        {:use, _, [{:__aliases__, _, parts} | _]} = node, acc ->
          mod_name = Enum.join(parts, ".")
          {node, %{acc | uses: [mod_name | acc.uses]}}

        node, acc ->
          {node, acc}
      end)

    acc
  end
end
