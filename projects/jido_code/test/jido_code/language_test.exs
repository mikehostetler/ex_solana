defmodule JidoCode.LanguageTest do
  use ExUnit.Case, async: true

  alias JidoCode.Language

  describe "detect/1" do
    setup do
      # Create a temp directory for each test
      tmp_dir = Path.join(System.tmp_dir!(), "language_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
      end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "detects elixir from mix.exs", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "mix.exs"), "")
      assert Language.detect(tmp_dir) == :elixir
    end

    test "detects javascript from package.json", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "package.json"), "{}")
      assert Language.detect(tmp_dir) == :javascript
    end

    test "detects typescript from tsconfig.json", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "tsconfig.json"), "{}")
      assert Language.detect(tmp_dir) == :typescript
    end

    test "detects rust from Cargo.toml", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "Cargo.toml"), "")
      assert Language.detect(tmp_dir) == :rust
    end

    test "detects python from pyproject.toml", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "pyproject.toml"), "")
      assert Language.detect(tmp_dir) == :python
    end

    test "detects python from requirements.txt", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "requirements.txt"), "")
      assert Language.detect(tmp_dir) == :python
    end

    test "detects go from go.mod", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "go.mod"), "")
      assert Language.detect(tmp_dir) == :go
    end

    test "detects ruby from Gemfile", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "Gemfile"), "")
      assert Language.detect(tmp_dir) == :ruby
    end

    test "detects java from pom.xml", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "pom.xml"), "")
      assert Language.detect(tmp_dir) == :java
    end

    test "detects java from build.gradle", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "build.gradle"), "")
      assert Language.detect(tmp_dir) == :java
    end

    test "detects kotlin from build.gradle.kts", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "build.gradle.kts"), "")
      assert Language.detect(tmp_dir) == :kotlin
    end

    test "detects php from composer.json", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "composer.json"), "{}")
      assert Language.detect(tmp_dir) == :php
    end

    test "detects cpp from CMakeLists.txt", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "CMakeLists.txt"), "")
      assert Language.detect(tmp_dir) == :cpp
    end

    test "detects csharp from .csproj file", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "MyProject.csproj"), "")
      assert Language.detect(tmp_dir) == :csharp
    end

    test "detects c from Makefile with .c files", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "Makefile"), "")
      File.write!(Path.join(tmp_dir, "main.c"), "")
      assert Language.detect(tmp_dir) == :c
    end

    test "defaults to elixir when no marker found", %{tmp_dir: tmp_dir} do
      # Empty directory
      assert Language.detect(tmp_dir) == :elixir
    end

    test "defaults to elixir for nil path" do
      assert Language.detect(nil) == :elixir
    end

    test "defaults to elixir for non-string path" do
      assert Language.detect(123) == :elixir
    end

    test "priority: mix.exs wins over package.json", %{tmp_dir: tmp_dir} do
      # Both present - mix.exs has higher priority
      File.write!(Path.join(tmp_dir, "mix.exs"), "")
      File.write!(Path.join(tmp_dir, "package.json"), "{}")
      assert Language.detect(tmp_dir) == :elixir
    end

    test "priority: package.json wins over tsconfig.json", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "package.json"), "{}")
      File.write!(Path.join(tmp_dir, "tsconfig.json"), "{}")
      assert Language.detect(tmp_dir) == :javascript
    end
  end

  describe "default/0" do
    test "returns :elixir" do
      assert Language.default() == :elixir
    end
  end

  describe "valid?/1" do
    test "returns true for valid language atoms" do
      assert Language.valid?(:elixir) == true
      assert Language.valid?(:javascript) == true
      assert Language.valid?(:typescript) == true
      assert Language.valid?(:rust) == true
      assert Language.valid?(:python) == true
      assert Language.valid?(:go) == true
      assert Language.valid?(:ruby) == true
      assert Language.valid?(:java) == true
      assert Language.valid?(:kotlin) == true
      assert Language.valid?(:csharp) == true
      assert Language.valid?(:php) == true
      assert Language.valid?(:cpp) == true
      assert Language.valid?(:c) == true
    end

    test "returns false for invalid atoms" do
      assert Language.valid?(:invalid) == false
      assert Language.valid?(:unknown) == false
      assert Language.valid?(:swift) == false
    end

    test "returns false for non-atoms" do
      assert Language.valid?("elixir") == false
      assert Language.valid?(123) == false
      assert Language.valid?(nil) == false
    end
  end

  describe "all_languages/0" do
    test "returns a list of all supported languages" do
      languages = Language.all_languages()

      assert is_list(languages)
      assert :elixir in languages
      assert :javascript in languages
      assert :python in languages
      assert :rust in languages
    end

    test "contains all valid languages" do
      for lang <- Language.all_languages() do
        assert Language.valid?(lang)
      end
    end
  end

  describe "normalize/1" do
    test "returns {:ok, atom} for valid language atoms" do
      assert Language.normalize(:elixir) == {:ok, :elixir}
      assert Language.normalize(:python) == {:ok, :python}
    end

    test "returns {:ok, atom} for valid language strings" do
      assert Language.normalize("elixir") == {:ok, :elixir}
      assert Language.normalize("python") == {:ok, :python}
      assert Language.normalize("javascript") == {:ok, :javascript}
    end

    test "normalizes case-insensitively" do
      assert Language.normalize("ELIXIR") == {:ok, :elixir}
      assert Language.normalize("Python") == {:ok, :python}
      assert Language.normalize("JavaScript") == {:ok, :javascript}
    end

    test "handles common aliases" do
      assert Language.normalize("js") == {:ok, :javascript}
      assert Language.normalize("ts") == {:ok, :typescript}
      assert Language.normalize("py") == {:ok, :python}
      assert Language.normalize("rb") == {:ok, :ruby}
      assert Language.normalize("c++") == {:ok, :cpp}
      assert Language.normalize("c#") == {:ok, :csharp}
      assert Language.normalize("cs") == {:ok, :csharp}
    end

    test "trims whitespace" do
      assert Language.normalize("  elixir  ") == {:ok, :elixir}
      assert Language.normalize("\tpython\n") == {:ok, :python}
    end

    test "returns {:error, :invalid_language} for invalid input" do
      assert Language.normalize(:invalid) == {:error, :invalid_language}
      assert Language.normalize("invalid") == {:error, :invalid_language}
      assert Language.normalize("") == {:error, :invalid_language}
    end

    test "returns {:error, :invalid_language} for non-string/atom input" do
      assert Language.normalize(123) == {:error, :invalid_language}
      assert Language.normalize(nil) == {:error, :invalid_language}
      assert Language.normalize([]) == {:error, :invalid_language}
    end
  end

  describe "display_name/1" do
    test "returns human-readable names for all languages" do
      assert Language.display_name(:elixir) == "Elixir"
      assert Language.display_name(:javascript) == "JavaScript"
      assert Language.display_name(:typescript) == "TypeScript"
      assert Language.display_name(:rust) == "Rust"
      assert Language.display_name(:python) == "Python"
      assert Language.display_name(:go) == "Go"
      assert Language.display_name(:ruby) == "Ruby"
      assert Language.display_name(:java) == "Java"
      assert Language.display_name(:kotlin) == "Kotlin"
      assert Language.display_name(:csharp) == "C#"
      assert Language.display_name(:php) == "PHP"
      assert Language.display_name(:cpp) == "C++"
      assert Language.display_name(:c) == "C"
    end

    test "returns Unknown for invalid languages" do
      assert Language.display_name(:invalid) == "Unknown"
      assert Language.display_name(nil) == "Unknown"
    end
  end

  describe "icon/1" do
    test "returns icons for all languages" do
      assert Language.icon(:elixir) == "💧"
      assert Language.icon(:javascript) == "🟨"
      assert Language.icon(:typescript) == "🔷"
      assert Language.icon(:rust) == "🦀"
      assert Language.icon(:python) == "🐍"
      assert Language.icon(:go) == "🐹"
      assert Language.icon(:ruby) == "💎"
      assert Language.icon(:java) == "☕"
      assert Language.icon(:kotlin) == "🎯"
      assert Language.icon(:csharp) == "🟣"
      assert Language.icon(:php) == "🐘"
      assert Language.icon(:cpp) == "⚡"
      assert Language.icon(:c) == "🔧"
    end

    test "returns default icon for invalid languages" do
      assert Language.icon(:invalid) == "📝"
      assert Language.icon(nil) == "📝"
    end
  end
end
