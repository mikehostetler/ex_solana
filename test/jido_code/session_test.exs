defmodule JidoCode.SessionTest do
  use ExUnit.Case, async: true

  alias JidoCode.Session

  describe "Session struct" do
    test "can be created with all fields" do
      now = DateTime.utc_now()

      session = %Session{
        id: "550e8400-e29b-41d4-a716-446655440000",
        name: "test-project",
        project_path: "/home/user/projects/test-project",
        config: %{
          provider: "anthropic",
          model: "claude-3-5-sonnet-20241022",
          temperature: 0.7,
          max_tokens: 4096
        },
        created_at: now,
        updated_at: now
      }

      assert session.id == "550e8400-e29b-41d4-a716-446655440000"
      assert session.name == "test-project"
      assert session.project_path == "/home/user/projects/test-project"
      assert session.config.provider == "anthropic"
      assert session.config.model == "claude-3-5-sonnet-20241022"
      assert session.config.temperature == 0.7
      assert session.config.max_tokens == 4096
      assert session.created_at == now
      assert session.updated_at == now
    end

    test "struct has all expected fields" do
      fields = Session.__struct__() |> Map.keys() |> Enum.sort()

      expected_fields =
        [
          :__struct__,
          :config,
          :connection_status,
          :created_at,
          :id,
          :language,
          :name,
          :project_path,
          :updated_at
        ]
        |> Enum.sort()

      assert fields == expected_fields
    end

    test "can be created with nil fields" do
      session = %Session{}

      assert session.id == nil
      assert session.name == nil
      assert session.project_path == nil
      assert session.config == nil
      assert session.created_at == nil
      assert session.updated_at == nil
    end

    test "config can contain provider-specific fields" do
      session = %Session{
        id: "test-id",
        name: "test",
        project_path: "/tmp/test",
        config: %{
          provider: "ollama",
          model: "qwen3:32b",
          temperature: 0.5,
          max_tokens: 2048,
          base_url: "http://localhost:11434"
        },
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }

      assert session.config[:base_url] == "http://localhost:11434"
    end
  end

  describe "Session type compliance" do
    test "id is a string" do
      session = %Session{id: "uuid-string"}
      assert is_binary(session.id)
    end

    test "name is a string" do
      session = %Session{name: "project-name"}
      assert is_binary(session.name)
    end

    test "project_path is a string" do
      session = %Session{project_path: "/absolute/path"}
      assert is_binary(session.project_path)
    end

    test "config is a map" do
      config = %{provider: "test", model: "test", temperature: 0.5, max_tokens: 1000}
      session = %Session{config: config}
      assert is_map(session.config)
    end

    test "created_at is a DateTime" do
      now = DateTime.utc_now()
      session = %Session{created_at: now}
      assert %DateTime{} = session.created_at
    end

    test "updated_at is a DateTime" do
      now = DateTime.utc_now()
      session = %Session{updated_at: now}
      assert %DateTime{} = session.updated_at
    end
  end

  describe "Session.new/1" do
    setup do
      # Create a temporary directory for testing
      tmp_dir = Path.join(System.tmp_dir!(), "session_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
      end)

      %{tmp_dir: tmp_dir}
    end

    test "creates session with valid project_path", %{tmp_dir: tmp_dir} do
      assert {:ok, session} = Session.new(project_path: tmp_dir)

      assert session.project_path == tmp_dir
      assert is_binary(session.id)
      assert is_binary(session.name)
      assert is_map(session.config)
      assert %DateTime{} = session.created_at
      assert %DateTime{} = session.updated_at
    end

    test "uses folder name as default name", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      assert session.name == Path.basename(tmp_dir)
    end

    test "accepts custom name override", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir, name: "My Custom Project")

      assert session.name == "My Custom Project"
    end

    test "accepts custom config override", %{tmp_dir: tmp_dir} do
      custom_config = %{
        provider: "ollama",
        model: "qwen3:32b",
        temperature: 0.5,
        max_tokens: 2048
      }

      {:ok, session} = Session.new(project_path: tmp_dir, config: custom_config)

      assert session.config == custom_config
    end

    test "loads default config from Settings when not provided", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      # Should have default config values
      assert is_binary(session.config.provider)
      assert is_binary(session.config.model)
      assert is_float(session.config.temperature)
      assert is_integer(session.config.max_tokens)
    end

    test "returns error for non-existent path" do
      assert {:error, :path_not_found} = Session.new(project_path: "/nonexistent/path/12345")
    end

    test "returns error for file path (not directory)", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "test_file.txt")
      File.write!(file_path, "test content")

      assert {:error, :path_not_directory} = Session.new(project_path: file_path)
    end

    test "returns error when project_path is missing" do
      assert {:error, :missing_project_path} = Session.new([])
    end

    test "returns error when project_path is not a string", %{tmp_dir: _tmp_dir} do
      assert {:error, :invalid_project_path} = Session.new(project_path: 123)
    end

    test "sets created_at and updated_at to same value", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      assert session.created_at == session.updated_at
    end

    test "generates unique ids for each session", %{tmp_dir: tmp_dir} do
      {:ok, session1} = Session.new(project_path: tmp_dir)
      {:ok, session2} = Session.new(project_path: tmp_dir)

      assert session1.id != session2.id
    end

    # B1: Path traversal security tests
    test "returns error for path with traversal sequences", %{tmp_dir: tmp_dir} do
      traversal_path = Path.join(tmp_dir, "../etc")
      assert {:error, :path_traversal_detected} = Session.new(project_path: traversal_path)
    end

    test "returns error for path with multiple traversal sequences" do
      assert {:error, :path_traversal_detected} =
               Session.new(project_path: "/tmp/../../etc/passwd")
    end

    test "returns error for path with embedded traversal" do
      assert {:error, :path_traversal_detected} =
               Session.new(project_path: "/home/user/../../../etc")
    end

    # S4: Path length validation
    test "returns error for path exceeding max length" do
      # Create a path longer than 4096 bytes
      long_segment = String.duplicate("a", 500)
      long_path = "/" <> Enum.join(List.duplicate(long_segment, 10), "/")
      assert {:error, :path_too_long} = Session.new(project_path: long_path)
    end

    # B2: Symlink security tests
    test "accepts valid symlink pointing to existing directory", %{tmp_dir: tmp_dir} do
      target_dir = Path.join(tmp_dir, "real_dir")
      symlink_path = Path.join(tmp_dir, "link_to_real")
      File.mkdir_p!(target_dir)
      File.ln_s!(target_dir, symlink_path)

      # Should work - symlink points to valid directory
      assert {:ok, session} = Session.new(project_path: symlink_path)
      assert session.project_path == Path.expand(symlink_path)
    end

    test "returns error for symlink pointing to non-existent target", %{tmp_dir: tmp_dir} do
      symlink_path = Path.join(tmp_dir, "broken_link")
      # Create symlink to non-existent target
      File.ln_s!("/nonexistent/target/12345", symlink_path)

      assert {:error, :path_not_found} = Session.new(project_path: symlink_path)
    end

    test "returns error for symlink pointing to a file", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "target_file.txt")
      symlink_path = Path.join(tmp_dir, "link_to_file")
      File.write!(file_path, "content")
      File.ln_s!(file_path, symlink_path)

      assert {:error, :path_not_directory} = Session.new(project_path: symlink_path)
    end
  end

  describe "Session.generate_id/0" do
    test "generates valid UUID v4 format" do
      id = Session.generate_id()

      # UUID format: 8-4-4-4-12 hex chars
      assert Regex.match?(
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
               id
             )
    end

    test "version nibble is 4" do
      id = Session.generate_id()

      # Extract the version nibble (13th character, after second hyphen)
      version_char = String.at(id, 14)
      assert version_char == "4"
    end

    test "variant bits are correct (8, 9, a, or b)" do
      id = Session.generate_id()

      # Extract the variant nibble (first char after third hyphen, position 19)
      variant_char = String.at(id, 19)
      assert variant_char in ["8", "9", "a", "b"]
    end

    test "generates unique ids" do
      ids = for _ <- 1..100, do: Session.generate_id()

      assert length(Enum.uniq(ids)) == 100
    end

    test "id is 36 characters (including hyphens)" do
      id = Session.generate_id()

      assert String.length(id) == 36
    end
  end

  describe "Session.validate/1" do
    setup do
      # Create a temporary directory for testing
      tmp_dir = Path.join(System.tmp_dir!(), "session_validate_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
      end)

      # Create a valid session for testing
      now = DateTime.utc_now()

      valid_session = %Session{
        id: Session.generate_id(),
        name: "test-project",
        project_path: tmp_dir,
        config: %{
          provider: "anthropic",
          model: "claude-3-5-sonnet-20241022",
          temperature: 0.7,
          max_tokens: 4096
        },
        created_at: now,
        updated_at: now
      }

      %{tmp_dir: tmp_dir, valid_session: valid_session}
    end

    test "returns {:ok, session} for valid session", %{valid_session: session} do
      assert {:ok, ^session} = Session.validate(session)
    end

    test "validates session created with new/1", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      assert {:ok, ^session} = Session.validate(session)
    end

    # ID validation tests
    test "returns error for empty id", %{valid_session: session} do
      session = %{session | id: ""}
      assert {:error, reasons} = Session.validate(session)
      assert :invalid_id in reasons
    end

    test "returns error for nil id", %{valid_session: session} do
      session = %{session | id: nil}
      assert {:error, reasons} = Session.validate(session)
      assert :invalid_id in reasons
    end

    # Name validation tests
    test "returns error for empty name", %{valid_session: session} do
      session = %{session | name: ""}
      assert {:error, reasons} = Session.validate(session)
      assert :invalid_name in reasons
    end

    test "returns error for nil name", %{valid_session: session} do
      session = %{session | name: nil}
      assert {:error, reasons} = Session.validate(session)
      assert :invalid_name in reasons
    end

    test "returns error for name too long (> 50 chars)", %{valid_session: session} do
      long_name = String.duplicate("a", 51)
      session = %{session | name: long_name}
      assert {:error, reasons} = Session.validate(session)
      assert :name_too_long in reasons
    end

    test "accepts name with exactly 50 chars", %{valid_session: session} do
      name_50 = String.duplicate("a", 50)
      session = %{session | name: name_50}
      assert {:ok, _} = Session.validate(session)
    end

    # Project path validation tests
    test "returns error for non-absolute path", %{valid_session: session} do
      session = %{session | project_path: "relative/path"}
      assert {:error, reasons} = Session.validate(session)
      assert :path_not_absolute in reasons
    end

    test "returns error for non-existent path", %{valid_session: session} do
      session = %{session | project_path: "/nonexistent/path/12345"}
      assert {:error, reasons} = Session.validate(session)
      assert :path_not_found in reasons
    end

    test "returns error for file path (not directory)", %{
      valid_session: session,
      tmp_dir: tmp_dir
    } do
      file_path = Path.join(tmp_dir, "test_file.txt")
      File.write!(file_path, "test content")
      session = %{session | project_path: file_path}
      assert {:error, reasons} = Session.validate(session)
      assert :path_not_directory in reasons
    end

    test "returns error for nil project_path", %{valid_session: session} do
      session = %{session | project_path: nil}
      assert {:error, reasons} = Session.validate(session)
      assert :invalid_project_path in reasons
    end

    # Config validation tests
    test "returns error for nil config", %{valid_session: session} do
      session = %{session | config: nil}
      assert {:error, reasons} = Session.validate(session)
      assert :invalid_config in reasons
    end

    test "returns error for empty provider", %{valid_session: session} do
      session = %{session | config: %{session.config | provider: ""}}
      assert {:error, reasons} = Session.validate(session)
      assert :invalid_provider in reasons
    end

    test "accepts nil provider (not configured yet)", %{valid_session: session} do
      config = Map.delete(session.config, :provider)
      session = %{session | config: config}
      assert {:ok, _} = Session.validate(session)
    end

    test "returns error for empty model", %{valid_session: session} do
      session = %{session | config: %{session.config | model: ""}}
      assert {:error, reasons} = Session.validate(session)
      assert :invalid_model in reasons
    end

    test "accepts nil model (not configured yet)", %{valid_session: session} do
      config = Map.delete(session.config, :model)
      session = %{session | config: config}
      assert {:ok, _} = Session.validate(session)
    end

    test "returns error for temperature below 0.0", %{valid_session: session} do
      session = %{session | config: %{session.config | temperature: -0.1}}
      assert {:error, reasons} = Session.validate(session)
      assert :invalid_temperature in reasons
    end

    test "returns error for temperature above 2.0", %{valid_session: session} do
      session = %{session | config: %{session.config | temperature: 2.1}}
      assert {:error, reasons} = Session.validate(session)
      assert :invalid_temperature in reasons
    end

    test "accepts integer temperature within range", %{valid_session: session} do
      session = %{session | config: %{session.config | temperature: 1}}
      assert {:ok, _} = Session.validate(session)
    end

    test "accepts temperature at boundary values", %{valid_session: session} do
      session_0 = %{session | config: %{session.config | temperature: 0.0}}
      session_2 = %{session | config: %{session.config | temperature: 2.0}}

      assert {:ok, _} = Session.validate(session_0)
      assert {:ok, _} = Session.validate(session_2)
    end

    test "returns error for nil temperature", %{valid_session: session} do
      config = Map.delete(session.config, :temperature)
      session = %{session | config: config}
      assert {:error, reasons} = Session.validate(session)
      assert :invalid_temperature in reasons
    end

    test "returns error for zero max_tokens", %{valid_session: session} do
      session = %{session | config: %{session.config | max_tokens: 0}}
      assert {:error, reasons} = Session.validate(session)
      assert :invalid_max_tokens in reasons
    end

    test "returns error for negative max_tokens", %{valid_session: session} do
      session = %{session | config: %{session.config | max_tokens: -100}}
      assert {:error, reasons} = Session.validate(session)
      assert :invalid_max_tokens in reasons
    end

    test "returns error for nil max_tokens", %{valid_session: session} do
      config = Map.delete(session.config, :max_tokens)
      session = %{session | config: config}
      assert {:error, reasons} = Session.validate(session)
      assert :invalid_max_tokens in reasons
    end

    # Config with string keys (for JSON compatibility)
    test "accepts config with string keys", %{valid_session: session, tmp_dir: tmp_dir} do
      string_config = %{
        "provider" => "anthropic",
        "model" => "claude-3-5-sonnet-20241022",
        "temperature" => 0.7,
        "max_tokens" => 4096
      }

      session = %{session | project_path: tmp_dir, config: string_config}
      assert {:ok, _} = Session.validate(session)
    end

    # Timestamp validation tests
    test "returns error for nil created_at", %{valid_session: session} do
      session = %{session | created_at: nil}
      assert {:error, reasons} = Session.validate(session)
      assert :invalid_created_at in reasons
    end

    test "returns error for nil updated_at", %{valid_session: session} do
      session = %{session | updated_at: nil}
      assert {:error, reasons} = Session.validate(session)
      assert :invalid_updated_at in reasons
    end

    test "returns error for non-DateTime created_at", %{valid_session: session} do
      session = %{session | created_at: "2024-01-01"}
      assert {:error, reasons} = Session.validate(session)
      assert :invalid_created_at in reasons
    end

    test "returns error for non-DateTime updated_at", %{valid_session: session} do
      session = %{session | updated_at: ~N[2024-01-01 00:00:00]}
      assert {:error, reasons} = Session.validate(session)
      assert :invalid_updated_at in reasons
    end

    # Multiple errors test
    test "returns all errors when multiple fields are invalid", %{valid_session: session} do
      session = %{session | id: "", name: nil, project_path: "relative", config: nil}
      assert {:error, reasons} = Session.validate(session)

      assert :invalid_id in reasons
      assert :invalid_name in reasons
      assert :path_not_absolute in reasons
      assert :invalid_config in reasons
    end

    test "errors are returned in consistent order", %{valid_session: session} do
      session = %{session | id: "", name: ""}
      {:error, reasons1} = Session.validate(session)

      session = %{session | id: "", name: ""}
      {:error, reasons2} = Session.validate(session)

      assert reasons1 == reasons2
    end
  end

  describe "Session.update_config/2" do
    setup do
      tmp_dir =
        Path.join(System.tmp_dir!(), "session_update_config_test_#{:rand.uniform(100_000)}")

      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
      end)

      {:ok, session} = Session.new(project_path: tmp_dir)

      %{tmp_dir: tmp_dir, session: session}
    end

    test "merges new config with existing config", %{session: session} do
      original_provider = session.config.provider
      {:ok, updated} = Session.update_config(session, %{temperature: 0.5})

      assert updated.config.temperature == 0.5
      assert updated.config.provider == original_provider
    end

    test "updates updated_at timestamp", %{session: session} do
      original_updated_at = session.updated_at
      Process.sleep(1)
      {:ok, updated} = Session.update_config(session, %{temperature: 0.5})

      assert DateTime.compare(updated.updated_at, original_updated_at) == :gt
    end

    test "preserves created_at timestamp", %{session: session} do
      {:ok, updated} = Session.update_config(session, %{temperature: 0.5})

      assert updated.created_at == session.created_at
    end

    test "can update multiple config values at once", %{session: session} do
      {:ok, updated} =
        Session.update_config(session, %{
          provider: "openai",
          model: "gpt-4",
          temperature: 1.0,
          max_tokens: 8192
        })

      assert updated.config.provider == "openai"
      assert updated.config.model == "gpt-4"
      assert updated.config.temperature == 1.0
      assert updated.config.max_tokens == 8192
    end

    test "accepts string keys in new config", %{session: session} do
      {:ok, updated} = Session.update_config(session, %{"temperature" => 0.3})

      assert updated.config.temperature == 0.3
    end

    test "returns error for invalid provider", %{session: session} do
      assert {:error, reasons} = Session.update_config(session, %{provider: ""})
      assert :invalid_provider in reasons
    end

    test "returns error for invalid model", %{session: session} do
      assert {:error, reasons} = Session.update_config(session, %{model: ""})
      assert :invalid_model in reasons
    end

    test "returns error for temperature below range", %{session: session} do
      assert {:error, reasons} = Session.update_config(session, %{temperature: -0.1})
      assert :invalid_temperature in reasons
    end

    test "returns error for temperature above range", %{session: session} do
      assert {:error, reasons} = Session.update_config(session, %{temperature: 2.1})
      assert :invalid_temperature in reasons
    end

    test "returns error for zero max_tokens", %{session: session} do
      assert {:error, reasons} = Session.update_config(session, %{max_tokens: 0})
      assert :invalid_max_tokens in reasons
    end

    test "returns error for negative max_tokens", %{session: session} do
      assert {:error, reasons} = Session.update_config(session, %{max_tokens: -100})
      assert :invalid_max_tokens in reasons
    end

    test "returns error for non-map config", %{session: session} do
      assert {:error, reasons} = Session.update_config(session, "not a map")
      assert :invalid_config in reasons
    end

    # C1: Test accumulating errors (consistent with validate/1)
    test "returns all errors when multiple config values are invalid", %{session: session} do
      assert {:error, reasons} =
               Session.update_config(session, %{
                 provider: "",
                 model: "",
                 temperature: -1,
                 max_tokens: 0
               })

      assert :invalid_provider in reasons
      assert :invalid_model in reasons
      assert :invalid_temperature in reasons
      assert :invalid_max_tokens in reasons
    end

    # C2: Test that falsy values (0, 0.0) are properly handled
    test "accepts temperature of 0 (not treated as falsy)", %{session: session} do
      {:ok, updated} = Session.update_config(session, %{temperature: 0})
      assert updated.config.temperature == 0
    end

    test "accepts temperature of 0.0 (not treated as falsy)", %{session: session} do
      {:ok, updated} = Session.update_config(session, %{temperature: 0.0})
      assert updated.config.temperature == 0.0
    end

    test "accepts integer temperature within range", %{session: session} do
      {:ok, updated} = Session.update_config(session, %{temperature: 1})

      assert updated.config.temperature == 1
    end

    test "accepts temperature at boundary values", %{session: session} do
      {:ok, updated_0} = Session.update_config(session, %{temperature: 0.0})
      {:ok, updated_2} = Session.update_config(session, %{temperature: 2.0})

      assert updated_0.config.temperature == 0.0
      assert updated_2.config.temperature == 2.0
    end

    test "empty config map is valid (no changes)", %{session: session} do
      {:ok, updated} = Session.update_config(session, %{})

      assert updated.config == session.config
    end
  end

  describe "Session.rename/2" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "session_rename_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
      end)

      {:ok, session} = Session.new(project_path: tmp_dir)

      %{tmp_dir: tmp_dir, session: session}
    end

    test "changes session name", %{session: session} do
      {:ok, renamed} = Session.rename(session, "New Name")

      assert renamed.name == "New Name"
    end

    test "updates updated_at timestamp", %{session: session} do
      original_updated_at = session.updated_at
      Process.sleep(1)
      {:ok, renamed} = Session.rename(session, "New Name")

      assert DateTime.compare(renamed.updated_at, original_updated_at) == :gt
    end

    test "preserves created_at timestamp", %{session: session} do
      {:ok, renamed} = Session.rename(session, "New Name")

      assert renamed.created_at == session.created_at
    end

    test "preserves other fields", %{session: session} do
      {:ok, renamed} = Session.rename(session, "New Name")

      assert renamed.id == session.id
      assert renamed.project_path == session.project_path
      assert renamed.config == session.config
    end

    test "returns error for empty name", %{session: session} do
      assert {:error, :invalid_name} = Session.rename(session, "")
    end

    test "returns error for nil name", %{session: session} do
      assert {:error, :invalid_name} = Session.rename(session, nil)
    end

    test "returns error for non-string name", %{session: session} do
      assert {:error, :invalid_name} = Session.rename(session, 123)
    end

    test "returns error for name too long (> 50 chars)", %{session: session} do
      long_name = String.duplicate("a", 51)
      assert {:error, :name_too_long} = Session.rename(session, long_name)
    end

    test "accepts name with exactly 50 chars", %{session: session} do
      name_50 = String.duplicate("a", 50)
      {:ok, renamed} = Session.rename(session, name_50)

      assert renamed.name == name_50
    end

    test "accepts single character name", %{session: session} do
      {:ok, renamed} = Session.rename(session, "X")

      assert renamed.name == "X"
    end

    test "accepts name with spaces", %{session: session} do
      {:ok, renamed} = Session.rename(session, "My Project Name")

      assert renamed.name == "My Project Name"
    end

    test "accepts name with special characters", %{session: session} do
      {:ok, renamed} = Session.rename(session, "project-v2.0_beta")

      assert renamed.name == "project-v2.0_beta"
    end
  end
end
