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
CANDIDATE_BUILD="$TMP_ROOT/candidate-build"
CANDIDATE_TARBALL="$TMP_ROOT/visualhud-1.2.0.tgz"

mkdir -p "$CANDIDATE_BUILD/package"
cp "$ROOT_DIR/package.json" "$CANDIDATE_BUILD/package/package.json"
tar -czf "$CANDIDATE_TARBALL" -C "$CANDIDATE_BUILD" package
CANDIDATE_SHA256="$(shasum -a 256 "$CANDIDATE_TARBALL" | awk '{print $1}')"

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

assert_file_exists() {
    local label="$1" filepath="$2"
    TOTAL=$((TOTAL + 1))
    if [ -f "$filepath" ]; then
        pass "$label"
    else
        fail "$label (missing file: $filepath)"
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
    "publish ${VISUALHUD_TEST_CANDIDATE:?} --access public --ignore-scripts --dry-run")
        printf 'dry run ok\n'
        ;;
    "publish ${VISUALHUD_TEST_CANDIDATE:?} --access public --ignore-scripts")
        printf 'publish ok\n'
        ;;
    "view visualhud@1.2.0 version")
        printf '1.2.0\n'
        ;;
    "trust github --file publish.yml --repo BaseInfinity/visualhud --yes")
        printf 'trusted publisher linked\n'
        ;;
    *)
        printf 'unexpected npm command: %s\n' "$*" >&2
        exit 64
        ;;
esac
EOF
    chmod +x "$FAKE_BIN/npm"

    cat > "$FAKE_BIN/npx" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'npx|%s\n' "$*" >> "$VISUALHUD_RELEASE_CALL_LOG"
case "$*" in
    "--yes npm@11.14.1 trust github visualhud --file publish.yml --repo BaseInfinity/visualhud --yes")
        printf 'trusted publisher linked\n'
        ;;
    *)
        printf 'unexpected npx command: %s\n' "$*" >&2
        exit 64
        ;;
esac
EOF
    chmod +x "$FAKE_BIN/npx"
}

release_with_fakes() {
    PATH="$FAKE_BIN:$PATH" \
        VISUALHUD_RELEASE_CALL_LOG="$CALL_LOG" \
        VISUALHUD_RELEASE_NPM_CACHE="$TMP_ROOT/npm-cache" \
        VISUALHUD_TEST_CANDIDATE="$CANDIDATE_TARBALL" \
        "$ROOT_DIR/scripts/release-npm.sh" "$@"
}

echo "=== Test Suite: npm release automation ==="
echo ""

echo "--- Test 1: dry-run verifies and targets the retained candidate only ---"
write_fake_tools
set +e
dry_output="$(release_with_fakes --dry-run --candidate "$CANDIDATE_TARBALL" --sha256 "$CANDIDATE_SHA256" 2>&1)"
dry_status=$?
set -e
dry_log="$(cat "$CALL_LOG")"
assert_eq "Dry-run exits cleanly" "0" "$dry_status"
assert_contains "Dry-run checks npm auth" "npm|whoami" "$dry_log"
assert_not_contains "Dry-run does not rerun the frozen source proof" "npm|test" "$dry_log"
assert_contains "Dry-run targets the retained tarball without lifecycle reruns" "npm|publish $CANDIDATE_TARBALL --access public --ignore-scripts --dry-run" "$dry_log"
assert_not_contains "Dry-run does not publish for real" "npm|publish $CANDIDATE_TARBALL --access public --ignore-scripts"$'\n' "$dry_log"
assert_contains "Dry-run output is explicit" "Dry-run complete; no package was published." "$dry_output"
echo ""

echo "--- Test 2: publish release dry-runs before publishing and verifies registry ---"
write_fake_tools
set +e
publish_output="$(release_with_fakes --publish --candidate "$CANDIDATE_TARBALL" --sha256 "$CANDIDATE_SHA256" 2>&1)"
publish_status=$?
set -e
publish_log="$(cat "$CALL_LOG")"
assert_eq "Publish exits cleanly" "0" "$publish_status"
assert_contains "Publish checks npm auth" "npm|whoami" "$publish_log"
assert_not_contains "Publish does not rerun the frozen source proof" "npm|test" "$publish_log"
assert_contains "Publish dry-runs the retained tarball without lifecycle reruns" "npm|publish $CANDIDATE_TARBALL --access public --ignore-scripts --dry-run" "$publish_log"
assert_contains "Publish sends the retained tarball without lifecycle reruns" "npm|publish $CANDIDATE_TARBALL --access public --ignore-scripts"$'\n' "$publish_log"
assert_not_contains "Publish never sends the source directory" "npm|publish --access public" "$publish_log"
assert_contains "Publish verifies registry version" "npm|view visualhud@1.2.0 version" "$publish_log"
assert_contains "Publish output confirms registry version" "Published visualhud@1.2.0." "$publish_output"
echo ""

echo "--- Test 3: dirty worktree blocks release before npm commands ---"
write_fake_tools
set +e
dirty_output="$(VISUALHUD_FAKE_GIT_STATUS=" M package.json" release_with_fakes --dry-run --candidate "$CANDIDATE_TARBALL" --sha256 "$CANDIDATE_SHA256" 2>&1)"
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
auth_output="$(VISUALHUD_FAKE_NPM_AUTH=fail release_with_fakes --dry-run --candidate "$CANDIDATE_TARBALL" --sha256 "$CANDIDATE_SHA256" 2>&1)"
auth_status=$?
set -e
auth_log="$(cat "$CALL_LOG")"
assert_eq "Missing auth exits nonzero" "1" "$auth_status"
assert_contains "Missing auth explains npm login" "npm auth is not available. Run npm login, then retry." "$auth_output"
assert_not_contains "Missing auth does not run tests" "npm|test" "$auth_log"
assert_not_contains "Missing auth does not publish" "npm|publish" "$auth_log"
echo ""

echo "--- Test 4b: release requires the exact retained candidate identity ---"
write_fake_tools
set +e
missing_candidate_output="$(release_with_fakes --dry-run 2>&1)"
missing_candidate_status=$?
set -e
assert_eq "Missing candidate exits nonzero" "2" "$missing_candidate_status"
assert_contains "Missing candidate explains required artifact inputs" "--candidate and --sha256 are required" "$missing_candidate_output"

write_fake_tools
set +e
mismatch_output="$(release_with_fakes --dry-run --candidate "$CANDIDATE_TARBALL" --sha256 "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" 2>&1)"
mismatch_status=$?
set -e
mismatch_log="$(cat "$CALL_LOG")"
assert_eq "Candidate checksum mismatch exits nonzero" "1" "$mismatch_status"
assert_contains "Candidate checksum mismatch is explicit" "Candidate SHA-256 mismatch" "$mismatch_output"
assert_not_contains "Checksum mismatch stops before npm auth" "npm|" "$mismatch_log"
echo ""

echo "--- Test 4c: quarantined candidates are rejected before npm access ---"
write_fake_tools
quarantined_sha="319cc1472d8e7bd35d140b8b31038d05460eb8876c7079b5739dd4f4284ea174"
set +e
quarantined_output="$(release_with_fakes --publish --candidate "$CANDIDATE_TARBALL" --sha256 "$quarantined_sha" 2>&1)"
quarantined_status=$?
set -e
quarantined_log="$(cat "$CALL_LOG")"
assert_eq "Quarantined candidate exits nonzero" "1" "$quarantined_status"
assert_contains "Quarantined candidate explains immutable block" "Candidate SHA-256 is quarantined and must not be published" "$quarantined_output"
assert_not_contains "Quarantine rejection happens before npm access" "npm|" "$quarantined_log"
echo ""

echo "--- Test 5: release workflow is documented ---"
README_DOC="$(cat "$ROOT_DIR/README.md")"
TESTING_DOC="$(cat "$ROOT_DIR/TESTING.md")"
assert_contains "README documents dry-run release" "scripts/release-npm.sh --dry-run" "$README_DOC"
assert_contains "README documents real publish release" "scripts/release-npm.sh --publish" "$README_DOC"
assert_contains "README binds release commands to the retained candidate" "--candidate /absolute/path/to/visualhud-1.2.0.tgz" "$README_DOC"
assert_contains "README binds release commands to the accepted checksum" "--sha256 <accepted-sha256>" "$README_DOC"
assert_contains "README documents one-time npm bootstrap auth" "First publish bootstrap:" "$README_DOC"
assert_contains "README documents Trusted Publishing follow-up" "Trusted Publishing" "$README_DOC"
assert_contains "README documents npm trust CLI automation" "npm run release:trust" "$README_DOC"
assert_contains "Testing docs include release suite" "tests/test-npm-release.sh" "$TESTING_DOC"
echo ""

echo "--- Test 6: GitHub Actions publication is manual and artifact-bound ---"
workflow="$ROOT_DIR/.github/workflows/publish.yml"
assert_file_exists "Trusted publish workflow exists" "$workflow"
if [ -f "$workflow" ]; then
    workflow_doc="$(cat "$workflow")"
    assert_contains "Workflow requires manual dispatch" "workflow_dispatch:" "$workflow_doc"
    assert_not_contains "Tag pushes cannot publish automatically" "tags:" "$workflow_doc"
    assert_contains "Workflow requires a release tag input" "release_tag:" "$workflow_doc"
    assert_contains "Workflow requires a candidate checksum input" "candidate_sha256:" "$workflow_doc"
    assert_contains "Workflow has OIDC permission" "id-token: write" "$workflow_doc"
    assert_contains "Workflow uses npm registry" "registry-url: 'https://registry.npmjs.org'" "$workflow_doc"
    assert_contains "Workflow downloads the retained release asset" "gh release download" "$workflow_doc"
    assert_contains "Workflow verifies the accepted SHA-256" "shasum -a 256" "$workflow_doc"
    assert_contains "Workflow carries the quarantined candidate SHA" "319cc1472d8e7bd35d140b8b31038d05460eb8876c7079b5739dd4f4284ea174" "$workflow_doc"
    assert_contains "Workflow rejects quarantined candidates" "Candidate SHA-256 is quarantined and must not be published" "$workflow_doc"
    assert_contains "Workflow dry-runs the retained tarball without lifecycle reruns" "npm publish \"\$candidate\" --access public --ignore-scripts --dry-run" "$workflow_doc"
    assert_contains "Workflow publishes the retained tarball without lifecycle reruns" "npm publish \"\$candidate\" --access public --ignore-scripts" "$workflow_doc"
    assert_not_contains "Workflow does not rerun source tests" "npm test" "$workflow_doc"
    assert_not_contains "Workflow does not require long-lived npm token" "NPM_TOKEN" "$workflow_doc"
fi
echo ""

echo "--- Test 7: Trusted Publishing setup is CLI-automated ---"
if [ -f "$ROOT_DIR/package.json" ]; then
    assert_eq "Package exposes Trusted Publishing setup script" \
        "npx --yes npm@11.14.1 trust github visualhud --file publish.yml --repo BaseInfinity/visualhud --yes" \
        "$(jq -r '.scripts["release:trust"]' "$ROOT_DIR/package.json")"
fi
write_fake_tools
trust_command="$(jq -r '.scripts["release:trust"]' "$ROOT_DIR/package.json")"
set +e
trust_output="$(cd "$ROOT_DIR" && PATH="$FAKE_BIN:$PATH" VISUALHUD_RELEASE_CALL_LOG="$CALL_LOG" bash -c "$trust_command" 2>&1)"
trust_status=$?
set -e
trust_log="$(cat "$CALL_LOG")"
assert_eq "Trusted Publishing setup exits cleanly" "0" "$trust_status"
assert_contains "Trusted Publishing setup uses npm trust github" \
    "npx|--yes npm@11.14.1 trust github visualhud --file publish.yml --repo BaseInfinity/visualhud --yes" \
    "$trust_log"
assert_contains "Trusted Publishing setup reports linked publisher" "trusted publisher linked" "$trust_output"
echo ""

echo "--- Test 8: Candidate CI proves changes without publishing ---"
candidate_workflow="$ROOT_DIR/.github/workflows/ci.yml"
assert_file_exists "Candidate CI workflow exists" "$candidate_workflow"
if [ -f "$candidate_workflow" ]; then
    candidate_doc="$(cat "$candidate_workflow")"
    assert_contains "Candidate CI runs for pull requests" "pull_request:" "$candidate_doc"
    assert_contains "Candidate CI runs for main branch pushes" "branches: [main]" "$candidate_doc"
    assert_contains "Candidate CI installs dependencies reproducibly" "npm ci" "$candidate_doc"
    assert_contains "Candidate CI installs contact-sheet image dependency" "python3 -m pip install Pillow" "$candidate_doc"
    assert_contains "Candidate CI runs the full test gate" "npm test" "$candidate_doc"
    assert_not_contains "Candidate CI never publishes" "npm publish" "$candidate_doc"
    assert_not_contains "Candidate CI does not request publish credentials" "id-token: write" "$candidate_doc"
fi
echo ""

echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
