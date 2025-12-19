# Phase 2: LLM Agent with Chain-of-Thought Reasoning

This phase implements the core LLM agent using JidoAI's Agent and Chain-of-Thought runner. The agent handles user queries, applies structured reasoning to complex problems, and returns responses through PubSub for TUI consumption.

## 2.1 LLM Agent Implementation

The LLM agent encapsulates all LLM interaction logic using JidoAI's `Jido.AI.Agent` pattern. It supports multiple providers (Anthropic, OpenAI) with runtime configuration and integrates Chain-of-Thought reasoning for improved accuracy on complex coding tasks.

### 2.1.1 Basic Agent Module
- [x] **Task 2.1.1 Complete**

Create the primary LLM agent that handles chat interactions with configurable model selection.

- [x] 2.1.1.1 Create `JidoCode.Agents.LLMAgent` module
- [x] 2.1.1.2 Implement `start_link/1` using `Jido.AI.Agent.start_link/1` with dynamic model config
- [x] 2.1.1.3 Build model from config: `Jido.AI.Model.from({provider, model: model_name, ...})`
- [x] 2.1.1.4 Define system prompt for coding assistant personality and capabilities
- [x] 2.1.1.5 Implement `chat/2` function calling `Jido.AI.Agent.chat_response/3`
- [x] 2.1.1.6 Add PubSub broadcast of responses to `"tui.events"` topic
- [x] 2.1.1.7 Write integration test with mock LLM responses (success: message round-trip works)

### 2.1.2 Provider Configuration API
- [x] **Task 2.1.2 Complete**

Implement runtime API for switching LLM providers and models without restart. Any provider from `Jido.AI.Provider.providers/0` is valid (50+ providers via ReqLLM). Model names are validated against the provider's available models.

- [x] 2.1.2.1 Create `JidoCode.Agents.LLMAgent.configure/2` to update agent model settings
- [x] 2.1.2.2 Accept any provider atom from `Jido.AI.Model.Registry.Adapter.list_providers/0` (dynamic discovery)
- [x] 2.1.2.3 Validate model exists for provider via `Jido.AI.Model.Registry.Adapter.model_exists?/2` before accepting config
- [x] 2.1.2.4 Return descriptive error if model invalid: "Model X not found for provider Y"
- [x] 2.1.2.5 Implement `get_config/1` to inspect active model settings (already existed from 2.1.1)
- [x] 2.1.2.6 Add API key validation via `Jido.AI.Keyring` for the configured provider
- [x] 2.1.2.7 Broadcast config change events for TUI status display
- [x] 2.1.2.8 Write tests for hot-swapping providers (success: config changes apply immediately)

### 2.1.3 Agent Lifecycle Observability
- [x] **Task 2.1.3 Complete**

Add telemetry and logging for agent lifecycle events to enable debugging and monitoring.

- [x] 2.1.3.1 Add Telemetry events for agent start: `[:jido_code, :agent, :start]`
- [x] 2.1.3.2 Add Telemetry events for agent stop: `[:jido_code, :agent, :stop]`
- [x] 2.1.3.3 Add Telemetry events for agent crash: `[:jido_code, :agent, :crash]`
- [x] 2.1.3.4 Include metadata: agent name, module, duration, error reason (for crashes)
- [x] 2.1.3.5 Add optional Logger handler for telemetry events (configurable log level)
- [x] 2.1.3.6 Track restart counts per agent for detecting restart loops
- [x] 2.1.3.7 Write tests verifying telemetry events are emitted (success: events captured in test)

## 2.2 Chain-of-Thought Integration

Chain-of-Thought (CoT) reasoning enables step-by-step problem decomposition for complex coding queries. Using JidoAI's CoT runner provides 8-15% accuracy improvement on multi-step reasoning tasks at the cost of 3-4x token usage.

### 2.2.1 CoT Runner Configuration
- [x] **Task 2.2.1 Complete**

Configure the Chain-of-Thought runner with appropriate settings for coding assistance.

- [x] 2.2.1.1 Create `JidoCode.Reasoning.ChainOfThought` wrapper module
- [x] 2.2.1.2 Define default CoT config: `mode: :zero_shot`, `temperature: 0.2`, `enable_validation: true`
- [x] 2.2.1.3 Implement `run_with_reasoning/3` accepting agent, query, and optional config overrides
- [x] 2.2.1.4 Parse reasoning plan from LLM response (zero_shot and structured formats)
- [x] 2.2.1.5 Extract and format reasoning steps for TUI display
- [x] 2.2.1.6 Handle CoT fallback to direct execution on reasoning failure
- [x] 2.2.1.7 Add telemetry events for reasoning duration and step count

### 2.2.2 Query Classification
- [x] **Task 2.2.2 Complete**

Implement heuristics to determine when CoT reasoning should be applied vs. direct response.

- [x] 2.2.2.1 Create `JidoCode.Reasoning.QueryClassifier` module
- [x] 2.2.2.2 Define query complexity indicators: code keywords, multi-step phrases, debugging patterns
- [x] 2.2.2.3 Implement `should_use_cot?/1` returning boolean based on query analysis
- [x] 2.2.2.4 Classify as complex: "debug", "explain", "step by step", "how to", code blocks
- [x] 2.2.2.5 Classify as simple: greetings, single-word queries, confirmations
- [x] 2.2.2.6 Add configuration option to force CoT on/off regardless of classification
- [x] 2.2.2.7 Write classification tests with example queries (success: 90%+ correct classification)

### 2.2.3 Reasoning Display Format
- [x] **Task 2.2.3 Complete**

Format Chain-of-Thought reasoning steps for clear TUI presentation.

- [x] 2.2.3.1 Create `JidoCode.Reasoning.Formatter` module
- [x] 2.2.3.2 Define reasoning step struct: `%Step{number: int, description: string, outcome: string}`
- [x] 2.2.3.3 Implement `format_plan/1` converting ReasoningPlan to display strings
- [x] 2.2.3.4 Add step status indicators: pending (○), in-progress (◐), complete (●), failed (✗)
- [x] 2.2.3.5 Format validation results with confidence scores
- [x] 2.2.3.6 Create collapsible reasoning summary for long chains
- [x] 2.2.3.7 Write formatter tests with sample reasoning plans (success: output is human-readable)
