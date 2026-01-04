import Config

config :jido_workspace,
  projects: [
    %{
      name: "jido",
      upstream_url: "git@github.com:agentjido/jido.git",
      branch: "v2",
      type: :library,
      path: "projects/jido"
    },
    # Read-only reference to Jido v1 (main branch) for comparison
    %{
      name: "jido_v1",
      upstream_url: "git@github.com:agentjido/jido.git",
      branch: "main",
      type: :library,
      path: "projects/jido_v1",
      read_only: true
    },
    %{
      name: "jido_action",
      upstream_url: "git@github.com:agentjido/jido_action.git",
      branch: "main",
      type: :library,
      path: "projects/jido_action"
    },
    %{
      name: "jido_signal",
      upstream_url: "git@github.com:agentjido/jido_signal.git",
      branch: "main",
      type: :library,
      path: "projects/jido_signal"
    },
    # EXPERIMENTAL - Ash framework integration
    %{
      name: "ash_jido",
      upstream_url: "git@github.com:agentjido/ash_jido.git",
      branch: "main",
      type: :library,
      path: "projects/ash_jido"
    },
    %{
      name: "ash_ai",
      upstream_url: "git@github.com:mikehostetler/ash_ai.git",
      branch: "main",
      type: :library,
      path: "projects/ash_ai"
    },
    %{
      name: "jido_ai",
      upstream_url: "git@github.com:agentjido/jido_ai.git",
      branch: "v2",
      type: :library,
      path: "projects/jido_ai"
    },
    # Read-only reference to Jido AI v1 (main branch) for comparison
    %{
      name: "jido_ai_v1",
      upstream_url: "git@github.com:agentjido/jido_ai.git",
      branch: "main",
      type: :library,
      path: "projects/jido_ai_v1",
      read_only: true
    },
    # EXPERIMENTAL - LLM evaluation framework
    %{
      name: "jido_eval",
      upstream_url: "git@github.com:agentjido/jido_eval.git",
      branch: "main",
      type: :library,
      path: "projects/jido_eval"
    },
    %{
      name: "jido_workbench",
      upstream_url: "git@github.com:agentjido/jido_workbench.git",
      branch: "main",
      type: :library,
      path: "projects/jido_workbench"
    },
    %{
      name: "hako",
      upstream_url: "git@github.com:agentjido/hako.git",
      branch: "main",
      type: :library,
      path: "projects/hako"
    },
    # EXPERIMENTAL - Behavior tree implementation
    %{
      name: "jido_behaviortree",
      upstream_url: "git@github.com:agentjido/jido_behaviortree.git",
      branch: "main",
      type: :library,
      path: "projects/jido_behaviortree"
    },
    %{
      name: "jido_chat",
      upstream_url: "git@github.com:agentjido/jido_chat.git",
      branch: "main",
      type: :library,
      path: "projects/jido_chat"
    },
    %{
      name: "sparq",
      upstream_url: "git@github.com:epic-creative/sparq.git",
      branch: "main",
      type: :library,
      path: "projects/sparq"
    },
    %{
      name: "jido_character",
      upstream_url: "git@github.com:agentjido/jido_character.git",
      branch: "main",
      type: :library,
      path: "projects/jido_character"
    },
    %{
      name: "jido_htn",
      upstream_url: "git@github.com:epic-creative/jido_htn.git",
      branch: "main",
      type: :library,
      path: "projects/jido_htn"
    },
    %{
      name: "kodo",
      upstream_url: "git@github.com:agentjido/kodo.git",
      branch: "main",
      type: :library,
      path: "projects/kodo"
    },
    %{
      name: "req_llm",
      upstream_url: "git@github.com:agentjido/req_llm.git",
      branch: "main",
      type: :library,
      path: "projects/req_llm"
    },
    # LLM model metadata catalog - high churn, independent version stream
    %{
      name: "llm_db",
      upstream_url: "git@github.com:agentjido/llm_db.git",
      branch: "main",
      type: :library,
      path: "projects/llm_db"
    },
    # EXPERIMENTAL - Evolutionary optimization
    %{
      name: "kaizen",
      upstream_url: "git@github.com:agentjido/kaizen.git",
      branch: "main",
      type: :library,
      path: "projects/kaizen"
    },
    %{
      name: "jido_hub",
      upstream_url: "git@github.com:mikehostetler/jido_hub.git",
      branch: "main",
      type: :library,
      path: "projects/jido_hub"
    },
    %{
      name: "jido_code",
      upstream_url: "git@github.com:agentjido/jido_code.git",
      branch: "main",
      type: :library,
      path: "projects/jido_code"
    },
    %{
      name: "jido_messaging",
      upstream_url: "git@github.com:epic-creative/jido_messaging.git",
      branch: "main",
      type: :library,
      path: "projects/jido_messaging"
    },
    %{
      name: "karo",
      upstream_url: "git@github.com:epic-creative/karo.git",
      branch: "main",
      type: :library,
      path: "projects/karo"
    }
  ],
  hex_packages: [
    # Core packages - publish together as version train
    %{
      name: "jido_signal",
      path: "projects/jido_signal",
      publish_order: 1,
      dependencies: [],
      version_train: :core
    },
    %{
      name: "jido_action",
      path: "projects/jido_action",
      publish_order: 2,
      dependencies: [],
      version_train: :core
    },
    %{
      name: "jido",
      path: "projects/jido",
      publish_order: 3,
      dependencies: ["jido_signal", "jido_action"],
      version_train: :core
    },
    %{
      name: "jido_ai",
      path: "projects/jido_ai",
      publish_order: 4,
      dependencies: ["jido", "jido_action"],
      version_train: :core
    },
    # Independent packages - own version streams
    %{
      name: "llm_db",
      path: "projects/llm_db",
      publish_order: 10,
      dependencies: [],
      version_train: :independent
    },
    %{
      name: "req_llm",
      path: "projects/req_llm",
      publish_order: 11,
      dependencies: ["llm_db"],
      version_train: :independent
    },
    %{
      name: "github-actions",
      upstream_url: "https://github.com/agentjido/github-actions.git",
      branch: "main",
      type: :library,
      path: "projects/github-actions"
    },
    %{
      name: "jido_sandbox",
      upstream_url: "git@github.com:agentjido/jido_sandbox.git",
      branch: "main",
      type: :library,
      path: "projects/jido_sandbox"
    }

  ]
