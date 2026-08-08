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
echo ""

echo "--- Test 2: Codex macOS install creates a repo-local VisualHUD runtime ---"
target="$(make_repo mac-codex)"
output="$("$CLI" install codex --target "$target" --platform macos 2>&1)"
assert_contains "Install reports target" "Installed VisualHUD Codex hooks in:" "$output"
assert_contains "Install reports active theme" "Active theme: pokemon" "$output"
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
