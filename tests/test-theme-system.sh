#!/bin/bash
# Theme-system contract tests.
# Proves themes are data-only JSON packs and a third theme can be added without
# changing engine.sh.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_UNDER_TEST="${VISUALHUD_ENGINE_UNDER_TEST:-$ROOT_DIR/engine.sh}"
PASS=0
FAIL=0
TOTAL=0

TEST_SESSION="w0t0p0:THEME_SYSTEM_$(date +%s)"
export ITERM_SESSION_ID="$TEST_SESSION"
SESSION_KEY=$(printf '%s' "$TEST_SESSION" | tr ':/' '__')
COUNTER_FILE="/private/tmp/claude-cooking-counter_${SESSION_KEY}"
STAGE_FILE="/private/tmp/claude-cooking-stage_${SESSION_KEY}"
ATTENTION_FILE="/private/tmp/claude-cooking-attention_${SESSION_KEY}"
CONTEXT_FILE="/private/tmp/claude-cooking-context_${SESSION_KEY}"
TMP_ROOT=""

cleanup() {
    rm -f "$COUNTER_FILE" "$STAGE_FILE" "$ATTENTION_FILE" "$CONTEXT_FILE" 2>/dev/null
    if [ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ]; then
        rm -rf "$TMP_ROOT"
    fi
    unset VISUALHUD_THEME VISUALHUD_THEMES_DIR VISUALHUD_SET_BG VISUALHUD_SET_BG_LOG
    unset VISUALHUD_TTY VISUALHUD_SPRITES_DIR VISUALHUD_CONTEXT_USED_PERCENT
}
trap cleanup EXIT

run_hook() {
    local json="$1"
    printf '%s\n' "$json" | bash "$SCRIPT_UNDER_TEST" 2>/dev/null || true
}

pass() {
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    printf "  FAIL: %s\n" "$1"
}

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$actual')"
    fi
}

assert_file_exists() {
    local label="$1" filepath="$2"
    TOTAL=$((TOTAL + 1))
    if [ -f "$filepath" ]; then
        pass "$label"
    else
        fail "$label (missing file: $filepath)"
    fi
}

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        pass "$label"
    else
        fail "$label (expected content to contain '$needle')"
    fi
}

assert_not_contains() {
    local label="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" != *"$needle"* ]]; then
        pass "$label"
    else
        fail "$label (expected content not to contain '$needle')"
    fi
}

assert_no_repo_match() {
    local label="$1" pattern="$2"
    shift 2
    TOTAL=$((TOTAL + 1))
    if rg -n "$pattern" "$@" >/dev/null 2>&1; then
        fail "$label (matched forbidden pattern: $pattern)"
    else
        pass "$label"
    fi
}

assert_jq() {
    local label="$1" file="$2" filter="$3"
    TOTAL=$((TOTAL + 1))
    if jq -e "$filter" "$file" >/dev/null; then
        pass "$label"
    else
        fail "$label (jq contract failed for $file)"
    fi
}

echo "=== Test Suite: theme-system ==="
echo ""

echo "--- Test 1: Theme authoring contract is documented ---"
assert_file_exists "THEMES.md exists" "$ROOT_DIR/THEMES.md"
THEMES_DOC=""
if [ -f "$ROOT_DIR/THEMES.md" ]; then
    THEMES_DOC=$(cat "$ROOT_DIR/THEMES.md")
fi
README_DOC=$(cat "$ROOT_DIR/README.md")
ARCH_DOC=$(cat "$ROOT_DIR/ARCHITECTURE.md")
ROADMAP_DOC=$(cat "$ROOT_DIR/ROADMAP.md")
TESTING_DOC=$(cat "$ROOT_DIR/TESTING.md")
assert_contains "Theme docs define max-threshold stages" '"max"' "$THEMES_DOC"
assert_contains "Theme docs define sprite-backed states" '"sprite"' "$THEMES_DOC"
assert_contains "Theme docs define color families" '"color_family"' "$THEMES_DOC"
assert_contains "Theme docs define stage shades" '"shades"' "$THEMES_DOC"
assert_contains "Theme docs define shade sprite variants" '"shade_sprites"' "$THEMES_DOC"
assert_contains "Theme docs define progress bar as shared visual status strip" "shared visual progress strip" "$THEMES_DOC"
assert_contains "Theme docs define theme-colored sprite backdrops" "backdrop_color" "$THEMES_DOC"
assert_contains "Theme docs define lifecycle colors as semantic terminal states" "Lifecycle colors are semantic terminal states" "$THEMES_DOC"
assert_contains "Theme docs forbid neutral matte leaks" "neutral corner mattes" "$THEMES_DOC"
assert_contains "Theme docs include TDD acceptance gates" "TDD" "$THEMES_DOC"
assert_contains "Theme docs require Claude adapter proof" "bash tests/test-claude-visualhud.sh" "$THEMES_DOC"
assert_contains "Theme docs shellcheck Claude adapter" ".claude/hooks/*.sh" "$THEMES_DOC"
assert_contains "README has install section" "## Install" "$README_DOC"
assert_contains "README documents Codex local hook install" ".codex/hooks.json" "$README_DOC"
assert_contains "README documents Claude local hook install" ".claude/settings.json" "$README_DOC"
assert_contains "README documents iTerm2 setup command" "./setup-iterm2.sh" "$README_DOC"
assert_contains "README documents Windows status" "Windows Terminal" "$README_DOC"
assert_contains "README points theme authors to tests" "bash tests/test-theme-system.sh" "$README_DOC"
assert_contains "README documents per-shade sprite variants" "shade_sprites" "$README_DOC"
assert_contains "README documents matte stripping for source sprites" "neutral corner mattes" "$README_DOC"
assert_contains "README documents repo-local theme switch command" "./visualhud theme set" "$README_DOC"
assert_contains "README documents theme switch without restart" "next hook" "$README_DOC"
assert_contains "README documents calibration command" "./visualhud theme calibrate" "$README_DOC"
assert_contains "README records Batman as a future theme candidate" "Batman" "$README_DOC"
assert_contains "README records Power Rangers as a future theme candidate" "Power Rangers" "$README_DOC"
assert_contains "Roadmap prioritizes TMNT hardening before new themes" "## TMNT Hardening Before New Themes" "$ROADMAP_DOC"
assert_contains "Roadmap parks Batman theme candidate" "**Batman** (parked)" "$ROADMAP_DOC"
assert_contains "Roadmap parks Power Rangers theme candidate" "**Power Rangers** (parked)" "$ROADMAP_DOC"
assert_contains "Roadmap captures TMNT roster packs under one theme" "TMNT roster packs" "$ROADMAP_DOC"
assert_contains "Roadmap keeps Windows as separate portability track" "Windows Terminal/PowerShell stays a separate renderer track" "$ROADMAP_DOC"
assert_contains "Roadmap marks easy theme swapping shipped" "[x] **Easy theme swapping**" "$ROADMAP_DOC"
assert_contains "Roadmap parks TDLC for hard terminal visual testing" "TDLC" "$ROADMAP_DOC"
assert_contains "Testing docs include calibration test" "test-theme-calibration" "$TESTING_DOC"
assert_contains "Architecture documents Claude adapter" "visualhud-claude.sh" "$ARCH_DOC"
assert_contains "Architecture documents terminal surface palette" "SetColors=tab" "$ARCH_DOC"
assert_contains "Architecture documents normal black surface palette" "SetColors=black" "$ARCH_DOC"
assert_contains "Architecture documents delayed reapply guard" "VISUALHUD_REAPPLY_DELAY" "$ARCH_DOC"
assert_contains "Architecture documents theme shades" "shades" "$ARCH_DOC"
assert_contains "Architecture documents source sprite backdrop colors" "backdrop_color" "$ARCH_DOC"
assert_contains "Architecture documents non-destructive context alerts" "preserving the selected theme stage color and sprite" "$ARCH_DOC"
assert_contains "Architecture documents theme selection precedence" "VISUALHUD_THEME > repo-local active theme file > VISUALHUD_DEFAULT_THEME > pokemon" "$ARCH_DOC"
assert_contains "Theme docs document theme switch CLI" "./visualhud theme set" "$THEMES_DOC"
assert_contains "Theme docs document active theme file" "repo-local active theme file" "$THEMES_DOC"
assert_contains "Theme docs document calibration review flow" "theme calibration" "$THEMES_DOC"
assert_no_repo_match "Public theme docs do not advertise legacy at/image/title schema" \
    '"at":|"image":|"title":' "$ROOT_DIR/README.md" "$ROOT_DIR/THEMES.md"
assert_no_repo_match "README does not describe the old Claude-only implementation as current" \
    'Current implementation lives in|No "needs attention" state|No smooth color blending|This README is the blueprint|Move hook scripts \+ sprites into this repo|install\.sh.*symlinks' "$ROOT_DIR/README.md"
echo ""

echo "--- Test 2: Shipped theme JSON files follow the contract ---"
while IFS= read -r theme_file; do
    theme_name=$(basename "$(dirname "$theme_file")")
    assert_jq "$theme_name has a display name" "$theme_file" '.name | type == "string" and length > 0'
    # shellcheck disable=SC2016
    assert_jq "$theme_name has ordered stages" "$theme_file" '
      (.stages | type == "array" and length > 0)
      and ([.stages[].max] as $maxes | all(range(1; $maxes | length); $maxes[.] > $maxes[. - 1]))
    '
    assert_jq "$theme_name uses data-only stage entries" "$theme_file" '
      all(.stages[]; (
        (.max | type == "number")
        and (.sprite | type == "string")
        and (.badge | type == "string")
        and (.name | type == "string" and length > 0)
        and (.color | type == "array" and length == 3)
        and (.color_family | type == "string" and length > 0)
        and (
          (.color_family_singleton == true)
          or ((.shades | type == "array") and (.shades | length > 1))
        )
      ))
    '
    # shellcheck disable=SC2016
    assert_jq "$theme_name has lifecycle states" "$theme_file" '
      . as $theme
      | all(["blocked", "done", "idle", "error"][]; . as $state |
        ($theme[$state].name | type == "string")
        and ($theme[$state].badge | type == "string")
        and ($theme[$state].sprite | type == "string")
        and ($theme[$state].color | type == "array" and length == 3)
      )
    '
    assert_jq "$theme_name RGB values stay in terminal-safe range" "$theme_file" '
      [
        .stages[].color[],
        .blocked.color[],
        .done.color[],
        .idle.color[],
        .error.color[],
        .context_alerts.warning.color[],
        .context_alerts.critical.color[]
      ] | all(. >= 0 and . <= 255)
    '
    assert_jq "$theme_name context alert thresholds are ordered" "$theme_file" '
      (.context_alerts.warning.min_percent | type == "number")
      and (.context_alerts.critical.min_percent | type == "number")
      and (.context_alerts.warning.min_percent < .context_alerts.critical.min_percent)
    '
    assert_jq "$theme_name color families either shade or declare singleton" "$theme_file" '
      all(.stages[]; (
        (.color_family_singleton == true)
        or (
          [.shades[]]
          | unique
          | length > 1
        )
      ))
    '
    # shellcheck disable=SC2016
    assert_jq "$theme_name shade sprite variants match shade ramps when present" "$theme_file" '
      all(.stages[]; . as $stage |
        (
          ($stage.shade_sprites == null)
          or (
            ($stage.shade_sprites | type == "array")
            and ($stage.shade_sprites | length == ($stage.shades | length))
            and all($stage.shade_sprites[]; type == "string" and length > 0)
          )
        )
      )
    '
done < <(find "$ROOT_DIR/themes" -mindepth 2 -maxdepth 2 -name theme.json | sort)
assert_jq "TMNT Raphael red band defines per-shade sprite variants" "$ROOT_DIR/themes/tmnt/theme.json" '
  .stages[]
  | select(.name == "Raphael")
  | .shade_sprites == ["tmnt-raphael", "tmnt-raphael-red-2", "tmnt-raphael-red-3"]
'
# shellcheck disable=SC2016
assert_jq "TMNT every multi-shade stage defines per-shade sprite variants" "$ROOT_DIR/themes/tmnt/theme.json" '
  all(.stages[]; . as $stage |
    (($stage.shades | length) <= 1)
    or (
      ($stage.shade_sprites | type == "array")
      and ($stage.shade_sprites | length == ($stage.shades | length))
      and ($stage.shade_sprites[0] == $stage.sprite)
    )
  )
'
echo ""

echo "--- Test 3: Engine accepts a third theme by JSON only ---"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/visualhud-theme-system.XXXXXX")
THIRD_THEME="$TMP_ROOT/themes/third"
mkdir -p "$THIRD_THEME/sprites"

cat > "$THIRD_THEME/theme.json" <<'JSON'
{
  "name": "Third Theme Fixture",
  "progress_bar": ["A", "B", "G"],
  "stages": [
    { "max": 1, "sprite": "alpha", "badge": "A", "name": "Alpha", "color": [10, 20, 30] },
    { "max": 3, "sprite": "beta", "badge": "B", "name": "Beta", "color": [40, 50, 60] },
    { "max": 999999, "sprite": "gamma", "badge": "G", "name": "Gamma", "color": [70, 80, 90] }
  ],
  "blocked": { "sprite": "blocked", "badge": "BLOCK", "name": "Blocked", "color": [90, 80, 70] },
  "done": { "sprite": "done", "badge": "DONE", "name": "Done", "stage": 3, "color": [20, 180, 90] },
  "idle": { "sprite": "idle", "badge": "IDLE", "name": "Idle", "stage": 3, "color": [45, 120, 160] },
  "error": { "sprite": "error", "badge": "ERR", "name": "Error", "color": [255, 20, 20] },
  "context_alerts": {
    "warning": { "min_percent": 70, "badge": "LOW", "name": "Battery Low", "color": [200, 180, 40] },
    "critical": { "min_percent": 85, "badge": "MAX", "name": "Critical Mass", "color": [255, 255, 255] }
  }
}
JSON

python3 - "$THIRD_THEME/sprites" <<'PY'
from pathlib import Path
from PIL import Image
import sys

sprites_dir = Path(sys.argv[1])
colors = {
    "alpha": (10, 20, 30),
    "beta": (40, 50, 60),
    "gamma": (70, 80, 90),
    "blocked": (90, 80, 70),
    "done": (20, 180, 90),
    "idle": (45, 120, 160),
    "error": (255, 20, 20),
}
for name, color in colors.items():
    Image.new("RGB", (32, 32), color).save(sprites_dir / f"{name}.png")
PY

SET_BG_LOG="$TMP_ROOT/set-bg.log"
TTY_LOG="$TMP_ROOT/tty.log"
MOCK_SET_BG="$TMP_ROOT/set_bg.py"
cat > "$MOCK_SET_BG" <<'PY'
import os
import sys

with open(os.environ["VISUALHUD_SET_BG_LOG"], "a", encoding="utf-8") as handle:
    handle.write((sys.argv[1] if len(sys.argv) > 1 else "") + "\n")
PY

export VISUALHUD_THEMES_DIR="$TMP_ROOT/themes"
export VISUALHUD_THEME="third"
export VISUALHUD_SET_BG="$MOCK_SET_BG"
export VISUALHUD_SET_BG_LOG="$SET_BG_LOG"
export VISUALHUD_TTY="$TTY_LOG"

run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "third-theme"}'
for _ in 1 2 3 4 5; do
    [ -f "$SET_BG_LOG" ] && break
    sleep 0.1
done
assert_eq "Third theme count 1 uses Alpha sprite" "alpha" "$(cat "$STAGE_FILE" 2>/dev/null)"
assert_contains "Third theme writes Alpha tint escape" "SetColors=bg=030609" "$(cat "$TTY_LOG" 2>/dev/null)"
assert_eq "Third theme calls set_bg with theme-local Alpha sprite" \
    "$THIRD_THEME/sprites/alpha.png" \
    "$(tail -n 1 "$SET_BG_LOG" 2>/dev/null)"

: > "$TTY_LOG"
printf '1' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "third-theme"}'
assert_eq "Third theme count 2 uses Beta sprite" "beta" "$(cat "$STAGE_FILE" 2>/dev/null)"
assert_contains "Third theme writes Beta tint escape" "SetColors=bg=0c0f12" "$(cat "$TTY_LOG" 2>/dev/null)"

: > "$TTY_LOG"
printf '1' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "third-theme", "info": {"last_token_usage": {"total_tokens": 183000}, "model_context_window": 258400}}'
assert_eq "Third theme warning context keeps Beta sprite" "beta" "$(cat "$STAGE_FILE" 2>/dev/null)"
assert_contains "Third theme warning context keeps Beta tint" "SetColors=bg=0c0f12" "$(cat "$TTY_LOG" 2>/dev/null)"
assert_contains "Third theme warning context labels token pressure" "Battery Low CTX 70%" "$(cat "$TTY_LOG" 2>/dev/null)"

: > "$TTY_LOG"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "third-theme", "info": {"last_token_usage": {"total_tokens": 220000}, "model_context_window": 258400}}'
assert_contains "Third theme critical context keeps active stage tint" "SetColors=bg=0c0f12" "$(cat "$TTY_LOG" 2>/dev/null)"
assert_contains "Third theme critical context labels token pressure" "Critical Mass CTX 85%" "$(cat "$TTY_LOG" 2>/dev/null)"
assert_not_contains "Third theme critical context does not emergency-wash the pane" "SetColors=bg=4c4c4c" "$(cat "$TTY_LOG" 2>/dev/null)"

: > "$TTY_LOG"
run_hook '{"hook_event_name": "Stop", "session_id": "third-theme"}'
assert_eq "Third theme Stop uses Done sprite" "done" "$(cat "$STAGE_FILE" 2>/dev/null)"
assert_contains "Third theme Stop title uses Done name" "Done" "$(cat "$TTY_LOG" 2>/dev/null)"
echo ""

echo "--- Test 4: Visual smoke can render the third theme contact sheet ---"
CONTACT_SHEET="$TMP_ROOT/third-contact-sheet.png"
CONTACT_REPORT="$TMP_ROOT/third-contact-sheet.json"
python3 "$ROOT_DIR/scripts/render-theme-contact-sheet.py" \
    --theme "$THIRD_THEME/theme.json" \
    --sprites-dir "$THIRD_THEME/sprites" \
    --output "$CONTACT_SHEET" \
    --report "$CONTACT_REPORT"

assert_file_exists "Third theme visual smoke writes contact sheet" "$CONTACT_SHEET"
assert_file_exists "Third theme visual smoke writes report" "$CONTACT_REPORT"
assert_eq "Third theme visual smoke covers stages/lifecycle/context" \
    "9" \
    "$(jq -r '.entries | length' "$CONTACT_REPORT")"
assert_eq "Third theme visual smoke has no missing sprite-backed states" \
    "" \
    "$(jq -r '.missing_sprites | join(",")' "$CONTACT_REPORT")"
assert_contains "Third theme visual smoke covers Beta" \
    "stage:Beta:beta:40-50-60" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite // ""):\(.color | join("-"))"] | join(",")' "$CONTACT_REPORT")"
assert_contains "Third theme visual smoke covers Critical Mass" \
    "context:Critical Mass::255-255-255" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite // ""):\(.color | join("-"))"] | join(",")' "$CONTACT_REPORT")"
echo ""

cleanup

echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
