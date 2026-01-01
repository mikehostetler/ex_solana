# Jido CodeMapper Demo

A **multi-agent** demonstration that maps and analyzes a codebase using hierarchical agents with maximum BEAM scheduler utilization.

## Overview

```
RootCoordinator (1)
├── FolderAgent (N folders, scheduler-aware concurrency)
│   └── FileAgent (batch spawning, ~3x schedulers)
└── Aggregates results → summary report

Features:
- Maximum BEAM scheduler utilization by default
- Scheduler-aware concurrency (auto-tunes to your CPU)
- DETS-based caching to avoid re-parsing unchanged files
- Gitignore-aware file discovery
- AST extraction (modules, functions, imports, aliases, uses)
- Auto-clamping for large codebases (1000+ files)
- Scheduler utilization metrics
```

## Usage

```bash
# Map the jido project (default - MAXIMUM PERFORMANCE)
mix run examples/code_mapper/runner.exs

# Map a specific project
mix run examples/code_mapper/runner.exs ../jido_action

# Map the full workspace (auto-clamps concurrency for large repos)
mix run examples/code_mapper/runner.exs /path/to/jido_workspace

# Clear cache and re-analyze everything
CLEAR_CACHE=1 mix run examples/code_mapper/runner.exs

# Demo mode with spawn delays for dramatic effect
CODEMAPPER_DEMO=1 mix run examples/code_mapper/runner.exs

# Safe mode for very large codebases (sequential processing)
SAFE_MODE=1 mix run examples/code_mapper/runner.exs

# Override concurrency settings
MAX_FOLDERS=8 MAX_FILES=20 mix run examples/code_mapper/runner.exs

# Simple single-process version (no agents, no caching)
mix run examples/code_mapper/simple_runner.exs
```

## Performance Modes

| Mode | Description | When to Use |
|------|-------------|-------------|
| **Default** | Maximum performance, scheduler-aware | Normal use |
| **Demo** | Spawn delays for visual effect | Presentations |
| **Safe** | Sequential processing | Very large repos (5000+ files) |

## Configuration

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `CLEAR_CACHE` | unset | Clear DETS cache before running |
| `MAX_FOLDERS` | ~schedulers | Override max concurrent folder agents |
| `MAX_FILES` | ~3x schedulers/folders | Override max files per batch |
| `CODEMAPPER_DEMO` | unset | Enable spawn delays (25ms) for demo |
| `SEQUENTIAL` | unset | Process folders one at a time |
| `SAFE_MODE` | unset | Alias for SEQUENTIAL with conservative settings |

### Auto-Tuning

By default, concurrency is tuned based on BEAM schedulers:
- **Max folders**: ~min(schedulers, 12)
- **Max files/batch**: ~3x schedulers / folders
- **Target**: ~3x schedulers worth of concurrent file agents

### Large Codebase Handling

The system auto-detects and handles large codebases:

| Files | Behavior |
|-------|----------|
| < 1000 | Full scheduler utilization |
| 1000-5000 | Moderate clamping (8 folders, 10 files/batch) |
| > 5000 | Conservative clamping (4 folders, 8 files/batch) |
| Any + SAFE_MODE | Sequential (1 folder, 5 files/batch) |

## Architecture

### Agents

1. **RootCoordinator** - Discovers files, spawns FolderAgents, aggregates final report
2. **FolderAgent** - Manages files in a directory, spawns FileAgents, aggregates folder summary  
3. **FileAgent** - Parses file AST, checks cache, emits results to parent

### Strategy

All agents use `CodeMapper.Strategy.MapperStrategy` which:
- Defines `signal_routes/1` to map signals to command handlers
- Implements `cmd/3` to process instructions
- Handles scheduler-aware spawning with configurable batch sizes
- Integrates with DETS cache for file results
- Auto-clamps concurrency for large codebases

### Signal Flow

```
root.start → RootCoordinator
  ├─ SpawnAgent(FolderAgent) × batch
  │    ├─ jido.agent.child.started → folder.process
  │    ├─ SpawnAgent(FileAgent) × batch
  │    │    ├─ jido.agent.child.started → file.process
  │    │    │    └─ Check cache → parse if miss → cache result
  │    │    └─ file.done → FolderAgent
  │    └─ folder.done → RootCoordinator
  │         └─ Spawn next folder batch
  └─ Complete → Generate report with stats
```

### Caching

The cache (`CodeMapper.Cache`) uses DETS to persist parsed file results:

- **Key**: File path + mtime (modification time)
- **Storage**: `.code_mapper_cache` file in target directory
- **Invalidation**: Automatic when file is modified

Cache benefits:
- First run: All files parsed (○ = cache miss)
- Subsequent runs: Only modified files re-parsed (· = cache hit)
- LLM calls can be cached to avoid re-summarizing

### Signals

| Signal | Handler | Purpose |
|--------|---------|---------|
| `root.start` | `:root_start` | Begin codebase mapping |
| `root.spawn_batch` | `:spawn_folder_batch` | Spawn next batch of folders |
| `folder.process` | `:folder_process` | Process a directory |
| `folder.spawn_batch` | `:spawn_file_batch` | Spawn next batch of files |
| `file.process` | `:file_process` | Parse a file's AST (check cache first) |
| `file.done` | `:file_done` | File analysis complete |
| `folder.done` | `:folder_done` | Folder analysis complete |
| `jido.agent.child.started` | `:child_started` | Child agent ready |

## Files

```
examples/code_mapper/
├── README.md
├── runner.exs              # Multi-agent runner (max performance)
├── simple_runner.exs       # Single-process version (no agents)
├── cache.ex                # DETS-based result cache
├── strategy/
│   └── mapper_strategy.ex  # Custom strategy with scheduler awareness
└── agents/
    ├── root_coordinator.ex # Root agent
    ├── folder_agent.ex     # Folder agent
    └── file_agent.ex       # File agent
```

## Output Legend

During processing:
- `○` = Cache miss (file parsed)
- `·` = Cache hit (result from cache)
- `✓` = Folder complete

## Example Output

```
╔═══════════════════════════════════════════════════════════════════╗
║            J I D O   C O D E M A P P E R                         ║
║         Multi-Agent Codebase Analysis System                      ║
╚═══════════════════════════════════════════════════════════════════╝

   🧠 BEAM: 10/10 schedulers online (10 logical cores)
   🎯 Target: /path/to/jido_workspace
   🚀 Mode: MAXIMUM PERFORMANCE
   ⚙️  Config: 10 concurrent folders, 3 files/batch

┌─────────────────────────────────────────────────────────────────┐
│  🔍 DISCOVERING FILES                                           │
└─────────────────────────────────────────────────────────────────┘

   📂 Root: /path/to/jido_workspace
   📄 Files: 1196
   📁 Folders: 349
   ⚡ Medium-large codebase (1196 files), moderate concurrency
   ⚙️  Max concurrent: 8 folders, 10 files/batch

┌─────────────────────────────────────────────────────────────────┐
│  🚀 SPAWNING AGENTS                                             │
└─────────────────────────────────────────────────────────────────┘

   [1/349] 📁 projects/jido/lib/jido
      └─ Processing 8 files
   ········
   ✓ projects/jido/lib/jido (8 files)
   ...

╔═══════════════════════════════════════════════════════════════════╗
║  ✅ MAPPING COMPLETE                                              ║
╠═══════════════════════════════════════════════════════════════════╣
║   📄 Files:     1196                                              ║
║   📁 Folders:   349                                               ║
║   📦 Modules:   1547                                              ║
║   ⏱️  Time:      4523ms                                            ║
║   💾 Cache:     1196 hits / 0 misses                              ║
╠═══════════════════════════════════════════════════════════════════╣
║  🤖 AGENTS SPAWNED                                                ║
╠═══════════════════════════════════════════════════════════════════╣
║   🎯 Root:      1                                                 ║
║   📁 Folder:    349                                               ║
║   📄 File:      1196                                              ║
║   ─────────────────────────────────────────────────────────────   ║
║   🤖 TOTAL:     1546 agents                                       ║
╚═══════════════════════════════════════════════════════════════════╝

┌─────────────────────────────────────────────────────────────────┐
│  🧮 SCHEDULER UTILIZATION                                       │
└─────────────────────────────────────────────────────────────────┘
   Scheduler  1: ████████████████░░░░ 78.3%
   Scheduler  2: ███████████████░░░░░ 74.1%
   Scheduler  3: ████████████████░░░░ 81.2%
   ...
   ─────────────────────────────────────────────────────────────
   Average:      76.4% busy
```

## Next Steps

- [ ] Add LLM summarization via `ReqLLMStream` (cached per file)
- [ ] Add embedding generation for semantic search
- [ ] Build query agent for codebase Q&A
- [ ] Add live terminal visualization with progress bars
- [ ] Export to JSON/Markdown documentation
