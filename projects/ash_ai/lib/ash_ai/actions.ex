# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Actions do
  @moduledoc "Builtin generic action implementations"

  defmacro prompt(model, opts \\ []) do
    {model, function1} =
      Spark.CodeHelpers.lift_functions(model, :ash_ai_prompt_model, __CALLER__)

    {opts, function3} =
      Spark.CodeHelpers.lift_functions(opts, :ash_ai_prompt_opts, __CALLER__)

    quote do
      unquote(function1)
      unquote(function3)

      {AshAi.Actions.Prompt, Keyword.merge(unquote(opts), model: unquote(model))}
    end
  end
end
