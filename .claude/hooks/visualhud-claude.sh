#!/bin/bash
# Bridge Claude Code hook events into the VisualHUD engine.

set -euo pipefail

INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENGINE="${VISUALHUD_ENGINE:-$REPO_ROOT/engine.sh}"
JSON_HELPER="${VISUALHUD_JSON_HELPER:-$REPO_ROOT/scripts/visualhud-json.js}"

if [ ! -f "$ENGINE" ]; then
  exit 0
fi

PAYLOAD=$(printf '%s' "$INPUT" | node "$JSON_HELPER" claude-payload 2>/dev/null || true)
if [ -z "$PAYLOAD" ]; then
  exit 0
fi

export VISUALHUD_BG="${VISUALHUD_BG:-on}"
export VISUALHUD_DEFAULT_THEME="${VISUALHUD_DEFAULT_THEME:-pokemon}"
export VISUALHUD_REAPPLY_DELAY="${VISUALHUD_REAPPLY_DELAY:-0.12}"
export VISUALHUD_PROJECT_ROOT="${VISUALHUD_PROJECT_ROOT:-$REPO_ROOT}"
export VISUALHUD_JOURNEY_PROFILE="${VISUALHUD_JOURNEY_PROFILE:-codex-default}"

# Claude hook output is user-visible. The engine writes terminal control
# sequences to /dev/tty, so keep stdout empty here.
printf '%s' "$PAYLOAD" | bash "$ENGINE" >/dev/null 2>/dev/null || true
