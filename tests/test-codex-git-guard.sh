#!/bin/bash
# Integration tests for the active Codex Node SDLC git guard.

set -euo pipefail

PASS=0
FAIL=0
TOTAL=0

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_GUARD="$ROOT_DIR/.codex/hooks/git-guard.cjs"
TMP_DIR="$(mktemp -d)"
REPO="$TMP_DIR/repo"
OTHER_REPO="$TMP_DIR/other-repo"
GUARD="$REPO/.codex/hooks/git-guard.cjs"

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
    local command="$1" cwd="${2:-$REPO}"
    jq -nc --arg command "$command" --arg cwd "$cwd" '{tool_input:{command:$command,workdir:$cwd}}' \
        | (cd "$cwd" && node "$GUARD")
}

run_guard_without_workdir() {
    local command="$1"
    jq -nc --arg command "$command" '{tool_input:{command:$command}}' \
        | (cd "$REPO" && node "$GUARD")
}

mkdir -p "$REPO/.codex/hooks" "$REPO/.codex-sdlc" "$REPO/nested" "$OTHER_REPO"
cp "$SOURCE_GUARD" "$GUARD"
cat > "$REPO/.codex-sdlc/manifest.json" <<'JSON'
{
  "resolved_values": {
    "test_command": "true",
    "lint_command": "N/A",
    "typecheck_command": "N/A",
    "build_command": "N/A"
  }
}
JSON
printf 'baseline\n' > "$REPO/tracked.txt"
git -C "$REPO" init -q
git -C "$OTHER_REPO" init -q
git -C "$REPO" config user.name "VisualHUD Test"
git -C "$REPO" config user.email "visualhud@example.invalid"
git -C "$REPO" add .

echo "=== Test Suite: codex git guard ==="
echo ""

echo "--- Test 1: Interactive shell bypass remains blocked ---"
output="$(run_guard "bash")"
assert_contains "Interactive shell is blocked" "SDLC GUARD" "$output"
echo ""

echo "--- Test 2: git commit is blocked without reviewed proof ---"
output="$(run_guard "git commit -m baseline")"
assert_contains "Commit without proof is blocked" "proof is missing" "$output"
echo ""

echo "--- Test 3: reviewed proof allows commit from a nested directory ---"
(cd "$REPO" && node "$GUARD" prove --reviewed >/dev/null)
assert_eq "Proof stamp is written to the writable worktree" "yes" "$([ -f "$REPO/.codex-sdlc/proof.json" ] && printf yes || printf no)"
assert_eq "Proof stamp is not written under protected .git" "no" "$([ -f "$REPO/.git/codex-sdlc/proof.json" ] && printf yes || printf no)"
verify_output="$(cd "$REPO" && node "$GUARD" verify-proof --json)"
assert_contains "Proof verification endpoint reports fresh proof" '"ok":true' "$verify_output"
output="$(run_guard "git commit -m baseline" "$REPO/nested")"
assert_eq "Commit with current proof is allowed" "" "$output"
output="$(run_guard "git -C $REPO commit -m baseline" "$REPO")"
assert_eq "Standalone absolute -C commit for the proven repo is allowed" "" "$output"
output="$(run_guard_without_workdir "git -C $REPO commit -m baseline")"
assert_eq "Same-repo -C commit works when hook payload omits workdir" "" "$output"
output="$(run_guard "git -C $REPO push origin main" "$REPO")"
assert_eq "Standalone absolute -C push for the proven repo is allowed" "" "$output"
output="$(run_guard "git -C $OTHER_REPO commit -m foreign" "$REPO")"
assert_contains "Absolute -C commit for another repo remains blocked" "another repo context" "$output"
nested_command="git -C $REPO commit -m \"\$(cd $OTHER_REPO && git commit -m foreign)\""
output="$(run_guard "$nested_command" "$REPO")"
assert_contains "Same-repo -C commit with a foreign command substitution remains blocked" "another repo context" "$output"
process_substitution_command="git -C $REPO commit -F <(cd $OTHER_REPO && git commit -m foreign)"
output="$(run_guard "$process_substitution_command" "$REPO")"
assert_contains "Same-repo -C commit with a foreign process substitution remains blocked" "another repo context" "$output"
echo ""

echo "--- Test 4: workspace changes invalidate proof ---"
printf 'changed\n' >> "$REPO/tracked.txt"
output="$(run_guard "git commit -am changed")"
assert_contains "Commit with stale proof is blocked" "proof is stale" "$output"
echo ""

echo "--- Test 5: proof rejects staged content that differs from the tested worktree ---"
printf 'bad staged\n' > "$REPO/tracked.txt"
git -C "$REPO" add tracked.txt
printf 'good worktree\n' > "$REPO/tracked.txt"
set +e
output="$(cd "$REPO" && node "$GUARD" prove --reviewed 2>&1)"
status=$?
set -e
assert_eq "Proof with split index and worktree fails" "2" "$status"
assert_contains "Proof explains the untested staged-content risk" "unstaged tracked changes" "$output"
echo ""

echo "--- Test 6: proof rejects untracked files shadowing staged deletions ---"
git -C "$REPO" add tracked.txt
git -C "$REPO" commit -q -m fixture
git -C "$REPO" rm --cached -f -q tracked.txt
set +e
output="$(cd "$REPO" && node "$GUARD" prove --reviewed 2>&1)"
status=$?
set -e
assert_eq "Proof with a staged-deletion shadow fails" "2" "$status"
assert_contains "Proof explains staged-deletion shadow risk" "shadow staged deletions" "$output"
git -C "$REPO" add tracked.txt
echo ""

echo "--- Test 7: changing the staged index after proof invalidates it ---"
printf 'verified\n' > "$REPO/tracked.txt"
git -C "$REPO" add tracked.txt
(cd "$REPO" && node "$GUARD" prove --reviewed >/dev/null)
bad_blob="$(printf 'different staged content\n' | git -C "$REPO" hash-object -w --stdin)"
git -C "$REPO" update-index --cacheinfo "100644,$bad_blob,tracked.txt"
output="$(run_guard "git commit -m changed-index")"
assert_contains "Commit with post-proof index changes is blocked" "proof is stale" "$output"
echo ""

echo "--- Test 8: proof refuses a symlink target without overwriting its victim ---"
printf 'verified\n' > "$REPO/tracked.txt"
git -C "$REPO" add tracked.txt
rm -f "$REPO/.codex-sdlc/proof.json"
victim="$TMP_DIR/proof-victim.txt"
printf 'valuable\n' > "$victim"
ln -s "$victim" "$REPO/.codex-sdlc/proof.json"
set +e
output="$(cd "$REPO" && node "$GUARD" prove --reviewed 2>&1)"
status=$?
set -e
assert_eq "Proof with symlink target fails" "2" "$status"
assert_contains "Proof explains symlink refusal" "symlink" "$output"
assert_eq "Proof symlink victim remains unchanged" "valuable" "$(cat "$victim")"
echo ""

echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
