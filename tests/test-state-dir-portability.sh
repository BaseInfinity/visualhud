#!/bin/bash
# Proves shell tests do not assume macOS-only /private/tmp state paths.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
TOTAL=0

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

echo "=== Test Suite: state-dir-portability ==="
echo ""

matches=$(
    grep -R -n '/private/tmp' "$ROOT_DIR/tests" \
        --include='*.sh' \
        --exclude='test-state-dir-portability.sh' \
        || true
)
assert_eq "Shell tests avoid macOS-only /private/tmp state paths" "" "$matches"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
