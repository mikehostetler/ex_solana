import Config

if Mix.env() == :dev do
  config :git_ops,
    mix_project: Jido.Character.MixProject,
    changelog_file: "CHANGELOG.md",
    repository_url: "https://github.com/agentjido/jido_character",
    manage_mix_version?: true,
    manage_readme_version: false,
    version_tag_prefix: "v"

  config :git_hooks,
    auto_install: true,
    verbose: true,
    hooks: [
      commit_msg: [
        tasks: [
          {:cmd, "MIX_ENV=dev mix git_ops.check_message", include_hook_args: true}
        ]
      ],
      pre_commit: [
        tasks: [
          {:mix_task, :format, ["--check-formatted"]}
        ]
      ],
      pre_push: [
        tasks: [
          {:mix_task, :test},
          {:mix_task, :quality}
        ]
      ]
    ]
end
