ExUnit.start(capture_log: true)

# Load all test support files
support_files =
  __DIR__
  |> Path.join("support/**/*.exs")
  |> Path.wildcard()
  |> Enum.sort()

Enum.each(support_files, &Code.require_file/1)
