import Config

config :git_hooks,
  auto_install: true,
  verbose: true,
  hooks: [
    commit_msg: [
      tasks: [
        {:cmd, "mix git_ops.check_message"}
      ]
    ],
    pre_commit: [
      tasks: [
        {:mix_task, :format, ["--check-formatted"]}
      ]
    ],
    pre_push: [
      tasks: [
        {:mix_task, :quality}
      ]
    ]
  ]
