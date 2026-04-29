#!/bin/bash
# Integration tests for the Codex Bash SDLC guard.

set -euo pipefail

PASS=0
FAIL=0
TOTAL=0

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT_DIR/.codex/hooks/bash-guard.sh"
TMP_DIR="$(mktemp -d)"
PROOF_FILE="$TMP_DIR/full-suite.sha256"

cleanup() {
    rm -rf "$TMP_DIR"
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
        printf "  FAIL: %s (missing '%s')\n" "$label" "$needle"
    fi
}

run_guard() {
    local command="$1"
    jq -nc --arg command "$command" '{tool_input:{command:$command}}' \
        | VISUALHUD_SDLC_PROOF_FILE="$PROOF_FILE" bash "$GUARD"
}

staged_hash() {
    git -C "$ROOT_DIR" diff --cached --binary | LC_ALL=C LANG=C shasum -a 256 | awk '{print $1}'
}

echo "=== Test Suite: codex bash guard ==="
echo ""

echo "--- Test 1: Interactive shell bypass remains blocked ---"
output="$(run_guard "bash")"
assert_contains "Interactive shell is blocked" "SDLC GUARD" "$output"
echo ""

echo "--- Test 2: git commit is blocked without current proof ---"
rm -f "$PROOF_FILE"
output="$(run_guard "git commit -m baseline")"
assert_contains "Commit without proof is blocked" "TDD CHECK" "$output"
printf 'stale-proof\n' > "$PROOF_FILE"
output="$(run_guard "git commit -m baseline")"
assert_contains "Commit with stale proof is blocked" "TDD CHECK" "$output"
echo ""

echo "--- Test 3: git commit is allowed with current staged-diff proof ---"
staged_hash > "$PROOF_FILE"
output="$(run_guard "git commit -m baseline")"
assert_eq "Commit with current proof is allowed" "" "$output"
echo ""

echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
