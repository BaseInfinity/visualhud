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
assert_eq "PreToolUse hook registered" "true" "$(jq -r 'any(.hooks.PreToolUse[]?.hooks[]?; .command | contains("visualhud-codex.sh"))' "$target/.codex/hooks.json")"
assert_eq "PermissionRequest hook registered" "true" "$(jq -r 'any(.hooks.PermissionRequest[]?.hooks[]?; .command | contains("visualhud-codex.sh"))' "$target/.codex/hooks.json")"
assert_eq "UserPromptSubmit hook registered" "true" "$(jq -r 'any(.hooks.UserPromptSubmit[]?.hooks[]?; .command | contains("visualhud-codex.sh"))' "$target/.codex/hooks.json")"
assert_eq "Stop hook registered" "true" "$(jq -r 'any(.hooks.Stop[]?.hooks[]?; .command | contains("visualhud-codex.sh"))' "$target/.codex/hooks.json")"
assert_eq "TaskCompleted hook registered" "true" "$(jq -r 'any(.hooks.TaskCompleted[]?.hooks[]?; .command | contains("visualhud-codex.sh"))' "$target/.codex/hooks.json")"
assert_eq "SessionStart hook registered" "true" "$(jq -r 'any(.hooks.SessionStart[]?.hooks[]?; .command | contains("visualhud-codex.sh"))' "$target/.codex/hooks.json")"
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
    ]
  }
}
JSON
printf -- '---\nname: existing-skill\ndescription: keep me\n---\n' > "$target/.agents/skills/existing-skill/SKILL.md"
"$CLI" install codex --target "$target" --platform macos --theme pokemon >/dev/null
"$CLI" install codex --target "$target" --platform macos --theme pokemon >/dev/null
assert_eq "Existing hook is preserved" "true" "$(jq -r 'any(.hooks.PreToolUse[]?.hooks[]?; .command == "bash .codex/hooks/existing.sh")' "$target/.codex/hooks.json")"
assert_eq "VisualHUD hook is not duplicated" "1" "$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.command | contains("visualhud-codex.sh"))] | length' "$target/.codex/hooks.json")"
assert_eq "TaskCompleted hook is not duplicated" "1" "$(jq -r '[.hooks.TaskCompleted[]?.hooks[]? | select(.command | contains("visualhud-codex.sh"))] | length' "$target/.codex/hooks.json")"
assert_eq "Reinstall can switch active theme" "pokemon" "$(cat "$target/.visualhud/theme")"
assert_file_exists "Existing repo skill is preserved" "$target/.agents/skills/existing-skill/SKILL.md"
"$target/.visualhud/visualhud" install codex --target "$target" --platform macos --theme tmnt >/dev/null
assert_file_exists "Installed runtime self-repair keeps Pokemon sprites" "$target/.visualhud/themes/pokemon/sprites/charmander.png"
assert_file_exists "Installed runtime self-repair keeps VisualHUD skills" "$target/.agents/skills/visualhud-update/SKILL.md"
assert_eq "Installed runtime self-repair can switch theme" "tmnt" "$(cat "$target/.visualhud/theme")"
echo ""

echo "--- Test 4: Windows Codex install is explicit until a renderer exists ---"
target="$(make_repo windows-codex)"
set +e
windows_output="$("$CLI" install codex --target "$target" --platform windows --theme tmnt 2>&1)"
windows_status=$?
set -e
assert_eq "Windows install exits nonzero" "1" "$windows_status"
assert_contains "Windows install explains renderer gap" "Windows Terminal/PowerShell renderer is not supported yet" "$windows_output"
assert_eq "Windows install does not write hooks" "false" "$(test -f "$target/.codex/hooks.json" && printf true || printf false)"
echo ""

echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
