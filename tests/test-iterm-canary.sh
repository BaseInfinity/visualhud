#!/bin/bash
# Renderer-boundary tests for iTerm2 profile enforcement and canary comparison.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/visualhud-iterm-canary.XXXXXX")"
PASS=0
FAIL=0
TOTAL=0

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        printf '  PASS: %s\n' "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s (expected '%s', got '%s')\n" "$label" "$expected" "$actual"
    fi
}

mkdir -p "$TMP_ROOT/fake-sdk"
cat > "$TMP_ROOT/fake-sdk/iterm2.py" <<'PY'
import asyncio
import json
import os


class BackgroundImageMode:
    ASPECT_FIT = "aspect-fit"


class LocalWriteOnlyProfile:
    def __init__(self, values=None):
        self.values = dict(values or {})

    def set_background_image_location(self, value):
        self.values["Background Image Location"] = value

    def set_background_image_mode(self, value):
        self.values["Background Image Mode"] = value

    def set_blend(self, value):
        self.values["Blend"] = value


class Session:
    session_id = "CANARY"

    async def async_set_profile_properties(self, profile):
        with open(os.environ["VISUALHUD_ITERM_TEST_LOG"], "w", encoding="utf-8") as handle:
            json.dump(profile.values, handle)


class Tab:
    sessions = [Session()]

    async def async_set_title(self, title):
        with open(os.environ["VISUALHUD_ITERM_TITLE_LOG"], "w", encoding="utf-8") as handle:
            handle.write(title)


class Window:
    tabs = [Tab()]


class App:
    terminal_windows = [Window()]


async def async_get_app(_connection):
    return App()


def run_until_complete(coro):
    asyncio.run(coro(None))
PY

echo "=== Test Suite: iTerm2 semantic canary ==="
echo ""
echo "--- Test 1: Session profile pins the VisualHUD tab title ---"
PROFILE_LOG="$TMP_ROOT/profile.json"
TITLE_LOG="$TMP_ROOT/tab-title.txt"
PYTHONPATH="$TMP_ROOT/fake-sdk" VISUALHUD_ITERM_TEST_LOG="$PROFILE_LOG" \
    VISUALHUD_ITERM_TITLE_LOG="$TITLE_LOG" \
    python3 "$ROOT_DIR/set_bg.py" "/tmp/raichu.png" "w0t0p0:CANARY"
assert_eq "Background helper targets the requested sprite" "/tmp/raichu.png" \
    "$(jq -r '.["Background Image Location"]' "$PROFILE_LOG")"
assert_eq "Background helper enables a custom tab title" "true" \
    "$(jq -r '.["Use Custom Tab Title"]' "$PROFILE_LOG")"
assert_eq "Background helper binds the tab title to hudProgress" '\(user.hudProgress)' \
    "$(jq -r '.["Custom Tab Title"]' "$PROFILE_LOG")"
assert_eq "Background helper pins the containing tab to hudProgress" '\(currentSession.user.hudProgress)' \
    "$(cat "$TITLE_LOG" 2>/dev/null || true)"
echo ""

echo "--- Test 2: Two converged semantic samples form the non-pixel oracle ---"
cat > "$TMP_ROOT/expected.json" <<'JSON'
{
  "checkpoint": "5/12 IMPLEMENT",
  "aggregate": "Tasks 3/4",
  "sprite": "raichu.png",
  "tab_color": [230, 180, 40]
}
JSON
cat > "$TMP_ROOT/good-samples.json" <<'JSON'
[
  {
    "session_id": "CANARY",
    "session_name": "spinner frame 1",
    "hud_progress": "blocks 5/12 IMPLEMENT | visualhud | Tasks 3/4",
    "resolved_tab_title": "blocks 5/12 IMPLEMENT | visualhud | Tasks 3/4",
    "use_custom_tab_title": true,
    "custom_tab_title": "\\(user.hudProgress)",
    "background_image_location": "/themes/pokemon/sprites/raichu.png",
    "tab_color": [230, 180, 40]
  },
  {
    "session_id": "CANARY",
    "session_name": "spinner frame 2",
    "hud_progress": "blocks 5/12 IMPLEMENT | visualhud | Tasks 3/4",
    "resolved_tab_title": "blocks 5/12 IMPLEMENT | visualhud | Tasks 3/4",
    "use_custom_tab_title": true,
    "custom_tab_title": "\\(user.hudProgress)",
    "background_image_location": "/themes/pokemon/sprites/raichu.png",
    "tab_color": [230, 180, 40]
  }
]
JSON
good_status=0
python3 "$ROOT_DIR/scripts/visualhud-iterm-canary.py" compare \
    --expected "$TMP_ROOT/expected.json" --samples "$TMP_ROOT/good-samples.json" \
    > "$TMP_ROOT/good.out" 2>&1 || good_status=$?
assert_eq "Two matching semantic samples pass" "0" "$good_status"

jq '.[1].session_name = .[0].session_name' \
    "$TMP_ROOT/good-samples.json" > "$TMP_ROOT/static-host-title-samples.json"
static_title_status=0
python3 "$ROOT_DIR/scripts/visualhud-iterm-canary.py" compare \
    --expected "$TMP_ROOT/expected.json" --samples "$TMP_ROOT/static-host-title-samples.json" \
    > "$TMP_ROOT/static-host-title.out" 2>&1 || static_title_status=$?
assert_eq "The canary requires evidence that the host title changed" "1" "$static_title_status"

jq '.[1].session_id = "OTHER-PANE"' \
    "$TMP_ROOT/good-samples.json" > "$TMP_ROOT/cross-pane-samples.json"
cross_pane_status=0
python3 "$ROOT_DIR/scripts/visualhud-iterm-canary.py" compare \
    --expected "$TMP_ROOT/expected.json" --samples "$TMP_ROOT/cross-pane-samples.json" \
    > "$TMP_ROOT/cross-pane.out" 2>&1 || cross_pane_status=$?
assert_eq "The canary rejects samples from different panes" "1" "$cross_pane_status"

jq 'map(del(.session_id))' \
    "$TMP_ROOT/good-samples.json" > "$TMP_ROOT/missing-session-samples.json"
missing_session_status=0
python3 "$ROOT_DIR/scripts/visualhud-iterm-canary.py" compare \
    --expected "$TMP_ROOT/expected.json" --samples "$TMP_ROOT/missing-session-samples.json" \
    > "$TMP_ROOT/missing-session.out" 2>&1 || missing_session_status=$?
assert_eq "The canary rejects samples without pane identity" "1" "$missing_session_status"

jq '.[1].background_image_location = "/themes/pokemon/sprites/pikachu.png"' \
    "$TMP_ROOT/good-samples.json" > "$TMP_ROOT/stale-samples.json"
stale_status=0
python3 "$ROOT_DIR/scripts/visualhud-iterm-canary.py" compare \
    --expected "$TMP_ROOT/expected.json" --samples "$TMP_ROOT/stale-samples.json" \
    > "$TMP_ROOT/stale.out" 2>&1 || stale_status=$?
assert_eq "A stale second sample fails convergence" "1" "$stale_status"

jq '.[1].resolved_tab_title = "spinner visualhud (codex)"' \
    "$TMP_ROOT/good-samples.json" > "$TMP_ROOT/overwritten-title-samples.json"
title_status=0
python3 "$ROOT_DIR/scripts/visualhud-iterm-canary.py" compare \
    --expected "$TMP_ROOT/expected.json" --samples "$TMP_ROOT/overwritten-title-samples.json" \
    > "$TMP_ROOT/overwritten-title.out" 2>&1 || title_status=$?
assert_eq "A host-overwritten visible tab title fails the canary" "1" "$title_status"

profile_status=0
PYTHONDONTWRITEBYTECODE=1 python3 - "$ROOT_DIR" <<'PY' || profile_status=$?
import importlib.util
import sys

root = sys.argv[1]
spec = importlib.util.spec_from_file_location(
    "visualhud_iterm_canary", f"{root}/scripts/visualhud-iterm-canary.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Profile:
    _Profile__props = {
        "Use Custom Tab Title": 1,
        "Custom Tab Title": r"\(user.hudProgress)",
    }


assert module.profile_property(Profile(), "Use Custom Tab Title", "use_custom_tab_title") == 1
assert module.profile_property(Profile(), "Custom Tab Title", "custom_tab_title") == r"\(user.hudProgress)"
PY
assert_eq "Canary reads effective properties omitted by the public iTerm2 SDK" "0" "$profile_status"

printf '\n=== Results: %s/%s passed, %s failed ===\n' "$PASS" "$TOTAL" "$FAIL"
[ "$FAIL" -eq 0 ]
