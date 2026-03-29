# VisualHUD - Development Guidelines

## TDD ENFORCEMENT (READ BEFORE CODING!)

**STOP! Before writing ANY implementation code:**

1. **Write failing tests FIRST** (TDD RED phase)
2. **Use integration tests** primarily - see TESTING.md
3. **Use REAL fixtures** for mock data - never guess shapes

## Commands

- Run demo: `./demo.sh`
- Run all tests: `bash tests/run_all.sh` (once test suite exists)
- Run specific test: `bash tests/<test_name>.sh`
- Shellcheck lint: `shellcheck *.sh`

## Architecture

- **Hook scripts**: Shell scripts (bash) driven by Claude Code hooks
- **Background image control**: Python 3 via iTerm2 Python API (`set_bg.py`)
- **Theme engine**: Reads `theme.json`, drives iTerm2 escape sequences
- **State**: File-based per-session state via `ITERM_SESSION_ID`
- **Sprites**: Static PNGs (512x512) in theme directories

## Code Style

- Shell scripts: bash, `#!/bin/bash` shebang
- Use `shellcheck`-clean bash
- Python: Python 3, minimal dependencies (just `iterm2` package)
- Quote all variable expansions in shell
- Use `printf` over `echo` for escape sequences

## Git Commits

- Follow conventional commits: `type(scope): description`
- NEVER commit with failing tests

## Plan Docs

- Before coding a feature: READ its `*_PLAN.md` file
- After completing work: UPDATE the plan doc

## Testing Notes

- Test timeout: up to 5 minutes for full suite
- Shell integration tests should use temp dirs for isolation
- Mock iTerm2 API calls (can't run in test env)
- Test real shell behavior where possible
