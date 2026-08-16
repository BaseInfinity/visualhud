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
if [ -n "${VISUALHUD_REAPPLY_DELAY+x}" ]; then
  export VISUALHUD_REAPPLY_DELAYS="${VISUALHUD_REAPPLY_DELAYS:-$VISUALHUD_REAPPLY_DELAY}"
else
  export VISUALHUD_REAPPLY_DELAY=0.12
  export VISUALHUD_REAPPLY_DELAYS="${VISUALHUD_REAPPLY_DELAYS:-0.12 0.50}"
fi
export VISUALHUD_PROJECT_ROOT="${VISUALHUD_PROJECT_ROOT:-$REPO_ROOT}"
if [ -z "${VISUALHUD_JOURNEY_PROFILE:-}" ]; then
  if [ -f "$REPO_ROOT/.codex-sdlc/manifest.json" ] || [ -f "$REPO_ROOT/.agents/skills/sdlc/SKILL.md" ]; then
    export VISUALHUD_JOURNEY_PROFILE=sdlc
  else
    export VISUALHUD_JOURNEY_PROFILE=codex-default
  fi
fi

# Claim the terminal target before any external JSON parsing so an older hook
# cannot resume from classification and supersede a newer pane frame.
REPAINT_CLAIM=$(env -u VISUALHUD_REPAINT_EVENT_TOKEN -u VISUALHUD_REPAINT_CLAIM_MODE \
  -u VISUALHUD_REPAINT_FALLBACK_RECORD_TOKEN bash "$ENGINE" --register-repaint 2>/dev/null || true)
REPAINT_CLAIM_MODE=${REPAINT_CLAIM%%$'\t'*}
REPAINT_CLAIM_FIELDS=${REPAINT_CLAIM#*$'\t'}
REPAINT_EVENT_TOKEN=${REPAINT_CLAIM_FIELDS%%$'\t'*}
REPAINT_FALLBACK_RECORD_TOKEN=${REPAINT_CLAIM_FIELDS#*$'\t'}
export VISUALHUD_REPAINT_CLAIM_MODE="${REPAINT_CLAIM_MODE:-unguarded}"
export VISUALHUD_REPAINT_FALLBACK_RECORD_TOKEN="${REPAINT_FALLBACK_RECORD_TOKEN:-}"
RAW_EVENT_NAME=$(printf '%s' "$INPUT" | node "$JSON_HELPER" event-name 2>/dev/null || true)
if [ -n "$REPAINT_EVENT_TOKEN" ]; then
  export VISUALHUD_REPAINT_EVENT_TOKEN="$REPAINT_EVENT_TOKEN"
fi
export VISUALHUD_REPAINT_EVENT_CLASS="$RAW_EVENT_NAME"

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
