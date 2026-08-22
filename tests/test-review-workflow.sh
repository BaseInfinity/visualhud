#!/bin/bash
# Contract tests for the local proof-aware reviewer helpers.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FABLE_REVIEW="$ROOT_DIR/.codex/hooks/fable-review.cjs"
DUAL_REVIEW="$ROOT_DIR/.codex/hooks/dual-review.cjs"
IGNORE_DOC="$ROOT_DIR/.gitignore"
SDLC_DOC="$ROOT_DIR/SDLC-LOOP.md"
PASS=0
FAIL=0
TOTAL=0

assert_contains() {
    local label="$1" needle="$2" file="$3"
    local content
    TOTAL=$((TOTAL + 1))
    content=$(cat "$file")
    if [[ "$content" == *"$needle"* ]]; then
        PASS=$((PASS + 1))
        printf '  PASS: %s\n' "$label"
    else
        FAIL=$((FAIL + 1))
        printf '  FAIL: %s (missing %s)\n' "$label" "$needle"
    fi
}

assert_not_contains() {
    local label="$1" needle="$2" file="$3"
    local content
    TOTAL=$((TOTAL + 1))
    content=$(cat "$file")
    if [[ "$content" == *"$needle"* ]]; then
        FAIL=$((FAIL + 1))
        printf '  FAIL: %s (found forbidden %s)\n' "$label" "$needle"
    else
        PASS=$((PASS + 1))
        printf '  PASS: %s\n' "$label"
    fi
}

assert_command() {
    local label="$1"
    shift
    TOTAL=$((TOTAL + 1))
    if "$@"; then
        PASS=$((PASS + 1))
        printf '  PASS: %s\n' "$label"
    else
        FAIL=$((FAIL + 1))
        printf '  FAIL: %s\n' "$label"
    fi
}

echo "=== Test Suite: proof-aware review workflow ==="
echo ""

assert_contains "Review receipts use ignored worktree state" ".codex-sdlc/reviews/" "$IGNORE_DOC"
assert_contains "Standalone Fable receipt uses worktree state" 'safeReviewReceiptPath(root, "fable-review.json")' "$FABLE_REVIEW"
assert_contains "Dual-review receipt uses worktree state" 'safeReviewReceiptPath(root, "dual-review.json")' "$DUAL_REVIEW"

assert_not_contains "Standalone review does not write a tree into the protected index" 'candidateTree: git(root, ["write-tree"])' "$FABLE_REVIEW"
assert_not_contains "Dual review does not write a tree into the protected index" 'candidateTree: git(root, ["write-tree"])' "$DUAL_REVIEW"
assert_contains "Standalone candidate tree uses a temporary object database" "GIT_OBJECT_DIRECTORY" "$FABLE_REVIEW"
assert_contains "Dual-review candidate tree uses a temporary object database" "GIT_OBJECT_DIRECTORY" "$DUAL_REVIEW"
assert_contains "Standalone review revalidates proof before receipt" "assertProofCurrentAndUnchanged(root, proof)" "$FABLE_REVIEW"
assert_contains "Dual review revalidates proof before receipt" "assertProofCurrentAndUnchanged(root, proof)" "$DUAL_REVIEW"
assert_contains "Standalone receipt path rejects symlinked state directories" "safeReviewReceiptPath" "$FABLE_REVIEW"
assert_contains "Dual-review receipt path rejects symlinked state directories" "safeReviewReceiptPath" "$DUAL_REVIEW"
assert_contains "Standalone receipt path inspects each directory without following symlinks" "lstatSync(current).isSymbolicLink()" "$FABLE_REVIEW"
assert_contains "Dual-review receipt path inspects each directory without following symlinks" "lstatSync(current).isSymbolicLink()" "$DUAL_REVIEW"

assert_command "Reviewer helpers enforce runtime process and filesystem boundaries" \
    env FABLE_REVIEW="$FABLE_REVIEW" DUAL_REVIEW="$DUAL_REVIEW" node <<'NODE'
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const helpers = [
  require(process.env.FABLE_REVIEW),
  require(process.env.DUAL_REVIEW),
];

async function verifyHelper(helper) {
  assert.equal(typeof helper.runAsync, "function");
  assert.equal(typeof helper.createNeutralTemporaryDirectory, "function");
  assert.equal(typeof helper.writeJsonAtomically, "function");

  if (process.platform !== "win32") {
    const started = Date.now();
    const pending = helper.runAsync(process.execPath, ["-e", "setInterval(() => {}, 1000)"], {
      timeout: 5000,
      killGrace: 200,
    });
    setTimeout(() => process.kill(process.pid, "SIGTERM"), 50);
    const result = await pending;
    assert.equal(result.parentSignal, "SIGTERM");
    assert.ok(Date.now() - started < 3000, "signal cleanup exceeded its bound");

    const descendantMarker = path.join(os.tmpdir(), `review-descendant-${process.pid}-${Date.now()}`);
    const descendantScript = [
      'const fs = require("node:fs");',
      'const marker = process.argv[1];',
      'process.on("SIGTERM", () => {});',
      'setTimeout(() => fs.writeFileSync(marker, "survived"), 650);',
      'setInterval(() => {}, 1000);',
    ].join("");
    const parentScript = [
      'const { spawn } = require("node:child_process");',
      'spawn(process.execPath, ["-e", process.argv[1], process.argv[2]], { stdio: "ignore" });',
      'process.on("SIGTERM", () => process.exit(0));',
      'setInterval(() => {}, 1000);',
    ].join("");
    const descendantRun = helper.runAsync(process.execPath, ["-e", parentScript, descendantScript, descendantMarker], {
      timeout: 300,
      killGrace: 100,
    });
    const descendantResult = await descendantRun;
    assert.equal(descendantResult.timedOut, true);
    await new Promise((resolve) => setTimeout(resolve, 700));
    assert.equal(fs.existsSync(descendantMarker), false, "SIGKILL escalation left reviewer descendant alive");
  }

  assert.equal(typeof helper.bindingForReviewedPatch, "function");
  const reviewedPatch = Buffer.from("exact reviewed patch\nwith trailing bytes\0", "utf8");
  const binding = helper.bindingForReviewedPatch("base", "head", "tree", reviewedPatch);
  assert.equal(
    binding.patchSha256,
    `sha256:${crypto.createHash("sha256").update(reviewedPatch).digest("hex")}`,
  );

  const candidate = fs.mkdtempSync(path.join(os.tmpdir(), "review-candidate-"));
  const nestedTemp = path.join(candidate, "tmp");
  fs.mkdirSync(nestedTemp);
  const previous = {
    TMPDIR: process.env.TMPDIR,
    TMP: process.env.TMP,
    TEMP: process.env.TEMP,
  };
  process.env.TMPDIR = nestedTemp;
  process.env.TMP = nestedTemp;
  process.env.TEMP = nestedTemp;
  try {
    assert.throws(
      () => helper.createNeutralTemporaryDirectory(candidate, "review-"),
      /outside the candidate repository/,
    );
    assert.deepEqual(fs.readdirSync(nestedTemp), []);
  } finally {
    for (const [name, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
  }

  if (process.platform !== "win32") {
    const reviews = path.join(candidate, ".codex-sdlc", "reviews");
    fs.mkdirSync(reviews, { recursive: true });
    const target = path.join(reviews, "review.json");
    const victim = path.join(candidate, "victim.txt");
    fs.writeFileSync(victim, "unchanged\n");
    const suffix = Buffer.alloc(12, 0xab);
    const originalRandomBytes = crypto.randomBytes;
    crypto.randomBytes = () => suffix;
    const planted = `${target}.tmp.${process.pid}.${suffix.toString("hex")}`;
    fs.symlinkSync(victim, planted);
    try {
      assert.throws(() => helper.writeJsonAtomically(target, { ok: true }), /EEXIST|symlink/i);
      assert.equal(fs.readFileSync(victim, "utf8"), "unchanged\n");
    } finally {
      crypto.randomBytes = originalRandomBytes;
    }
  }

  fs.rmSync(candidate, { recursive: true, force: true });
}

(async () => {
  for (const helper of helpers) await verifyHelper(helper);
})().catch((error) => {
  console.error(error.stack || error.message);
  process.exitCode = 1;
});
NODE

assert_not_contains "Sol review does not load candidate project instructions" $'"-C", root,\n    "-m"' "$DUAL_REVIEW"
assert_contains "Sol review runs from a neutral temporary directory" "cwd: temporaryDirectory" "$DUAL_REVIEW"
assert_contains "Sol review permits its neutral non-Git working directory" '"--skip-git-repo-check"' "$DUAL_REVIEW"
assert_contains "Sol independent review receives the frozen patch" 'independentPrompt("Sol High", binding, proof, patchBuffer), temporaryDirectory' "$DUAL_REVIEW"
assert_contains "Sol reconciliation receives the frozen patch" 'reconciliationPrompt("Sol High", { name: "fable", review: fableInitial }, solInitial, binding, proof, patchBuffer), temporaryDirectory' "$DUAL_REVIEW"

assert_command "Fable certification fails closed on model substitution" \
    env FABLE_REVIEW="$FABLE_REVIEW" DUAL_REVIEW="$DUAL_REVIEW" node <<'NODE'
const assert = require("node:assert/strict");

for (const helperPath of [process.env.FABLE_REVIEW, process.env.DUAL_REVIEW]) {
  const helper = require(helperPath);
  assert.equal(typeof helper.assertFableEnvelope, "function");
  assert.doesNotThrow(() => helper.assertFableEnvelope({ model: "fable" }));
  assert.doesNotThrow(() => helper.assertFableEnvelope({ modelUsage: { "claude-fable-5": {} } }));
  assert.throws(() => helper.assertFableEnvelope({}), /model identity/i);
  assert.throws(() => helper.assertFableEnvelope({ model: "claude-opus-4-8" }), /substitution/i);
  assert.throws(
    () => helper.assertFableEnvelope({ modelUsage: { "claude-opus-4-8": {} } }),
    /substitution/i,
  );
}
NODE

assert_contains "Standalone reviewer has process-tree termination" "terminateProcessTree" "$FABLE_REVIEW"
assert_contains "Standalone reviewer uses asynchronous process control" "runAsync" "$FABLE_REVIEW"
assert_contains "Windows timeout terminates descendants" '"taskkill.exe"' "$FABLE_REVIEW"

assert_command "Managed-file hashes describe the finalized candidate" \
    env ROOT_DIR="$ROOT_DIR" node <<'NODE'
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const root = process.env.ROOT_DIR;
const manifest = JSON.parse(fs.readFileSync(path.join(root, ".codex-sdlc", "manifest.json"), "utf8"));
for (const [relative, expected] of Object.entries(manifest.managed_files || {})) {
  if (expected === "") continue;
  const actual = `sha256:${crypto.createHash("sha256").update(fs.readFileSync(path.join(root, relative))).digest("hex")}`;
  assert.equal(actual, expected, `${relative} managed hash is stale`);
}
NODE

assert_not_contains "SDLC guidance does not promise focused-proof commits" "Commit coherent green slices after focused proof." "$SDLC_DOC"
assert_contains "SDLC guidance explains cumulative staged work" "Keep cumulative green work staged" "$SDLC_DOC"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
