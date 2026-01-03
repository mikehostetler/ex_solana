defmodule JidoCode.Language do
  @moduledoc """
  Programming language detection for JidoCode projects.

  Detects the primary programming language of a project by examining
  marker files in the project root (mix.exs, package.json, etc.).

  ## Detection Rules

  Languages are detected by checking for the presence of marker files
  in the project root directory. The first match wins:

  | File | Language |
  |------|----------|
  | `mix.exs` | elixir |
  | `package.json` | javascript |
  | `tsconfig.json` | typescript |
  | `Cargo.toml` | rust |
  | `pyproject.toml` | python |
  | `requirements.txt` | python |
  | `go.mod` | go |
  | `Gemfile` | ruby |
  | `pom.xml` | java |
  | `build.gradle` | java |
  | `build.gradle.kts` | kotlin |
  | `composer.json` | php |
  | `CMakeLists.txt` | cpp |

  When no marker file is found, the default language is `:elixir`.
  """

  @type language ::
          :elixir
          | :javascript
          | :typescript
          | :rust
          | :python
          | :go
          | :ruby
          | :java
          | :kotlin
          | :csharp
          | :php
          | :cpp
          | :c

  # Detection rules in priority order - first match wins
  @detection_rules [
    {"mix.exs", :elixir},
    {"package.json", :javascript},
    {"tsconfig.json", :typescript},
    {"Cargo.toml", :rust},
    {"pyproject.toml", :python},
    {"requirements.txt", :python},
    {"go.mod", :go},
    {"Gemfile", :ruby},
    {"pom.xml", :java},
    {"build.gradle", :java},
    {"build.gradle.kts", :kotlin},
    {"composer.json", :php},
    {"CMakeLists.txt", :cpp}
  ]

  @default_language :elixir

  @all_languages [
    :elixir,
    :javascript,
    :typescript,
    :rust,
    :python,
    :go,
    :ruby,
    :java,
    :kotlin,
    :csharp,
    :php,
    :cpp,
    :c
  ]

  @doc """
  Detects the programming language of a project from its root directory.

  Checks for common marker files (mix.exs, package.json, etc.) and returns
  the corresponding language. Falls back to `:elixir` if no marker is found.

  ## Examples

      iex> JidoCode.Language.detect("/path/to/elixir/project")
      :elixir

      iex> JidoCode.Language.detect("/path/to/javascript/project")
      :javascript
  """
  @spec detect(String.t()) :: language()
  def detect(project_path) when is_binary(project_path) do
    @detection_rules
    |> Enum.find_value(fn {file, lang} ->
      if File.exists?(Path.join(project_path, file)), do: lang
    end)
    |> case do
      nil -> check_csharp_or_c(project_path)
      lang -> lang
    end
  end

  def detect(_), do: @default_language

  # Check for .csproj files (C#) or .c files with Makefile (C)
  defp check_csharp_or_c(project_path) do
    cond do
      has_csproj_files?(project_path) -> :csharp
      has_c_with_makefile?(project_path) -> :c
      true -> @default_language
    end
  end

  defp has_csproj_files?(project_path) do
    case File.ls(project_path) do
      {:ok, files} -> Enum.any?(files, &String.ends_with?(&1, ".csproj"))
      _ -> false
    end
  end

  defp has_c_with_makefile?(project_path) do
    has_makefile = File.exists?(Path.join(project_path, "Makefile"))

    has_c_files =
      case File.ls(project_path) do
        {:ok, files} -> Enum.any?(files, &String.ends_with?(&1, ".c"))
        _ -> false
      end

    has_makefile and has_c_files
  end

  @doc """
  Returns the default language (`:elixir`).
  """
  @spec default() :: language()
  def default, do: @default_language

  @doc """
  Returns true if the given value is a valid language atom.

  ## Examples

      iex> JidoCode.Language.valid?(:elixir)
      true

      iex> JidoCode.Language.valid?(:invalid)
      false
  """
  @spec valid?(term()) :: boolean()
  def valid?(lang) when is_atom(lang), do: lang in @all_languages
  def valid?(_), do: false

  @doc """
  Returns a list of all supported languages.
  """
  @spec all_languages() :: [language()]
  def all_languages, do: @all_languages

  @doc """
  Normalizes a language string or atom to a valid language atom.

  ## Examples

      iex> JidoCode.Language.normalize("elixir")
      {:ok, :elixir}

      iex> JidoCode.Language.normalize(:python)
      {:ok, :python}

      iex> JidoCode.Language.normalize("invalid")
      {:error, :invalid_language}
  """
  @spec normalize(String.t() | atom()) :: {:ok, language()} | {:error, :invalid_language}
  def normalize(lang) when is_atom(lang) do
    if valid?(lang), do: {:ok, lang}, else: {:error, :invalid_language}
  end

  def normalize(lang) when is_binary(lang) do
    normalized =
      lang
      |> String.downcase()
      |> String.trim()

    # Handle common aliases
    atom =
      case normalized do
        "js" -> :javascript
        "ts" -> :typescript
        "py" -> :python
        "rb" -> :ruby
        "c++" -> :cpp
        "c#" -> :csharp
        "cs" -> :csharp
        other -> String.to_atom(other)
      end

    normalize(atom)
  rescue
    _ -> {:error, :invalid_language}
  end

  def normalize(_), do: {:error, :invalid_language}

  @doc """
  Returns a human-readable display name for a language.

  ## Examples

      iex> JidoCode.Language.display_name(:elixir)
      "Elixir"

      iex> JidoCode.Language.display_name(:javascript)
      "JavaScript"
  """
  @spec display_name(language()) :: String.t()
  def display_name(:elixir), do: "Elixir"
  def display_name(:javascript), do: "JavaScript"
  def display_name(:typescript), do: "TypeScript"
  def display_name(:rust), do: "Rust"
  def display_name(:python), do: "Python"
  def display_name(:go), do: "Go"
  def display_name(:ruby), do: "Ruby"
  def display_name(:java), do: "Java"
  def display_name(:kotlin), do: "Kotlin"
  def display_name(:csharp), do: "C#"
  def display_name(:php), do: "PHP"
  def display_name(:cpp), do: "C++"
  def display_name(:c), do: "C"
  def display_name(_), do: "Unknown"

  @doc """
  Returns an icon/emoji for the language (for status bar display).

  ## Examples

      iex> JidoCode.Language.icon(:elixir)
      "💧"

      iex> JidoCode.Language.icon(:python)
      "🐍"
  """
  @spec icon(language()) :: String.t()
  def icon(:elixir), do: "💧"
  def icon(:javascript), do: "🟨"
  def icon(:typescript), do: "🔷"
  def icon(:rust), do: "🦀"
  def icon(:python), do: "🐍"
  def icon(:go), do: "🐹"
  def icon(:ruby), do: "💎"
  def icon(:java), do: "☕"
  def icon(:kotlin), do: "🎯"
  def icon(:csharp), do: "🟣"
  def icon(:php), do: "🐘"
  def icon(:cpp), do: "⚡"
  def icon(:c), do: "🔧"
  def icon(_), do: "📝"
end
