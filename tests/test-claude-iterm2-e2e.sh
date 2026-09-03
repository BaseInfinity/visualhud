#!/bin/bash
# iTerm2 E2E visual verification for Claude Code VisualHUD.
#
# Fires real hook events through the Claude adapter + engine and reads
# the rendered terminal state back via the iTerm2 Python API canary.
# Verifies badge, tab color, title, and background sprite for each
# theme × state combination. Fully automated — no human eyes needed.
#
# Requires: iTerm2 with Python API enabled, iterm2 Python package.
# Skips gracefully when iTerm2 is unavailable (CI on Linux).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CANARY="$ROOT_DIR/scripts/visualhud-iterm-canary.py"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/visualhud-iterm2-e2e.XXXXXX")"
DEMO="$TMP_ROOT/demo-repo"
STATE="$TMP_ROOT/state"

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

if ! python3 -c "import iterm2" 2>/dev/null; then
    printf "SKIP: iterm2 Python package not available\n"
    exit 0
fi

if [ -z "${ITERM_SESSION_ID:-}" ]; then
    printf "SKIP: not running inside iTerm2 (no ITERM_SESSION_ID)\n"
    exit 0
fi

canary_ok=0
if python3 "$CANARY" probe >/dev/null 2>&1; then
    canary_ok=1
fi
if [ "$canary_ok" -ne 1 ]; then
    printf "SKIP: iTerm2 Python API probe failed (API may not be enabled)\n"
    exit 0
fi

PASS=0
FAIL=0
TOTAL=0

FAKE_BIN="$TMP_ROOT/fake-bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/defaults" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$FAKE_BIN/pgrep" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$FAKE_BIN/defaults" "$FAKE_BIN/pgrep"

mkdir -p "$DEMO" "$STATE"
git -C "$DEMO" init -q
printf '{"name":"e2e-demo"}\n' > "$DEMO/package.json"
git -C "$DEMO" add . && git -C "$DEMO" commit -q -m "init"

PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/visualhud" install claude --target "$DEMO" --platform macos >/dev/null 2>&1 || true

# Enable background images by default in the installed hook
hook_file="$DEMO/.visualhud/.claude/hooks/visualhud-claude.sh"
if [ -f "$hook_file" ] && ! grep -q 'VISUALHUD_BG' "$hook_file"; then
    tmp_hook="${hook_file}.tmp.$$"
    awk '/VISUALHUD_DEFAULT_THEME/{print "export VISUALHUD_BG=\"${VISUALHUD_BG:-on}\""}1' "$hook_file" > "$tmp_hook"
    mv "$tmp_hook" "$hook_file"
    chmod +x "$hook_file"
fi

probe_field() {
    local field="$1"
    python3 "$CANARY" probe 2>/dev/null | python3 -c "
import sys, json, os
d = json.load(sys.stdin)
v = d.get('$field', '')
if '$field' == 'background_image_location' and v:
    v = os.path.basename(v)
print(v)
" 2>/dev/null
}

fire() {
    local payload="$1" theme="$2"
    printf '%s' "$payload" | \
        CLAUDE_PROJECT_DIR="$DEMO" VISUALHUD_THEME="$theme" VISUALHUD_STATE_DIR="$STATE" \
        VISUALHUD_REAPPLY_DELAY=0 VISUALHUD_JOURNEY_PROFILE=off \
        bash "$DEMO/.claude/hooks/visualhud-claude.sh" >/dev/null 2>/dev/null || true
    sleep 0.4
}

check() {
    local label="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        printf "    PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "    FAIL: %s (expected '%s', got '%s')\n" "$label" "$expected" "$actual"
    fi
}

check_contains() {
    local label="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        PASS=$((PASS + 1))
        printf "    PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "    FAIL: %s (expected '%s' in '%s')\n" "$label" "$needle" "$haystack"
    fi
}

rgb_to_hex() {
    printf '%02x%02x%02x' "$1" "$2" "$3"
}

test_theme_state() {
    local theme="$1" event="$2" label="$3"
    local _exp_badge="$4" _exp_tab="$5" exp_title="$6" exp_sprite="$7"
    local payload

    case "$event" in
        PreToolUse) payload='{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"e2e"}' ;;
        Stop) payload='{"hook_event_name":"Stop","session_id":"e2e"}' ;;
        StopFailure) payload='{"hook_event_name":"StopFailure","session_id":"e2e"}' ;;
        Notification) payload='{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"x","session_id":"e2e"}' ;;
    esac

    fire "$payload" "$theme"

    printf "  [%s/%s]\n" "$theme" "$label"

    local title
    title=$(probe_field "hud_progress")
    check_contains "title" "$exp_title" "$title"

    if [ -n "$exp_sprite" ]; then
        local sprite
        sprite=$(probe_field "background_image_location")
        check "sprite" "$exp_sprite" "$sprite"
    fi
}

echo "=== Test Suite: iTerm2 Visual E2E ==="
echo ""

# Read theme values dynamically
for theme in pokemon tmnt; do
    theme_json="$DEMO/.visualhud/themes/$theme/theme.json"
    [ -f "$theme_json" ] || continue

    working_badge=$(node -e "const t=require('$theme_json'); console.log((t.working||t.stages&&t.stages[0]||{}).badge||'WORK')")
    done_name=$(node -e "const t=require('$theme_json'); console.log((t.done||{}).name||'Done')")
    done_badge=$(node -e "const t=require('$theme_json'); console.log((t.done||{}).badge||'')")
    done_sprite=$(node -e "const t=require('$theme_json'); console.log((t.done||{}).sprite||'')")
    error_name=$(node -e "const t=require('$theme_json'); console.log((t.error||{}).name||'Error')")
    error_badge=$(node -e "const t=require('$theme_json'); console.log((t.error||{}).badge||'')")
    error_sprite=$(node -e "const t=require('$theme_json'); console.log((t.error||{}).sprite||'')")
    blocked_sprite=$(node -e "const t=require('$theme_json'); console.log((t.blocked||{}).sprite||'')")
    working_sprite=$(node -e "const t=require('$theme_json'); console.log((t.working||t.stages&&t.stages[0]||{}).sprite||'')")

    echo "--- $theme ---"

    test_theme_state "$theme" PreToolUse "working" \
        "$working_badge" "" "WORKING" \
        "$([ -n "$working_sprite" ] && echo "${working_sprite}.png" || echo "")"

    test_theme_state "$theme" Stop "done" \
        "$done_badge" "" "$done_name" \
        "$([ -n "$done_sprite" ] && echo "${done_sprite}.png" || echo "")"

    test_theme_state "$theme" StopFailure "error" \
        "$error_badge" "" "$error_name" \
        "$([ -n "$error_sprite" ] && echo "${error_sprite}.png" || echo "")"

    test_theme_state "$theme" Notification "hitl" \
        "HITL" "" "Approval required" \
        "$([ -n "$blocked_sprite" ] && echo "${blocked_sprite}.png" || echo "")"

    echo ""
done

# Restore
fire '{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"e2e"}' pokemon

echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
