#!/bin/bash
# Integration tests for installing VisualHUD into another Codex repo.

set -euo pipefail

PASS=0
FAIL=0
TOTAL=0

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT_DIR/visualhud"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/visualhud-install.XXXXXX")"

cleanup() {
    rm -rf "$TMP_ROOT"
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

assert_not_contains() {
    local label="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" != *"$needle"* ]]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s (expected output not to contain '%s')\n" "$label" "$needle"
    fi
}

assert_file_exists() {
    local label="$1" filepath="$2"
    TOTAL=$((TOTAL + 1))
    if [ -f "$filepath" ]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s (missing file: %s)\n" "$label" "$filepath"
    fi
}

assert_file_not_exists() {
    local label="$1" filepath="$2"
    TOTAL=$((TOTAL + 1))
    if [ ! -e "$filepath" ]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s (unexpected file: %s)\n" "$label" "$filepath"
    fi
}

assert_executable() {
    local label="$1" filepath="$2"
    TOTAL=$((TOTAL + 1))
    if [ -x "$filepath" ]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s (not executable: %s)\n" "$label" "$filepath"
    fi
}

make_repo() {
    local name="$1"
    local target="$TMP_ROOT/$name"
    mkdir -p "$target"
    git -C "$target" init -q
    printf '%s\n' "$target"
}

FAKE_BIN="$TMP_ROOT/fake-bin"
TEST_HOME="$TMP_ROOT/home"
DEFAULTS_LOG="$TMP_ROOT/defaults.log"
mkdir -p "$FAKE_BIN" "$TEST_HOME"
cat > "$FAKE_BIN/defaults" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$VISUALHUD_TEST_DEFAULTS_LOG"
[ "${VISUALHUD_TEST_DEFAULTS_FAIL:-0}" != "1" ] || exit 1
state_dir="${VISUALHUD_TEST_DEFAULTS_STATE:?}"
mkdir -p "$state_dir"
operation="${1:-}"
domain="${2:-}"
key="${3:-}"
state_file="$state_dir/${domain}_${key}"
case "$operation" in
    write)
        value="${5:-}"
        case "${4:-}" in
            -bool) [ "$value" = true ] && value=1 || value=0 ;;
        esac
        printf '%s\n' "$value" > "$state_file"
        ;;
    read)
        [ -f "$state_file" ] || exit 1
        cat "$state_file"
        ;;
    delete)
        rm -f "$state_file"
        ;;
esac
EOF
cat > "$FAKE_BIN/pgrep" <<'EOF'
#!/bin/bash
if [ -n "${VISUALHUD_TEST_PGREP_STATUS:-}" ]; then
    status="$VISUALHUD_TEST_PGREP_STATUS"
else
    [ "${VISUALHUD_TEST_ITERM_RUNNING:-0}" = "1" ] && status=0 || status=1
fi
if [ "$status" = "0" ]; then
    printf '%s\n' "${VISUALHUD_TEST_PGREP_PID:-4242}"
fi
exit "$status"
EOF
chmod +x "$FAKE_BIN/defaults" "$FAKE_BIN/pgrep"
export HOME="$TEST_HOME"
export PATH="$FAKE_BIN:$PATH"
export VISUALHUD_TEST_DEFAULTS_LOG="$DEFAULTS_LOG"
export VISUALHUD_TEST_DEFAULTS_STATE="$TMP_ROOT/defaults-state"

hook_registered() {
    local hooks_json="$1" event="$2" needle="$3"
    node - "$hooks_json" "$event" "$needle" <<'JS'
const fs = require("fs");
const [, , hooksJson, event, needle] = process.argv;
const data = JSON.parse(fs.readFileSync(hooksJson, "utf8"));
const groups = (data.hooks && data.hooks[event]) || [];
const found = groups.some((group) =>
  (group.hooks || []).some((hook) => String(hook.command || "").includes(needle)),
);
console.log(found ? "true" : "false");
JS
}

hook_command_registered() {
    local hooks_json="$1" event="$2" command="$3"
    node - "$hooks_json" "$event" "$command" <<'JS'
const fs = require("fs");
const [, , hooksJson, event, command] = process.argv;
const data = JSON.parse(fs.readFileSync(hooksJson, "utf8"));
const groups = (data.hooks && data.hooks[event]) || [];
const found = groups.some((group) =>
  (group.hooks || []).some((hook) => String(hook.command || "") === command),
);
console.log(found ? "true" : "false");
JS
}

hook_count() {
    local hooks_json="$1" event="$2" needle="$3"
    node - "$hooks_json" "$event" "$needle" <<'JS'
const fs = require("fs");
const [, , hooksJson, event, needle] = process.argv;
const data = JSON.parse(fs.readFileSync(hooksJson, "utf8"));
const groups = (data.hooks && data.hooks[event]) || [];
let count = 0;
for (const group of groups) {
  for (const hook of group.hooks || []) {
    if (String(hook.command || "").includes(needle)) count += 1;
  }
}
console.log(String(count));
JS
}

echo "=== Test Suite: visualhud install ==="
echo ""

echo "--- Test 1: Bare CLI installs Codex hooks in the current repo ---"
target="$(make_repo bare-current-repo)"
pushd "$target" >/dev/null
output="$("$CLI" --platform macos 2>&1)"
popd >/dev/null
assert_contains "Bare install reports target" "Installed VisualHUD Codex hooks in:" "$output"
assert_file_exists "Bare install writes Codex hooks" "$target/.codex/hooks.json"
assert_file_exists "Bare install writes runtime CLI" "$target/.visualhud/visualhud"
assert_file_exists "Bare install writes iTerm2 setup helper" "$target/.visualhud/setup-iterm2.sh"
assert_eq "Bare install defaults to Pokemon" "pokemon" "$(cat "$target/.visualhud/theme")"
"$target/.visualhud/setup-iterm2.sh" --reset >/dev/null
echo ""

echo "--- Test 2: Codex macOS install creates a repo-local VisualHUD runtime ---"
target="$(make_repo mac-codex)"
output="$(TERM_PROGRAM='' ITERM_SESSION_ID='' "$CLI" install codex --target "$target" --platform macos 2>&1)"
assert_contains "Install reports target" "Installed VisualHUD Codex hooks in:" "$output"
assert_contains "Install reports active theme" "Active theme: pokemon" "$output"
assert_contains "Install reports runtime phase" "[ok] repo runtime installed" "$output"
assert_contains "Install reports hooks phase" "[ok] Codex hooks installed" "$output"
assert_contains "Install applies the iTerm2 helper" "[ok] iTerm2 platform helper applied" "$output"
assert_contains "Install reports restart state" "[ok] iTerm2 restart not currently required" "$output"
assert_contains "Fresh install requires a new Codex session" "[restart required] Reopen Codex to load hooks and skills" "$output"
assert_contains "Fresh install gives the exact Codex action" "Next: exit this Codex session, then run: codex --yolo" "$output"
assert_contains "Install writes iTerm2 preferences through the helper" "write com.googlecode.iterm2 EnableAPIServer -bool true" "$(cat "$DEFAULTS_LOG")"
assert_file_exists "Install writes the iTerm2 dynamic profile" "$TEST_HOME/Library/Application Support/iTerm2/DynamicProfiles/visualhud-profile.json"
assert_file_exists "Fresh install records pending Codex discovery" "$target/.visualhud/codex-restart-required"
assert_file_exists "Target Codex hook wrapper exists" "$target/.codex/hooks/visualhud-codex.sh"
assert_executable "Target Codex hook wrapper is executable" "$target/.codex/hooks/visualhud-codex.sh"
assert_file_exists "Target Codex hooks.json exists" "$target/.codex/hooks.json"
assert_file_exists "Runtime engine is copied" "$target/.visualhud/engine.sh"
assert_file_exists "Runtime background helper is copied" "$target/.visualhud/set_bg.py"
assert_file_exists "Runtime CLI is copied" "$target/.visualhud/visualhud"
assert_file_exists "Runtime iTerm2 setup helper is copied" "$target/.visualhud/setup-iterm2.sh"
assert_file_exists "Pokemon ships in installed runtime" "$target/.visualhud/themes/pokemon/theme.json"
assert_file_exists "Pokemon Charmander sprite ships in installed runtime" "$target/.visualhud/themes/pokemon/sprites/charmander.png"
assert_file_exists "Pokemon Blastoise sprite ships in installed runtime" "$target/.visualhud/themes/pokemon/sprites/blastoise.png"
assert_file_exists "TMNT ships in installed runtime" "$target/.visualhud/themes/tmnt/theme.json"
assert_file_exists "TMNT sprite pack ships in installed runtime" "$target/.visualhud/themes/tmnt/sprites/tmnt-leonardo.png"
assert_eq "Installed active theme defaults to Pokemon" "pokemon" "$(cat "$target/.visualhud/theme")"
assert_eq "Installed runtime CLI reads active theme" "pokemon" "$("$target/.visualhud/visualhud" theme current)"
assert_file_exists "Setup skill is installed for Codex discovery" "$target/.agents/skills/visualhud-setup/SKILL.md"
assert_file_exists "Update skill is installed for Codex discovery" "$target/.agents/skills/visualhud-update/SKILL.md"
assert_file_exists "Theme skill is installed for Codex discovery" "$target/.agents/skills/visualhud-theme/SKILL.md"
assert_file_exists "Feedback skill is installed for Codex discovery" "$target/.agents/skills/visualhud-feedback/SKILL.md"
assert_contains "Setup skill points at installed runtime CLI" ".visualhud/visualhud install codex" "$(cat "$target/.agents/skills/visualhud-setup/SKILL.md")"
assert_contains "Theme skill points at installed runtime CLI" ".visualhud/visualhud theme set" "$(cat "$target/.agents/skills/visualhud-theme/SKILL.md")"
assert_eq "PreToolUse hook registered" "true" "$(hook_registered "$target/.codex/hooks.json" "PreToolUse" "visualhud-codex.sh")"
assert_eq "PermissionRequest hook registered" "true" "$(hook_registered "$target/.codex/hooks.json" "PermissionRequest" "visualhud-codex.sh")"
assert_eq "UserPromptSubmit hook registered" "true" "$(hook_registered "$target/.codex/hooks.json" "UserPromptSubmit" "visualhud-codex.sh")"
assert_eq "Stop hook registered" "true" "$(hook_registered "$target/.codex/hooks.json" "Stop" "visualhud-codex.sh")"
assert_eq "PostToolUse hook registered" "true" "$(hook_registered "$target/.codex/hooks.json" "PostToolUse" "visualhud-codex.sh")"
assert_eq "SessionStart hook registered" "true" "$(hook_registered "$target/.codex/hooks.json" "SessionStart" "visualhud-codex.sh")"
assert_eq "Unsupported TaskCompleted hook is absent" "false" "$(hook_registered "$target/.codex/hooks.json" "TaskCompleted" "visualhud-codex.sh")"
assert_eq "Unsupported CwdChanged hook is absent" "false" "$(hook_registered "$target/.codex/hooks.json" "CwdChanged" "visualhud-codex.sh")"
assert_eq "PreCompact hook registered" "true" "$(hook_registered "$target/.codex/hooks.json" "PreCompact" "visualhud-codex.sh")"
assert_eq "PostCompact hook registered" "true" "$(hook_registered "$target/.codex/hooks.json" "PostCompact" "visualhud-codex.sh")"
assert_eq "SubagentStart hook registered" "true" "$(hook_registered "$target/.codex/hooks.json" "SubagentStart" "visualhud-codex.sh")"
assert_eq "SubagentStop hook registered" "true" "$(hook_registered "$target/.codex/hooks.json" "SubagentStop" "visualhud-codex.sh")"
assert_eq "Unsupported PostToolUseFailure hook is absent" "false" "$(hook_registered "$target/.codex/hooks.json" "PostToolUseFailure" "visualhud-codex.sh")"

doctor_capture="$TMP_ROOT/install-doctor.capture"
doctor_state="$TMP_ROOT/install-doctor-state"
set +e
doctor_restart_output="$(VISUALHUD_TTY="$doctor_capture" VISUALHUD_STATE_DIR="$doctor_state" VISUALHUD_REAPPLY_DELAY=0 \
    "$target/.visualhud/visualhud" doctor 2>&1)"
doctor_restart_status=$?
set -e
assert_eq "Doctor remains healthy while Codex restart is pending" "0" "$doctor_restart_status"
assert_contains "Doctor reports the pending Codex phase" "[restart required] Reopen Codex to load hooks and skills" "$doctor_restart_output"
assert_contains "Doctor reports the exact Codex next action" "Next: exit this Codex session, then run: codex --yolo" "$doctor_restart_output"

(cd "$target" && printf '%s' '{"hook_event_name":"SessionStart","source":"startup","session_id":"new-codex-session"}' | \
    VISUALHUD_TTY=/dev/null VISUALHUD_BG=off VISUALHUD_REAPPLY_DELAY=0 bash .codex/hooks/visualhud-codex.sh)
assert_file_not_exists "A new Codex SessionStart clears the discovery marker" "$target/.visualhud/codex-restart-required"

jq -c . "$target/.codex/hooks.json" > "$target/.codex/hooks.json.tmp"
mv "$target/.codex/hooks.json.tmp" "$target/.codex/hooks.json"
reinstall_output="$(TERM_PROGRAM='' ITERM_SESSION_ID='' "$CLI" install codex --target "$target" --platform macos 2>&1)"
assert_contains "Idempotent reinstall applies on the next hook" "[ok] Codex restart not required; runtime and theme apply on the next hook" "$reinstall_output"
assert_contains "Unchanged iTerm preferences need no terminal restart" "[ok] iTerm2 preferences already current; terminal restart not required" "$reinstall_output"
assert_not_contains "No-restart output does not ask to reopen Codex" "[restart required] Reopen Codex" "$reinstall_output"
assert_not_contains "No-restart output does not ask to restart iTerm2" "restart iTerm2 later" "$reinstall_output"
assert_not_contains "No-restart output does not contradict its current-pane action" "Then start Codex" "$reinstall_output"
profile_engine="$TMP_ROOT/profile-engine.sh"
profile_log="$TMP_ROOT/profile.log"
cat > "$profile_engine" <<'SH'
#!/bin/bash
cat >/dev/null
printf '%s\n' "${VISUALHUD_JOURNEY_PROFILE:-}" >> "$VISUALHUD_TEST_PROFILE_LOG"
SH
chmod +x "$profile_engine"
cp "$profile_engine" "$target/.visualhud/engine.sh"
unset VISUALHUD_JOURNEY_PROFILE
(cd "$target" && printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Read"}' | \
    VISUALHUD_TEST_PROFILE_LOG="$profile_log" bash .codex/hooks/visualhud-codex.sh)
assert_eq "Installed wrapper gives a plain Codex repo the coarse journey" "codex-default" "$(tail -n 1 "$profile_log")"
mkdir -p "$target/.agents/skills/sdlc"
touch "$target/.agents/skills/sdlc/SKILL.md"
(cd "$target" && printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Read"}' | \
    VISUALHUD_TEST_PROFILE_LOG="$profile_log" bash .codex/hooks/visualhud-codex.sh)
assert_eq "Installed wrapper selects the richer journey from SDLC evidence" "sdlc" "$(tail -n 1 "$profile_log")"

dynamic_source="$TMP_ROOT/dynamic-skill-source"
dynamic_target="$(make_repo dynamic-skill-target)"
mkdir -p "$dynamic_source/.codex"
cp "$ROOT_DIR/visualhud" "$ROOT_DIR/engine.sh" "$ROOT_DIR/set_bg.py" \
    "$ROOT_DIR/setup-iterm2.sh" "$ROOT_DIR/setup-wezterm.ps1" "$dynamic_source/"
cp -R "$ROOT_DIR/.codex/hooks" "$dynamic_source/.codex/hooks"
cp -R "$ROOT_DIR/themes" "$ROOT_DIR/scripts" "$ROOT_DIR/wezterm" "$ROOT_DIR/skills" "$dynamic_source/"
"$dynamic_source/visualhud" install codex --target "$dynamic_target" --platform windows >/dev/null
(cd "$dynamic_target" && printf '%s' '{"hook_event_name":"SessionStart","source":"startup","session_id":"dynamic-session"}' | \
    VISUALHUD_TTY=/dev/null VISUALHUD_BG=off VISUALHUD_REAPPLY_DELAY=0 bash .codex/hooks/visualhud-codex.sh)
mkdir -p "$dynamic_source/skills/visualhud-extra"
printf '%s\n' '---' 'name: visualhud-extra' '---' '# Extra VisualHUD skill' > "$dynamic_source/skills/visualhud-extra/SKILL.md"
dynamic_output="$("$dynamic_source/visualhud" install codex --target "$dynamic_target" --platform windows 2>&1)"
assert_file_exists "A newly added VisualHUD skill is installed" "$dynamic_target/.agents/skills/visualhud-extra/SKILL.md"
assert_contains "A newly added VisualHUD skill requires Codex discovery" "[restart required] Reopen Codex to load hooks and skills" "$dynamic_output"

self_source="$TMP_ROOT/self-install-source"
mkdir -p "$self_source/.codex"
cp "$ROOT_DIR/visualhud" "$ROOT_DIR/engine.sh" "$ROOT_DIR/set_bg.py" \
    "$ROOT_DIR/setup-iterm2.sh" "$ROOT_DIR/setup-wezterm.ps1" "$ROOT_DIR/package.json" "$self_source/"
cp -R "$ROOT_DIR/.codex/hooks" "$self_source/.codex/hooks"
cp -R "$ROOT_DIR/themes" "$ROOT_DIR/scripts" "$ROOT_DIR/wezterm" "$ROOT_DIR/skills" "$self_source/"
git -C "$self_source" init -q
git -C "$self_source" add .codex/hooks/visualhud-codex.sh
cp "$self_source/.codex/hooks/visualhud-codex.sh" "$TMP_ROOT/source-adapter.before"
"$self_source/visualhud" install codex --target "$self_source" --platform windows --theme tmnt >/dev/null
assert_eq "Installing from a source checkout preserves its development adapter" \
    "$(shasum -a 256 "$TMP_ROOT/source-adapter.before" | awk '{print $1}')" \
    "$(shasum -a 256 "$self_source/.codex/hooks/visualhud-codex.sh" | awk '{print $1}')"
assert_file_exists "A source self-install still refreshes its repo-local runtime" "$self_source/.visualhud/engine.sh"
assert_eq "A source self-install applies the selected theme to its preserved development adapter" \
    "tmnt" \
    "$("$self_source/visualhud" theme current)"
"$self_source/.visualhud/visualhud" install codex --target "$self_source" --platform windows --theme pokemon >/dev/null
assert_eq "Installed-runtime repair preserves a tracked development adapter" \
    "$(shasum -a 256 "$TMP_ROOT/source-adapter.before" | awk '{print $1}')" \
    "$(shasum -a 256 "$self_source/.codex/hooks/visualhud-codex.sh" | awk '{print $1}')"
assert_eq "Installed-runtime repair applies its selected source theme" \
    "pokemon" \
    "$("$self_source/visualhud" theme current)"
echo ""

echo "--- Test 3: Codex install preserves existing hooks and is idempotent ---"
target="$(make_repo existing-hooks)"
mkdir -p "$target/.codex" "$target/.agents/skills/existing-skill"
cat > "$target/.codex/hooks.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "^Bash$",
        "hooks": [
          {
            "type": "command",
            "command": "bash .codex/hooks/existing.sh"
          }
        ]
      }
    ],
    "TaskCompleted": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$(git rev-parse --show-toplevel)/.codex/hooks/visualhud-codex.sh\""
          },
          {
            "type": "command",
            "command": "bash .codex/hooks/existing-task-hook.sh"
          }
        ]
      }
    ]
  }
}
JSON
printf -- '---\nname: existing-skill\ndescription: keep me\n---\n' > "$target/.agents/skills/existing-skill/SKILL.md"
"$CLI" install codex --target "$target" --platform macos --theme pokemon >/dev/null
"$CLI" install codex --target "$target" --platform macos --theme pokemon >/dev/null
assert_eq "Existing hook is preserved" "true" "$(hook_command_registered "$target/.codex/hooks.json" "PreToolUse" "bash .codex/hooks/existing.sh")"
assert_eq "VisualHUD hook is not duplicated" "1" "$(hook_count "$target/.codex/hooks.json" "PreToolUse" "visualhud-codex.sh")"
assert_eq "PostToolUse hook is not duplicated" "1" "$(hook_count "$target/.codex/hooks.json" "PostToolUse" "visualhud-codex.sh")"
assert_eq "Legacy unsupported VisualHUD hook is removed" "0" "$(hook_count "$target/.codex/hooks.json" "TaskCompleted" "visualhud-codex.sh")"
assert_eq "Unrelated unsupported-event hook is preserved" "true" "$(hook_command_registered "$target/.codex/hooks.json" "TaskCompleted" "bash .codex/hooks/existing-task-hook.sh")"
assert_eq "Reinstall can switch active theme" "pokemon" "$(cat "$target/.visualhud/theme")"
assert_file_exists "Existing repo skill is preserved" "$target/.agents/skills/existing-skill/SKILL.md"
"$target/.visualhud/visualhud" install codex --target "$target" --platform macos --theme tmnt >/dev/null
assert_file_exists "Installed runtime self-repair keeps Pokemon sprites" "$target/.visualhud/themes/pokemon/sprites/charmander.png"
assert_file_exists "Installed runtime self-repair keeps VisualHUD skills" "$target/.agents/skills/visualhud-update/SKILL.md"
assert_eq "Installed runtime self-repair can switch theme" "tmnt" "$(cat "$target/.visualhud/theme")"
echo ""

echo "--- Test 3a: macOS setup stays non-disruptive and reports blockers ---"
target="$(make_repo mac-running)"
set +e
running_output="$(HOME="$TMP_ROOT/home-running" VISUALHUD_TEST_DEFAULTS_STATE="$TMP_ROOT/state-running" \
    TERM_PROGRAM='' ITERM_SESSION_ID='' VISUALHUD_TEST_ITERM_RUNNING=1 \
    "$CLI" install codex --target "$target" --platform macos 2>&1)"
running_status=$?
set -e
assert_eq "Running iTerm2 does not block repo installation" "0" "$running_status"
assert_contains "Running iTerm2 reports deferred visual refresh" "[pending] iTerm2 restart later to refresh terminal visuals" "$running_output"
assert_not_contains "Running iTerm2 never prompts to quit" "Continue anyway?" "$running_output"
assert_file_exists "Changed terminal preferences record a restart-later phase" "$target/.visualhud/iterm2-setup-status"

running_repeat_output="$(HOME="$TMP_ROOT/home-running" VISUALHUD_TEST_DEFAULTS_STATE="$TMP_ROOT/state-running" \
    TERM_PROGRAM='' ITERM_SESSION_ID='' VISUALHUD_TEST_ITERM_RUNNING=1 \
    "$CLI" install codex --target "$target" --platform macos 2>&1)"
assert_contains "Repeated setup preserves a pending terminal restart" "[pending] iTerm2 restart later to refresh terminal visuals" "$running_repeat_output"
assert_eq "Repeated setup preserves the originating iTerm2 process" "restart-required:4242" "$(cat "$target/.visualhud/iterm2-setup-status")"

running_doctor_capture="$TMP_ROOT/running-doctor.capture"
running_doctor_state="$TMP_ROOT/running-doctor-state"
running_doctor_output="$(VISUALHUD_TEST_ITERM_RUNNING=1 VISUALHUD_TEST_PGREP_PID=4343 \
    VISUALHUD_TTY="$running_doctor_capture" VISUALHUD_STATE_DIR="$running_doctor_state" VISUALHUD_REAPPLY_DELAY=0 \
    "$target/.visualhud/visualhud" doctor 2>&1)"
assert_contains "Doctor recognizes a replacement iTerm2 process" "[ok] Terminal restart not required" "$running_doctor_output"
assert_eq "Doctor records terminal readiness after a replacement process" "ready" "$(cat "$target/.visualhud/iterm2-setup-status")"

for unresolved_status in restart-required restart-unknown; do
    printf '%s\n' "$unresolved_status" > "$target/.visualhud/iterm2-setup-status"
    stopped_doctor_output="$(TERM_PROGRAM='' ITERM_SESSION_ID='' VISUALHUD_TEST_ITERM_RUNNING=0 \
        VISUALHUD_TTY="$running_doctor_capture" VISUALHUD_STATE_DIR="$running_doctor_state" VISUALHUD_REAPPLY_DELAY=0 \
        "$target/.visualhud/visualhud" doctor 2>&1)"
    assert_contains "Doctor clears $unresolved_status when iTerm2 is stopped" "[ok] Terminal restart not required" "$stopped_doctor_output"
    assert_eq "Doctor records readiness after $unresolved_status" "ready" "$(cat "$target/.visualhud/iterm2-setup-status")"
done
printf 'ready\n' > "$target/.visualhud/iterm2-setup-status"

running_restarted_output="$(HOME="$TMP_ROOT/home-running" VISUALHUD_TEST_DEFAULTS_STATE="$TMP_ROOT/state-running" \
    TERM_PROGRAM='' ITERM_SESSION_ID='' VISUALHUD_TEST_ITERM_RUNNING=1 VISUALHUD_TEST_PGREP_PID=4343 \
    "$CLI" install codex --target "$target" --platform macos 2>&1)"
assert_contains "A different iTerm2 process clears the pending restart" "[ok] iTerm2 preferences already current; terminal restart not required" "$running_restarted_output"
assert_eq "A different iTerm2 process records terminal readiness" "ready" "$(cat "$target/.visualhud/iterm2-setup-status")"

target="$(make_repo mac-term-program-detected)"
term_program_output="$(HOME="$TMP_ROOT/home-term" VISUALHUD_TEST_DEFAULTS_STATE="$TMP_ROOT/state-term" \
    TERM_PROGRAM=iTerm.app ITERM_SESSION_ID='' VISUALHUD_TEST_PGREP_STATUS=3 \
    "$CLI" install codex --target "$target" --platform macos 2>&1)"
assert_contains "TERM_PROGRAM survives a denied process probe" "[pending] iTerm2 restart later to refresh terminal visuals" "$term_program_output"
assert_not_contains "TERM_PROGRAM fallback does not report a settings failure" "[blocked] iTerm2 settings could not be written" "$term_program_output"

target="$(make_repo mac-session-detected)"
session_output="$(HOME="$TMP_ROOT/home-session" VISUALHUD_TEST_DEFAULTS_STATE="$TMP_ROOT/state-session" \
    TERM_PROGRAM='' ITERM_SESSION_ID=visualhud-test VISUALHUD_TEST_PGREP_STATUS=3 \
    "$CLI" install codex --target "$target" --platform macos 2>&1)"
assert_contains "ITERM_SESSION_ID survives a denied process probe" "[pending] iTerm2 restart later to refresh terminal visuals" "$session_output"
assert_not_contains "ITERM_SESSION_ID fallback does not report a settings failure" "[blocked] iTerm2 settings could not be written" "$session_output"

target="$(make_repo mac-process-unknown)"
unknown_output="$(HOME="$TMP_ROOT/home-unknown" VISUALHUD_TEST_DEFAULTS_STATE="$TMP_ROOT/state-unknown" \
    TERM_PROGRAM='' ITERM_SESSION_ID='' VISUALHUD_TEST_PGREP_STATUS=3 \
    "$CLI" install codex --target "$target" --platform macos 2>&1)"
assert_contains "Denied process inspection reports an honest pending state" "[pending] iTerm2 process status unavailable" "$unknown_output"
assert_not_contains "Denied process inspection does not report a settings failure" "[blocked] iTerm2 settings could not be written" "$unknown_output"

target="$(make_repo mac-helper-blocked)"
set +e
blocked_output="$(VISUALHUD_TEST_DEFAULTS_FAIL=1 "$CLI" install codex --target "$target" --platform macos 2>&1)"
blocked_status=$?
set -e
assert_eq "A failed platform helper marks setup blocked" "1" "$blocked_status"
assert_contains "Blocked setup preserves the runtime phase" "[ok] repo runtime installed" "$blocked_output"
assert_contains "Blocked setup preserves the hooks phase" "[ok] Codex hooks installed" "$blocked_output"
assert_contains "Blocked setup reports the helper phase" "[blocked] iTerm2 platform helper" "$blocked_output"
assert_contains "Blocked setup includes the helper failure reason" "iTerm2 settings could not be written" "$blocked_output"
assert_file_exists "Blocked platform setup still installs Codex hooks" "$target/.codex/hooks.json"

reset_status="$TMP_ROOT/reset-status"
reset_output="$(TERM_PROGRAM='' ITERM_SESSION_ID='' VISUALHUD_TEST_ITERM_RUNNING=0 VISUALHUD_TEST_DEFAULTS_FAIL=0 \
    VISUALHUD_SETUP_STATUS_FILE="$reset_status" "$target/.visualhud/setup-iterm2.sh" --reset 2>&1)"
assert_contains "Reset while iTerm2 is closed needs no terminal restart" "[ok] iTerm2 restart not currently required" "$reset_output"
assert_eq "Reset while iTerm2 is closed records terminal readiness" "ready" "$(cat "$reset_status")"
assert_eq "Reset removes the VisualHUD dynamic profile" "absent" "$([ ! -e "$TEST_HOME/Library/Application Support/iTerm2/DynamicProfiles/visualhud-profile.json" ] && printf absent || printf present)"

VISUALHUD_SETUP_STATUS_FILE="$reset_status" TERM_PROGRAM='' ITERM_SESSION_ID='' VISUALHUD_TEST_ITERM_RUNNING=0 \
    "$target/.visualhud/setup-iterm2.sh" >/dev/null
running_reset_output="$(VISUALHUD_SETUP_STATUS_FILE="$reset_status" TERM_PROGRAM='' ITERM_SESSION_ID='' \
    VISUALHUD_TEST_ITERM_RUNNING=1 VISUALHUD_TEST_PGREP_PID=5151 \
    "$target/.visualhud/setup-iterm2.sh" --reset 2>&1)"
assert_contains "Reset while iTerm2 is open defers the visual refresh" "[pending] iTerm2 restart later to refresh terminal visuals" "$running_reset_output"
assert_eq "Reset records the originating iTerm2 process" "restart-required:5151" "$(cat "$reset_status")"
repeat_reset_output="$(VISUALHUD_SETUP_STATUS_FILE="$reset_status" TERM_PROGRAM='' ITERM_SESSION_ID='' \
    VISUALHUD_TEST_ITERM_RUNNING=1 VISUALHUD_TEST_PGREP_PID=5151 \
    "$target/.visualhud/setup-iterm2.sh" --reset 2>&1)"
assert_contains "Idempotent reset preserves a pending terminal restart" "[pending] iTerm2 restart later to refresh terminal visuals" "$repeat_reset_output"

reset_failure_status="$TMP_ROOT/reset-failure-status"
set +e
reset_failure_output="$(VISUALHUD_SETUP_STATUS_FILE="$reset_failure_status" VISUALHUD_TEST_DEFAULTS_FAIL=1 \
    "$target/.visualhud/setup-iterm2.sh" --reset 2>&1)"
reset_failure_exit=$?
set -e
assert_eq "A failed reset exits nonzero" "1" "$reset_failure_exit"
assert_eq "A failed reset records a blocked status" "blocked:1" "$(cat "$reset_failure_status" 2>/dev/null || true)"
assert_contains "A failed reset explains the blocker" "[blocked] iTerm2 settings could not be written" "$reset_failure_output"
echo ""

echo "--- Test 3b: Claude install wires repo-local Claude hooks and runtime ---"
target="$(make_repo mac-claude)"
output="$("$CLI" install claude --target "$target" --platform macos 2>&1)"
assert_contains "Claude install reports target" "Installed VisualHUD Claude hooks in:" "$output"
assert_contains "Claude install reports active theme" "Active theme: pokemon" "$output"
assert_file_exists "Claude hook wrapper exists" "$target/.claude/hooks/visualhud-claude.sh"
assert_executable "Claude hook wrapper is executable" "$target/.claude/hooks/visualhud-claude.sh"
assert_file_exists "Claude settings.json exists" "$target/.claude/settings.json"
assert_file_exists "Claude runtime engine copied" "$target/.visualhud/engine.sh"
assert_file_exists "Claude runtime CLI copied" "$target/.visualhud/visualhud"
assert_file_exists "Pokemon theme ships in Claude runtime" "$target/.visualhud/themes/pokemon/theme.json"
assert_eq "Claude install defaults to Pokemon" "pokemon" "$(cat "$target/.visualhud/theme")"
assert_eq "Claude PreToolUse VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.PreToolUse[]?.hooks[]?; .command | contains("visualhud-claude.sh"))' "$target/.claude/settings.json")"
assert_eq "Claude Notification VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.Notification[]?.hooks[]?; .command | contains("visualhud-claude.sh"))' "$target/.claude/settings.json")"
assert_eq "Claude UserPromptSubmit VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.UserPromptSubmit[]?.hooks[]?; .command | contains("visualhud-claude.sh"))' "$target/.claude/settings.json")"
assert_eq "Claude Stop VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.Stop[]?.hooks[]?; .command | contains("visualhud-claude.sh"))' "$target/.claude/settings.json")"
assert_eq "Claude StopFailure VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.StopFailure[]?.hooks[]?; .command | contains("visualhud-claude.sh"))' "$target/.claude/settings.json")"
assert_eq "Claude TaskCompleted VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.TaskCompleted[]?.hooks[]?; .command | contains("visualhud-claude.sh"))' "$target/.claude/settings.json")"
assert_eq "Claude CwdChanged VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.CwdChanged[]?.hooks[]?; .command | contains("visualhud-claude.sh"))' "$target/.claude/settings.json")"
assert_eq "Claude SessionStart VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.SessionStart[]?.hooks[]?; .command | contains("visualhud-claude.sh"))' "$target/.claude/settings.json")"
assert_eq "Claude PreCompact VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.PreCompact[]?.hooks[]?; .command | contains("visualhud-claude.sh"))' "$target/.claude/settings.json")"
assert_eq "Claude PostCompact VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.PostCompact[]?.hooks[]?; .command | contains("visualhud-claude.sh"))' "$target/.claude/settings.json")"
assert_eq "Claude SubagentStart VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.SubagentStart[]?.hooks[]?; .command | contains("visualhud-claude.sh"))' "$target/.claude/settings.json")"
assert_eq "Claude SubagentStop VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.SubagentStop[]?.hooks[]?; .command | contains("visualhud-claude.sh"))' "$target/.claude/settings.json")"
assert_eq "Claude PostToolUseFailure VisualHUD hook registered" "true" "$(jq -r 'any(.hooks.PostToolUseFailure[]?.hooks[]?; .command | contains("visualhud-claude.sh"))' "$target/.claude/settings.json")"
echo ""

echo "--- Test 3c: Claude install preserves existing hooks + is idempotent ---"
target="$(make_repo claude-existing)"
mkdir -p "$target/.claude"
cat > "$target/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "bash .claude/hooks/existing-sdlc.sh" } ] }
    ],
    "PreToolUse": [
      { "matcher": "^Bash$", "hooks": [ { "type": "command", "command": "bash .claude/hooks/existing-tdd.sh" } ] }
    ]
  }
}
JSON
"$CLI" install claude --target "$target" --platform macos --theme tmnt >/dev/null
"$CLI" install claude --target "$target" --platform macos --theme tmnt >/dev/null
assert_eq "Claude install preserves existing SDLC hook" "true" "$(jq -r 'any(.hooks.UserPromptSubmit[]?.hooks[]?; .command == "bash .claude/hooks/existing-sdlc.sh")' "$target/.claude/settings.json")"
assert_eq "Claude install preserves existing TDD hook" "true" "$(jq -r 'any(.hooks.PreToolUse[]?.hooks[]?; .command == "bash .claude/hooks/existing-tdd.sh")' "$target/.claude/settings.json")"
assert_eq "Claude VisualHUD UserPromptSubmit hook not duplicated" "1" "$(jq -r '[.hooks.UserPromptSubmit[]?.hooks[]? | select(.command | contains("visualhud-claude.sh"))] | length' "$target/.claude/settings.json")"
assert_eq "Claude VisualHUD Stop hook not duplicated" "1" "$(jq -r '[.hooks.Stop[]?.hooks[]? | select(.command | contains("visualhud-claude.sh"))] | length' "$target/.claude/settings.json")"
assert_eq "Claude install can switch active theme" "tmnt" "$(cat "$target/.visualhud/theme")"
echo ""

echo "--- Test 3d: Claude install rejects unsupported platforms ---"
target="$(make_repo claude-windows)"
set +e
win_output="$("$CLI" install claude --target "$target" --platform windows 2>&1)"
win_status=$?
set -e
assert_eq "Claude Windows install exits nonzero" "1" "$win_status"
assert_contains "Claude Windows install explains gap" "Windows" "$win_output"
echo ""

echo "--- Test 3e: Claude PreToolUse hook is hardened against parse-time failures ---"
target="$(make_repo claude-harden)"
"$CLI" install claude --target "$target" --platform macos --theme pokemon >/dev/null
pretoolcmd=$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.command | contains("visualhud-claude.sh")) | .command] | first' "$target/.claude/settings.json")
assert_contains "Hardened PreToolUse command wraps in bash -c" "bash -c" "$pretoolcmd"
assert_contains "Hardened PreToolUse command has '|| true' safety net" "|| true" "$pretoolcmd"
echo ""

echo "--- Test 3f: hardened wrapper survives a corrupted hook script ---"
broken="$TMP_ROOT/broken-hook-$$.sh"
cat > "$broken" <<'EOF'
#!/bin/bash
<<<<<<< HEAD
echo a
=======
echo b
>>>>>>> branch
EOF
chmod +x "$broken"
set +e
bash "$broken" >/dev/null 2>&1
direct_exit=$?
bash -c "bash \"$broken\" 2>/dev/null || true"
wrapped_exit=$?
set -e
TOTAL=$((TOTAL + 1))
if [ "$direct_exit" -ne 0 ]; then
    PASS=$((PASS + 1))
    printf "  PASS: corrupt hook exits non-zero when called directly (exit %d)\n" "$direct_exit"
else
    FAIL=$((FAIL + 1))
    printf "  FAIL: corrupt hook should fail directly to establish baseline\n"
fi
assert_eq "hardened wrapper exits 0 despite corrupt hook" "0" "$wrapped_exit"
rm -f "$broken"
echo ""

echo "--- Test 4: Windows Codex install writes the status renderer ---"
target="$(make_repo windows-codex)"
set +e
windows_output="$("$CLI" install codex --target "$target" --platform windows --theme tmnt 2>&1)"
windows_status=$?
set -e
assert_eq "Windows install exits zero" "0" "$windows_status"
assert_contains "Windows install reports renderer" "Renderer: Windows Terminal/PowerShell" "$windows_output"
assert_contains "Windows install points to WezTerm renderer for richer visuals" "--platform wezterm" "$windows_output"
assert_contains "Windows install points to WezTerm setup helper" "setup-wezterm.ps1" "$windows_output"
assert_file_exists "Windows install writes hooks" "$target/.codex/hooks.json"
assert_contains "Windows wrapper pins renderer" 'VISUALHUD_RENDERER="windows"' "$(cat "$target/.codex/hooks/visualhud-codex.sh")"
echo ""

echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
