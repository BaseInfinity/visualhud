#!/bin/bash
# Bridge Claude Code hook events into the VisualHUD engine.

set -euo pipefail

INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENGINE="${VISUALHUD_ENGINE:-$REPO_ROOT/engine.sh}"

if [ ! -f "$ENGINE" ]; then
  exit 0
fi

EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null || true)
case "$EVENT" in
  PreToolUse|Notification|UserPromptSubmit|Stop|StopFailure|TaskCompleted)
    ;;
  *)
    exit 0
    ;;
esac

export VISUALHUD_DEFAULT_THEME="${VISUALHUD_DEFAULT_THEME:-pokemon}"
export VISUALHUD_REAPPLY_DELAY="${VISUALHUD_REAPPLY_DELAY:-0.12}"

# Claude hook output is user-visible. The engine writes terminal control
# sequences to /dev/tty, so keep stdout empty here.
printf '%s' "$INPUT" | bash "$ENGINE" >/dev/null 2>/dev/null || true
