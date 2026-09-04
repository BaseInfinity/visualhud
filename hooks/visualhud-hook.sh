#!/usr/bin/env bash
# VisualHUD Claude Code plugin hook.
# Bridges Claude Code hook events into the VisualHUD engine.
# This hook must never block or fail Claude Code's normal flow.

set -euo pipefail

INPUT=$(cat)

if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}" ]; then
  PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
else
  HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PLUGIN_ROOT="$(cd "$HOOK_DIR/.." && pwd)"
fi

HOOK_LOG="${VISUALHUD_HOOK_LOG:-}"

log_err() {
  [ -n "$HOOK_LOG" ] && [ "$HOOK_LOG" != "0" ] || return 0
  printf '%s visualhud-hook: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf '?')" "$*" >>"$HOOK_LOG" 2>/dev/null || :
}

ENGINE="${VISUALHUD_ENGINE:-$PLUGIN_ROOT/engine.sh}"
JSON_HELPER="${VISUALHUD_JSON_HELPER:-$PLUGIN_ROOT/scripts/visualhud-json.js}"

if [ ! -f "$ENGINE" ] || [ ! -f "$JSON_HELPER" ]; then
  log_err "missing engine=$ENGINE or helper=$JSON_HELPER"
  exit 0
fi

if ! command -v node >/dev/null 2>&1; then
  log_err "node not on PATH"
  exit 0
fi

export VISUALHUD_BG="${VISUALHUD_BG:-on}"
export VISUALHUD_DEFAULT_THEME="${VISUALHUD_DEFAULT_THEME:-pokemon}"
export VISUALHUD_REAPPLY_DELAY="${VISUALHUD_REAPPLY_DELAY:-0.12}"
export VISUALHUD_PROJECT_ROOT="${VISUALHUD_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$PWD}}"
export VISUALHUD_JOURNEY_PROFILE="${VISUALHUD_JOURNEY_PROFILE:-codex-default}"

PAYLOAD=$(printf '%s' "$INPUT" | node "$JSON_HELPER" claude-payload 2>/dev/null || true)
if [ -z "$PAYLOAD" ]; then
  exit 0
fi

if ! printf '%s' "$PAYLOAD" | bash "$ENGINE" >/dev/null 2>/dev/null; then
  log_err "engine exited non-zero"
fi
