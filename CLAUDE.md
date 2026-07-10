# VisualHUD - Development Guidelines

## Project Overview

VisualHUD is a visual status engine for Claude Code, Codex, and iTerm2 that transforms terminal appearance in real-time as an agent works. Pokemon-themed 11-stage progression with per-session isolation across multiple terminals.

**Stack:** Bash + Python 3 (iTerm2 Python API)
**State:** File-based per-session via `ITERM_SESSION_ID` in `/private/tmp/`
**Security:** Personal CLI tool — basic sanity checks only

## TDD ENFORCEMENT (READ BEFORE CODING!)

**STOP! Before writing ANY implementation code:**

1. **Write failing tests FIRST** (TDD RED phase)
2. **Use integration tests** primarily — see TESTING.md
3. **Use REAL fixtures** for mock data — never guess shapes

## Commands

| Action | Command |
|--------|---------|
| Run demo | `./demo.sh` |
| Run specific test | `bash tests/<test_name>.sh` |
| Lint shell scripts | `shellcheck *.sh tests/*.sh .codex/hooks/*.sh .claude/hooks/*.sh` |
| Type-check | N/A (bash) |
| Build | N/A (interpreted scripts) |
| Deploy | N/A |

**Test duration:** Up to 5 minutes for full suite

## Architecture

- **Hook scripts**: Shell scripts (bash) driven by Claude Code and Codex hooks
- **Background image control**: Python 3 via iTerm2 Python API (`set_bg.py`)
- **Theme engine**: Reads `theme.json`, drives iTerm2 escape sequences (planned)
- **State**: File-based per-session state via `ITERM_SESSION_ID`
- **Sprites**: Static PNGs (512x512) in theme directories
- **Production hook**: `~/.claude/hooks/visualhud-claude.sh` (global default install via `visualhud install claude --global`; a project's own `visualhud install claude --target <repo>` install always takes precedence)
- **Codex adapter**: `.codex/hooks/visualhud-codex.sh`

## Code Style

- Shell scripts: bash, `#!/bin/bash` shebang
- Use `shellcheck`-clean bash
- Python: Python 3, minimal dependencies (just `iterm2` package)
- Quote all variable expansions in shell
- Use `printf` over `echo` for escape sequences

## Git Commits

- Follow conventional commits: `type(scope): description`
- NEVER commit with failing tests
- NEVER add AI attribution footers or Co-Authored-By lines

## Plan Docs

- Before coding a feature: READ its `*_PLAN.md` file
- After completing work: UPDATE the plan doc

## Testing Notes

- Test timeout: up to 5 minutes for full suite
- Shell integration tests should use temp dirs for isolation
- Mock iTerm2 API calls (can't run in test env)
- Test real shell behavior where possible
