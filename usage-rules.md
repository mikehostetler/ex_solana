# Jido Sandbox Usage Rules

## For LLM Tool Builders

### Allowed Operations

- Read/write files to the virtual filesystem
- List directory contents
- Create directories
- Execute sandboxed Lua scripts
- Create/restore snapshots

### Forbidden Operations

- Real filesystem access (blocked by design)
- Network requests (not available)
- Shell command execution (not available)
- Loading external Lua modules (blocked)
- Path traversal attacks (paths validated)

### Path Rules

- All paths MUST be absolute (start with `/`)
- Path traversal (`..`) is blocked
- Paths are case-sensitive
- Multiple slashes are collapsed

### Lua Sandbox Rules

The Lua environment has these globals removed:
- `os` - No operating system access
- `io` - No real I/O
- `package` - No module loading
- `require` - No external modules
- `debug` - No debug access
- `loadfile` - No file loading
- `dofile` - No file execution

Available in Lua:
- `vfs.read(path)` - Read file contents
- `vfs.write(path, content)` - Write file
- `vfs.list(path)` - List directory
- `vfs.mkdir(path)` - Create directory
- `vfs.delete(path)` - Delete file
