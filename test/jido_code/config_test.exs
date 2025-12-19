defmodule JidoCode.ConfigTest do
  use ExUnit.Case, async: false

  alias JidoCode.Config
  alias JidoCode.TestHelpers.EnvIsolation

  setup do
    EnvIsolation.isolate(
      ["JIDO_CODE_PROVIDER", "JIDO_CODE_MODEL", "ANTHROPIC_API_KEY", "OPENAI_API_KEY"],
      [{:jido_code, :llm}]
    )
  end

  describe "get_llm_config/0" do
    test "returns error when no provider configured" do
      assert {:error, message} = Config.get_llm_config()
      assert message =~ "No LLM provider configured"
      assert message =~ "JIDO_CODE_PROVIDER"
    end

    test "returns error when provider configured but no model" do
      Application.put_env(:jido_code, :llm, provider: :anthropic)
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      assert {:error, message} = Config.get_llm_config()
      assert message =~ "No LLM model configured"
    end

    test "returns error when provider is invalid" do
      Application.put_env(:jido_code, :llm, provider: :invalid_provider, model: "test-model")
      System.put_env("INVALID_PROVIDER_API_KEY", "test-key")

      assert {:error, message} = Config.get_llm_config()
      assert message =~ "Invalid provider"
      assert message =~ "Available providers"
    end

    test "returns error when API key is missing" do
      Application.put_env(:jido_code, :llm, provider: :anthropic, model: "claude-3-5-sonnet")
      System.delete_env("ANTHROPIC_API_KEY")

      assert {:error, message} = Config.get_llm_config()
      assert message =~ "No API key found"
      assert message =~ "ANTHROPIC_API_KEY"
    end

    test "returns valid config when properly configured" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet",
        temperature: 0.5,
        max_tokens: 2048
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      assert {:ok, config} = Config.get_llm_config()
      assert config.provider == :anthropic
      assert config.model == "claude-3-5-sonnet"
      assert config.temperature == 0.5
      assert config.max_tokens == 2048
    end

    test "uses default values for optional config" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet"
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      assert {:ok, config} = Config.get_llm_config()
      assert config.temperature == 0.7
      assert config.max_tokens == 4096
    end
  end

  describe "environment variable overrides" do
    test "JIDO_CODE_PROVIDER overrides config" do
      Application.put_env(:jido_code, :llm,
        provider: :openai,
        model: "gpt-4"
      )

      System.put_env("JIDO_CODE_PROVIDER", "anthropic")
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      assert {:ok, config} = Config.get_llm_config()
      assert config.provider == :anthropic
    end

    test "JIDO_CODE_MODEL overrides config" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-opus"
      )

      System.put_env("JIDO_CODE_MODEL", "claude-3-5-sonnet")
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      assert {:ok, config} = Config.get_llm_config()
      assert config.model == "claude-3-5-sonnet"
    end

    test "empty env vars fall back to config" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet"
      )

      System.put_env("JIDO_CODE_PROVIDER", "")
      System.put_env("JIDO_CODE_MODEL", "")
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      assert {:ok, config} = Config.get_llm_config()
      assert config.provider == :anthropic
      assert config.model == "claude-3-5-sonnet"
    end
  end

  describe "get_llm_config!/0" do
    test "raises on missing provider" do
      assert_raise RuntimeError, ~r/No LLM provider configured/, fn ->
        Config.get_llm_config!()
      end
    end

    test "returns config when valid" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet"
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      config = Config.get_llm_config!()
      assert config.provider == :anthropic
    end
  end

  describe "configured?/0" do
    test "returns false when not configured" do
      refute Config.configured?()
    end

    test "returns true when properly configured" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet"
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      assert Config.configured?()
    end
  end

  describe "parameter range validation" do
    test "temperature is clamped to [0.0, 1.0] range" do
      # Below 0
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet",
        temperature: -0.5
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      assert {:ok, config} = Config.get_llm_config()
      assert config.temperature == 0.0
    end

    test "temperature above 1.0 is clamped to 1.0" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet",
        temperature: 1.5
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      assert {:ok, config} = Config.get_llm_config()
      assert config.temperature == 1.0
    end

    test "non-positive max_tokens falls back to default" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet",
        max_tokens: 0
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      assert {:ok, config} = Config.get_llm_config()
      assert config.max_tokens == 4096
    end

    test "negative max_tokens falls back to default" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet",
        max_tokens: -100
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      assert {:ok, config} = Config.get_llm_config()
      assert config.max_tokens == 4096
    end
  end
end
