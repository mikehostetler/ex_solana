# Jido Workspace Package Tree

Reference catalog of all packages in `projects/` with their versions and key dependencies.

---

## Core Ecosystem

| Package | Version | Description | Key Dependencies |
|---------|---------|-------------|------------------|
| **jido** | 1.2.0 | Autonomous agent framework | jido_action, jido_signal |
| **jido_action** | 1.0.0 | Composable actions with AI tool integration | zoi, nimble_options, splode |
| **jido_signal** | 1.2.0 | Agent communication envelope | phoenix_pubsub, splode, zoi |

## AI Layer

| Package | Version | Description | Key Dependencies |
|---------|---------|-------------|------------------|
| **req_llm** | 1.2.0 | LLM interactions via Req | llm_db, zoi, splode |
| **jido_ai** | 2.0.0 | AI integration layer | req_llm, zoi, splode |
| **llm_db** | 2025.12.3 | LLM model metadata catalog | zoi, req |

## Applications

| Package | Version | Description | Key Dependencies |
|---------|---------|-------------|------------------|
| **jido_chat** | 0.5.0 | Structured chat room system | jido, jido_ai |
| **jido_eval** | 0.1.0 | LLM evaluation framework | jido_ai |
| **jido_code** | 0.1.0 | Agentic coding assistant TUI | jido, jido_ai, term_ui |
| **jido_hub** | 0.1.0 | Phoenix web application | ash, phoenix |
| **jido_workbench** | 0.1.0 | Phoenix development UI | phoenix, req_llm |

## Extensions

| Package | Version | Description | Key Dependencies |
|---------|---------|-------------|------------------|
| **jido_behaviortree** | 1.0.0 | Behavior tree implementation | jido, jido_action, jido_signal, zoi |
| **jido_htn** | 0.1.0 | Hierarchical Task Networks | jido, jido_action |
| **jido_character** | 1.0.0 | Character definition for AI agents | zoi, req_llm |

## Utilities

| Package | Version | Description | Key Dependencies |
|---------|---------|-------------|------------------|
| **kodo** | 3.0.0 | Virtual workspace shell | hako, zoi |
| **hako** | 1.0.0 | Filesystem abstraction | ex_aws, splode |
| **kaizen** | 0.1.0 | Evolutionary optimization | splode, nimble_options |
| **sparq** | 0.1.0 | Parser utilities | nimble_parsec |

---

## Dependency Graph

```
jido
├── jido_action
└── jido_signal

jido_ai
└── req_llm
    └── llm_db

jido_chat
├── jido
└── jido_ai

jido_code
├── jido
└── jido_ai

jido_behaviortree
├── jido
├── jido_action
└── jido_signal

jido_htn
├── jido
└── jido_action

kodo
└── hako
```
