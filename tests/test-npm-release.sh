#!/bin/bash
# Proves npm release automation is repeatable and safe.

set -euo pipefail

PASS=0
FAIL=0
TOTAL=0

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/visualhud-release.XXXXXX")"
FAKE_BIN="$TMP_ROOT/bin"
CALL_LOG="$TMP_ROOT/calls.log"

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

assert_not_contains() {
    local label="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" != *"$needle"* ]]; then
        pass "$label"
    else
        fail "$label (expected content to omit '$needle')"
    fi
}

write_fake_tools() {
    rm -rf "$FAKE_BIN"
    mkdir -p "$FAKE_BIN"
    : > "$CALL_LOG"

    cat > "$FAKE_BIN/git" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'git|%s\n' "$*" >> "$VISUALHUD_RELEASE_CALL_LOG"
case "$*" in
    "status --porcelain")
        printf '%s' "${VISUALHUD_FAKE_GIT_STATUS:-}"
        ;;
    *)
        printf 'unexpected git command: %s\n' "$*" >&2
        exit 64
        ;;
esac
EOF
    chmod +x "$FAKE_BIN/git"

    cat > "$FAKE_BIN/npm" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'npm|%s\n' "$*" >> "$VISUALHUD_RELEASE_CALL_LOG"
case "$*" in
    "whoami")
        if [ "${VISUALHUD_FAKE_NPM_AUTH:-ok}" = "fail" ]; then
            printf 'E401 Unauthorized\n' >&2
            exit 1
        fi
        printf 'baseinfinity\n'
        ;;
    "test")
        printf 'tests ok\n'
        ;;
    "publish --access public --dry-run")
        printf 'dry run ok\n'
        ;;
    "publish --access public")
        printf 'publish ok\n'
        ;;
    "view visualhud@0.1.0 version")
        printf '0.1.0\n'
        ;;
    *)
        printf 'unexpected npm command: %s\n' "$*" >&2
        exit 64
        ;;
esac
EOF
    chmod +x "$FAKE_BIN/npm"
}

release_with_fakes() {
    PATH="$FAKE_BIN:$PATH" \
        VISUALHUD_RELEASE_CALL_LOG="$CALL_LOG" \
        VISUALHUD_RELEASE_NPM_CACHE="$TMP_ROOT/npm-cache" \
        "$ROOT_DIR/scripts/release-npm.sh" "$@"
}

echo "=== Test Suite: npm release automation ==="
echo ""

echo "--- Test 1: dry-run release checks auth, tests, and publish dry-run only ---"
write_fake_tools
set +e
dry_output="$(release_with_fakes --dry-run 2>&1)"
dry_status=$?
set -e
dry_log="$(cat "$CALL_LOG")"
assert_eq "Dry-run exits cleanly" "0" "$dry_status"
assert_contains "Dry-run checks npm auth" "npm|whoami" "$dry_log"
assert_contains "Dry-run runs full npm test gate" "npm|test" "$dry_log"
assert_contains "Dry-run runs npm publish dry-run" "npm|publish --access public --dry-run" "$dry_log"
assert_not_contains "Dry-run does not publish for real" "npm|publish --access public"$'\n' "$dry_log"
assert_contains "Dry-run output is explicit" "Dry-run complete; no package was published." "$dry_output"
echo ""

echo "--- Test 2: publish release dry-runs before publishing and verifies registry ---"
write_fake_tools
set +e
publish_output="$(release_with_fakes --publish 2>&1)"
publish_status=$?
set -e
publish_log="$(cat "$CALL_LOG")"
assert_eq "Publish exits cleanly" "0" "$publish_status"
assert_contains "Publish checks npm auth" "npm|whoami" "$publish_log"
assert_contains "Publish runs tests" "npm|test" "$publish_log"
assert_contains "Publish runs dry-run first" "npm|publish --access public --dry-run" "$publish_log"
assert_contains "Publish runs real npm publish" "npm|publish --access public"$'\n' "$publish_log"
assert_contains "Publish verifies registry version" "npm|view visualhud@0.1.0 version" "$publish_log"
assert_contains "Publish output confirms registry version" "Published visualhud@0.1.0." "$publish_output"
echo ""

echo "--- Test 3: dirty worktree blocks release before npm commands ---"
write_fake_tools
set +e
dirty_output="$(VISUALHUD_FAKE_GIT_STATUS=" M package.json" release_with_fakes --dry-run 2>&1)"
dirty_status=$?
set -e
dirty_log="$(cat "$CALL_LOG")"
assert_eq "Dirty release exits nonzero" "1" "$dirty_status"
assert_contains "Dirty release explains blocker" "Worktree is dirty; commit or stash changes before release." "$dirty_output"
assert_not_contains "Dirty release does not call npm" "npm|" "$dirty_log"
echo ""

echo "--- Test 4: missing npm auth blocks before tests or publish ---"
write_fake_tools
set +e
auth_output="$(VISUALHUD_FAKE_NPM_AUTH=fail release_with_fakes --dry-run 2>&1)"
auth_status=$?
set -e
auth_log="$(cat "$CALL_LOG")"
assert_eq "Missing auth exits nonzero" "1" "$auth_status"
assert_contains "Missing auth explains npm login" "npm auth is not available. Run npm login, then retry." "$auth_output"
assert_not_contains "Missing auth does not run tests" "npm|test" "$auth_log"
assert_not_contains "Missing auth does not publish" "npm|publish" "$auth_log"
echo ""

echo "--- Test 5: release workflow is documented ---"
README_DOC="$(cat "$ROOT_DIR/README.md")"
TESTING_DOC="$(cat "$ROOT_DIR/TESTING.md")"
assert_contains "README documents dry-run release" "scripts/release-npm.sh --dry-run" "$README_DOC"
assert_contains "README documents real publish release" "scripts/release-npm.sh --publish" "$README_DOC"
assert_contains "Testing docs include release suite" "tests/test-npm-release.sh" "$TESTING_DOC"
echo ""

echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
