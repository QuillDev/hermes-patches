# Hermes Agent - Development Guide

Instructions for AI coding assistants and developers working on the Hermes Agent codebase.

**Never give up on the right solution.**

Hermes runs the same agent core across the CLI, messaging gateway, TUI, desktop app, cron, and API surfaces. It learns through memory and skills, delegates to subagents, schedules jobs, and drives terminal/browser tools. Extend Hermes primarily at the edges: CLI commands, skills, plugins, MCP servers, service-gated tools, and provider adapters. Keep the core agent and model tool schema narrow.

## Non-Negotiable Design Constraints

- **Prompt caching is sacred.** Do not mutate prior context, swap toolsets, reload memories, or rebuild the system prompt mid-conversation. The only normal exception is context compression. Slash commands that affect prompt/tool state must default to deferred effect and offer an explicit `--now` path only when immediate invalidation is intentional.
- **Strict message alternation.** Preserve provider-compatible role ordering. Do not inject synthetic user/assistant messages that create duplicate adjacent roles. Cron and background deliveries must be framed outside the target session instead of mirrored into live conversation history.
- **Core tool footprint is expensive.** Every core tool schema is sent on every model call. Prefer extending existing code, then CLI+skill, service-gated tool, plugin, MCP server, and only then a new core tool.
- **Profile isolation matters.** Use profile-aware paths (`get_hermes_home()` / `display_hermes_home()`) for Hermes state. Do not couple profiles except through explicit profile commands such as clone/import/export.
- **Config belongs in config.yaml.** `.env` is for secrets only: API keys, tokens, passwords. Non-secret behavior knobs belong in `config.yaml`; bridge to env vars internally only when needed for compatibility.
- **Tests validate behavior, not snapshots.** Prefer invariants and real-path integration tests over mocks and fragile enumeration checks.

## Contribution Rules

### We Want

- Real bug fixes with a demonstrated reproduction or traced failure path.
- Fixes for the whole bug class, including sibling call paths when applicable.
- Product expansion at the edges: platforms, providers, plugins, TUI/desktop/dashboard features, setup/config UX.
- Large declared refactors that split god files into focused modules when the request is the extraction.
- Contributor credit preservation: salvage external work and keep authorship when possible.
- E2E validation for config propagation, resolution chains, providers, security boundaries, and file/network I/O.

### We Do Not Want

- Speculative hooks, callbacks, managers, or extension points with no concrete consumer.
- New `HERMES_*` env vars for non-secret settings.
- Core tools when terminal/file/CLI+skill/plugin/MCP already solve the problem.
- Instructional tools or prompts with lazy-reading pagination that lets agents skip required context.
- Security “fixes” that destroy the feature being protected; preserve intent and constrain safely.
- Outbound telemetry, attribution tags, or third-party identifiers without opt-in config/setup gating.
- Plugins that patch core files. Widen generic plugin surfaces instead of special-casing a plugin in core.

### Verify the Premise Before Coding

Before accepting a rationale or changing behavior:

1. Reproduce or trace the failure on current code.
2. Read the original intent when behavior looks like an omission: `git log -p -S '<symbol>'`.
3. Confirm the proposed branch actually executes at runtime.
4. Keep the change scoped to the agreed problem; park unrelated improvements for follow-up.

Common traps: profile isolation is deliberate, omitted `__init__.py` files may prevent test/package shadowing, rate-limit cooldowns may be based on proven empty buckets, and stale squash merges can silently revert unrelated fixes.

## Footprint Ladder for New Capability

Choose the least permanent surface that works:

1. Extend existing code.
2. CLI command plus skill.
3. Service-gated tool with `check_fn` and `requires_env` / config gating.
4. Plugin (`~/.hermes/plugins/`, repo plugin, or pip entry point).
5. MCP server in the catalog.
6. New core tool only when broadly fundamental and unreachable by the above.

If several PRs add the same category of integration, design one ABC/orchestrator and migrate the integrations into plugins/providers instead of merging one-off code paths.

## Repository Map

Use the filesystem as source of truth; this map highlights load-bearing entry points:

```
run_agent.py                    AIAgent and core conversation loop
model_tools.py                  tool discovery, schema resolution, dispatch
toolsets.py                     TOOLSETS and _HERMES_CORE_TOOLS
cli.py                          classic interactive CLI orchestration
hermes_state.py                 SQLite session store and FTS search
hermes_constants.py             get_hermes_home(), display_hermes_home()
hermes_logging.py               profile-aware logging setup
agent/                          prompt builder, compression, memory, routing, display
hermes_cli/                     CLI subcommands, config, setup, plugins, skin engine
tools/                          tool implementations registered via tools/registry.py
tools/environments/             terminal backends
gateway/                        messaging gateway runtime and platform adapters
plugins/                        general plugins, providers, kanban, image/context engines
skills/                         bundled skills loaded by default
optional-skills/                heavier/niche official skills installed explicitly
ui-tui/                         Ink TUI frontend
tui_gateway/                    Python JSON-RPC backend for TUI/desktop
apps/desktop/                   Electron desktop chat app
cron/                           scheduler and job store
tests/                          pytest suite
website/                        Docusaurus docs
```

Dependency chain: `tools/registry.py` -> `tools/*.py` -> `model_tools.py` -> `run_agent.py` / `cli.py` / `batch_runner.py` / environments.

## Development Environment and Verification

- Prefer the repo venv: `source .venv/bin/activate` or `source venv/bin/activate`.
- Use `uv` for Python dependency workflows; this checkout may not have `pip` because of PEP 668.
- **Always run tests through `scripts/run_tests.sh`, not raw pytest.** The wrapper enforces CI parity: credential env vars unset, temp `HERMES_HOME`, UTC, `C.UTF-8`, xdist, and subprocess-per-test isolation.

Examples:

```bash
scripts/run_tests.sh                                  # full suite
scripts/run_tests.sh tests/gateway/                   # area
scripts/run_tests.sh tests/foo.py::test_name -q        # single test
scripts/run_tests.sh --no-isolate tests/foo.py -q      # debug only
```

Subprocess isolation lives in `tests/_isolate_plugin.py`; each test runs in a spawned child process with a timeout. Tests must never read or write the user's real `~/.hermes`.

## Testing Style

Do not write change-detector tests that fail on routine catalog/config growth:

```python
# Bad: snapshots mutable data.
assert DEFAULT_CONFIG["_config_version"] == 21
assert len(_PROVIDER_MODELS["huggingface"]) == 8
assert "specific-new-model" in models
```

Prefer behavior and invariants:

```python
assert raw["_config_version"] == DEFAULT_CONFIG["_config_version"]
assert "gemini" in _PROVIDER_MODELS
assert len(_PROVIDER_MODELS["gemini"]) >= 1
assert not (set(moonshot_models) & coding_plan_only_models)
for model in provider_models:
    assert model.lower() in DEFAULT_CONTEXT_LENGTHS_LOWER
```

Use real imports and temp `HERMES_HOME` for integration behavior. Mock only external services or genuinely slow boundaries.

## Python/Core Conventions

- Trace definitions and usages before editing. Do not invent APIs, imports, config keys, or files.
- Keep changes minimal and local; no drive-by refactors.
- Use `get_hermes_home()` for state paths and `display_hermes_home()` for user-facing paths.
- Profile operations that need to see all profiles are HOME-anchored by design; `_get_profiles_root()` uses `Path.home() / ".hermes" / "profiles"`.
- Gateway platform adapters that connect with a unique credential should acquire a scoped token lock in `connect()`/`start()` and release it in `disconnect()`/`stop()`; see Telegram for the canonical pattern.
- New persistent config keys go in `DEFAULT_CONFIG` (`hermes_cli/config.py`). Bump `_config_version` only when migrating/transforming existing user config, not when merely adding a default key.
- Add optional secret env vars to `OPTIONAL_ENV_VARS`; do not put non-secret settings there.
- Know the three config loaders:
  - `load_cli_config()` in `cli.py` for classic CLI runtime.
  - `load_config()` in `hermes_cli/config.py` for setup/tools/subcommands.
  - Gateway direct YAML load in `gateway/run.py` / `gateway/config.py`.
- CLI CWD is `os.getcwd()`. Messaging agents use `terminal.cwd` from config bridged to `TERMINAL_CWD` for child tools. `MESSAGING_CWD` is obsolete.

## TypeScript/UI Conventions

Applies to desktop, TUI, website, and future TS packages.

- Prefer small nanostores over prop drilling or broad component state.
- Feature atoms live near the feature; shared atoms live in `src/store`.
- Components that render atom state use `useStore`; non-rendering actions read `$atom.get()`.
- Keep route roots thin. No monolithic hooks; colocate narrow action modules.
- Prefer interfaces for public/shared object props. Extend React primitive props with `React.ComponentProps<...>`.
- Prefer table-driven maps over condition ladders for ids/routes/views.
- Use terse void forms for intentional async/side-effect callbacks: `onClick={() => void save()}`.

## Architecture Notes

### Agent Loop

`AIAgent` lives in `run_agent.py`. The main loop is synchronous: build messages and tool schemas, call the provider, dispatch tool calls through `handle_function_call()`, append tool results, and continue until a final assistant response or budget/interrupt condition. Messages follow OpenAI format; reasoning content is stored on assistant messages.

### Slash Commands

`hermes_cli/commands.py` is the registry of record. Add commands there first; CLI, gateway help, Telegram menu, Slack routing, autocomplete, and command help derive from it. `cli.py` dispatches via `HermesCLI.process_command()`. Gateway handlers live in `gateway/run.py` when the command is platform-available. Adding an alias should usually only change the registry entry.

Skill slash commands are scanned by `agent/skill_commands.py` and injected as user messages rather than system-prompt mutations to preserve prompt caching.

### TUI and Dashboard

The TUI is Ink over stdio JSON-RPC to `tui_gateway`. TypeScript owns the screen; Python owns sessions, tools, model calls, and slash-command fallback. Local TUI commands are handled client-side; unknown commands go through `slash.exec` and `command.dispatch`.

The dashboard `/chat` embeds the real `hermes --tui` through a PTY websocket (`hermes_cli/pty_bridge.py`, `hermes_cli/web_server.py`). Do not rebuild the transcript/composer/chat surface in React. Supporting sidebars and inspectors are fine if they complement the embedded TUI and fail non-destructively.

### Desktop App

`apps/desktop/` is a separate Electron + React + nanostore chat surface backed by `tui_gateway` JSON-RPC. It does not embed `hermes --tui`.

Desktop slash-command curation lives in `apps/desktop/src/lib/desktop-slash-commands.ts`. Curation should hide terminal/messaging/settings noise, not user extensions. Keep skill commands and `quick_commands` flowing through discovery and execution via `isDesktopSlashExtensionCommand()`, `isDesktopSlashSuggestion()`, and catalog filtering. Test with `apps/desktop/src/lib/desktop-slash-commands.test.ts`.

### Plugins

General plugins are discovered by `hermes_cli/plugins.py` from repo plugins, `$HERMES_HOME/plugins`, `.hermes/plugins`, and entry points. They can register hooks, tools, and CLI subcommands. Discovery normally happens via `model_tools.py`; code paths reading plugin state without importing `model_tools.py` must call `discover_plugins()` explicitly.

Memory providers implement `agent/memory_provider.py` and are orchestrated by `agent/memory_manager.py`. No new in-tree memory providers: the built-in `plugins/memory/` set is closed, so new memory backends should be standalone plugins rather than new directories in this repo.

Model providers live under `plugins/model-providers/<name>/` and register a `ProviderProfile`. Discovery is lazy and separate from the general plugin manager. Scan order is bundled, user `$HERMES_HOME`, then legacy `providers/<name>.py`; user providers override bundled names.

Context-engine, image-gen, dashboard, and similar plugin directories should follow the same ABC/orchestrator pattern. Companion example plugins belong in the external `hermes-example-plugins` repo, not this tree.

### Skills

`skills/` are bundled and available by default. `optional-skills/` are heavier/niche official skills installed explicitly via the skills hub. Review PRs for the correct target.

Modern skill standards:

- Frontmatter: `name`, short `description` (<=60 chars, one sentence, ends with a period), `version`, `author`, `license`, optional `platforms`, and `metadata.hermes.*`.
- Credit the human contributor first; Hermes may be a collaborator, not the primary author.
- Use modern sections: title, short intro, `When to Use`, `Prerequisites`, `How to Run`, `Quick Reference`, `Procedure`, `Pitfalls`, `Verification`.
- Put scripts in `scripts/`, references in `references/`, templates in `templates/`.
- Skill prose should reference native Hermes tools (`read_file`, `search_files`, `patch`, `terminal`, `web_extract`, etc.) instead of shell equivalents (`cat`, `grep`, `sed`, `find`) unless the shell utility is truly part of a script.
- Audit `platforms:` against actual imports and commands. Prefer cross-platform Python where possible.
- Tests go under `tests/skills/test_<skill>_skill.py` and use stdlib/pytest/mocking only.

## Adding a Core Tool

Only do this after applying the footprint ladder. Built-in tools require two pieces:

1. A `tools/<name>.py` module that imports `tools.registry.registry`, defines a JSON-string-returning handler, and calls `registry.register(...)` with schema, handler, toolset, optional `check_fn`, and `requires_env`.
2. Toolset exposure in `toolsets.py` (`_HERMES_CORE_TOOLS` or a specific `TOOLSETS` entry). Auto-discovery imports and registers tools, but a tool is invisible until a toolset exposes it.

Use `display_hermes_home()` in schema descriptions and `get_hermes_home()` for state. Agent-level tools such as todo/memory may be intercepted in `run_agent.py`; follow existing patterns.

Do not hardcode references to tools from other toolsets in schema descriptions. If dynamic cross-tool guidance is needed, add it in `get_tool_definitions()` post-processing so unavailable tools are not hallucinated.

## Dependencies

All dependencies must have upper bounds.

| Source | Rule |
| --- | --- |
| PyPI post-1.0 | `>=floor,<next_major` |
| PyPI pre-1.0 | `>=floor,<0.(current_minor+2)` |
| Git URL | pin a full commit SHA |
| GitHub Actions | pin SHA and comment the human version |
| CI-only pip | exact `==` |

After changing Python dependencies, run `uv lock`. Never add a bare unbounded `>=` dependency.

## Durable and Background Systems

### Delegation

`tools/delegate_tool.py` spawns isolated subagents. Single task uses `goal`; batch uses `tasks=[...]` and runs concurrently up to `delegation.max_concurrent_children`. Parent agents get handles immediately, and each child summary re-enters the parent conversation when complete; subagents themselves run nested delegations synchronously. Leaf agents cannot delegate or call clarify/memory/send_message/execute_code. Orchestrators can re-delegate only when enabled and within `delegation.max_spawn_depth`. Delegation is not durable; use cron or tracked background terminals for work that must outlive the current session.

### Cron

Cron jobs live in `cron/jobs.py` and `cron/scheduler.py`. Users interact via `hermes cron`, `/cron`, or the `cronjob` tool. Schedules support durations, “every” phrases, cron expressions, and ISO one-shots. Jobs can carry skills, model/provider overrides, scripts, `no_agent`, `context_from`, workdir, and delivery targets. Invariants: hard run timeout, tick file lock, bounded catchup/grace windows, skip-memory defaults, and no direct mirroring into target gateway sessions.

### Curator

Curator maintains agent-created skills only. It tracks usage in a sidecar, marks stale skills, archives rather than deletes, and skips pinned skills for auto-transitions and LLM review. CLI: `hermes curator`; slash: `/curator`. Bundled and hub-installed skills are off-limits.

### Kanban

Kanban is a durable SQLite work queue for multi-profile workers. Users use `hermes kanban`; dispatcher-spawned workers get focused `kanban_*` tools gated by task env vars. The gateway normally runs the dispatcher. Board is the hard isolation boundary (`HERMES_KANBAN_BOARD`); tenant is a soft namespace inside a board. Tasks auto-block after repeated spawn failures.

### Background Process Notifications

Gateway notification verbosity for `terminal(background=true, notify_on_complete=true)` is controlled by `display.background_process_notifications` (`all`, `result`, `error`, `off`). Prefer `notify_on_complete=true` for bounded long-running commands.

## Known Pitfalls

- Do not hardcode `~/.hermes` in code or tests. Use profile-aware helpers; tests should set `HERMES_HOME` and mock `Path.home()` when profile roots are involved.
- Do not introduce new `simple_term_menu` usage; use `hermes_cli/curses_ui.py` for interactive menus.
- Do not use ANSI erase-to-EOL (`\033[K`) in spinner/display code under prompt_toolkit; use explicit space padding.
- `_last_resolved_tool_names` in `model_tools.py` is process-global and temporarily saved/restored around subagent runs.
- Gateway running-message controls must bypass both guards: the base adapter active-session queue and the gateway runner command intercept. Approval/control commands should dispatch inline, not through `_process_message_background()`.
- Before squash-merging, ensure the branch is up to date with main; stale squash merges can overwrite unrelated recent fixes. Inspect `git diff HEAD~1..HEAD` after merge.
- Do not wire unused/dead modules into live paths without E2E validation against real imports and a temp `HERMES_HOME`.

## Area Checklists

### Adding Configuration

1. Add defaults to `DEFAULT_CONFIG` if user-facing.
2. Add secret metadata to `OPTIONAL_ENV_VARS` only for credentials.
3. Update all relevant loaders/consumers: CLI, setup/subcommands, gateway direct YAML.
4. Use `display_hermes_home()` in messages and docs snippets when showing profile-aware paths.
5. Test migration/default behavior with temp `HERMES_HOME`.

### Adding a Slash Command

1. Add `CommandDef` in `hermes_cli/commands.py`.
2. Add CLI handler in `HermesCLI.process_command()` if applicable.
3. Add gateway handler in `gateway/run.py` if gateway-available.
4. For persistent settings, write through config helpers.
5. Preserve prompt caching; defer prompt/tool/memory mutations unless `--now` is explicit.

### Adding a Platform Adapter

1. Follow existing `gateway/platforms/` adapters and `ADDING_A_PLATFORM.md`.
2. Use scoped locks for unique credentials.
3. Add config/setup docs without new non-secret env vars.
4. Test command routing and active-session control bypasses.

### Adding a Provider

1. Prefer `plugins/model-providers/<name>/` with `ProviderProfile` registration.
2. Put credentials in `.env` metadata and behavior in config.
3. Verify model resolution, auth, context lengths, and real request path where possible.
4. Avoid snapshot tests of specific mutable model catalog contents.

### Modifying TUI/Desktop/Dashboard

1. Respect surface boundaries: Ink owns TUI, dashboard embeds TUI, desktop is separate React/Electron.
2. Put shared state in feature/local nanostores; keep route roots thin.
3. Verify slash-command discovery/execution paths and extension command preservation.
4. Run relevant `npm` checks from the workspace root or package directory as appropriate.

## Documentation Pointers

Prefer live docs over duplicating large reference tables in this file:

- User docs: `website/docs/user-guide/`
- Developer docs: `website/docs/developer-guide/`
- Tools/toolsets: `toolsets.py`, `tools/registry.py`, and the tools reference docs
- Config: `hermes_cli/config.py` and configuration docs
- Slash commands: `hermes_cli/commands.py` and slash-command reference
- Platform guide: `gateway/platforms/ADDING_A_PLATFORM.md`
- Provider guide: `website/docs/developer-guide/model-provider-plugin.md`

When this guide conflicts with code, inspect the code and update the guide if it is stale.
