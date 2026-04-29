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
    "38" \
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
assert_contains "Calibration includes Casey context review state" \
    "context:Casey Jones:tmnt-casey-jones:245-245-245" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite):\(.color | join("-"))"] | join(",")' "$CALIBRATION_JSON")"
echo ""

echo "--- Test 2: Calibration text is human-reviewable ---"
CALIBRATION_TEXT=$("$CLI" theme calibrate tmnt)
assert_contains "Calibration text starts with step count" "[01/38]" "$CALIBRATION_TEXT"
assert_contains "Calibration text shows progress bar" "progress=🟥" "$CALIBRATION_TEXT"
assert_contains "Calibration text shows Pizza Party done state" "PIZZA Pizza Party" "$CALIBRATION_TEXT"
assert_contains "Calibration text shows context overlay caveat" "context overlay" "$CALIBRATION_TEXT"
echo ""

echo "--- Test 3: Live calibration can drive the engine against a mocked terminal ---"
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

LIVE_OUTPUT=$("$CLI" theme calibrate tmnt --live --delay 0 --limit 2)
for _ in 1 2 3 4 5; do
    [ -f "$VISUALHUD_TTY" ] && break
    sleep 0.1
done
assert_contains "Live calibration prints first step" "[01/38]" "$LIVE_OUTPUT"
assert_contains "Live calibration prints second step" "[02/38]" "$LIVE_OUTPUT"
assert_contains "Live calibration emits Leonardo tab color" "SetColors=tab=1969ff" "$(cat "$VISUALHUD_TTY" 2>/dev/null)"
assert_contains "Live calibration reaches Leonardo shade 2" "Leonardo" "$(cat "$VISUALHUD_TTY" 2>/dev/null)"
echo ""

echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
