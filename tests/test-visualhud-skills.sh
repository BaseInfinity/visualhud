#!/bin/bash
# Contract tests for the packaged VisualHUD Codex skills.

set -euo pipefail

PASS=0
FAIL=0
TOTAL=0

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$ROOT_DIR/skills"
AGENT_SKILLS_DIR="$ROOT_DIR/.agents/skills"

pass() {
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    printf "  FAIL: %s\n" "$1"
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

skill_doc() {
    local skill="$1"
    cat "$SKILLS_DIR/$skill/SKILL.md"
}

echo "=== Test Suite: visualhud skills ==="
echo ""

echo "--- Test 1: Four Codex skills are packaged ---"
for skill in visualhud-setup visualhud-update visualhud-theme visualhud-feedback; do
    assert_file_exists "$skill has SKILL.md" "$SKILLS_DIR/$skill/SKILL.md"
done
echo ""

echo "--- Test 2: Source checkout exposes VisualHUD skills to Codex ---"
for skill in visualhud-setup visualhud-update visualhud-theme visualhud-feedback; do
    assert_file_exists "repo exposes \$$skill skill" "$AGENT_SKILLS_DIR/$skill/SKILL.md"
    TOTAL=$((TOTAL + 1))
    if [ ! -L "$AGENT_SKILLS_DIR/$skill/SKILL.md" ]; then
        pass "repo \$$skill uses a real SKILL.md file"
    else
        fail "repo \$$skill uses a real SKILL.md file"
    fi
    TOTAL=$((TOTAL + 1))
    if cmp -s "$SKILLS_DIR/$skill/SKILL.md" "$AGENT_SKILLS_DIR/$skill/SKILL.md"; then
        pass "repo \$$skill mirrors packaged skill"
    else
        fail "repo \$$skill mirrors packaged skill"
    fi
done
echo ""

echo "--- Test 3: Skills route to the repo-local VisualHUD runtime ---"
README_DOC="$(cat "$ROOT_DIR/README.md")"
TESTING_DOC="$(cat "$ROOT_DIR/TESTING.md")"
SETUP_DOC="$(skill_doc visualhud-setup 2>/dev/null || true)"
UPDATE_DOC="$(skill_doc visualhud-update 2>/dev/null || true)"
THEME_DOC="$(skill_doc visualhud-theme 2>/dev/null || true)"
FEEDBACK_DOC="$(skill_doc visualhud-feedback 2>/dev/null || true)"

assert_contains "Setup skill installs Codex hooks with bundled CLI" ".visualhud/visualhud install codex --target" "$SETUP_DOC"
assert_contains "Setup skill defaults to Pokemon for clean Mac installs" "--theme pokemon" "$SETUP_DOC"
assert_contains "Setup skill supports WezTerm installs" "--platform wezterm" "$SETUP_DOC"
assert_contains "Setup skill runs WezTerm helper itself" "pwsh -ExecutionPolicy Bypass -File" "$SETUP_DOC"
assert_contains "Setup skill handles existing WezTerm config without user chore" "merge the generated snippet" "$SETUP_DOC"
assert_contains "Setup skill says macOS install applies the helper automatically" "applies setup-iterm2.sh automatically" "$SETUP_DOC"
assert_contains "Setup skill distinguishes restart-later from blocked" "restart-later state" "$SETUP_DOC"
assert_not_contains "Setup skill does not call Windows unsupported" "Windows Terminal/PowerShell renderer is not supported yet" "$SETUP_DOC"
assert_contains "Update skill reruns install idempotently" ".visualhud/visualhud install codex --target" "$UPDATE_DOC"
assert_contains "Update skill preserves local theme selection" ".visualhud/visualhud theme current" "$UPDATE_DOC"
assert_contains "Update skill preserves installed renderer" "VISUALHUD_RENDERER" "$UPDATE_DOC"
assert_contains "Update skill reruns WezTerm helper" "setup-wezterm.ps1" "$UPDATE_DOC"
assert_contains "Theme skill lists themes" ".visualhud/visualhud theme list" "$THEME_DOC"
assert_contains "Theme skill sets themes" ".visualhud/visualhud theme set" "$THEME_DOC"
assert_contains "Theme skill documents calibration" ".visualhud/visualhud theme calibrate" "$THEME_DOC"
assert_contains "Theme skill marks Power Rangers shipped colors-only" "Power Rangers is shipped colors-only" "$THEME_DOC"
assert_not_contains "Theme skill does not park shipped Power Rangers" "Batman, Power Rangers, and Sonic are parked" "$THEME_DOC"
assert_contains "Feedback skill is privacy-first" "Do not scan source code" "$FEEDBACK_DOC"
assert_contains "Feedback skill records issues locally first" ".visualhud/feedback" "$FEEDBACK_DOC"
LEGACY_HOME_MARKER="~"
LEGACY_GLOBAL_HOOKS="$LEGACY_HOME_MARKER/.claude/hooks"
assert_not_contains "Skills do not tell users to run global hooks" "$LEGACY_GLOBAL_HOOKS" "$SETUP_DOC$UPDATE_DOC$THEME_DOC$FEEDBACK_DOC"
assert_contains "README documents installed VisualHUD skills" "visualhud-setup" "$README_DOC"
assert_contains "README says VisualHUD skills run setup helpers" "VisualHUD setup/update skills should run platform setup helpers" "$README_DOC"
assert_contains "README says macOS install applies iTerm2 setup" "automatically applies the copied iTerm2 helper" "$README_DOC"
assert_contains "README documents update skill" "visualhud-update" "$README_DOC"
assert_contains "README documents theme skill" "visualhud-theme" "$README_DOC"
assert_contains "README documents feedback skill" "visualhud-feedback" "$README_DOC"
assert_contains "Testing docs include skill suite test" "test-visualhud-skills" "$TESTING_DOC"
echo ""

echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
