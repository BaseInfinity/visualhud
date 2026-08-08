#!/bin/bash
# Integration tests for VisualHUD theme calibration previews.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT_DIR/visualhud"
PASS=0
FAIL=0
TOTAL=0
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/visualhud-calibration.XXXXXX")"

cleanup() {
    rm -rf "$TMP_ROOT"
    unset VISUALHUD_TTY VISUALHUD_SET_BG VISUALHUD_SET_BG_LOG VISUALHUD_REAPPLY_DELAY ITERM_SESSION_ID
}
trap cleanup EXIT

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s (expected '%s', got '%s')\n" "$label" "$expected" "$actual"
    fi
}

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s (expected output to contain '%s')\n" "$label" "$needle"
    fi
}

echo "=== Test Suite: visualhud theme calibrate ==="
echo ""

echo "--- Test 1: Calibration JSON covers every reviewable TMNT state ---"
CALIBRATION_JSON="$TMP_ROOT/tmnt-calibration.json"
"$CLI" theme calibrate tmnt --json > "$CALIBRATION_JSON"
assert_eq "TMNT calibration includes stage/shade/lifecycle/context entries" \
    "44" \
    "$(jq -r '.entries | length' "$CALIBRATION_JSON")"
assert_eq "First calibration entry is Leonardo with progress bar" \
    "1:🟥:Leonardo:tmnt-leonardo:25-105-255" \
    "$(jq -r '.entries[0] | "\(.step):\(.progress_bar):\(.name):\(.sprite):\(.color | join("-"))"' "$CALIBRATION_JSON")"
assert_contains "Calibration includes April yellow shade correction point" \
    "stage-shade:April shade 2:tmnt-april-yellow-2:255-235-90" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite):\(.color | join("-"))"] | join(",")' "$CALIBRATION_JSON")"
assert_contains "Calibration includes green Pizza Party done state" \
    "done:Pizza Party:tmnt-pizza:20-185-85" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite):\(.color | join("-"))"] | join(",")' "$CALIBRATION_JSON")"
assert_contains "Calibration includes Splinter review state" \
    "review:Splinter Review:tmnt-splinter:130-95-65" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite):\(.color | join("-"))"] | join(",")' "$CALIBRATION_JSON")"
assert_contains "Calibration includes Casey context review state" \
    "context:Casey Jones:tmnt-casey-jones:245-245-245" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite):\(.color | join("-"))"] | join(",")' "$CALIBRATION_JSON")"
assert_contains "Calibration includes semantic WORKING state" \
    "working:WORKING:tmnt-leonardo:25-105-255" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite):\(.color | join("-"))"] | join(",")' "$CALIBRATION_JSON")"
echo ""

echo "--- Test 2: Calibration text is human-reviewable ---"
CALIBRATION_TEXT=$("$CLI" theme calibrate tmnt)
assert_contains "Calibration text starts with step count" "[01/44]" "$CALIBRATION_TEXT"
assert_contains "Calibration text shows progress bar" "progress=🟥" "$CALIBRATION_TEXT"
assert_contains "Calibration text shows Pizza Party done state" "PIZZA Pizza Party" "$CALIBRATION_TEXT"
assert_contains "Calibration text shows Mutagen Compacting state" "OOZE Mutagen Compacting" "$CALIBRATION_TEXT"
assert_contains "Calibration text shows context overlay caveat" "context overlay" "$CALIBRATION_TEXT"
echo ""

echo "--- Test 3: Power Rangers calibration covers every shipped colors-only state ---"
POWER_RANGERS_JSON="$TMP_ROOT/power-rangers-calibration.json"
"$CLI" theme calibrate power-rangers --json > "$POWER_RANGERS_JSON"
assert_eq "Power Rangers calibration includes stages/lifecycle/context entries" \
    "44" \
    "$(jq -r '.entries | length' "$POWER_RANGERS_JSON")"
assert_contains "Power Rangers calibration starts with Red Ranger" \
    "stage:Red Ranger:R:145-24-28" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.badge):\(.color | join("-"))"] | join(",")' "$POWER_RANGERS_JSON")"
assert_contains "Power Rangers calibration includes Red Ranger shade 2" \
    "stage-shade:Red Ranger shade 2:R:190-28-30" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.badge):\(.color | join("-"))"] | join(",")' "$POWER_RANGERS_JSON")"
assert_contains "Power Rangers calibration reaches Ultrazord" \
    "stage:Ultrazord:UZ:120-130-160" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.badge):\(.color | join("-"))"] | join(",")' "$POWER_RANGERS_JSON")"
assert_contains "Power Rangers calibration labels approval as HITL" \
    "blocked:Approval required:HITL:100-30-120" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.badge):\(.color | join("-"))"] | join(",")' "$POWER_RANGERS_JSON")"
assert_contains "Power Rangers calibration includes Morphin Grid compacting state" \
    "compacting:Morphin Grid:GRID:180-60-220" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.badge):\(.color | join("-"))"] | join(",")' "$POWER_RANGERS_JSON")"
echo ""

echo "--- Test 4: Live calibration can drive the engine against a mocked terminal ---"
export ITERM_SESSION_ID="w0t0p0:VISUALHUD_CALIBRATION_TEST"
export VISUALHUD_TTY="$TMP_ROOT/tty.log"
export VISUALHUD_SET_BG="$TMP_ROOT/set_bg.py"
export VISUALHUD_REAPPLY_DELAY="0"
cat > "$VISUALHUD_SET_BG" <<'PY'
#!/usr/bin/env python3
import os
import sys

with open(os.environ["VISUALHUD_SET_BG_LOG"], "a", encoding="utf-8") as handle:
    handle.write((sys.argv[1] if len(sys.argv) > 1 else "") + "\n")
PY
chmod +x "$VISUALHUD_SET_BG"
export VISUALHUD_SET_BG_LOG="$TMP_ROOT/set-bg.log"
export VISUALHUD_STATE_DIR="$TMP_ROOT/state"
CALIBRATION_SESSION_KEY="w0t0p0_VISUALHUD_CALIBRATION_TEST"
CALIBRATION_PERMISSION_FILE="$VISUALHUD_STATE_DIR/claude-cooking-permission_${CALIBRATION_SESSION_KEY}"
CALIBRATION_REVIEW_FILE="$VISUALHUD_STATE_DIR/claude-cooking-review_${CALIBRATION_SESSION_KEY}"
mkdir -p "${CALIBRATION_PERMISSION_FILE}.d"
printf 'stale-request\t1\tblocked\n' > "${CALIBRATION_PERMISSION_FILE}.d/stale"
printf 'blocked' > "$VISUALHUD_STATE_DIR/claude-cooking-attention_${CALIBRATION_SESSION_KEY}"
printf 'review' > "$CALIBRATION_REVIEW_FILE"

LIVE_OUTPUT=$("$CLI" theme calibrate tmnt --live --delay 0 --limit 2)
for _ in 1 2 3 4 5; do
    [ -f "$VISUALHUD_TTY" ] && break
    sleep 0.1
done
assert_contains "Live calibration prints first step" "[01/44]" "$LIVE_OUTPUT"
assert_contains "Live calibration prints second step" "[02/44]" "$LIVE_OUTPUT"
assert_contains "Live calibration emits Leonardo tab color" "SetColors=tab=1969ff" "$(cat "$VISUALHUD_TTY" 2>/dev/null)"
assert_contains "Live calibration reaches Leonardo shade 2" "Leonardo" "$(cat "$VISUALHUD_TTY" 2>/dev/null)"
printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Calibration","session_id":"visualhud-calibration"}' \
    | VISUALHUD_ACTIVITY_MODE=semantic VISUALHUD_THEME=tmnt bash "$ROOT_DIR/engine.sh" >/dev/null
assert_contains "Live calibration renders semantic WORKING" "WORKING" "$(cat "$VISUALHUD_TTY" 2>/dev/null)"
assert_eq "Live calibration clears stale permission attention before rendering" "no" "$([ -e "$VISUALHUD_STATE_DIR/claude-cooking-attention_${CALIBRATION_SESSION_KEY}" ] && printf yes || printf no)"
assert_eq "Live calibration clears stale permission markers between entries" "no" "$([ -e "${CALIBRATION_PERMISSION_FILE}.d" ] && printf yes || printf no)"
assert_eq "Live calibration clears stale review markers between entries" "no" "$([ -e "$CALIBRATION_REVIEW_FILE" ] && printf yes || printf no)"

"$CLI" theme calibrate minimal --live --delay 0 --limit 9 >/dev/null
assert_eq "Live calibration clears a final synthetic review marker on exit" "no" "$([ -e "$CALIBRATION_REVIEW_FILE" ] && printf yes || printf no)"
assert_eq "Live calibration clears final synthetic permission state on exit" "no" "$([ -e "${CALIBRATION_PERMISSION_FILE}.d" ] || [ -e "$VISUALHUD_STATE_DIR/claude-cooking-attention_${CALIBRATION_SESSION_KEY}" ] && printf yes || printf no)"
echo ""

echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
