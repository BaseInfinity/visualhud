#!/bin/bash
# Bridge Codex hook events into the existing VisualHUD Claude hook engine.

set -euo pipefail

INPUT=$(cat)
RAW_EVENT_NAME=""
RAW_START_SOURCE=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENGINE="${VISUALHUD_ENGINE:-$REPO_ROOT/engine.sh}"
JSON_HELPER="${VISUALHUD_JSON_HELPER:-$REPO_ROOT/scripts/visualhud-json.js}"

if [ ! -f "$ENGINE" ]; then
  exit 0
fi

export VISUALHUD_DEFAULT_THEME="${VISUALHUD_DEFAULT_THEME:-tmnt}"
export VISUALHUD_REAPPLY_DELAY="${VISUALHUD_REAPPLY_DELAY:-0.12}"
export VISUALHUD_PROJECT_ROOT="${VISUALHUD_PROJECT_ROOT:-$REPO_ROOT}"
if [ -z "${VISUALHUD_JOURNEY_PROFILE:-}" ]; then
  if [ -f "$REPO_ROOT/.codex-sdlc/manifest.json" ] || [ -f "$REPO_ROOT/.agents/skills/sdlc/SKILL.md" ]; then
    export VISUALHUD_JOURNEY_PROFILE=sdlc
  else
    export VISUALHUD_JOURNEY_PROFILE=codex-default
  fi
fi

RAW_EVENT_NAME=$(printf '%s' "$INPUT" | node "$JSON_HELPER" event-name 2>/dev/null || true)
RAW_START_SOURCE=$(printf '%s' "$INPUT" | node "$JSON_HELPER" field source 2>/dev/null || true)
PAYLOAD=$(printf '%s' "$INPUT" | node "$JSON_HELPER" codex-payload 2>/dev/null || true)

if [ -z "$PAYLOAD" ]; then
  exit 0
fi

case "$RAW_EVENT_NAME:$RAW_START_SOURCE" in
  SessionStart:startup|SessionStart:resume)
    rm -f "$VISUALHUD_PROJECT_ROOT/.visualhud/codex-restart-required"
    ;;
esac

# Codex consumes hook stdout as protocol output. The engine writes terminal
# control sequences to /dev/tty, so keep stdout empty for Codex.
printf '%s' "$PAYLOAD" | bash "$ENGINE" >/dev/null 2>/dev/null || true
