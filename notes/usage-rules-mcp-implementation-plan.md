<!--
SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Usage Rules MCP Tool Integration Implementation Plan

## Problem Statement

AI coding assistants need access to package-specific usage rules and best practices when working with Elixir dependencies. Currently, there's no way for tools like Claude Code to discover and access the `usage-rules.md` files that many packages include.

**Why this matters**: Package maintainers provide critical guidance in usage-rules.md files that helps developers avoid common pitfalls and follow best practices. Making this accessible to AI assistants improves code quality and reduces implementation errors.

## Solution Overview

Integrate usage rules functionality into ash_ai's development MCP server by exposing package usage rules through MCP tools. This enables AI coding assistants to automatically discover and access usage rules from project dependencies.

**Key design decisions**:
- Leverage existing MCP infrastructure in ash_ai
- Focus on read-only discovery and access (no project modification)
- Use direct file system access for simplicity
- Build on existing commented implementation

## Implementation Plan

### Step 1: Enable Basic Functionality ✅ **COMPLETED**
- [x] Uncomment existing implementation in `lib/ash_ai/dev_tools/tools.ex` (lines 66-102)
- [x] Fix type reference from `PackageRules` to `UsageRules` 
- [x] Update tool registration in `lib/ash_ai/dev_tools.ex`
- [x] Test basic `get_usage_rules` functionality works
- [x] Verify successful package rules retrieval (found 5+ packages with rules)

### Step 2: Add Package Discovery ✅ **COMPLETED**
- [x] Implement `list_packages_with_rules` action
- [x] Register new tool in domain for MCP exposure
- [x] Test package discovery functionality
- [x] Verify clean read-only API design

### Step 3: Comprehensive Testing ✅ **COMPLETED**
- [x] Add comprehensive test suite for all usage rules functionality
- [x] Test edge cases (non-existent packages, empty lists, mixed scenarios)
- [x] Verify integration with existing dev tools test patterns
- [x] Ensure 100% test coverage for new functionality (17 tests passing)

### Step 4: Manual Integration Verification ✅ **COMPLETED**
- [x] Test MCP protocol integration with actual Claude Desktop connection
- [x] Verify tools are properly exposed through development server
- [x] Test error handling in real MCP environment
- [x] Confirm tool descriptions and arguments work correctly
- [x] Successfully tested in another project - tools working as expected

## Technical Details

### File Locations and Structure
- **Main implementation**: `lib/ash_ai/dev_tools/tools.ex` (actions for tool functionality)
- **Tool registration**: `lib/ash_ai/dev_tools.ex` (domain with tools block)
- **Test coverage**: `test/ash_ai/dev_tools/tools_test.ex` (comprehensive test suite)
- **Type definitions**: Already defined `UsageRules` type in existing codebase

### Dependencies and Prerequisites
- **Mix.Project.deps_paths()**: Used for dependency discovery
- **File system access**: Direct reading of `usage-rules.md` files
- **Ash framework**: Actions and domain patterns
- **MCP server**: Existing `AshAi.Mcp.Dev` infrastructure

### API Design
```elixir
# Two main tools exposed via MCP:

action :get_usage_rules, {:array, UsageRules} do
  argument :packages, {:array, :string}, description: "Package names to get usage rules for"
  # Returns: [%{package: "ash", rules: "...markdown content..."}]
end

action :list_packages_with_rules, {:array, :string} do
  # Returns: ["ash", "ash_postgres", "igniter", ...]
end
```

## Success Criteria

- AI assistants can discover which packages have usage rules via `list_packages_with_rules`
- AI assistants can retrieve specific package rules via `get_usage_rules`
- Tools integrate seamlessly with existing MCP development server
- Zero performance impact on normal development workflow (read-only operations)
- 100% test coverage maintained for all functionality
- Error handling works correctly for edge cases (missing packages, files, etc.)

## Notes/Considerations

### Edge Cases Handled
- Packages without usage-rules.md files (filtered out gracefully)
- Non-existent package names (returns empty results)
- File system access errors (handled by existing error patterns)
- Mix task documentation that returns `false` instead of strings

### Current Status Summary
**Implementation complete** ✅
- Both MCP tools (`get_usage_rules` and `list_packages_with_rules`) implemented and tested
- 17 comprehensive tests covering all scenarios and edge cases
- Clean, focused read-only API design
- Successfully integrated with existing ash_ai patterns
- Manual testing confirmed working in real project environment

**All planned steps completed successfully!**

### Future Improvements
- Consider caching for frequently accessed rules (if performance becomes an issue)
