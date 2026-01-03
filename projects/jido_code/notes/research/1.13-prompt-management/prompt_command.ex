defmodule JidoCode.TUI.Commands.PromptCommand do
  @moduledoc """
  TUI command handlers for prompt management.
  
  This module implements the `/prompt` command family for managing
  user-defined prompts in JidoCode.
  
  ## Commands
  
      /prompt use <slug>           - Load a prompt into the current context
      /prompt list [--category=X]  - List available prompts
      /prompt show <slug>          - Display prompt details
      /prompt new                  - Create a new prompt interactively
      /prompt edit <slug>          - Edit an existing prompt
      /prompt delete <slug>        - Delete a prompt
      /prompt search <query>       - Search prompts
      /prompt categories           - List available categories
      /prompt import <file>        - Import prompt from markdown file
      /prompt export <slug>        - Export prompt to markdown file
  """

  alias JidoCode.Prompt
  alias JidoCode.Prompt.Repository

  @behaviour JidoCode.TUI.Command

  @impl true
  def name, do: "prompt"

  @impl true
  def aliases, do: ["p"]

  @impl true
  def description, do: "Manage and use prompts"

  @impl true
  def usage do
    """
    Usage: /prompt <subcommand> [arguments]
    
    Subcommands:
      use <slug>           Load a prompt into the current context
      list [--category=X]  List available prompts
      show <slug>          Display prompt details
      new                  Create a new prompt interactively
      edit <slug>          Edit an existing prompt
      delete <slug>        Delete a prompt (with confirmation)
      search <query>       Search prompts by text
      categories           List available categories
      import <file>        Import prompt from markdown file
      export <slug>        Export prompt to markdown file
    
    Examples:
      /prompt list
      /prompt list --category=code-review
      /prompt use my-review-prompt
      /prompt show my-review-prompt
      /prompt search elixir review
      /prompt new
    """
  end

  @impl true
  def execute(args, context) do
    case args do
      ["use", slug] -> execute_use(slug, context)
      ["use", slug | var_args] -> execute_use_with_vars(slug, var_args, context)
      ["list" | opts] -> execute_list(opts, context)
      ["show", slug] -> execute_show(slug, context)
      ["new"] -> execute_new(context)
      ["edit", slug] -> execute_edit(slug, context)
      ["delete", slug] -> execute_delete(slug, context)
      ["search" | terms] -> execute_search(Enum.join(terms, " "), context)
      ["categories"] -> execute_categories(context)
      ["import", file_path] -> execute_import(file_path, context)
      ["export", slug] -> execute_export(slug, context)
      [] -> {:ok, %{action: :display, content: usage()}}
      _ -> {:error, "Unknown subcommand. Use /prompt for help."}
    end
  end

  # /prompt use <slug>
  defp execute_use(slug, context) do
    with {:ok, prompt} <- Repository.get(slug) do
      required = Prompt.required_variables(prompt)

      if Enum.empty?(required) do
        # No variables needed, interpolate with defaults
        {:ok, content} = Prompt.interpolate(prompt, %{})

        {:ok,
         %{
           action: :inject_prompt,
           prompt: prompt,
           content: content,
           message: format_prompt_loaded(prompt, %{})
         }}
      else
        # Need to collect variables
        {:ok,
         %{
           action: :collect_variables,
           prompt: prompt,
           required: required,
           optional: Prompt.optional_variables(prompt),
           message: format_variable_request(prompt)
         }}
      end
    else
      {:error, :not_found} ->
        {:error, "Prompt '#{slug}' not found. Use /prompt list to see available prompts."}

      {:error, reason} ->
        {:error, "Failed to load prompt: #{inspect(reason)}"}
    end
  end

  # /prompt use <slug> key=value key=value
  defp execute_use_with_vars(slug, var_args, _context) do
    with {:ok, prompt} <- Repository.get(slug),
         {:ok, vars} <- parse_variable_args(var_args),
         {:ok, content} <- Prompt.interpolate(prompt, vars) do
      {:ok,
       %{
         action: :inject_prompt,
         prompt: prompt,
         content: content,
         message: format_prompt_loaded(prompt, vars)
       }}
    else
      {:error, :not_found} ->
        {:error, "Prompt '#{slug}' not found."}

      {:error, {:missing_variables, names}} ->
        {:error, "Missing required variables: #{Enum.join(names, ", ")}"}

      {:error, reason} ->
        {:error, "Failed to load prompt: #{inspect(reason)}"}
    end
  end

  # /prompt list [--category=X]
  defp execute_list(opts, _context) do
    filters = parse_list_options(opts)

    case Repository.list(filters) do
      {:ok, prompts} ->
        {:ok,
         %{
           action: :display,
           content: format_prompt_list(prompts, filters[:category])
         }}

      {:error, reason} ->
        {:error, "Failed to list prompts: #{inspect(reason)}"}
    end
  end

  # /prompt show <slug>
  defp execute_show(slug, _context) do
    case Repository.get(slug) do
      {:ok, prompt} ->
        {:ok,
         %{
           action: :display,
           content: format_prompt_details(prompt)
         }}

      {:error, :not_found} ->
        {:error, "Prompt '#{slug}' not found."}
    end
  end

  # /prompt new
  defp execute_new(_context) do
    {:ok,
     %{
       action: :interactive,
       handler: &handle_new_prompt/2,
       initial_state: %{step: :get_id, data: %{}},
       message: """
       Creating new prompt.
       
       Enter prompt ID (slug, e.g., 'my-review-prompt'):
       """
     }}
  end

  # /prompt edit <slug>
  defp execute_edit(slug, _context) do
    case Repository.get(slug) do
      {:ok, prompt} ->
        markdown = Prompt.to_markdown(prompt)

        {:ok,
         %{
           action: :edit,
           content: markdown,
           handler: &handle_edit_save/2,
           state: %{original_id: slug},
           message: "Editing prompt '#{slug}'. Modify the content below and save when done."
         }}

      {:error, :not_found} ->
        {:error, "Prompt '#{slug}' not found."}
    end
  end

  # /prompt delete <slug>
  defp execute_delete(slug, _context) do
    case Repository.get(slug) do
      {:ok, prompt} ->
        {:ok,
         %{
           action: :confirm,
           message: """
           Are you sure you want to delete prompt '#{prompt.name}' (#{slug})?
           This action cannot be undone. Type 'yes' to confirm:
           """,
           handler: fn
             "yes" ->
               case Repository.delete(slug) do
                 :ok -> {:ok, "✓ Prompt '#{slug}' deleted."}
                 {:error, reason} -> {:error, "Failed to delete: #{inspect(reason)}"}
               end

             _ ->
               {:ok, "Deletion cancelled."}
           end
         }}

      {:error, :not_found} ->
        {:error, "Prompt '#{slug}' not found."}
    end
  end

  # /prompt search <query>
  defp execute_search(query, _context) do
    case Repository.search(query) do
      {:ok, prompts} ->
        {:ok,
         %{
           action: :display,
           content: format_search_results(prompts, query)
         }}

      {:error, reason} ->
        {:error, "Search failed: #{inspect(reason)}"}
    end
  end

  # /prompt categories
  defp execute_categories(_context) do
    {:ok,
     %{
       action: :display,
       content: format_categories()
     }}
  end

  # /prompt import <file>
  defp execute_import(file_path, _context) do
    expanded_path = Path.expand(file_path)

    with {:ok, markdown} <- File.read(expanded_path),
         {:ok, prompt} <- Prompt.from_markdown(markdown),
         {:ok, saved} <- Repository.create(prompt) do
      {:ok,
       %{
         action: :display,
         content: "✓ Imported prompt '#{saved.name}' (#{saved.id})"
       }}
    else
      {:error, :enoent} ->
        {:error, "File not found: #{file_path}"}

      {:error, :no_frontmatter} ->
        {:error, "File does not contain valid frontmatter. See /prompt for format."}

      {:error, {:already_exists, id}} ->
        {:error, "A prompt with ID '#{id}' already exists. Use a different ID or delete the existing one."}

      {:error, reason} ->
        {:error, "Import failed: #{inspect(reason)}"}
    end
  end

  # /prompt export <slug>
  defp execute_export(slug, _context) do
    case Repository.get(slug) do
      {:ok, prompt} ->
        markdown = Prompt.to_markdown(prompt)
        filename = "#{slug}.md"

        {:ok,
         %{
           action: :save_file,
           content: markdown,
           filename: filename,
           message: "Exported prompt to #{filename}"
         }}

      {:error, :not_found} ->
        {:error, "Prompt '#{slug}' not found."}
    end
  end

  # Interactive prompt creation handler
  defp handle_new_prompt(input, %{step: :get_id, data: data}) do
    id = String.trim(input)

    if valid_id?(id) do
      if Repository.exists?(id) do
        {:continue,
         %{
           step: :get_id,
           data: data,
           message: "A prompt with ID '#{id}' already exists. Enter a different ID:"
         }}
      else
        {:continue,
         %{
           step: :get_name,
           data: Map.put(data, :id, id),
           message: "Enter prompt name (human-readable title):"
         }}
      end
    else
      {:continue,
       %{
         step: :get_id,
         data: data,
         message: "Invalid ID. Use only letters, numbers, hyphens, and underscores:"
       }}
    end
  end

  defp handle_new_prompt(input, %{step: :get_name, data: data}) do
    name = String.trim(input)

    if name != "" do
      {:continue,
       %{
         step: :get_type,
         data: Map.put(data, :name, name),
         message: """
         Select prompt type:
           1. system    - System-level context prompt
           2. user      - User interaction template
           3. assistant - Response template
           4. meta      - Prompt that generates prompts
           5. fragment  - Reusable partial prompt
           6. tool      - Tool definition prompt
           7. validation - Output validation prompt
         
         Enter number or type name:
         """
       }}
    else
      {:continue,
       %{
         step: :get_name,
         data: data,
         message: "Name cannot be empty. Enter prompt name:"
       }}
    end
  end

  defp handle_new_prompt(input, %{step: :get_type, data: data}) do
    type = parse_type_input(String.trim(input))

    if type do
      {:continue,
       %{
         step: :get_description,
         data: Map.put(data, :type, type),
         message: "Enter description (optional, press Enter to skip):"
       }}
    else
      {:continue,
       %{
         step: :get_type,
         data: data,
         message: "Invalid type. Enter a number (1-7) or type name:"
       }}
    end
  end

  defp handle_new_prompt(input, %{step: :get_description, data: data}) do
    description = String.trim(input)
    description = if description == "", do: nil, else: description

    {:continue,
     %{
       step: :get_categories,
       data: Map.put(data, :description, description),
       message: """
       Enter domain categories (comma-separated, e.g., 'code-review, elixir'):
       Available: coding, code-review, elixir, otp, phoenix, ecto, ash, etc.
       Press Enter to skip:
       """
     }}
  end

  defp handle_new_prompt(input, %{step: :get_categories, data: data}) do
    categories = parse_categories(String.trim(input))

    {:continue,
     %{
       step: :get_tags,
       data: Map.put(data, :categories, categories),
       message: "Enter tags (comma-separated, e.g., 'review, custom'):"
     }}
  end

  defp handle_new_prompt(input, %{step: :get_tags, data: data}) do
    tags = parse_tags(String.trim(input))

    {:continue,
     %{
       step: :get_content,
       data: Map.put(data, :tags, tags),
       message: """
       Now enter the prompt content (markdown format).
       Use {{variable_name}} for variables.
       
       Type your content, then enter '---END---' on a new line when done:
       """
     }}
  end

  defp handle_new_prompt(input, %{step: :get_content, data: data, content_buffer: buffer}) do
    if String.trim(input) == "---END---" do
      content = Enum.join(Enum.reverse(buffer), "\n")
      variables = extract_variables(content)

      prompt =
        Prompt.new(%{
          id: data.id,
          name: data.name,
          type: data.type,
          description: data.description,
          categories: data.categories,
          tags: data.tags,
          content: content,
          variables: variables
        })

      case Repository.create(prompt) do
        {:ok, saved} ->
          {:done, "✓ Prompt '#{saved.name}' (#{saved.id}) created successfully!"}

        {:error, reason} ->
          {:error, "Failed to create prompt: #{inspect(reason)}"}
      end
    else
      {:continue,
       %{
         step: :get_content,
         data: data,
         content_buffer: [input | buffer || []],
         message: nil
       }}
    end
  end

  defp handle_new_prompt(input, %{step: :get_content, data: data}) do
    handle_new_prompt(input, %{step: :get_content, data: data, content_buffer: []})
  end

  # Edit save handler
  defp handle_edit_save(markdown, %{original_id: original_id}) do
    with {:ok, prompt} <- Prompt.from_markdown(markdown) do
      # If ID changed, delete old and create new
      if prompt.id != original_id do
        with :ok <- Repository.delete(original_id),
             {:ok, saved} <- Repository.create(prompt) do
          {:ok, "✓ Prompt updated (ID changed from '#{original_id}' to '#{saved.id}')"}
        end
      else
        with {:ok, updated} <- Repository.update(original_id, Map.from_struct(prompt)) do
          {:ok, "✓ Prompt '#{updated.id}' updated successfully!"}
        end
      end
    else
      {:error, reason} ->
        {:error, "Failed to save: #{inspect(reason)}"}
    end
  end

  # Formatting helpers

  defp format_prompt_loaded(prompt, vars) do
    used_vars =
      if map_size(vars) > 0 do
        vars
        |> Enum.map(fn {k, v} -> "#{k}=#{inspect(v)}" end)
        |> Enum.join(", ")
        |> then(&"Variables: #{&1}")
      else
        ""
      end

    """
    ┌─────────────────────────────────────────────────────
    │ Prompt Loaded: #{prompt.name}
    │ Version: #{prompt.version}
    │ Type: #{prompt.type}
    #{if used_vars != "", do: "│ #{used_vars}", else: ""}
    └─────────────────────────────────────────────────────
    """
  end

  defp format_variable_request(prompt) do
    required = Prompt.required_variables(prompt)
    optional = Prompt.optional_variables(prompt)

    optional_str =
      optional
      |> Enum.map(fn {name, default} ->
        if default, do: "#{name} (default: #{default})", else: name
      end)
      |> Enum.join(", ")

    """
    [Prompt: #{prompt.name} v#{prompt.version}]
    
    Required variables: #{Enum.join(required, ", ")}
    #{if optional != [], do: "Optional variables: #{optional_str}", else: ""}
    
    Provide variables as: /prompt use #{prompt.slug} var1=value1 var2=value2
    Or paste content when prompted.
    """
  end

  defp format_prompt_list(prompts, category) do
    header = if category, do: "Prompts (#{category}):", else: "Available Prompts:"

    if Enum.empty?(prompts) do
      """
      #{header}
        (no prompts found)
      
      Use /prompt new to create one, or /prompt import <file> to import.
      """
    else
      items =
        prompts
        |> Enum.with_index(1)
        |> Enum.map(fn {p, i} ->
          slug = String.pad_trailing(p.slug || p.id, 25)
          "  #{i}. #{slug} #{p.name}"
        end)
        |> Enum.join("\n")

      """
      #{header}
      #{items}
      
      Use /prompt show <slug> for details, /prompt use <slug> to load.
      """
    end
  end

  defp format_prompt_details(prompt) do
    categories =
      prompt.categories
      |> Enum.map(fn {k, v} -> "    #{k}: #{format_category_value(v)}" end)
      |> Enum.join("\n")

    variables =
      prompt.variables
      |> Enum.map(fn v ->
        req = if v.required, do: "*", else: ""
        default = if v[:default], do: " = #{v[:default]}", else: ""
        "    #{v.name}#{req} (#{v.type})#{default}"
      end)
      |> Enum.join("\n")

    """
    ╔═══════════════════════════════════════════════════════════════╗
    ║ #{String.pad_trailing(prompt.name, 61)} ║
    ╠═══════════════════════════════════════════════════════════════╣
    ║ ID:          #{String.pad_trailing(prompt.id, 49)} ║
    ║ Slug:        #{String.pad_trailing(prompt.slug || prompt.id, 49)} ║
    ║ Type:        #{String.pad_trailing(to_string(prompt.type), 49)} ║
    ║ Version:     #{String.pad_trailing(prompt.version, 49)} ║
    ╠═══════════════════════════════════════════════════════════════╣
    ║ Description:                                                  ║
    ║   #{String.pad_trailing(prompt.description || "(none)", 61)} ║
    ╠═══════════════════════════════════════════════════════════════╣
    ║ Categories:                                                   ║
    #{format_box_content(categories)}
    ╠═══════════════════════════════════════════════════════════════╣
    ║ Variables (* = required):                                     ║
    #{format_box_content(if variables == "", do: "    (none)", else: variables)}
    ╠═══════════════════════════════════════════════════════════════╣
    ║ Tags: #{String.pad_trailing(Enum.join(prompt.tags, ", "), 55)} ║
    ╠═══════════════════════════════════════════════════════════════╣
    ║ Target:                                                       ║
    ║   Language: #{String.pad_trailing(prompt.target[:language] || "any", 50)} ║
    ║   Model:    #{String.pad_trailing(prompt.target[:model] || "any", 50)} ║
    ╠═══════════════════════════════════════════════════════════════╣
    ║ Created:  #{String.pad_trailing(format_datetime(prompt.created_at), 51)} ║
    ║ Modified: #{String.pad_trailing(format_datetime(prompt.modified_at), 51)} ║
    ║ Author:   #{String.pad_trailing(prompt.author || "unknown", 51)} ║
    ╚═══════════════════════════════════════════════════════════════╝

    Content Preview:
    ─────────────────────────────────────────────────────────────────
    #{String.slice(prompt.content, 0, 500)}#{if String.length(prompt.content) > 500, do: "\n... (truncated)", else: ""}
    ─────────────────────────────────────────────────────────────────
    """
  end

  defp format_box_content(content) do
    content
    |> String.split("\n")
    |> Enum.map(fn line -> "║ #{String.pad_trailing(line, 61)} ║" end)
    |> Enum.join("\n")
  end

  defp format_category_value(v) when is_list(v), do: Enum.join(v, ", ")
  defp format_category_value(v), do: to_string(v)

  defp format_datetime(nil), do: "unknown"
  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")

  defp format_search_results(prompts, query) do
    if Enum.empty?(prompts) do
      "No prompts found matching '#{query}'."
    else
      """
      Search results for '#{query}':
      #{format_prompt_list(prompts, nil)}
      """
    end
  end

  defp format_categories do
    """
    ╔═══════════════════════════════════════════════════════════════╗
    ║                    Available Categories                       ║
    ╠═══════════════════════════════════════════════════════════════╣
    ║ Domain:                                                       ║
    ║   coding, code-generation, code-review, debugging, refactoring║
    ║   testing, documentation, architecture, analysis, planning    ║
    ║   elixir, otp, phoenix, ecto, ash, commanded, genserver      ║
    ║   supervisor, liveview, channels                             ║
    ╠═══════════════════════════════════════════════════════════════╣
    ║ Task:                                                         ║
    ║   generation, transformation, evaluation, extraction          ║
    ║   summarization, classification, reasoning, validation        ║
    ║   explanation                                                 ║
    ╠═══════════════════════════════════════════════════════════════╣
    ║ Technique:                                                    ║
    ║   zero-shot, few-shot, chain-of-thought, tree-of-thought     ║
    ║   self-consistency, react, reflection, role-play             ║
    ║   structured-output                                           ║
    ╠═══════════════════════════════════════════════════════════════╣
    ║ Complexity:                                                   ║
    ║   simple, intermediate, advanced, expert                      ║
    ╠═══════════════════════════════════════════════════════════════╣
    ║ Audience:                                                     ║
    ║   beginner, practitioner, advanced, developer                 ║
    ╚═══════════════════════════════════════════════════════════════╝
    
    User-defined categories can be created and will be stored separately.
    """
  end

  # Parsing helpers

  defp parse_list_options(opts) do
    Enum.reduce(opts, [], fn opt, acc ->
      case String.split(opt, "=", parts: 2) do
        ["--category", value] -> [{:category, value} | acc]
        ["--type", value] -> [{:type, String.to_atom(value)} | acc]
        ["--tag", value] -> [{:tag, value} | acc]
        ["--limit", value] -> [{:limit, String.to_integer(value)} | acc]
        _ -> acc
      end
    end)
  end

  defp parse_variable_args(args) do
    try do
      vars =
        args
        |> Enum.map(fn arg ->
          case String.split(arg, "=", parts: 2) do
            [key, value] -> {key, value}
            _ -> raise "Invalid variable format"
          end
        end)
        |> Map.new()

      {:ok, vars}
    rescue
      _ -> {:error, :invalid_variable_format}
    end
  end

  defp parse_type_input(input) do
    case input do
      "1" -> :system
      "system" -> :system
      "2" -> :user
      "user" -> :user
      "3" -> :assistant
      "assistant" -> :assistant
      "4" -> :meta
      "meta" -> :meta
      "5" -> :fragment
      "fragment" -> :fragment
      "6" -> :tool
      "tool" -> :tool
      "7" -> :validation
      "validation" -> :validation
      _ -> nil
    end
  end

  defp parse_categories(""), do: %{}

  defp parse_categories(input) do
    domains =
      input
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if Enum.empty?(domains), do: %{}, else: %{domain: domains}
  end

  defp parse_tags(""), do: []

  defp parse_tags(input) do
    input
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp valid_id?(id) do
    Regex.match?(~r/^[a-zA-Z0-9_-]+$/, id)
  end

  defp extract_variables(content) do
    # Extract {{variable}} patterns
    ~r/\{\{(\w+)\}\}/
    |> Regex.scan(content)
    |> Enum.map(fn [_, name] ->
      %{name: name, type: "string", required: true, default: nil, description: nil}
    end)
    |> Enum.uniq_by(& &1.name)
  end
end
