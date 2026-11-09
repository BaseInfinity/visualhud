#!/bin/bash
# Railway theme contract: an original steam-railway conductor theme.
# Proves the theme shape, signal-light colors, the "All aboard" start, the
# done whistle through the engine's optional sound contract, generated-asset
# provenance, and that no franchise names ship in the theme.
# shellcheck disable=SC2016 # jq programs are single-quoted on purpose.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME_DIR="$ROOT_DIR/themes/railway"
THEME_JSON="$THEME_DIR/theme.json"
MANIFEST="$THEME_DIR/sprites/manifest.json"
GENERATOR="$ROOT_DIR/scripts/generate-railway-assets.py"
ENGINE="$ROOT_DIR/engine.sh"
PASS=0
FAIL=0
TOTAL=0

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/visualhud-railway.XXXXXX")"
cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

pass() {
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    printf "  FAIL: %s\n" "$1"
}

check() {
    local label="$1"
    shift
    TOTAL=$((TOTAL + 1))
    if "$@" >/dev/null 2>&1; then
        pass "$label"
    else
        fail "$label"
    fi
}

check_not() {
    local label="$1"
    shift
    TOTAL=$((TOTAL + 1))
    if "$@" >/dev/null 2>&1; then
        fail "$label"
    else
        pass "$label"
    fi
}

theme_jq() {
    jq -e "$1" "$THEME_JSON"
}

# Franchise guard. The theme is original; none of these may appear in any
# shipped railway file or in the generator that draws its art.
BRAND_PATTERN='thomas|tank engine friends|sodor|mattel|awdry|topham|hatt|fat controller|really useful|percy|gordon|clarabel|troublesome truck|hit entertainment|gullane'

brand_terms_in() {
    grep -RIiEwl "$BRAND_PATTERN" "$@"
}

# Fires the engine for one hook event and returns the capture dir.
run_engine() {
    local theme="$1" json="$2" capture="$3"
    shift 3
    mkdir -p "$capture/state"
    printf '%s\n' "$json" | env -u ITERM_SESSION_ID -u VISUALHUD_TTY \
        ITERM_SESSION_ID="w0t0p0:RAILWAY_TEST" \
        VISUALHUD_THEME="$theme" \
        VISUALHUD_THEMES_DIR="$ROOT_DIR/themes" \
        VISUALHUD_STATE_DIR="$capture/state" \
        VISUALHUD_TEST_CAPTURE_DIR="$capture" \
        VISUALHUD_JOURNEY_PROFILE=off \
        VISUALHUD_REAPPLY_DELAY=0 \
        "$@" bash "$ENGINE" >/dev/null 2>&1 || true
}

printf '=== Railway theme ===\n'

check "theme.json exists and parses" jq empty "$THEME_JSON"
check "theme name is Railway Conductor" theme_jq '.name == "Railway Conductor"'

for state in working permission blocked review "done" idle error; do
    check "lifecycle state '$state' has sprite, badge, name, color" theme_jq "
      .${state} | (.sprite|type==\"string\" and length>0) and (.badge|length>0)
        and (.name|length>0) and (.color|length==3)"
done

check "stages ascend by max and end at 999999" theme_jq '
  [.stages[].max] as $m | ($m == ($m|sort)) and ($m|last) == 999999'
check "every stage carries the stage contract with a shade ramp" theme_jq '
  all(.stages[]; (.sprite|length>0) and (.badge|length>0) and (.name|length>0)
    and (.color_family|length>0) and (.color|length==3) and (.shades|length>=2)
    and ((.shade_sprites // .shades)|length) == (.shades|length))'
check "every RGB channel is an integer 0-255" theme_jq '
  [.. | arrays | select(length==3 and all(.[]; type=="number"))[]]
  | all(. == floor and . >= 0 and . <= 255)'
check "first stage greets with All aboard" theme_jq '.stages[0].name == "All aboard"'
check "blocked says HITL" theme_jq '(.blocked.badge + " " + .blocked.name) | test("HITL")'
check "permission does not claim human action" theme_jq '
  (.permission.badge + " " + .permission.name) | test("HITL|approv|required";"i") | not'

# Signal lights: red stops, amber cautions, green clears.
RED='.[0] > .[1] + 80 and .[0] > .[2] + 80'
AMBER='.[0] >= 200 and .[1] >= 100 and .[1] <= 200 and .[2] < 80'
GREEN='.[1] > .[0] + 40 and .[1] > .[2] + 40'
check "blocked shows a red signal" theme_jq ".blocked.color | $RED"
check "error shows a red signal" theme_jq ".error.color | $RED"
check "permission shows an amber signal" theme_jq ".permission.color | $AMBER"
check "review shows an amber signal" theme_jq ".review.color | $AMBER"
check "working shows a green signal" theme_jq ".working.color | $GREEN"
check "done shows a green signal" theme_jq ".done.color | $GREEN"
check "blocked and error stay distinguishable" theme_jq '.blocked.color != .error.color'

check "done blows the whistle" theme_jq '.done.sound == "whistle"'
check "only done carries a sound" theme_jq '[.. | objects | select(has("sound"))] | length == 1'
check "whistle is a 0.5-3s WAV" python3 -c "
import sys, wave
w = wave.open('$THEME_DIR/sounds/whistle.wav')
d = w.getnframes() / w.getframerate()
sys.exit(0 if 0.5 <= d <= 3.0 else 1)"

# Every referenced sprite exists as a 512x512 RGBA PNG.
SPRITES=$(jq -r '[.stages[] | .sprite, (.shade_sprites // [])[]] + [.working, .permission, .blocked, .review, .done, .idle, .error, .plan, .compacting, .subagent | .sprite? // empty] | map(select(length>0)) | unique[]' "$THEME_JSON" 2>/dev/null || true)
check "theme references at least one sprite" test -n "$SPRITES"
for sprite in $SPRITES; do
    check "sprite $sprite is a 512x512 RGBA PNG" python3 -c "
import sys
from PIL import Image
im = Image.open('$THEME_DIR/sprites/$sprite.png')
sys.exit(0 if im.size == (512, 512) and im.mode == 'RGBA' else 1)"
done

check "contact sheet reports no missing sprites" python3 "$ROOT_DIR/scripts/render-theme-contact-sheet.py" \
    --theme "$THEME_JSON" --sprites-dir "$THEME_DIR/sprites" \
    --output "$TMP_ROOT/sheet.png" --report "$TMP_ROOT/sheet.json"
check "contact sheet report is empty of missing sprites" jq -e '.missing_sprites == []' "$TMP_ROOT/sheet.json"

# Provenance: every shipped asset is recorded, generated, MIT, hash-bound.
check "manifest parses" jq empty "$MANIFEST"
ASSETS=$( (cd "$THEME_DIR" 2>/dev/null && find sprites sounds -type f \( -name '*.png' -o -name '*.wav' \)) | sort || true)
check "theme ships assets" test -n "$ASSETS"
for asset in $ASSETS; do
    sum=$(shasum -a 256 "$THEME_DIR/$asset" | cut -d' ' -f1)
    check "manifest binds $asset to its sha256, the generator and MIT" jq -e --arg p "$asset" --arg s "$sum" '
      .assets[$p] | .sha256 == $s and .generator == "scripts/generate-railway-assets.py"
        and .license == "MIT" and .origin == "original"' "$MANIFEST"
done
check "manifest lists no asset that is absent" jq -e --argjson n "$(printf '%s\n' "$ASSETS" | grep -c .)" \
    '.assets | length == $n' "$MANIFEST"

# The generator reproduces the shipped pixels and samples, so the script is the provenance.
check "generator runs into a scratch dir" python3 "$GENERATOR" --output "$TMP_ROOT/regen"
for asset in $ASSETS; do
    check "regenerated $asset matches the shipped content" python3 -c "
import sys, wave
a, b = '$THEME_DIR/$asset', '$TMP_ROOT/regen/$asset'
if a.endswith('.wav'):
    sys.exit(0 if wave.open(a).readframes(10**9) == wave.open(b).readframes(10**9) else 1)
from PIL import Image
sys.exit(0 if Image.open(a).tobytes() == Image.open(b).tobytes() else 1)"
done

# Franchise guard, with its own positive and negative fixtures.
mkdir -p "$TMP_ROOT/brand-dirty" "$TMP_ROOT/brand-clean"
printf '{"name": "Thomas and friends"}\n' > "$TMP_ROOT/brand-dirty/theme.json"
printf '{"name": "Railway Conductor", "badge": "tank engine"}\n' > "$TMP_ROOT/brand-clean/theme.json"
check "brand guard fires on a franchise name" brand_terms_in "$TMP_ROOT/brand-dirty"
check_not "brand guard passes a generic railway word" brand_terms_in "$TMP_ROOT/brand-clean"
check_not "no franchise names in the railway theme or its generator" brand_terms_in "$THEME_DIR" "$GENERATOR"

# Engine sound contract.
CAP="$TMP_ROOT/cap-done"
run_engine railway '{"hook_event_name":"Stop","session_id":"railway:test"}' "$CAP"
check "Stop on railway records the whistle" grep -qx "$ROOT_DIR/themes/railway/sounds/whistle.wav" "$CAP/sound.log"

whistles() {
    grep -c whistle.wav "$1/sound.log" 2>/dev/null || true
}

STOP='{"hook_event_name":"Stop","session_id":"railway:test"}'
CAP="$TMP_ROOT/cap-review"
run_engine railway '{"hook_event_name":"TaskCompleted","session_id":"railway:test","task":"code review completed"}' "$CAP"
run_engine railway "$STOP" "$CAP"
check "review TaskCompleted then Stop whistles once" test "$(whistles "$CAP")" = 1

CAP="$TMP_ROOT/cap-repeat"
run_engine railway "$STOP" "$CAP"
run_engine railway "$STOP" "$CAP"
check "a repeated done render whistles once" test "$(whistles "$CAP")" = 1

CAP="$TMP_ROOT/cap-next-turn"
run_engine railway "$STOP" "$CAP"
run_engine railway '{"hook_event_name":"UserPromptSubmit","session_id":"railway:test"}' "$CAP"
run_engine railway "$STOP" "$CAP"
check "a new turn with no tools whistles again" test "$(whistles "$CAP")" = 2

CAP="$TMP_ROOT/cap-tool-turn"
run_engine railway "$STOP" "$CAP"
run_engine railway '{"hook_event_name":"PreToolUse","session_id":"railway:test","tool_name":"Read"}' "$CAP"
run_engine railway "$STOP" "$CAP"
check "done after work whistles again" test "$(whistles "$CAP")" = 2

# A superseded prompt must not clear the sound state of a newer owned render.
CAP="$TMP_ROOT/cap-stale-prompt"
run_engine railway "$STOP" "$CAP"
STALE_TOKEN=$(env -u ITERM_SESSION_ID -u VISUALHUD_TTY ITERM_SESSION_ID="w0t0p0:RAILWAY_TEST" \
    VISUALHUD_STATE_DIR="$CAP/state" VISUALHUD_TEST_CAPTURE_DIR="$CAP" \
    bash "$ENGINE" --register-repaint | cut -f2)
run_engine railway "$STOP" "$CAP"
run_engine railway '{"hook_event_name":"UserPromptSubmit","session_id":"railway:test"}' "$CAP" \
    VISUALHUD_REPAINT_EVENT_TOKEN="$STALE_TOKEN"
run_engine railway "$STOP" "$CAP"
check "a stale token was issued" test -n "$STALE_TOKEN"
check "a superseded prompt cannot re-arm the whistle" test "$(whistles "$CAP")" = 1

CAP="$TMP_ROOT/cap-off"
run_engine railway '{"hook_event_name":"Stop","session_id":"railway:test"}' "$CAP" VISUALHUD_SOUND=off
check_not "VISUALHUD_SOUND=off silences the whistle" test -e "$CAP/sound.log"

CAP="$TMP_ROOT/cap-work"
run_engine railway '{"hook_event_name":"PreToolUse","session_id":"railway:test","tool_name":"Read"}' "$CAP"
check "PreToolUse on railway paints the terminal" test -s "$CAP/terminal.log"
check_not "PreToolUse on railway stays silent" test -e "$CAP/sound.log"

CAP="$TMP_ROOT/cap-pokemon"
run_engine pokemon '{"hook_event_name":"Stop","session_id":"railway:test"}' "$CAP"
check "Stop on pokemon still paints the terminal" test -s "$CAP/terminal.log"
check_not "a theme without sound stays silent on done" test -e "$CAP/sound.log"

# CLI and docs.
check "theme list includes railway" bash -c "'$ROOT_DIR/visualhud' theme list | grep -q railway"
check "theme calibrate railway succeeds" bash -c "'$ROOT_DIR/visualhud' theme calibrate railway --json | jq empty"
check "THEMES.md documents the sound field" grep -q '"sound"' "$ROOT_DIR/THEMES.md"
check "THEMES.md keeps personal franchise images local" grep -q 'Personal Images Stay Local' "$ROOT_DIR/THEMES.md"

printf '\nRailway theme: %d/%d passed, %d failed\n' "$PASS" "$TOTAL" "$FAIL"
[ "$FAIL" -eq 0 ]
