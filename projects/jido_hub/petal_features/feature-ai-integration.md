# Feature: AI Integration

## Overview
This feature provides LangChain-based AI capabilities for text generation, analysis, and intelligent automation within the application. It establishes patterns for prompt engineering, chain composition, and provider abstraction that enable seamless integration of large language models into business workflows.

The AI infrastructure supports multiple LLM providers through a unified interface, enabling easy switching between OpenAI, Anthropic, or other providers. Background job processing handles longer-running AI tasks asynchronously, ensuring responsive user experiences while leveraging expensive model inference. The architecture emphasizes prompt reusability, chain composition, and structured output handling.

## Key Capabilities
- LangChain-based abstraction for LLM interactions
- Prompt template management and chain composition
- Multiple LLM provider support (OpenAI, Anthropic, etc.)
- Streaming response handling for real-time feedback
- Background job processing for long-running AI tasks
- Structured output parsing and validation
- Context management and conversation history
- Token usage tracking and cost monitoring
- HTTP client abstraction with Tesla and Finch

## Architecture & Implementation

### Related Modules
- `lib/petal_pro/ai/` - Core AI abstractions, prompts, and chains
- `lib/petal_pro/ai/providers/` - Provider-specific client implementations
- `lib/petal_pro/ai/chains/` - Reusable chain compositions
- `lib/petal_pro/workers/ai/` - Background workers for async AI processing
- `lib/petal_pro_web/live/ai/` - LiveView components for AI interactions

### Key Dependencies
- `langchain` - LLM framework for Elixir with chain composition
- `tesla` - HTTP client middleware for API requests
- `finch` - HTTP/1 and HTTP/2 client with connection pooling
- `httpoison` - Alternative HTTP client (consider consolidating on Finch/Tesla)
- `jason` - JSON encoding/decoding for API payloads
- `oban` or background job library - Async processing of AI tasks

## Integration Points
The AI system integrates with Phoenix LiveView through real-time streaming updates, displaying generated content as it arrives from the LLM. Background workers (likely Oban) handle longer AI tasks, updating the UI through Phoenix PubSub when results are ready. The LangChain abstraction allows business logic to remain provider-agnostic while configuration determines which LLM backend is used. HTTP clients (Tesla/Finch) handle API communication with retry logic and timeout handling. Results are typically stored in the database for auditing, cost tracking, and caching purposes.

## Adaptation Notes
When extracting to JidoHub, carefully review API key management and ensure secrets are properly configured for your deployment environment. Assess which LLM providers you need and remove unused provider implementations. Consider implementing rate limiting and cost controls appropriate to your usage patterns and budget. Review prompt templates to ensure they align with your domain language and business requirements. Evaluate whether streaming responses are necessary for your use cases or if simpler async processing suffices. Configure background job concurrency based on your API rate limits and infrastructure capacity. Consider implementing prompt versioning and A/B testing infrastructure if AI features are core to your product.

## Gap Analysis: JidoHub vs Petal Pro

### Current JidoHub Implementation
- **Ash AI Foundation**: ash_ai (v0.2) included in dependencies
- **MCP Dev Integration**: AshAi.Mcp.Dev plug configured for development mode at `/ash_ai/mcp`
- **Protocol Support**: Model Context Protocol (MCP) version 2024-11-05 configured
- **Background Jobs**: Oban configured with ash_oban for async task processing
- **HTTP Client**: Req (v0.5) included as the standard HTTP client
- **API Infrastructure**: JSON API support via ash_json_api and OpenAPI via open_api_spex
- **Reserved AI Terms**: Username validation includes AI-related reserved words (ai, llm, gpt, etc.)
- **Infrastructure Readiness**: Telemetry, PubSub, and LiveView streaming infrastructure available

### Missing from JidoHub
- **LangChain Integration**: No LangChain Elixir library or chain composition patterns
- **LLM Provider Clients**: No OpenAI, Anthropic, or other LLM provider implementations
- **Prompt Management**: No prompt templates, versioning, or prompt engineering utilities
- **AI-Specific Modules**: No lib/jido_hub/ai/ directory structure or AI domain logic
- **Streaming Response Handling**: No LiveView components for streaming AI responses
- **Token Tracking**: No usage monitoring, cost tracking, or token counting
- **Context Management**: No conversation history or context window management
- **Structured Output**: No schema validation or structured response parsing
- **AI Background Workers**: No dedicated Oban workers for AI-specific tasks
- **Testing Infrastructure**: No AI response mocking or prompt testing utilities
- **Rate Limiting**: No AI-specific rate limiting or cost controls
- **Provider Abstraction**: No adapter pattern for swapping LLM providers

### Implementation Priority
**High Priority**:
- LLM provider client (OpenAI/Anthropic) - Core functionality for AI features
- Prompt template system - Essential for maintainable AI interactions
- Basic streaming response handling - Critical for user experience
- Token usage tracking - Necessary for cost management and monitoring

**Medium Priority**:
- AI background workers - Important for long-running tasks
- Structured output parsing - Improves reliability of AI responses
- Provider abstraction layer - Enables flexibility and testing
- AI-specific test helpers - Accelerates development and debugging

**Low Priority**:
- LangChain integration - Can build simpler patterns initially
- Advanced context management - Start with basic conversation history
- Prompt versioning/A/B testing - Add when AI features mature
- Advanced rate limiting - Can use infrastructure-level controls initially

### Migration Complexity
**Simple** (2-4 hours):
- Adding OpenAI or Anthropic HTTP client wrapper
- Basic prompt template module with string interpolation
- Simple token counting utilities
- Configuration for API keys and endpoints

**Moderate** (1-2 days):
- LiveView components for streaming AI responses
- Oban worker jobs for AI task processing
- Structured output parsing with schema validation
- Basic usage tracking and telemetry integration
- AI response mocking for tests

**Complex** (3-5 days):
- Full LangChain-style chain composition framework
- Provider abstraction layer with multiple backends
- Advanced context window management and conversation history
- Prompt versioning and A/B testing infrastructure
- Comprehensive AI testing suite with cassettes/fixtures
- Cost controls and rate limiting per user/org
- Real-time token streaming with backpressure handling
