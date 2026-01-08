[
  inputs: [
    "{mix,.formatter,.credo}.exs",
    "{config,lib,test}/**/*.{ex,exs}"
  ],
  line_length: 120,
  import_deps: [:typed_struct, :nimble_options, :flame]
]
