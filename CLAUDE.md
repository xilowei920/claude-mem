# CLAUDE.md
## 语言
中文，短句

## Project Overview

**claude-mem** is a persistent memory compression system for Claude Code that captures tool usage observations, generates semantic summaries using the Claude Agent SDK, and injects relevant context into future sessions. It's distributed as a Claude Code plugin with a worker daemon, SQLite database, vector search (Chroma), and a React web UI.

**License**: AGPL-3.0 (open-source core) + PolyForm Noncommercial 1.0.0 (ragtime/ directory)

## 本地化改动和环境介绍
轻量级代理 运行在WSL环境脚本文件 /home/laserqc/litellm/proxy_bridge.py
相关资料索引 ./Claude-mem 外部代理（Relay）接入第三方模型实施方案.md

## Build & Development

### Common Commands

```bash
npm run build              # Compile hooks and plugin manifests
npm run build-and-sync     # Build, sync to marketplace, restart worker
npm test                   # Run all tests (Bun)
npm run test:sqlite        # SQLite-specific tests
npm run test:agents        # Agent SDK tests
npm run test:search        # Search/Chroma tests
npm run typecheck          # TypeScript type checking
npm run worker:logs        # Tail worker logs (current day)
npm run worker:restart     # Restart worker daemon
npm run changelog:generate # Auto-generate CHANGELOG (do not edit manually)
```

### Development Workflow

1. **Make changes** to `src/` or `plugin/`
2. **Run `npm run build-and-sync`** to compile, sync to marketplace, and restart the worker
3. **Run tests** relevant to your changes (`npm test` or targeted test suites)
4. **Verify worker health** with `npm run worker:logs` or check http://localhost:37777 (viewer UI)

### TypeScript Configuration

- **Target**: ES2022, ESNext modules
- **Strict mode**: Enabled
- **JSX**: React
- **Exclude**: `tests/`, `dist/`, `src/ui/viewer/` (separate tsconfig)

## Architecture

### System Layers

```
Claude Code (host)
  ↓ [5 lifecycle hooks]
CLI Layer (Bun)
  ↓ [bun-runner.js bridge, hook-command.ts orchestrator]
Worker Daemon (Express, port 37700 + (uid % 100))
  ↓ [SessionManager, SDKAgent, SearchManager, ChromaSync]
Storage Layer
  ↓ [SQLite, ChromaDB, MCP Server]
```

### Hook Lifecycle (5 events)

| Event | Handler | Purpose | Timeout |
|-------|---------|---------|---------|
| **Setup** | `version-check.js` | Version marker check; prompts repair on mismatch | 60s |
| **SessionStart** | `worker start` + `context` | Start worker, inject context | 60s |
| **UserPromptSubmit** | `session-init` | Register session, start SDK agent | 60s |
| **PostToolUse** | `observation` | Capture tool usage, enqueue for processing | 120s |
| **Stop** | `summarize` | Request session summary from SDK agent | 120s |

**Exit Code Strategy**:
- **0**: Success or graceful shutdown (never blocks Claude Code)
- **1**: Non-blocking error (shown to user, continues)
- **2**: Blocking error (fed to Claude for processing)

### Key Services

**Worker Daemon** (`src/services/worker-service.ts`):
- Express HTTP API on per-user port
- SessionManager: Session lifecycle and state
- SDKAgent: Claude Agent SDK integration for observation compression
- SearchManager: Hybrid search orchestration (keyword + semantic)
- ChromaSync: Vector embedding synchronization
- ProcessRegistry: Subprocess lifecycle management

**Database** (`src/services/sqlite/`):
- SQLite3 at `~/.claude-mem/claude-mem.db`
- Tables: `sdk_sessions`, `observations`, `session_summaries`, `user_prompts`, `pending_messages`, `observation_feedback`
- Migrations auto-run on startup
- WAL mode, foreign keys enabled, memory temp store

**Search** (`src/services/worker/SearchManager.ts`):
- 3-layer workflow: `search()` → `timeline()` → `get_observations()`
- Full-text search via SQLite FTS5
- Semantic search via Chroma vector database
- MCP tools for Claude Code integration

**Context Injection** (`src/services/context/`):
- ContextBuilder: Assembles context from observations
- TokenCalculator: Estimates token usage
- Progressive disclosure: Layered context with cost visibility
- Formatters: Agent vs. human-readable output

### Data Flow

```
User prompt
  ↓ session-init → /api/sessions/init + /api/context/semantic
Tool use
  ↓ observation → /api/sessions/observations
  ↓ PendingMessageStore.enqueue()
  ↓ SDKAgent.startSession()
  ↓ Claude Agent SDK → ResponseProcessor
  ├─ storeObservations() → SQLite
  ├─ chromaSync.sync() → ChromaDB
  └─ broadcastObservation() → SSE/UI
Stop
  ↓ summarize → /api/sessions/summarize
  ↓ session-complete → /api/sessions/complete + drain
```

## Key Patterns & Concepts

### Pending Queue (PendingMessageStore)

Observations are enqueued before SDK processing. Parser is binary: `{ valid: true, observations, summary }` or `{ valid: false }`. Unparseable responses leave the queue untouched; the session iterator continues. Queue is cleared only when parser returns a valid response.

### Generator Restart Loop

SDK agent crashes trigger exponential backoff retries (1s → 2s → 4s). Counter resets on natural completion. Pending messages survive restarts and are cleared by the parser on next valid response.

### Graceful Degradation

Transport errors (ECONNREFUSED, timeout, 5xx) exit 0 (never block Claude Code). Client bugs (4xx, TypeError) exit 2 (blocking, needs fix).

### Deduplication

SHA256(memory_session_id + title + narrative)[:16] → content_hash. If hash exists within 30s window, return existing ID (no insert).

### Session ID Duality

- **contentSessionId**: From Claude Code, invariant during session
- **memorySessionId**: From SDK Agent, changes on worker restart
- SessionStore handles conversion; critical for FK constraints

## File Structure

```
src/
  ├─ hooks/              # Hook lifecycle logic
  ├─ cli/                # CLI handlers (context, session-init, observation, summarize)
  ├─ npx-cli/            # NPX installation CLI
  ├─ services/
  │  ├─ worker-service.ts    # Main Express server
  │  ├─ worker/              # Worker components (SessionManager, SDKAgent, etc.)
  │  ├─ sqlite/              # Database layer
  │  ├─ context/             # Context injection & formatting
  │  ├─ server/              # HTTP middleware & error handling
  │  ├─ integrations/        # IDE integrations (Cursor, Gemini, Windsurf, OpenCode)
  │  └─ sync/                # ChromaDB synchronization
  ├─ servers/            # MCP server for search tools
  ├─ ui/viewer/          # React web UI (separate tsconfig)
  └─ utils/              # Shared utilities (logger, tag-stripping, etc.)

plugin/
  ├─ hooks/hooks.json    # Hook registration
  ├─ scripts/            # Bun runner, worker service manager
  ├─ skills/             # Plugin skills (mem-search, make-plan, do, etc.)
  ├─ modes/              # Workflow modes (code, code--zh, code--ja, etc.)
  └─ ui/viewer.html      # Built React UI

tests/
  ├─ sqlite/             # Database tests
  ├─ worker/             # Worker & agent tests
  ├─ context/            # Context injection tests
  ├─ infrastructure/     # Process management, health checks
  ├─ integration/        # E2E hook execution
  └─ [many more]         # 80+ test files covering all layers
```

## Configuration & Environment

### Settings File

`~/.claude-mem/settings.json` (auto-created with defaults):
- AI model selection (Claude, Gemini, OpenRouter)
- Worker port (default: 37700 + (uid % 100))
- Data directory (default: ~/.claude-mem)
- Log level
- Context injection settings
- Mode selection (code, code--zh, code--ja, etc.)

### Multi-Account Support

Set environment variables to isolate profiles:

```bash
export CLAUDE_MEM_DATA_DIR="$HOME/.claude-mem-work"
export CLAUDE_MEM_WORKER_PORT=37800
```

All paths and ports derive from these two variables.

### Modes

Modes control workflow behavior and language. Located in `plugin/modes/`. Pattern: `code--[lang]` (e.g., `code--zh` for Simplified Chinese, `code--ja` for Japanese).

## Testing Strategy

### Test Organization

- **Unit tests**: Individual services, utilities, formatters
- **Integration tests**: Hook execution, worker API endpoints, Chroma sync
- **Infrastructure tests**: Process management, health checks, plugin distribution
- **SQLite tests**: Database migrations, schema, transactions

### Running Tests

```bash
npm test                          # All tests
npm run test:sqlite               # Database layer
npm run test:agents               # SDK agent integration
npm run test:search               # Search & Chroma
npm run test:context              # Context injection
npm run test:infra                # Infrastructure
npm run test:server               # HTTP server
```

### Test Patterns

- Use Bun's native test runner
- Mock external services (Claude API, Chroma)
- Test both happy path and error cases
- Verify exit codes and error handling
- Check database state after operations

## Important Implementation Details

### Exit Code Philosophy

Worker/hook errors exit 0 to prevent Windows Terminal tab accumulation. The wrapper/plugin layer handles restart logic. ERROR-level logging is maintained for diagnostics.

### Privacy Tags

`<private>content</private>` prevents storage. Tag stripping happens at hook layer (edge processing) before data reaches worker/database. See `src/utils/tag-stripping.ts`.

### Observation Compression

Claude Agent SDK compresses observations into semantic summaries. ResponseProcessor extracts structured data (facts, decisions, changes) and stores in SQLite. Chroma generates vector embeddings for semantic search.

### Worker Port Calculation

Default: `37700 + (uid % 100)`. Two different OS users on same box get different ports automatically. Override with `CLAUDE_MEM_WORKER_PORT` env var.

### Changelog

**Never edit CHANGELOG.md manually.** Run `npm run changelog:generate` to auto-generate from git history.

## Daily Maintenance

Run a daily version check and upgrade dependencies:

```bash
npm outdated                                    # Check all packages
npx npm-check-updates -u && npm install         # Upgrade to latest
npm audit fix                                   # Resolve advisories
npm run build-and-sync                          # Verify build
npm test                                        # Verify tests pass
```

Commit updated `package.json` and `package-lock.json` files. Bump majors too — staying on latest is the goal.

## Common Development Tasks

### Adding a New Hook

1. Create handler in `src/cli/handlers/`
2. Register in `plugin/hooks/hooks.json`
3. Add tests in `tests/`
4. Run `npm run build-and-sync`

### Adding a New API Endpoint

1. Create route in `src/services/worker/http/routes/`
2. Register in `src/services/server/Server.ts`
3. Add error handling in `src/services/server/ErrorHandler.ts`
4. Test with `npm run test:server`

### Adding a Database Migration

1. Create migration file in `src/services/sqlite/migrations/`
2. Export from `src/services/sqlite/migrations.ts`
3. MigrationRunner auto-runs on startup
4. Test with `npm run test:sqlite`

### Debugging Worker Issues

```bash
npm run worker:logs                             # View current logs
npm run worker:tail                             # Follow logs in real-time
npm run worker:status                           # Check worker status
npm run worker:restart                          # Restart worker
```

Worker logs are at `~/.claude-mem/logs/worker-YYYY-MM-DD.log`.

## References

- **Public Docs**: https://docs.claude-mem.ai
- **GitHub**: https://github.com/thedotmack/claude-mem
- **Issues**: https://github.com/thedotmack/claude-mem/issues
- **Discord**: https://discord.com/invite/J4wttp9vDu
- **Author**: Alex Newman (@thedotmack)

## Key Dependencies

- **@anthropic-ai/claude-agent-sdk**: Observation compression & semantic summarization
- **@modelcontextprotocol/sdk**: MCP server for search tools
- **express**: HTTP server
- **bun:sqlite**: Database (bundled with Bun)
- **tree-sitter-***: Code parsing for smart file reads
- **react**: Web UI viewer
- **zod**: Schema validation
- **yaml**: Configuration parsing
