defmodule Jido.Character do
  @moduledoc """
  Extensible character definition for AI agents.

  ## Direct API

      {:ok, bob} = Jido.Character.new(%{name: "Bob"})
      {:ok, bob} = Jido.Character.update(bob, %{identity: %{role: "Assistant"}})
      {:ok, bob} = Jido.Character.validate(bob)
      context = Jido.Character.to_context(bob)
      prompt = Jido.Character.to_system_prompt(bob)

  ## Raising Variants

      bob = Jido.Character.new!(%{name: "Bob"})
      bob = Jido.Character.update!(bob, %{identity: %{role: "Assistant"}})

  ## Module-Based Characters

      defmodule MyApp.Characters.Alice do
        use Jido.Character,
          defaults: %{name: "Alice"}
      end

      {:ok, alice} = MyApp.Characters.Alice.new()

  ## Functions

  - `new/1`, `new!/1` - Create a new character from a map of attributes
  - `update/2`, `update!/2` - Update an existing character with new attributes
  - `validate/1` - Validate a character map
  - `to_context/2` - Convert a character to a ReqLLM.Context struct
  - `to_system_prompt/2` - Generate a system prompt string from a character
  - `evolve/2`, `evolve!/2` - Evolve a character over simulated time

  ## Error Handling

  Functions returning `{:ok, t()} | {:error, errors()}` use Zoi validation errors.
  The `errors()` type is a list of `Zoi.Error.t()` structs with detailed information:

      case Jido.Character.new(%{}) do
        {:ok, char} -> char
        {:error, errors} ->
          Enum.each(errors, fn error ->
            IO.puts("Field \#{inspect(error.path)}: \#{error.message}")
          end)
      end

  Use the `!` variants (`new!/1`, `update!/2`) when you prefer exceptions over tuples.
  """

  @typedoc """
  A character map with the following fields:

  - `:id` (required) - Unique identifier (String.t())
  - `:name` - Character name (String.t() | nil)
  - `:description` - Character description (String.t() | nil)
  - `:identity` - Who the character is (Schema.Identity.t() | nil)
  - `:personality` - How the character behaves (Schema.Personality.t() | nil)
  - `:voice` - How the character communicates (Schema.Voice.t() | nil)
  - `:memory` - What the character remembers (Schema.Memory.t() | nil)
  - `:knowledge` - Permanent facts the character knows ([Schema.KnowledgeItem.t()])
  - `:instructions` - Behavioral instructions ([String.t()])
  - `:extensions` - Custom extension data (map())
  - `:created_at` - Creation timestamp (DateTime.t() | nil)
  - `:updated_at` - Last update timestamp (DateTime.t() | nil)
  - `:version` - Version number (non_neg_integer())
  """
  @type t :: %{
          required(:id) => String.t(),
          optional(:name) => String.t() | nil,
          optional(:description) => String.t() | nil,
          optional(:identity) => Jido.Character.Schema.Identity.t() | nil,
          optional(:personality) => Jido.Character.Schema.Personality.t() | nil,
          optional(:voice) => Jido.Character.Schema.Voice.t() | nil,
          optional(:memory) => Jido.Character.Schema.Memory.t() | nil,
          optional(:knowledge) => [Jido.Character.Schema.KnowledgeItem.t()],
          optional(:instructions) => [String.t()],
          optional(:extensions) => map(),
          optional(:created_at) => DateTime.t() | nil,
          optional(:updated_at) => DateTime.t() | nil,
          optional(:version) => non_neg_integer()
        }

  @type errors :: [Zoi.Error.t()]

  alias Jido.Character.Schema
  alias Jido.Character.Renderer

  @spec validate(map()) :: {:ok, t()} | {:error, errors()}
  def validate(attrs) when is_map(attrs) do
    schema = Schema.character()

    case Zoi.parse(schema, attrs) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, errors} -> {:error, errors}
    end
  end

  @spec new(map()) :: {:ok, t()} | {:error, errors()}
  def new(attrs \\ %{})

  def new(attrs) when is_map(attrs) do
    attrs
    |> normalize_keys()
    |> ensure_id()
    |> ensure_timestamps(:create)
    |> ensure_version()
    |> validate()
  end

  @doc """
  Creates a new character, raising on validation errors.

  ## Examples

      bob = Jido.Character.new!(%{name: "Bob"})

  Raises `ArgumentError` if validation fails.
  """
  @spec new!(map()) :: t()
  def new!(attrs \\ %{}) do
    case new(attrs) do
      {:ok, character} -> character
      {:error, errors} -> raise ArgumentError, format_errors("Invalid character", errors)
    end
  end

  defp normalize_keys(attrs) do
    Map.new(attrs, fn
      {k, v} when is_binary(k) ->
        atom_key = safe_to_existing_atom(k)
        {atom_key || k, v}

      {k, v} ->
        {k, v}
    end)
  end

  defp safe_to_existing_atom(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> nil
  end

  defp ensure_id(attrs) do
    case Map.get(attrs, :id) do
      nil -> Map.put(attrs, :id, Uniq.UUID.uuid7())
      _id -> attrs
    end
  end

  defp ensure_timestamps(attrs, :create) do
    now = DateTime.utc_now()

    attrs
    |> Map.put_new(:created_at, now)
    |> Map.put(:updated_at, now)
  end

  defp ensure_timestamps(attrs, :update) do
    Map.put(attrs, :updated_at, DateTime.utc_now())
  end

  defp ensure_version(attrs) do
    Map.put_new(attrs, :version, 1)
  end

  @spec update(t(), map()) :: {:ok, t()} | {:error, errors()}
  def update(%{} = character, %{} = attrs) do
    attrs = normalize_keys(attrs)

    base = %{
      id: character.id,
      created_at: Map.get(character, :created_at)
    }

    merged =
      character
      |> deep_merge(attrs)
      |> Map.merge(base)

    merged =
      merged
      |> bump_version(character)
      |> ensure_timestamps(:update)

    validate(merged)
  end

  @doc """
  Updates a character, raising on validation errors.

  ## Examples

      bob = Jido.Character.update!(bob, %{name: "Robert"})

  Raises `ArgumentError` if validation fails.
  """
  @spec update!(t(), map()) :: t()
  def update!(character, attrs) do
    case update(character, attrs) do
      {:ok, updated} -> updated
      {:error, errors} -> raise ArgumentError, format_errors("Invalid update", errors)
    end
  end

  defp bump_version(attrs, %{version: version}) when is_integer(version) do
    Map.put(attrs, :version, version + 1)
  end

  defp bump_version(attrs, _), do: Map.put_new(attrs, :version, 1)

  defp deep_merge(map1, map2) when is_map(map1) and is_map(map2) do
    Map.merge(map1, map2, fn _k, v1, v2 ->
      if is_map(v1) and is_map(v2) and not is_struct(v1) and not is_struct(v2) do
        deep_merge(v1, v2)
      else
        v2
      end
    end)
  end

  defp format_errors(prefix, errors) when is_list(errors) do
    details =
      errors
      |> Enum.map(fn
        %{path: path, message: msg} when path != [] ->
          "#{Enum.join(path, ".")}: #{msg}"

        %{message: msg} ->
          msg

        other ->
          inspect(other)
      end)
      |> Enum.join(", ")

    "#{prefix}: #{details}"
  end

  @spec to_context(t(), keyword()) :: ReqLLM.Context.t()
  def to_context(character, opts \\ [])
  def to_context(%{} = character, opts), do: Renderer.to_context(character, opts)

  @spec to_system_prompt(t(), keyword()) :: String.t()
  def to_system_prompt(character, opts \\ [])
  def to_system_prompt(%{} = character, opts), do: Renderer.to_system_prompt(character, opts)

  # ---------------------------------------------------------------------------
  # Pipe-Friendly Helpers
  # ---------------------------------------------------------------------------

  @doc """
  Add knowledge to a character.

  ## Examples

      # String shorthand
      {:ok, char} = Jido.Character.add_knowledge(char, "Expert in Elixir")

      # With options
      {:ok, char} = Jido.Character.add_knowledge(char, "Expert in Elixir", category: "skills", importance: 0.9)

      # Multiple items
      {:ok, char} = Jido.Character.add_knowledge(char, ["Knows Elixir", "Knows Python"])

      # Full map
      {:ok, char} = Jido.Character.add_knowledge(char, %{content: "Expert in Elixir", importance: 0.9})
  """
  @spec add_knowledge(t(), String.t() | map() | [String.t() | map()], keyword()) ::
          {:ok, t()} | {:error, errors()}
  def add_knowledge(character, content, opts \\ [])

  def add_knowledge(character, content, opts) when is_binary(content) do
    item = build_knowledge_item(content, opts)
    append_to_list(character, :knowledge, [item])
  end

  def add_knowledge(character, %{} = item, _opts) do
    append_to_list(character, :knowledge, [item])
  end

  def add_knowledge(character, items, opts) when is_list(items) do
    normalized =
      Enum.map(items, fn
        content when is_binary(content) -> build_knowledge_item(content, opts)
        %{} = item -> item
      end)

    append_to_list(character, :knowledge, normalized)
  end

  defp build_knowledge_item(content, opts) do
    %{content: content}
    |> maybe_put(:category, opts[:category])
    |> maybe_put(:importance, opts[:importance])
  end

  @doc """
  Add an instruction to a character.

  ## Examples

      {:ok, char} = Jido.Character.add_instruction(char, "Always be helpful")

      # Multiple
      {:ok, char} = Jido.Character.add_instruction(char, ["Be helpful", "Be concise"])
  """
  @spec add_instruction(t(), String.t() | [String.t()]) :: {:ok, t()} | {:error, errors()}
  def add_instruction(character, instruction) when is_binary(instruction) do
    append_to_list(character, :instructions, [instruction])
  end

  def add_instruction(character, instructions) when is_list(instructions) do
    append_to_list(character, :instructions, instructions)
  end

  @doc """
  Add a memory entry to a character.

  Memory entries are subject to the character's memory capacity. When adding
  an entry would exceed capacity, the oldest entries are dropped to make room.

  ## Examples

      # String shorthand
      {:ok, char} = Jido.Character.add_memory(char, "User prefers brief answers")

      # With options
      {:ok, char} = Jido.Character.add_memory(char, "Important event", importance: 0.9, category: "events")

      # Full map
      {:ok, char} = Jido.Character.add_memory(char, %{content: "User said hello", importance: 0.5})
  """
  @spec add_memory(t(), String.t() | map(), keyword()) :: {:ok, t()} | {:error, errors()}
  def add_memory(character, content, opts \\ [])

  def add_memory(character, content, opts) when is_binary(content) do
    entry = build_memory_entry(content, opts)
    append_memory_entry(character, entry)
  end

  def add_memory(character, %{} = entry, _opts) do
    append_memory_entry(character, entry)
  end

  defp build_memory_entry(content, opts) do
    %{content: content, timestamp: DateTime.utc_now()}
    |> maybe_put(:importance, opts[:importance])
    |> maybe_put(:decay_rate, opts[:decay_rate])
    |> maybe_put(:category, opts[:category])
  end

  defp append_memory_entry(character, entry) do
    memory = Map.get(character, :memory, %{entries: [], capacity: 100})
    entries = Map.get(memory, :entries, [])
    capacity = Map.get(memory, :capacity, 100)

    new_entries = entries ++ [entry]

    trimmed_entries =
      if length(new_entries) > capacity do
        Enum.drop(new_entries, length(new_entries) - capacity)
      else
        new_entries
      end

    updated_memory = Map.put(memory, :entries, trimmed_entries)
    update(character, %{memory: updated_memory})
  end

  @doc """
  Add a trait to a character's personality.

  ## Examples

      # String shorthand
      {:ok, char} = Jido.Character.add_trait(char, "curious")

      # With intensity
      {:ok, char} = Jido.Character.add_trait(char, "analytical", intensity: 0.9)

      # Multiple
      {:ok, char} = Jido.Character.add_trait(char, ["curious", "patient"])
  """
  @spec add_trait(t(), String.t() | map() | [String.t() | map()], keyword()) ::
          {:ok, t()} | {:error, errors()}
  def add_trait(character, trait, opts \\ [])

  def add_trait(character, trait, opts) when is_binary(trait) do
    item = if intensity = opts[:intensity], do: %{name: trait, intensity: intensity}, else: trait
    append_personality_field(character, :traits, [item])
  end

  def add_trait(character, %{} = trait, _opts) do
    append_personality_field(character, :traits, [trait])
  end

  def add_trait(character, traits, opts) when is_list(traits) do
    normalized =
      Enum.map(traits, fn
        trait when is_binary(trait) ->
          if intensity = opts[:intensity], do: %{name: trait, intensity: intensity}, else: trait

        %{} = trait ->
          trait
      end)

    append_personality_field(character, :traits, normalized)
  end

  @doc """
  Add a value to a character's personality.

  ## Examples

      {:ok, char} = Jido.Character.add_value(char, "accuracy")
      {:ok, char} = Jido.Character.add_value(char, ["accuracy", "clarity"])
  """
  @spec add_value(t(), String.t() | [String.t()]) :: {:ok, t()} | {:error, errors()}
  def add_value(character, value) when is_binary(value) do
    append_personality_field(character, :values, [value])
  end

  def add_value(character, values) when is_list(values) do
    append_personality_field(character, :values, values)
  end

  @doc """
  Add a quirk to a character's personality.

  ## Examples

      {:ok, char} = Jido.Character.add_quirk(char, "Uses analogies frequently")
      {:ok, char} = Jido.Character.add_quirk(char, ["Uses analogies", "Asks clarifying questions"])
  """
  @spec add_quirk(t(), String.t() | [String.t()]) :: {:ok, t()} | {:error, errors()}
  def add_quirk(character, quirk) when is_binary(quirk) do
    append_personality_field(character, :quirks, [quirk])
  end

  def add_quirk(character, quirks) when is_list(quirks) do
    append_personality_field(character, :quirks, quirks)
  end

  @doc """
  Add an expression to a character's voice.

  ## Examples

      {:ok, char} = Jido.Character.add_expression(char, "Let me think about that...")
      {:ok, char} = Jido.Character.add_expression(char, ["Let me think...", "Interesting point!"])
  """
  @spec add_expression(t(), String.t() | [String.t()]) :: {:ok, t()} | {:error, errors()}
  def add_expression(character, expression) when is_binary(expression) do
    append_voice_field(character, :expressions, [expression])
  end

  def add_expression(character, expressions) when is_list(expressions) do
    append_voice_field(character, :expressions, expressions)
  end

  @doc """
  Add a fact to a character's identity.

  ## Examples

      {:ok, char} = Jido.Character.add_fact(char, "Has a PhD in Computer Science")
      {:ok, char} = Jido.Character.add_fact(char, ["Has a PhD", "Worked at 3 startups"])
  """
  @spec add_fact(t(), String.t() | [String.t()]) :: {:ok, t()} | {:error, errors()}
  def add_fact(character, fact) when is_binary(fact) do
    append_identity_field(character, :facts, [fact])
  end

  def add_fact(character, facts) when is_list(facts) do
    append_identity_field(character, :facts, facts)
  end

  # ---------------------------------------------------------------------------
  # Private Helpers for Appending
  # ---------------------------------------------------------------------------

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp append_to_list(character, field, items) do
    existing = Map.get(character, field, [])
    update(character, %{field => existing ++ items})
  end

  defp append_personality_field(character, field, items) do
    personality = Map.get(character, :personality, %{})
    existing = Map.get(personality, field, [])
    updated_personality = Map.put(personality, field, existing ++ items)
    update(character, %{personality: updated_personality})
  end

  defp append_voice_field(character, field, items) do
    voice = Map.get(character, :voice, %{})
    existing = Map.get(voice, field, [])
    updated_voice = Map.put(voice, field, existing ++ items)
    update(character, %{voice: updated_voice})
  end

  defp append_identity_field(character, field, items) do
    identity = Map.get(character, :identity, %{})
    existing = Map.get(identity, field, [])
    updated_identity = Map.put(identity, field, existing ++ items)
    update(character, %{identity: updated_identity})
  end

  # ---------------------------------------------------------------------------
  # Evolution
  # ---------------------------------------------------------------------------

  @doc """
  Evolve a character over a period of simulated time.

  Time is relative: pass the delta since the last evolution call.

  ## Options

    * `:days` - number of days to advance (default: 0)
    * `:years` - number of years to advance (default: 0)
    * `:age?` - whether to update integer `identity.age` (default: true)
    * `:memory?` - whether to apply memory decay (default: true)
    * `:memory_prune_below` - drop memories whose decayed importance
        falls below this threshold (default: 0.05, set to nil to disable)

  ## Examples

      # Age by one year
      {:ok, older} = Jido.Character.evolve(char, years: 1)

      # Age by 30 days, decay memories
      {:ok, evolved} = Jido.Character.evolve(char, days: 30)

      # Only decay memories, don't age
      {:ok, evolved} = Jido.Character.evolve(char, days: 7, age?: false)

      # Disable memory pruning
      {:ok, evolved} = Jido.Character.evolve(char, days: 30, memory_prune_below: nil)
  """
  @spec evolve(t(), keyword()) :: {:ok, t()} | {:error, errors()}
  def evolve(%{} = character, opts \\ []) do
    days = opts[:days] || 0
    years = opts[:years] || 0
    total_days = days + years * 365

    if total_days <= 0 do
      {:ok, character}
    else
      age? = Keyword.get(opts, :age?, true)
      mem? = Keyword.get(opts, :memory?, true)

      attrs =
        %{}
        |> maybe_put_evolved_age(character, total_days, age?)
        |> maybe_put_evolved_memory(character, total_days, mem?, opts)

      if map_size(attrs) == 0 do
        {:ok, character}
      else
        update(character, attrs)
      end
    end
  end

  @doc """
  Evolve a character, raising on validation errors.

  ## Examples

      older = Jido.Character.evolve!(char, years: 1)

  Raises `ArgumentError` if validation fails.
  """
  @spec evolve!(t(), keyword()) :: t()
  def evolve!(character, opts \\ []) do
    case evolve(character, opts) do
      {:ok, evolved} -> evolved
      {:error, errors} -> raise ArgumentError, format_errors("Evolution failed", errors)
    end
  end

  defp maybe_put_evolved_age(attrs, _character, _total_days, false), do: attrs

  defp maybe_put_evolved_age(attrs, character, total_days, true) do
    identity = Map.get(character, :identity, %{})

    case Map.get(identity, :age) do
      age when is_integer(age) ->
        delta_years = trunc(Float.floor(total_days / 365))

        if delta_years > 0 do
          new_identity = Map.put(identity, :age, age + delta_years)
          Map.put(attrs, :identity, new_identity)
        else
          attrs
        end

      _string_or_nil ->
        attrs
    end
  end

  defp maybe_put_evolved_memory(attrs, _character, _total_days, false, _opts), do: attrs

  defp maybe_put_evolved_memory(attrs, character, total_days, true, opts) do
    memory = Map.get(character, :memory, %{entries: [], capacity: 100})
    entries = Map.get(memory, :entries, [])

    if entries == [] do
      attrs
    else
      min_imp = Keyword.get(opts, :memory_prune_below, 0.05)

      evolved_entries =
        entries
        |> Enum.map(&decay_entry(&1, total_days))
        |> maybe_prune_entries(min_imp)

      if evolved_entries == entries do
        attrs
      else
        new_memory = Map.put(memory, :entries, evolved_entries)
        Map.put(attrs, :memory, new_memory)
      end
    end
  end

  defp decay_entry(entry, total_days) do
    importance = Map.get(entry, :importance, 0.5)
    decay_rate = Map.get(entry, :decay_rate, 0.1)

    effective = importance * :math.pow(1.0 - decay_rate, total_days)
    Map.put(entry, :importance, effective)
  end

  defp maybe_prune_entries(entries, nil), do: entries

  defp maybe_prune_entries(entries, min_importance) do
    Enum.filter(entries, fn entry -> Map.get(entry, :importance, 0.5) >= min_importance end)
  end

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      alias Jido.Character
      alias Jido.Character.Definition

      @jido_character_definition %Definition{
        module: __MODULE__,
        extensions: Keyword.get(opts, :extensions, []),
        defaults: Keyword.get(opts, :defaults, %{}),
        adapter: Keyword.get(opts, :adapter, Jido.Character.Persistence.Memory),
        adapter_opts: Keyword.get(opts, :adapter_opts, []),
        renderer: Keyword.get(opts, :renderer, Jido.Character.Context.Renderer),
        renderer_opts: Keyword.get(opts, :renderer_opts, [])
      }

      @doc "Return this character module's definition."
      @spec definition() :: Definition.t()
      def definition, do: @jido_character_definition

      @doc "Return configured extensions."
      @spec extensions() :: [atom()]
      def extensions, do: @jido_character_definition.extensions

      @doc "Return default attributes."
      @spec defaults() :: map()
      def defaults, do: @jido_character_definition.defaults

      @doc "Return configured persistence adapter."
      @spec adapter() :: module()
      def adapter, do: @jido_character_definition.adapter

      @doc "Return configured adapter options."
      @spec adapter_opts() :: keyword()
      def adapter_opts, do: @jido_character_definition.adapter_opts

      @doc "Return configured renderer module."
      @spec renderer() :: module()
      def renderer, do: @jido_character_definition.renderer

      @doc "Return configured renderer options."
      @spec renderer_opts() :: keyword()
      def renderer_opts, do: @jido_character_definition.renderer_opts

      @doc "Create a new character instance using defaults and overrides."
      @spec new(map()) :: {:ok, Character.t()} | {:error, Character.errors()}
      def new(attrs \\ %{}) do
        merged = Map.merge(defaults(), attrs)
        Character.new(merged)
      end

      @doc "Create a new character instance, raising on error."
      @spec new!(map()) :: Character.t()
      def new!(attrs \\ %{}) do
        merged = Map.merge(defaults(), attrs)
        Character.new!(merged)
      end

      @doc "Update an existing character immutably."
      @spec update(Character.t(), map()) :: {:ok, Character.t()} | {:error, Character.errors()}
      def update(character, attrs), do: Character.update(character, attrs)

      @doc "Update an existing character, raising on error."
      @spec update!(Character.t(), map()) :: Character.t()
      def update!(character, attrs), do: Character.update!(character, attrs)

      @doc "Validate character attributes."
      @spec validate(map()) :: {:ok, Character.t()} | {:error, Character.errors()}
      def validate(attrs), do: Character.validate(attrs)

      @doc "Render this character to LLM context."
      @spec to_context(Character.t(), keyword()) :: ReqLLM.Context.t()
      def to_context(character, opts \\ []) do
        module_opts = [
          renderer: @jido_character_definition.renderer,
          renderer_opts: @jido_character_definition.renderer_opts
        ]

        merged_opts = Keyword.merge(module_opts, opts)
        Character.to_context(character, merged_opts)
      end

      @doc "Render this character to a system prompt string."
      @spec to_system_prompt(Character.t(), keyword()) :: String.t()
      def to_system_prompt(character, opts \\ []) do
        module_opts = [
          renderer: @jido_character_definition.renderer,
          renderer_opts: @jido_character_definition.renderer_opts
        ]

        merged_opts = Keyword.merge(module_opts, opts)
        Character.to_system_prompt(character, merged_opts)
      end

      @doc "Persist this character using the configured adapter."
      @spec save(Character.t()) :: {:ok, Character.t()} | {:error, term()}
      def save(character) do
        adapter().save(@jido_character_definition, character)
      end

      @doc "Add knowledge to a character."
      @spec add_knowledge(Character.t(), String.t() | map() | [String.t() | map()], keyword()) ::
              {:ok, Character.t()} | {:error, Character.errors()}
      def add_knowledge(character, content, opts \\ []),
        do: Character.add_knowledge(character, content, opts)

      @doc "Add an instruction to a character."
      @spec add_instruction(Character.t(), String.t() | [String.t()]) ::
              {:ok, Character.t()} | {:error, Character.errors()}
      def add_instruction(character, instruction), do: Character.add_instruction(character, instruction)

      @doc "Add a memory entry to a character."
      @spec add_memory(Character.t(), String.t() | map(), keyword()) ::
              {:ok, Character.t()} | {:error, Character.errors()}
      def add_memory(character, content, opts \\ []), do: Character.add_memory(character, content, opts)

      @doc "Add a trait to a character's personality."
      @spec add_trait(Character.t(), String.t() | map() | [String.t() | map()], keyword()) ::
              {:ok, Character.t()} | {:error, Character.errors()}
      def add_trait(character, trait, opts \\ []), do: Character.add_trait(character, trait, opts)

      @doc "Add a value to a character's personality."
      @spec add_value(Character.t(), String.t() | [String.t()]) ::
              {:ok, Character.t()} | {:error, Character.errors()}
      def add_value(character, value), do: Character.add_value(character, value)

      @doc "Add a quirk to a character's personality."
      @spec add_quirk(Character.t(), String.t() | [String.t()]) ::
              {:ok, Character.t()} | {:error, Character.errors()}
      def add_quirk(character, quirk), do: Character.add_quirk(character, quirk)

      @doc "Add an expression to a character's voice."
      @spec add_expression(Character.t(), String.t() | [String.t()]) ::
              {:ok, Character.t()} | {:error, Character.errors()}
      def add_expression(character, expression), do: Character.add_expression(character, expression)

      @doc "Add a fact to a character's identity."
      @spec add_fact(Character.t(), String.t() | [String.t()]) ::
              {:ok, Character.t()} | {:error, Character.errors()}
      def add_fact(character, fact), do: Character.add_fact(character, fact)

      @doc "Evolve a character over a period of simulated time."
      @spec evolve(Character.t(), keyword()) :: {:ok, Character.t()} | {:error, Character.errors()}
      def evolve(character, opts \\ []), do: Character.evolve(character, opts)

      @doc "Evolve a character, raising on error."
      @spec evolve!(Character.t(), keyword()) :: Character.t()
      def evolve!(character, opts \\ []), do: Character.evolve!(character, opts)

      defoverridable new: 1,
                     new!: 1,
                     update: 2,
                     update!: 2,
                     validate: 1,
                     to_context: 2,
                     to_system_prompt: 2,
                     save: 1,
                     renderer: 0,
                     renderer_opts: 0,
                     add_knowledge: 3,
                     add_instruction: 2,
                     add_memory: 3,
                     add_trait: 3,
                     add_value: 2,
                     add_quirk: 2,
                     add_expression: 2,
                     add_fact: 2,
                     evolve: 2,
                     evolve!: 2
    end
  end
end
