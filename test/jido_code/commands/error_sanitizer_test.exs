defmodule JidoCode.Commands.ErrorSanitizerTest do
  use ExUnit.Case, async: true

  alias JidoCode.Commands.ErrorSanitizer

  describe "sanitize_error/1" do
    test "sanitizes file system errors to generic messages" do
      assert ErrorSanitizer.sanitize_error(:eacces) == "Permission denied."
      assert ErrorSanitizer.sanitize_error(:enoent) == "Resource not found."
      assert ErrorSanitizer.sanitize_error(:enotdir) == "Invalid path."
      assert ErrorSanitizer.sanitize_error(:eexist) == "Resource already exists."
      assert ErrorSanitizer.sanitize_error(:enospc) == "Insufficient disk space."
    end

    test "sanitizes session-specific errors" do
      assert ErrorSanitizer.sanitize_error(:not_found) == "Session not found."

      assert ErrorSanitizer.sanitize_error(:project_path_not_found) ==
               "Project path no longer exists."

      assert ErrorSanitizer.sanitize_error(:project_path_changed) ==
               "Project path properties changed unexpectedly."

      assert ErrorSanitizer.sanitize_error(:project_already_open) ==
               "Project already open in another session."

      assert ErrorSanitizer.sanitize_error(:session_limit_reached) == "Maximum sessions reached."
    end

    test "sanitizes validation errors without exposing details" do
      # Should not expose which fields are missing
      assert ErrorSanitizer.sanitize_error({:missing_fields, [:id, :name]}) ==
               "Invalid data format."

      # Should not expose the invalid value
      assert ErrorSanitizer.sanitize_error({:invalid_id, "malicious-value"}) ==
               "Invalid identifier."

      assert ErrorSanitizer.sanitize_error({:invalid_version, 99}) ==
               "Unsupported format version."
    end

    test "sanitizes cryptographic errors without exposing details" do
      assert ErrorSanitizer.sanitize_error(:signature_verification_failed) ==
               "Data integrity check failed."

      assert ErrorSanitizer.sanitize_error({:signature_verification_failed, "details"}) ==
               "Data integrity check failed."
    end

    test "sanitizes file operation errors stripping path information" do
      # Should not expose file paths to users
      assert ErrorSanitizer.sanitize_error(
               {:file_error, "/home/user/.jido_code/sessions/abc.json", :eacces}
             ) ==
               "Permission denied."

      assert ErrorSanitizer.sanitize_error({:read_error, "/tmp/secret/file.txt", :enoent}) ==
               "Resource not found."

      assert ErrorSanitizer.sanitize_error({:write_error, "/var/data/session.json", :enospc}) ==
               "Insufficient disk space."
    end

    test "sanitizes JSON errors without exposing internal structure" do
      assert ErrorSanitizer.sanitize_error({:json_encode_error, "internal reason"}) ==
               "Data encoding failed."

      assert ErrorSanitizer.sanitize_error({:json_decode_error, %Jason.DecodeError{}}) ==
               "Data format error."
    end

    test "provides generic message for unknown errors" do
      # Unknown error types should get a generic message
      assert ErrorSanitizer.sanitize_error(:some_unknown_error) ==
               "Operation failed. Please try again or contact support."

      assert ErrorSanitizer.sanitize_error({:unknown_tuple, "details", 123}) ==
               "Operation failed. Please try again or contact support."

      assert ErrorSanitizer.sanitize_error("arbitrary string") ==
               "Operation failed. Please try again or contact support."
    end
  end

  describe "log_and_sanitize/2" do
    import ExUnit.CaptureLog

    test "logs detailed error internally and returns sanitized message" do
      log =
        capture_log(fn ->
          result =
            ErrorSanitizer.log_and_sanitize(
              {:file_error, "/secret/path.json", :eacces},
              "read file"
            )

          # Should return sanitized message
          assert result == "Permission denied."
        end)

      # Should log detailed error for debugging
      assert log =~ "Failed to read file"
      assert log =~ "/secret/path.json"
      assert log =~ "eacces"
    end

    test "logs unknown errors with full details for debugging" do
      log =
        capture_log(fn ->
          result =
            ErrorSanitizer.log_and_sanitize(
              {:complex_error, :reason, %{data: "sensitive"}},
              "complex operation"
            )

          # Should return generic message
          assert result == "Operation failed. Please try again or contact support."
        end)

      # Should log full details internally
      assert log =~ "Failed to complex operation"
      assert log =~ "complex_error"
      assert log =~ "sensitive"
    end

    test "provides context in log messages" do
      log =
        capture_log(fn ->
          ErrorSanitizer.log_and_sanitize(:enoent, "save session")
        end)

      assert log =~ "Failed to save session"
    end
  end

  describe "security properties" do
    test "never exposes file paths in sanitized messages" do
      sensitive_paths = [
        "/home/user/.jido_code/sessions/abc-123.json",
        "/var/lib/jido/session.json",
        "C:\\Users\\Admin\\AppData\\sessions\\file.json",
        "../../../etc/passwd"
      ]

      for path <- sensitive_paths do
        result = ErrorSanitizer.sanitize_error({:file_error, path, :eacces})

        refute String.contains?(result, path),
               "Sanitized message contains sensitive path: #{path}"
      end
    end

    test "never exposes UUIDs or session IDs in sanitized messages" do
      uuids = [
        "550e8400-e29b-41d4-a716-446655440000",
        "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
      ]

      for uuid <- uuids do
        result = ErrorSanitizer.sanitize_error({:invalid_id, uuid})
        refute String.contains?(result, uuid), "Sanitized message contains UUID: #{uuid}"
      end
    end

    test "never exposes internal error atoms in sanitized messages" do
      internal_errors = [
        {:missing_fields, [:password, :api_key]},
        {:unknown_error_type, :internal_detail},
        {:database_error, "connection failed"}
      ]

      for error <- internal_errors do
        result = ErrorSanitizer.sanitize_error(error)

        # Generic message should not contain sensitive details
        refute result =~ "password"
        refute result =~ "api_key"
        refute result =~ "unknown_error_type"
        refute result =~ "database_error"
        refute result =~ "connection failed"
      end
    end
  end
end
