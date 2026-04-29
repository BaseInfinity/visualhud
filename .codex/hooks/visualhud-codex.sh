#!/bin/bash
# Bridge Codex hook events into the existing VisualHUD Claude hook engine.

set -euo pipefail

INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENGINE="${VISUALHUD_ENGINE:-$REPO_ROOT/engine.sh}"

if [ ! -f "$ENGINE" ]; then
  exit 0
fi

EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null || true)
PAYLOAD=""
export VISUALHUD_DEFAULT_THEME="${VISUALHUD_DEFAULT_THEME:-tmnt}"
export VISUALHUD_REAPPLY_DELAY="${VISUALHUD_REAPPLY_DELAY:-0.12}"

case "$EVENT" in
  PreToolUse|UserPromptSubmit|Stop|TaskCompleted)
    PAYLOAD="$INPUT"
    ;;
  SessionStart)
    PAYLOAD=$(printf '%s' "$INPUT" | jq -c '{
      hook_event_name: "Stop",
      session_id: (.session_id // ""),
      source_event: "SessionStart",
      start_source: (.source // .start_source // "")
    }' 2>/dev/null || true)
    ;;
  PermissionRequest)
    PAYLOAD=$(printf '%s' "$INPUT" | jq -c '{
      hook_event_name: "Notification",
      notification_type: "permission_prompt",
      message: (.tool_input.description // "Codex is requesting permission"),
      session_id: (.session_id // ""),
      turn_id: (.turn_id // ""),
      tool_name: (.tool_name // ""),
      tool_input: (.tool_input // {})
    }' 2>/dev/null || true)
    ;;
  *)
    exit 0
    ;;
esac

if [ -z "$PAYLOAD" ]; then
  exit 0
fi

# Codex consumes hook stdout as protocol output. The engine writes terminal
# control sequences to /dev/tty, so keep stdout empty for Codex.
printf '%s' "$PAYLOAD" | bash "$ENGINE" >/dev/null 2>/dev/null || true
