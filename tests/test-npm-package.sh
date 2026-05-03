#!/bin/bash
# Proves VisualHUD can be installed through an npm/npx consumer path.

set -euo pipefail

PASS=0
FAIL=0
TOTAL=0

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/visualhud-npm.XXXXXX")"

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

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$actual')"
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

assert_file_exists() {
    local label="$1" filepath="$2"
    TOTAL=$((TOTAL + 1))
    if [ -f "$filepath" ]; then
        pass "$label"
    else
        fail "$label (missing file: $filepath)"
    fi
}

echo "=== Test Suite: npm package ==="
echo ""

echo "--- Test 1: package metadata exposes the VisualHUD CLI ---"
README_DOC="$(cat "$ROOT_DIR/README.md")"
RUN_ALL_DOC="$(cat "$ROOT_DIR/tests/run-all.sh" 2>/dev/null || true)"
assert_file_exists "package.json exists" "$ROOT_DIR/package.json"
assert_file_exists "Public release ships a license file" "$ROOT_DIR/LICENSE"
assert_file_exists "Full suite runner exists" "$ROOT_DIR/tests/run-all.sh"
if [ -f "$ROOT_DIR/package.json" ]; then
    assert_eq "Package name is visualhud" "visualhud" "$(jq -r '.name' "$ROOT_DIR/package.json")"
    assert_eq "Package license matches public wizard packages" "MIT" "$(jq -r '.license' "$ROOT_DIR/package.json")"
    assert_eq "Package repository points at public GitHub repo" "git+https://github.com/BaseInfinity/visualhud.git" "$(jq -r '.repository.url' "$ROOT_DIR/package.json")"
    assert_eq "Package bin exposes npm-normalized visualhud command" "visualhud" "$(jq -r '.bin.visualhud' "$ROOT_DIR/package.json")"
    assert_contains "Package files include themes" '"themes"' "$(jq -c '.files' "$ROOT_DIR/package.json")"
    assert_contains "Package files include screenshots" '"docs/screenshots"' "$(jq -c '.files' "$ROOT_DIR/package.json")"
    assert_contains "Package files include skills" '"skills"' "$(jq -c '.files' "$ROOT_DIR/package.json")"
    assert_eq "Package test script runs full suite" "bash tests/run-all.sh" "$(jq -r '.scripts.test' "$ROOT_DIR/package.json")"
    assert_eq "Package exposes package E2E script" "bash tests/test-npm-package.sh" "$(jq -r '.scripts["test:e2e"]' "$ROOT_DIR/package.json")"
    assert_eq "Package publish gate runs tests" "npm test" "$(jq -r '.scripts.prepublishOnly' "$ROOT_DIR/package.json")"
fi
assert_contains "Full suite runner includes lifecycle suite" "tests/test-cooking-status.sh" "$RUN_ALL_DOC"
assert_contains "README documents npx consumer install" "npx -y visualhud@latest install codex --target" "$README_DOC"
assert_contains "README documents one-command cwd install" "npx -y visualhud@latest install codex" "$README_DOC"
assert_contains "README documents local tarball npx proof" "npx -y --package ./visualhud-" "$README_DOC"
echo ""

echo "--- Test 2: npm pack includes install runtime assets ---"
pack_json="$TMP_ROOT/npm-pack.json"
pack_err="$TMP_ROOT/npm-pack.stderr"
set +e
NPM_CONFIG_CACHE="$TMP_ROOT/npm-cache" npm_config_cache="$TMP_ROOT/npm-cache" \
    NPM_CONFIG_DRY_RUN=false npm_config_dry_run=false \
    npm pack --json --pack-destination "$TMP_ROOT" >"$pack_json" 2>"$pack_err"
pack_status=$?
set -e
assert_eq "npm pack succeeds" "0" "$pack_status"
tarball=""
if [ "$pack_status" -eq 0 ]; then
    tarball="$TMP_ROOT/$(jq -r '.[0].filename' "$pack_json")"
    assert_file_exists "npm pack writes tarball" "$tarball"
    tar_contents="$(tar -tzf "$tarball")"
    assert_contains "Tarball includes CLI" "package/visualhud" "$tar_contents"
    assert_contains "Tarball includes engine" "package/engine.sh" "$tar_contents"
    assert_contains "Tarball includes Codex adapter" "package/.codex/hooks/visualhud-codex.sh" "$tar_contents"
    assert_contains "Tarball includes Pokemon sprites" "package/themes/pokemon/sprites/charmander.png" "$tar_contents"
    assert_contains "Tarball includes Pokemon screenshot" "package/docs/screenshots/pokemon-contact-sheet.png" "$tar_contents"
    assert_contains "Tarball includes TMNT screenshot" "package/docs/screenshots/tmnt-contact-sheet.png" "$tar_contents"
    assert_contains "Tarball includes VisualHUD skills" "package/skills/visualhud-setup/SKILL.md" "$tar_contents"
fi
echo ""

echo "--- Test 3: npx tarball install works in a consumer Codex repo ---"
target="$TMP_ROOT/consumer"
mkdir -p "$target"
git -C "$target" init -q
if [ -n "$tarball" ]; then
    set +e
    npx_output="$(NPM_CONFIG_CACHE="$TMP_ROOT/npm-cache" npm_config_cache="$TMP_ROOT/npm-cache" NPM_CONFIG_DRY_RUN=false npm_config_dry_run=false npx --yes --package "$tarball" visualhud install codex --target "$target" --platform macos 2>&1)"
    npx_status=$?
    set -e
    assert_eq "npx install succeeds" "0" "$npx_status"
    assert_contains "npx output reports install" "Installed VisualHUD Codex hooks in:" "$npx_output"
    assert_eq "npx install defaults target to Pokemon" "pokemon" "$(cat "$target/.visualhud/theme" 2>/dev/null || true)"
    assert_file_exists "npx install writes target hook" "$target/.codex/hooks/visualhud-codex.sh"
    assert_file_exists "npx install writes Pokemon sprite" "$target/.visualhud/themes/pokemon/sprites/charmander.png"
    assert_file_exists "npx install writes setup skill" "$target/.agents/skills/visualhud-setup/SKILL.md"
else
    assert_eq "npx install has tarball input" "present" "missing"
fi
echo ""

echo "--- Test 4: npx tarball install defaults target to the current repo ---"
cwd_target="$TMP_ROOT/consumer-cwd"
mkdir -p "$cwd_target"
git -C "$cwd_target" init -q
if [ -n "$tarball" ]; then
    set +e
    cwd_npx_output="$(cd "$cwd_target" && NPM_CONFIG_CACHE="$TMP_ROOT/npm-cache" npm_config_cache="$TMP_ROOT/npm-cache" NPM_CONFIG_DRY_RUN=false npm_config_dry_run=false npx --yes --package "$tarball" visualhud install codex --platform macos 2>&1)"
    cwd_npx_status=$?
    set -e
    assert_eq "npx cwd install succeeds" "0" "$cwd_npx_status"
    assert_contains "npx cwd install reports target" "Installed VisualHUD Codex hooks in:" "$cwd_npx_output"
    assert_eq "npx cwd install defaults to Pokemon" "pokemon" "$(cat "$cwd_target/.visualhud/theme" 2>/dev/null || true)"
    assert_file_exists "npx cwd install writes setup skill" "$cwd_target/.agents/skills/visualhud-setup/SKILL.md"
else
    assert_eq "npx cwd install has tarball input" "present" "missing"
fi
echo ""

echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
