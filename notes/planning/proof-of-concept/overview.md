# Jido Code - Agentic Coding Assistant TUI: Proof-of-Concept Plan

This proof-of-concept plan outlines the implementation of an agentic coding assistant TUI built on the BEAM platform. The system combines Jido's autonomous agent framework with TermUI's Elm Architecture to deliver a fault-tolerant, real-time coding assistant. This plan focuses on establishing the foundational architecture with Chain-of-Thought reasoning, configurable LLM providers, and a minimal but functional TUI interface.

## Overview

The proof-of-concept establishes three core architectural layers: the TUI Presentation Layer using Elm Architecture patterns, the Agent Orchestration Layer built on Jido's GenServer-based agents with Chain-of-Thought reasoning, and a Configuration Layer for LLM provider management. This phase prioritizes demonstrable functionality over feature completeness.

**Key Deliverables**:
- Functional TUI application with Elm Architecture (Model/Update/View)
- LLM Agent using JidoAI with configurable providers (no default - explicit config required)
- Streaming response display showing tokens as they arrive
- Chain-of-Thought reasoning integration for complex queries
- Sandboxed tool calling via Lua (luerl) with file, search, and shell tools
- Phoenix PubSub-based communication between TUI and agents
- Two-level JSON settings system (global `~/.jido_code/settings.json` + local `./jido_code/settings.json`)
- Persistent provider/model selection with custom provider and model lists
- Knowledge graph foundation stub with RDF.ex/libgraph for future expansion

**Proof-of-Concept Scope**: Chat interface with streaming responses, agent interaction with CoT reasoning, sandboxed tool execution, configurable LLM backends, proper OTP supervision, and knowledge graph infrastructure placeholder.

## Phase Documents

- [Phase 1: Project Foundation and Core Infrastructure](phase-01.md)
- [Phase 2: LLM Agent with Chain-of-Thought Reasoning](phase-02.md)
- [Phase 3: Tool Calling and Sandbox](phase-03.md)
- [Phase 4: TUI Application with Elm Architecture](phase-04.md)
- [Phase 5: Integration and Message Flow](phase-05.md)
- [Phase 6: Testing and Documentation](phase-06.md)
- [Phase 7: Theming and Styling](phase-07.md)

## Success Criteria

1. **Functional TUI**: Application starts, displays interface, accepts input, and renders responses
2. **LLM Integration**: Queries are processed by configured LLM provider and responses display correctly
3. **Chain-of-Thought**: Complex queries trigger CoT reasoning with visible step display
4. **Tool Execution**: Agent can read/write files, search code, and run commands within sandbox
5. **Security Boundaries**: All tool operations restricted to project directory, no direct shell access
6. **Provider Switching**: Runtime model/provider changes work without restart
7. **Settings Persistence**: Provider/model selections persist across sessions via JSON files
8. **Fault Tolerance**: Agent crashes recover automatically via supervision
9. **Test Coverage**: Minimum 80% code coverage with passing test suite

## Key Outputs

- Working `jido_code` Elixir application with TUI
- Streaming response display for real-time token output
- Configurable LLM agent supporting 50+ providers via JidoAI/ReqLLM (explicit config required)
- Chain-of-Thought reasoning integration for complex queries
- Lua-sandboxed tool manager (luerl) with security boundaries
- Core coding tools: file read/write, grep/find, shell execution
- Command interface for runtime configuration
- Persistent JSON settings with global/local merge (provider, model, custom lists)
- Knowledge graph infrastructure stub (RDF.ex + libgraph) for future expansion
- Comprehensive test suite and documentation

## Provides Foundation For

- **Phase 2**: Context management and file system integration
- **Phase 3**: Knowledge graph memory implementation
- **Phase 4**: MCP protocol integration for external tools
- **Phase 5**: Multi-agent coordination with specialized skills
