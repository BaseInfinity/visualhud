#!/bin/bash
# Theme-system contract tests.
# Proves themes are data-only JSON packs and a third theme can be added without
# changing engine.sh.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_UNDER_TEST="${VISUALHUD_ENGINE_UNDER_TEST:-$ROOT_DIR/engine.sh}"
PASS=0
FAIL=0
TOTAL=0

TEST_SESSION="w0t0p0:THEME_SYSTEM_$(date +%s)"
export ITERM_SESSION_ID="$TEST_SESSION"
SESSION_KEY=$(printf '%s' "$TEST_SESSION" | tr ':/' '__')
STATE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/visualhud-theme-state.XXXXXX")"
export VISUALHUD_STATE_DIR="$STATE_ROOT"
COUNTER_FILE="$STATE_ROOT/claude-cooking-counter_${SESSION_KEY}"
STAGE_FILE="$STATE_ROOT/claude-cooking-stage_${SESSION_KEY}"
ATTENTION_FILE="$STATE_ROOT/claude-cooking-attention_${SESSION_KEY}"
CONTEXT_FILE="$STATE_ROOT/claude-cooking-context_${SESSION_KEY}"
TMP_ROOT=""

cleanup() {
    rm -f "$COUNTER_FILE" "$STAGE_FILE" "$ATTENTION_FILE" "$CONTEXT_FILE" 2>/dev/null
    if [ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ]; then
        rm -rf "$TMP_ROOT"
    fi
    rm -rf "$STATE_ROOT"
    unset VISUALHUD_THEME VISUALHUD_THEMES_DIR VISUALHUD_SET_BG VISUALHUD_SET_BG_LOG
    unset VISUALHUD_TTY VISUALHUD_SPRITES_DIR VISUALHUD_CONTEXT_USED_PERCENT VISUALHUD_STATE_DIR
}
trap cleanup EXIT

run_hook() {
    local json="$1"
    printf '%s\n' "$json" | bash "$SCRIPT_UNDER_TEST" 2>/dev/null || true
}

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

assert_file_exists() {
    local label="$1" filepath="$2"
    TOTAL=$((TOTAL + 1))
    if [ -f "$filepath" ]; then
        pass "$label"
    else
        fail "$label (missing file: $filepath)"
    fi
}

assert_file_not_exists() {
    local label="$1" filepath="$2"
    TOTAL=$((TOTAL + 1))
    if [ ! -e "$filepath" ]; then
        pass "$label"
    else
        fail "$label (unexpected path: $filepath)"
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

assert_in_order() {
    local label="$1" haystack="$2" needle
    shift 2
    local remaining="$haystack"
    TOTAL=$((TOTAL + 1))
    for needle in "$@"; do
        if [[ "$remaining" != *"$needle"* ]]; then
            fail "$label (missing or out of order: $needle)"
            return
        fi
        remaining=${remaining#*"$needle"}
    done
    pass "$label"
}

assert_no_repo_match() {
    local label="$1" pattern="$2"
    shift 2
    TOTAL=$((TOTAL + 1))
    if grep -E -n -- "$pattern" "$@" >/dev/null 2>&1; then
        fail "$label (matched forbidden pattern: $pattern)"
    else
        pass "$label"
    fi
}

assert_jq() {
    local label="$1" file="$2" filter="$3"
    TOTAL=$((TOTAL + 1))
    if jq -e "$filter" "$file" >/dev/null; then
        pass "$label"
    else
        fail "$label (jq contract failed for $file)"
    fi
}

echo "=== Test Suite: theme-system ==="
echo ""

echo "--- Test 1: Theme authoring contract is documented ---"
assert_file_exists "THEMES.md exists" "$ROOT_DIR/THEMES.md"
assert_file_exists "Standing release documentation checklist exists" "$ROOT_DIR/RELEASE_CHECKLIST.md"
assert_file_exists "v1.2 release documentation audit exists" "$ROOT_DIR/docs/release-audits/v1.2.0-rc.md"
THEMES_DOC=""
if [ -f "$ROOT_DIR/THEMES.md" ]; then
    THEMES_DOC=$(cat "$ROOT_DIR/THEMES.md")
fi
README_DOC=$(cat "$ROOT_DIR/README.md")
ARCH_DOC=$(cat "$ROOT_DIR/ARCHITECTURE.md")
ROADMAP_DOC=$(cat "$ROOT_DIR/ROADMAP.md")
OVERNIGHT_ROADMAP=$(sed -n '/^### Unattended Overnight Scope$/,/^### Supervised Release Scope$/p' "$ROOT_DIR/ROADMAP.md")
SUPERVISED_ROADMAP=$(sed -n '/^### Supervised Release Scope$/,/^## Completion Criteria$/p' "$ROOT_DIR/ROADMAP.md")
TESTING_DOC=$(cat "$ROOT_DIR/TESTING.md")
AGENTS_DOC=$(cat "$ROOT_DIR/AGENTS.md")
SDLC_SKILL_DOC=$(cat "$ROOT_DIR/.agents/skills/sdlc/SKILL.md")
CODEX_CONFIG_DOC=$(cat "$ROOT_DIR/.codex/config.toml")
RELEASE_CHECKLIST_DOC=$(cat "$ROOT_DIR/RELEASE_CHECKLIST.md")
RELEASE_AUDIT_DOC=$(cat "$ROOT_DIR/docs/release-audits/v1.2.0-rc.md")
assert_contains "Theme docs define max-threshold stages" '"max"' "$THEMES_DOC"
assert_contains "Theme docs define sprite-backed states" '"sprite"' "$THEMES_DOC"
assert_contains "Theme docs define color families" '"color_family"' "$THEMES_DOC"
assert_contains "Theme docs define stage shades" '"shades"' "$THEMES_DOC"
assert_contains "Theme docs require shade ramps for fast-start themes" "Fast-start themes with early thresholds" "$THEMES_DOC"
assert_contains "Theme docs require balanced dwell for many-hue colors-only themes" "balanced dwell thresholds" "$THEMES_DOC"
assert_contains "Theme docs define shade sprite variants" '"shade_sprites"' "$THEMES_DOC"
assert_contains "Theme docs require branded shade sprites to be distinct portraits" "not just crop-only zooms" "$THEMES_DOC"
assert_contains "Theme docs define progress bar as shared visual status strip" "shared visual progress strip" "$THEMES_DOC"
assert_contains "Theme docs define theme-colored sprite backdrops" "backdrop_color" "$THEMES_DOC"
assert_contains "Theme docs define lifecycle colors as semantic terminal states" "Lifecycle colors are semantic terminal states" "$THEMES_DOC"
assert_contains "Theme docs define review as non-done lifecycle state" "review is not done" "$THEMES_DOC"
assert_contains "Theme docs forbid neutral matte leaks" "neutral corner mattes" "$THEMES_DOC"
assert_contains "Theme docs include TDD acceptance gates" "TDD" "$THEMES_DOC"
assert_contains "Theme docs require Claude adapter proof" "bash tests/test-claude-visualhud.sh" "$THEMES_DOC"
assert_contains "Theme docs shellcheck Claude adapter" ".claude/hooks/*.sh" "$THEMES_DOC"
assert_contains "README has install section" "## Install" "$README_DOC"
assert_contains "README documents Codex local hook install" ".codex/hooks.json" "$README_DOC"
assert_contains "README documents Claude local hook install" ".claude/settings.json" "$README_DOC"
assert_contains "README documents iTerm2 setup command" "./setup-iterm2.sh" "$README_DOC"
assert_contains "README includes screenshots section" "## Screenshots" "$README_DOC"
assert_contains "README front-loads npx quickstart" "npx -y visualhud@latest" "$README_DOC"
assert_contains "README front-loads Codex restart command" "codex --yolo" "$README_DOC"
assert_not_contains "README does not front-load legacy full-auto flag" "codex --full-auto" "$README_DOC"
assert_contains "README shows Pokemon screenshot" "docs/screenshots/pokemon-contact-sheet.png" "$README_DOC"
assert_contains "README screenshot has descriptive alt text" "![Pokemon VisualHUD contact sheet]" "$README_DOC"
assert_not_contains "README does not front-load TMNT screenshot before the theme docs are polished" "docs/screenshots/tmnt-contact-sheet.png" "$README_DOC"
assert_file_exists "Pokemon contact sheet screenshot is checked in" "$ROOT_DIR/docs/screenshots/pokemon-contact-sheet.png"
assert_file_exists "TMNT contact sheet screenshot is checked in" "$ROOT_DIR/docs/screenshots/tmnt-contact-sheet.png"
assert_contains "README documents Windows status" "Windows Terminal" "$README_DOC"
assert_contains "README points theme authors to tests" "bash tests/test-theme-system.sh" "$README_DOC"
assert_contains "README documents per-shade sprite variants" "shade_sprites" "$README_DOC"
assert_contains "README documents colors-only dwell pacing" "balanced stage" "$README_DOC"
assert_contains "README documents matte stripping for source sprites" "neutral corner mattes" "$README_DOC"
assert_contains "README documents repo-local theme switch command" "./visualhud theme set" "$README_DOC"
assert_contains "README documents theme switch without restart" "next hook" "$README_DOC"
assert_contains "README documents calibration command" "./visualhud theme calibrate" "$README_DOC"
assert_contains "README documents the semantic legend command" "./visualhud theme legend" "$README_DOC"
assert_contains "README labels ordinary work as indeterminate" "WORKING is indeterminate" "$README_DOC"
assert_contains "README documents doctor's real engine capture" "side-effect-free capture through the real engine" "$README_DOC"
assert_contains "README documents the shipped doctor CLI" ".visualhud/visualhud doctor" "$README_DOC"
assert_contains "README documents create-theme workflow" "## Create A Theme" "$README_DOC"
assert_contains "README tells agents to follow theme docs" "Tell your agent to follow \`THEMES.md\`" "$README_DOC"
assert_contains "README documents theme JSON scaffold path" "themes/<name>/theme.json" "$README_DOC"
assert_contains "README documents Codex target install" "./visualhud install codex --target" "$README_DOC"
assert_contains "README documents installed runtime theme switching" ".visualhud/visualhud theme set" "$README_DOC"
assert_contains "README records Batman as a future theme candidate" "Batman" "$README_DOC"
assert_contains "README records Power Rangers as a future theme candidate" "Power Rangers" "$README_DOC"
assert_contains "README records Sonic as a future theme candidate" "Sonic" "$README_DOC"
assert_contains "README documents Windows status renderer" "Windows Terminal/PowerShell is supported for Codex hook install" "$README_DOC"
assert_contains "README update guidance preserves the active theme" "active_theme=\"\$(./.visualhud/visualhud theme current)\"" "$README_DOC"
assert_contains "README update guidance preserves the active renderer" "renderer=\"\$(sed -n" "$README_DOC"
assert_contains "README scopes the POSIX update example to Bash" "**Bash update:**" "$README_DOC"
assert_contains "README provides a PowerShell update example" "**PowerShell update:**" "$README_DOC"
assert_contains "README Bash update reapplies the WezTerm module" "if [ \"\$platform\" = wezterm ]; then" "$README_DOC"
assert_contains "README PowerShell update reapplies the WezTerm module" "if (\$platform -eq 'wezterm') {" "$README_DOC"
assert_contains "README explains the installed-runtime update limitation" "without fetching a newer package" "$README_DOC"
assert_contains "README gives explicit Codex restart guidance" "**Codex restart guidance:**" "$README_DOC"
assert_contains "README gives explicit iTerm2 restart guidance" "**iTerm2 restart guidance:**" "$README_DOC"
assert_contains "README gives explicit WezTerm restart guidance" "**WezTerm restart guidance:**" "$README_DOC"
assert_contains "README gives explicit Windows Terminal restart guidance" "**Windows Terminal restart guidance:**" "$README_DOC"
assert_contains "README links the publication limitation to its owning issue" "https://github.com/BaseInfinity/visualhud/issues/17" "$README_DOC"
assert_contains "Release checklist runs the existing documentation contract test" "bash tests/test-theme-system.sh" "$RELEASE_CHECKLIST_DOC"
assert_contains "Release checklist runs the existing package contract test" "bash tests/test-npm-package.sh" "$RELEASE_CHECKLIST_DOC"
assert_contains "Release checklist requires the full suite" "\`npm test\`" "$RELEASE_CHECKLIST_DOC"
assert_not_contains "Release checklist does not claim a nonexistent audit script" "npm run audit:release-docs" "$RELEASE_CHECKLIST_DOC"
assert_contains "Release checklist keeps theme demos in issue #13" "GitHub issue #13" "$RELEASE_CHECKLIST_DOC"
assert_contains "Release checklist runs before supervised acceptance" "before supervised acceptance" "$RELEASE_CHECKLIST_DOC"
assert_contains "v1.2 audit records a passing documentation gate" "Status: PASS" "$RELEASE_AUDIT_DOC"
assert_contains "v1.2 audit records the candidate package version" "README/package version agreement: \`1.2.0\`" "$RELEASE_AUDIT_DOC"
assert_contains "v1.2 audit leaves theme demos in issue #13" "issue #13" "$RELEASE_AUDIT_DOC"
assert_contains "v1.2 audit leaves the real canary in issue #16" "issue #16" "$RELEASE_AUDIT_DOC"
assert_contains "v1.2 audit leaves publication in issue #17" "issue #17" "$RELEASE_AUDIT_DOC"
assert_file_not_exists "Planning stays consolidated without GOALS.md" "$ROOT_DIR/GOALS.md"
assert_eq "Repo-local VisualHUD runtime is ignored" "true" "$(git -C "$ROOT_DIR" check-ignore -q .visualhud/engine.sh && printf true || printf false)"
assert_contains "Roadmap delegates release scope to GitHub milestones" "GitHub milestones define release scope" "$ROADMAP_DOC"
assert_contains "Roadmap names v1.2 as Priority 1" "## Priority 1 - Ship v1.2.0" "$ROADMAP_DOC"
assert_contains "Roadmap states issue order is execution priority" "ordered by execution priority" "$ROADMAP_DOC"
assert_contains "Roadmap links the active v1.2.0 milestone" "v1.2.0 - Release Readiness" "$ROADMAP_DOC"
assert_contains "Roadmap links the next v1.3.0 milestone" "v1.3.0 - Theme and UX" "$ROADMAP_DOC"
assert_not_contains "Closed regression matrix issue #11 leaves the open roadmap" "https://github.com/BaseInfinity/visualhud/issues/11)" "$ROADMAP_DOC"
assert_not_contains "Closed Codex state issue #10 leaves the open roadmap" "https://github.com/BaseInfinity/visualhud/issues/10)" "$ROADMAP_DOC"
assert_not_contains "Closed reliability issue #9 leaves the open roadmap" "https://github.com/BaseInfinity/visualhud/issues/9)" "$ROADMAP_DOC"
assert_not_contains "Closed setup issue #5 leaves the open roadmap" "https://github.com/BaseInfinity/visualhud/issues/5)" "$ROADMAP_DOC"
assert_not_contains "Closed setup issue #2 leaves the open roadmap" "https://github.com/BaseInfinity/visualhud/issues/2)" "$ROADMAP_DOC"
assert_not_contains "Completed documentation issue #15 leaves the open roadmap" "https://github.com/BaseInfinity/visualhud/issues/15)" "$ROADMAP_DOC"
assert_not_contains "Closed Linux CI blocker #22 leaves the open roadmap" "https://github.com/BaseInfinity/visualhud/issues/22)" "$ROADMAP_DOC"
assert_not_contains "Closed installer blocker #19 leaves the open roadmap" "issues/19" "$SUPERVISED_ROADMAP"
assert_not_contains "Closed tab-placement blocker #20 leaves the open roadmap" "issues/20" "$SUPERVISED_ROADMAP"
assert_not_contains "Closed critical-context overlay #25 leaves the open roadmap" "issues/25" "$SUPERVISED_ROADMAP"
assert_contains "Roadmap links supervised canary issue #16" "issues/16" "$SUPERVISED_ROADMAP"
assert_contains "Roadmap links final publication issue #17" "issues/17" "$SUPERVISED_ROADMAP"
assert_not_contains "Overnight scope excludes the supervised canary" "issues/16" "$OVERNIGHT_ROADMAP"
assert_not_contains "Overnight scope excludes npm publication" "issues/17" "$OVERNIGHT_ROADMAP"
assert_contains "Roadmap explicitly excludes npm publication from overnight work" "Never publish npm" "$OVERNIGHT_ROADMAP"
assert_contains "Roadmap marks unattended v1.2 work complete" "unattended implementation and documentation slices are complete" "$OVERNIGHT_ROADMAP"
assert_in_order "Roadmap keeps canary before publication" "$SUPERVISED_ROADMAP" "issues/16" "issues/17"
assert_not_contains "Closed Claude conflict #7 leaves the open roadmap" "issues/7" "$ROADMAP_DOC"
assert_contains "Roadmap links next theme issue #4" "issues/4" "$ROADMAP_DOC"
assert_contains "Roadmap links next guided theme-pack issue #12" "issues/12" "$ROADMAP_DOC"
assert_contains "Roadmap links next theme-demo issue #13" "issues/13" "$ROADMAP_DOC"
assert_contains "Roadmap links next Stardew-inspired theme issue #14" "issues/14" "$ROADMAP_DOC"
assert_contains "Roadmap links GitHub issue and milestone HUD issue #23" "issues/23" "$ROADMAP_DOC"
assert_contains "Roadmap links checkpoint ETA learning issue #24" "issues/24" "$ROADMAP_DOC"
assert_contains "Roadmap names v1.3 as Priority 2" "## Priority 2 - Build v1.3.0" "$ROADMAP_DOC"
assert_in_order "Roadmap prioritizes Codex delivery context and learned ETA before theme expansion" "$ROADMAP_DOC" "## Priority 2 - Build v1.3.0" "issues/23" "issues/24" "issues/4" "issues/12" "issues/14" "issues/13"
assert_contains "Roadmap names v1.4 as Priority 3" "## Priority 3 - Expand v1.4.0" "$ROADMAP_DOC"
assert_contains "Roadmap links the v1.4 host and platform milestone" "v1.4.0 - Host and Platform Parity" "$ROADMAP_DOC"
assert_eq "Every roadmap release milestone links the standing documentation gate" "3" "$(grep -c '^\[Release documentation gate\](RELEASE_CHECKLIST.md)$' "$ROOT_DIR/ROADMAP.md")"
assert_contains "Roadmap assigns Windows renderer work to v1.4" "issues/3" "$ROADMAP_DOC"
assert_contains "Roadmap assigns Claude journey parity to v1.4" "issues/18" "$ROADMAP_DOC"
assert_contains "Roadmap assigns Codex SDLC v1.0 compatibility audit to v1.4" "issues/21" "$ROADMAP_DOC"
assert_in_order "Roadmap audits stable Codex SDLC before host expansion" "$ROADMAP_DOC" "## Priority 3 - Expand v1.4.0" "issues/21" "issues/18" "issues/3"
assert_not_contains "Roadmap does not duplicate open issue checklists" "- [ ]" "$ROADMAP_DOC"
assert_not_contains "Roadmap does not retain completed-history checklists" "- [x]" "$ROADMAP_DOC"
assert_contains "Roadmap identifies the active goal" "## Active Goal" "$ROADMAP_DOC"
assert_contains "Roadmap defines active completion criteria" "## Completion Criteria" "$ROADMAP_DOC"
assert_contains "Roadmap requires npm release verification" "npm view visualhud version" "$ROADMAP_DOC"
assert_contains "Roadmap requires non-publishing candidate CI before release completion" "Configured non-publishing candidate CI passes" "$ROADMAP_DOC"
assert_contains "Roadmap requires a release documentation audit" "release documentation audit passes" "$ROADMAP_DOC"
assert_contains "Roadmap requires a contributor-ready issue audit before milestone closure" "Every remaining open GitHub issue has current status, milestone, dependencies, and a contributor-ready next action" "$ROADMAP_DOC"
assert_contains "Roadmap records the landed exact-artifact correction" "785a801281e57527eb00c5acf8883ca0c966b510" "$ROADMAP_DOC"
assert_contains "Roadmap records the green correction CI" "32609262351" "$ROADMAP_DOC"
assert_contains "Roadmap records the accepted replacement candidate SHA" "fa3c6c20270ad32880347082d4abe242e306e96605c7a94c09798aff7eede4f1" "$ROADMAP_DOC"
assert_contains "Roadmap records the npm-authenticated dry-run blocker" "npm auth is currently unavailable" "$ROADMAP_DOC"
assert_contains "Roadmap records Nurse Joy pixel acceptance" "e767ad8bf8c8e504d4957ff1fcef922746a8acf889d0a602385ff71b53fecb37" "$ROADMAP_DOC"
assert_not_contains "Roadmap removes the completed rejected-candidate canary handoff" "Resume by opening iTerm2 with its Python API enabled" "$ROADMAP_DOC"
assert_contains "Roadmap records the Codex 0.147 live success-shape blocker" "Codex 0.147 emits successful PostToolUse responses" "$ROADMAP_DOC"
assert_contains "Roadmap keeps npm milestones open until publication" "A release milestone is not complete until the npm registry" "$ROADMAP_DOC"
assert_contains "Roadmap publishes release artifacts before milestone closure" "Release artifacts are published and verified before the milestone closes" "$ROADMAP_DOC"
assert_not_contains "Roadmap does not delegate active scope to GOALS.md" "GOALS.md" "$ROADMAP_DOC"
assert_contains "Codex SDLC skill defaults to medium effort" "effort: medium" "$SDLC_SKILL_DOC"
assert_contains "Codex project config defaults to medium reasoning" 'model_reasoning_effort = "medium"' "$CODEX_CONFIG_DOC"
assert_contains "Agent policy selects the balanced profile" "Selected profile: balanced" "$AGENTS_DOC"
assert_contains "Agent policy keeps high review escalation" "Sol high review" "$AGENTS_DOC"
assert_contains "Agent policy requires one proof-aware broad run" "one broad proof run total" "$AGENTS_DOC"
assert_contains "Agent policy reserves broad verification for one guarded proof" "Run focused tests during RED/GREEN; after self-review, run all tests exactly once through the guarded proof" "$AGENTS_DOC"
assert_not_contains "Agent policy removes the duplicate immediate full-suite rule" "**Run ALL tests**" "$AGENTS_DOC"
assert_contains "Self-review points to the single guarded proof" "Run the single full guarded proof from Before Every Task step 6 after this review" "$AGENTS_DOC"
assert_contains "SDLC skill uses prompt-only review for custom proof instructions" "prompt-only review" "$SDLC_SKILL_DOC"
assert_contains "SDLC skill forbids combining custom prompts with predefined review targets" "must not be combined with \`--uncommitted\`, \`--base\`, or \`--commit\`" "$SDLC_SKILL_DOC"
assert_contains "SDLC skill forbids redundant broad review tests" "Do not rerun tests" "$SDLC_SKILL_DOC"
assert_jq "Model profile selects balanced Sol medium" "$ROOT_DIR/.codex-sdlc/model-profile.json" '.selected_profile == "balanced" and .profiles.balanced.main_model == "gpt-5.6-sol" and .profiles.balanced.main_reasoning == "medium"'
assert_jq "Balanced profile keeps Sol high review" "$ROOT_DIR/.codex-sdlc/model-profile.json" '.profiles.balanced.review_model == "gpt-5.6-sol" and .profiles.balanced.review_reasoning == "high"'
assert_jq "Manifest records balanced medium baseline" "$ROOT_DIR/.codex-sdlc/manifest.json" '.model_profile.selected_profile == "balanced" and .model_profile.baseline_reasoning == "medium"'
assert_contains "Testing docs include calibration test" "test-theme-calibration" "$TESTING_DOC"
assert_contains "Architecture documents Claude adapter" "visualhud-claude.sh" "$ARCH_DOC"
assert_contains "Architecture documents terminal surface palette" "SetColors=tab" "$ARCH_DOC"
assert_contains "Architecture documents normal black surface palette" "SetColors=black" "$ARCH_DOC"
assert_contains "Architecture documents delayed reapply guard" "VISUALHUD_REAPPLY_DELAY" "$ARCH_DOC"
assert_contains "Architecture documents theme shades" "shades" "$ARCH_DOC"
assert_contains "Architecture documents source sprite backdrop colors" "backdrop_color" "$ARCH_DOC"
assert_contains "Architecture documents non-destructive context alerts" "selected theme stage color and primary sprite" "$ARCH_DOC"
assert_contains "Architecture documents visible source-backed context art" "deterministic side-by-side composite" "$ARCH_DOC"
assert_contains "Theme docs require context de-escalation rollback" "restore the unmodified primary image path" "$THEMES_DOC"
assert_contains "README says context art is renderer-visible" "separate right-side color and character layer" "$README_DOC"
assert_contains "Architecture documents theme selection precedence" "VISUALHUD_THEME > repo-local active theme file > VISUALHUD_DEFAULT_THEME > pokemon" "$ARCH_DOC"
assert_contains "Architecture does not treat tool count as completion" "telemetry, not completion" "$ARCH_DOC"
assert_contains "Architecture records a Codex-first task journey" "Codex-first task journey" "$ARCH_DOC"
assert_contains "Architecture makes characters optional for colors-only lanes" "character when the selected visual lane provides one" "$ARCH_DOC"
assert_contains "Architecture defers Claude journey parity" "Claude Code journey mapping is intentionally deferred" "$ARCH_DOC"
assert_contains "Architecture puts CI after local proof and PR creation" "configured CI/CD begins after" "$ARCH_DOC"
assert_contains "Architecture separates task and milestone progress" "Task journey and milestone progress are separate scopes" "$ARCH_DOC"
assert_contains "Architecture rolls back proof-invalidating CI failures" "A proof-invalidating CI failure moves the task journey back" "$ARCH_DOC"
assert_contains "Architecture preserves progress on transient CI failures" "A transient CI infrastructure or authentication failure remains at the CI gate" "$ARCH_DOC"
assert_contains "Theme docs document theme switch CLI" "./visualhud theme set" "$THEMES_DOC"
assert_contains "Theme docs require a working state" "\`working\` is mandatory" "$THEMES_DOC"
assert_contains "Theme docs require explicit HITL labeling" "HITL" "$THEMES_DOC"
assert_contains "Theme docs document active theme file" "repo-local active theme file" "$THEMES_DOC"
assert_contains "Theme docs document calibration review flow" "theme calibration" "$THEMES_DOC"
assert_no_repo_match "Public theme docs do not advertise legacy at/image/title schema" \
    '"at":|"image":|"title":' "$ROOT_DIR/README.md" "$ROOT_DIR/THEMES.md"
assert_no_repo_match "README does not describe the old Claude-only implementation as current" \
    'Current implementation lives in|No "needs attention" state|No smooth color blending|This README is the blueprint|Move hook scripts \+ sprites into this repo|install\.sh.*symlinks' "$ROOT_DIR/README.md"
echo ""

echo "--- Test 2: Shipped theme JSON files follow the contract ---"
while IFS= read -r theme_file; do
    theme_name=$(basename "$(dirname "$theme_file")")
    assert_jq "$theme_name has a display name" "$theme_file" '.name | type == "string" and length > 0'
    # shellcheck disable=SC2016
    assert_jq "$theme_name has ordered stages" "$theme_file" '
      (.stages | type == "array" and length > 0)
      and ([.stages[].max] as $maxes | all(range(1; $maxes | length); $maxes[.] > $maxes[. - 1]))
    '
    assert_jq "$theme_name uses data-only stage entries" "$theme_file" '
      all(.stages[]; (
        (.max | type == "number")
        and (.sprite | type == "string")
        and (.badge | type == "string")
        and (.name | type == "string" and length > 0)
        and (.color | type == "array" and length == 3)
        and (.color_family | type == "string" and length > 0)
        and (
          (.color_family_singleton == true)
          or ((.shades | type == "array") and (.shades | length > 1))
        )
      ))
    '
    # shellcheck disable=SC2016
    assert_jq "$theme_name has lifecycle states" "$theme_file" '
      . as $theme
      | all(["working", "permission", "blocked", "review", "done", "idle", "error"][]; . as $state |
        ($theme[$state].name | type == "string")
        and ($theme[$state].badge | type == "string")
        and ($theme[$state].sprite | type == "string")
        and ($theme[$state].color | type == "array" and length == 3)
      )
    '
    assert_jq "$theme_name labels human approval as HITL" "$theme_file" '
      (.blocked.badge | ascii_upcase | contains("HITL"))
      or (.blocked.name | ascii_upcase | contains("HITL"))
    '
    missing_sprites=$(
      jq -r '[.stages[].sprite, .stages[].shade_sprites[]?, .blocked.sprite, .done.sprite, .idle.sprite, .review.sprite, .context_alerts[].sprite?] | map(select(. != null and . != "")) | unique | .[]' "$theme_file" \
        | tr -d '\r' \
        | while IFS= read -r sprite_name; do
            if [ ! -f "$ROOT_DIR/themes/$theme_name/sprites/$sprite_name.png" ]; then
                printf '%s\n' "$sprite_name"
            fi
        done
    )
    assert_eq "$theme_name ships theme-local sprites for every referenced sprite" "" "$missing_sprites"
    assert_jq "$theme_name RGB values stay in terminal-safe range" "$theme_file" '
      [
        .working.color[],
        .permission.color[],
        .stages[].color[],
        .blocked.color[],
        .review.color[],
        .done.color[],
        .idle.color[],
        .error.color[],
        .context_alerts.warning.color[],
        .context_alerts.critical.color[]
      ] | all(. >= 0 and . <= 255)
    '
    assert_jq "$theme_name context alert thresholds are ordered" "$theme_file" '
      (.context_alerts.warning.min_percent | type == "number")
      and (.context_alerts.critical.min_percent | type == "number")
      and (.context_alerts.warning.min_percent < .context_alerts.critical.min_percent)
    '
    assert_jq "$theme_name color families either shade or declare singleton" "$theme_file" '
      all(.stages[]; (
        (.color_family_singleton == true)
        or (
          [.shades[]]
          | unique
          | length > 1
        )
      ))
    '
    # shellcheck disable=SC2016
    assert_jq "$theme_name shade sprite variants match shade ramps when present" "$theme_file" '
      all(.stages[]; . as $stage |
        (
          ($stage.shade_sprites == null)
          or (
            ($stage.shade_sprites | type == "array")
            and ($stage.shade_sprites | length == ($stage.shades | length))
            and all($stage.shade_sprites[]; type == "string" and length > 0)
          )
        )
      )
    '
done < <(find "$ROOT_DIR/themes" -mindepth 2 -maxdepth 2 -name theme.json | sort)
assert_jq "TMNT Raphael red band defines per-shade sprite variants" "$ROOT_DIR/themes/tmnt/theme.json" '
  .stages[]
  | select(.name == "Raphael")
  | .shade_sprites == ["tmnt-raphael", "tmnt-raphael-red-2", "tmnt-raphael-red-3"]
'
# shellcheck disable=SC2016
assert_jq "TMNT every multi-shade stage defines per-shade sprite variants" "$ROOT_DIR/themes/tmnt/theme.json" '
  all(.stages[]; . as $stage |
    (($stage.shades | length) <= 1)
    or (
      ($stage.shade_sprites | type == "array")
      and ($stage.shade_sprites | length == ($stage.shades | length))
      and ($stage.shade_sprites[0] == $stage.sprite)
    )
  )
'
# shellcheck disable=SC2016
assert_jq "Pokemon lifecycle and context states use filled unique non-stage sprites" "$ROOT_DIR/themes/pokemon/theme.json" '
  . as $theme
  | ([.stages[].sprite, .stages[].shade_sprites[]?] | unique) as $stage_sprites
  | [
      .blocked.sprite,
      .review.sprite,
      .done.sprite,
      .idle.sprite,
      .error.sprite,
      .context_alerts.warning.sprite,
      .context_alerts.critical.sprite
    ] as $state_sprites
  | all($state_sprites[]; type == "string" and length > 0)
    and (($state_sprites | unique | length) == ($state_sprites | length))
    and all($state_sprites[]; . as $sprite | ($stage_sprites | index($sprite) | not))
'
# shellcheck disable=SC2016
assert_jq "Power Rangers remains a shipped colors-only theme until source-backed sprites land" "$ROOT_DIR/themes/power-rangers/theme.json" '
  ([
    .stages[].sprite,
    .blocked.sprite,
    .review.sprite,
    .done.sprite,
    .idle.sprite,
    .error.sprite,
    (.plan.sprite // ""),
    (.compacting.sprite // ""),
    (.subagent.sprite // ""),
    (.context_alerts.warning.sprite // ""),
    (.context_alerts.critical.sprite // "")
  ] | all(. == ""))
  and ([.stages[].name] == [
    "Red Ranger",
    "Blue Ranger",
    "Yellow Ranger",
    "Pink Ranger",
    "Black Ranger",
    "Green Ranger",
    "White Ranger",
    "Gold Ranger",
    "Megazord",
    "Dragonzord",
    "Ultrazord"
  ])
'
# shellcheck disable=SC2016
assert_jq "Power Rangers uses shade ramps instead of singleton color flashes" "$ROOT_DIR/themes/power-rangers/theme.json" '
  all(.stages[]; (
    (.color_family_singleton != true)
    and (.shades | type == "array")
    and (.shades | length >= 2)
    and all(.shades[]; (type == "array") and (length == 3) and all(.[]; . >= 0 and . <= 255))
  ))
  and (.stages[0].shades | length == 2)
  and (.stages[1].shades | length == 3)
  and (.stages[2].shades[0] == [150, 120, 20])
'

assert_jq "Power Rangers colors-only stages use balanced dwell pacing" "$ROOT_DIR/themes/power-rangers/theme.json" '
  [.stages[0:10][].max] == [6, 12, 18, 24, 30, 36, 42, 48, 54, 60]
'

while IFS= read -r fast_theme_file; do
    assert_jq "$(basename "$(dirname "$fast_theme_file")") fast-start stages use shade ramps" "$fast_theme_file" '
      if ((.stages | length) >= 3 and .stages[0].max <= 2 and .stages[1].max <= 5 and .stages[2].max <= 12) then
        all(.stages[]; (
          (.color_family_singleton != true)
          and (.shades | type == "array")
          and (.shades | length >= 2)
        ))
      else
        true
      end
    '
done < <(find "$ROOT_DIR/themes" -mindepth 2 -maxdepth 2 -name theme.json | sort)
echo ""

echo "--- Test 3: Pokemon visual smoke renders filled lifecycle/context sprites ---"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/visualhud-theme-system.XXXXXX")
POKEMON_CONTACT_SHEET="$TMP_ROOT/pokemon-contact-sheet.png"
POKEMON_CONTACT_REPORT="$TMP_ROOT/pokemon-contact-sheet.json"
python3 "$ROOT_DIR/scripts/render-theme-contact-sheet.py" \
    --theme "$ROOT_DIR/themes/pokemon/theme.json" \
    --sprites-dir "$ROOT_DIR/themes/pokemon/sprites" \
    --output "$POKEMON_CONTACT_SHEET" \
    --report "$POKEMON_CONTACT_REPORT"

assert_file_exists "Pokemon visual smoke writes contact sheet" "$POKEMON_CONTACT_SHEET"
assert_file_exists "Pokemon visual smoke writes report" "$POKEMON_CONTACT_REPORT"
assert_eq "Pokemon visual smoke covers stages/lifecycle/context" \
    "18" \
    "$(jq -r '.entries | length' "$POKEMON_CONTACT_REPORT")"
assert_eq "Pokemon visual smoke has no missing sprite-backed states" \
    "" \
    "$(jq -r '.missing_sprites | join(",")' "$POKEMON_CONTACT_REPORT")"
assert_eq "Pokemon lifecycle/context visual smoke has no empty sprite cards" \
    "" \
    "$(jq -r '[.entries[] | select((.kind != "stage") and (.kind != "stage-shade") and ((.sprite // "") == "")) | "\(.kind):\(.name)"] | join(",")' "$POKEMON_CONTACT_REPORT")"
assert_eq "Pokemon lifecycle/context visual smoke uses unique sprites" \
    "" \
    "$(jq -r '[.entries[] | select((.kind != "stage") and (.kind != "stage-shade")) | .sprite] | group_by(.) | map(select(length > 1) | .[0]) | join(",")' "$POKEMON_CONTACT_REPORT")"
assert_contains "Pokemon visual smoke covers Alakazam review" \
    "review:Reviewing:alakazam" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite // "")"] | join(",")' "$POKEMON_CONTACT_REPORT")"
assert_contains "Pokemon visual smoke covers Mew done state" \
    "done:Complete:mew" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite // "")"] | join(",")' "$POKEMON_CONTACT_REPORT")"
assert_contains "Pokemon visual smoke covers Nurse Joy/Blissey context" \
    "context:Nurse Joy:blissey" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite // "")"] | join(",")' "$POKEMON_CONTACT_REPORT")"
echo ""

echo "--- Test 4: Engine accepts a third theme by JSON only ---"
THIRD_THEME="$TMP_ROOT/themes/third"
mkdir -p "$THIRD_THEME/sprites"

cat > "$THIRD_THEME/theme.json" <<'JSON'
{
  "name": "Third Theme Fixture",
  "progress_bar": ["A", "B", "G"],
  "stages": [
    { "max": 1, "sprite": "alpha", "badge": "A", "name": "Alpha", "color": [10, 20, 30] },
    { "max": 3, "sprite": "beta", "badge": "B", "name": "Beta", "color": [40, 50, 60] },
    { "max": 999999, "sprite": "gamma", "badge": "G", "name": "Gamma", "color": [70, 80, 90] }
  ],
  "blocked": { "sprite": "blocked", "badge": "BLOCK", "name": "Blocked", "color": [90, 80, 70] },
  "review": { "sprite": "review", "badge": "REV", "name": "Reviewing", "stage": 2, "color": [80, 120, 200] },
  "done": { "sprite": "done", "badge": "DONE", "name": "Done", "stage": 3, "color": [20, 180, 90] },
  "idle": { "sprite": "idle", "badge": "IDLE", "name": "Idle", "stage": 3, "color": [45, 120, 160] },
  "error": { "sprite": "error", "badge": "ERR", "name": "Error", "color": [255, 20, 20] },
  "context_alerts": {
    "warning": { "min_percent": 70, "badge": "LOW", "name": "Battery Low", "color": [200, 180, 40] },
    "critical": { "min_percent": 85, "badge": "MAX", "name": "Critical Mass", "color": [255, 255, 255] }
  }
}
JSON

python3 - "$THIRD_THEME/sprites" <<'PY'
from pathlib import Path
from PIL import Image
import sys

sprites_dir = Path(sys.argv[1])
colors = {
    "alpha": (10, 20, 30),
    "beta": (40, 50, 60),
    "gamma": (70, 80, 90),
    "blocked": (90, 80, 70),
    "review": (80, 120, 200),
    "done": (20, 180, 90),
    "idle": (45, 120, 160),
    "error": (255, 20, 20),
}
for name, color in colors.items():
    Image.new("RGB", (32, 32), color).save(sprites_dir / f"{name}.png")
PY

SET_BG_LOG="$TMP_ROOT/set-bg.log"
TTY_LOG="$TMP_ROOT/tty.log"
MOCK_SET_BG="$TMP_ROOT/set_bg.py"
cat > "$MOCK_SET_BG" <<'PY'
import os
import sys

with open(os.environ["VISUALHUD_SET_BG_LOG"], "a", encoding="utf-8") as handle:
    handle.write((sys.argv[1] if len(sys.argv) > 1 else "") + "\n")
PY

export VISUALHUD_THEMES_DIR="$TMP_ROOT/themes"
export VISUALHUD_THEME="third"
export VISUALHUD_SET_BG="$MOCK_SET_BG"
export VISUALHUD_SET_BG_LOG="$SET_BG_LOG"
export VISUALHUD_TTY="$TTY_LOG"
export VISUALHUD_BG="on"

run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "third-theme"}'
assert_eq "Third theme count 1 uses Alpha sprite" "alpha" "$(cat "$STAGE_FILE" 2>/dev/null)"
assert_contains "Third theme writes Alpha tint escape" "SetColors=bg=030609" "$(cat "$TTY_LOG" 2>/dev/null)"

rm -f "$COUNTER_FILE" "$STAGE_FILE"
VISUALHUD_TTY=/dev/null run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "third-theme"}'
for _ in 1 2 3 4 5; do
    [ -f "$SET_BG_LOG" ] && break
    sleep 0.1
done
assert_eq "Third theme calls set_bg with theme-local Alpha sprite when VISUALHUD_BG=on" \
    "$(cygpath -m "$THIRD_THEME/sprites/alpha.png" 2>/dev/null || printf '%s' "$THIRD_THEME/sprites/alpha.png")" \
    "$(tail -n 1 "$SET_BG_LOG" 2>/dev/null)"

: > "$TTY_LOG"
printf '1' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "third-theme"}'
assert_eq "Third theme count 2 uses Beta sprite" "beta" "$(cat "$STAGE_FILE" 2>/dev/null)"
assert_contains "Third theme writes Beta tint escape" "SetColors=bg=0c0f12" "$(cat "$TTY_LOG" 2>/dev/null)"

: > "$TTY_LOG"
printf '1' > "$COUNTER_FILE"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "third-theme", "info": {"last_token_usage": {"total_tokens": 183000}, "model_context_window": 258400}}'
assert_eq "Third theme warning context keeps Beta sprite" "beta" "$(cat "$STAGE_FILE" 2>/dev/null)"
assert_contains "Third theme warning context keeps Beta tint" "SetColors=bg=0c0f12" "$(cat "$TTY_LOG" 2>/dev/null)"
assert_contains "Third theme warning context labels token pressure" "Battery Low CTX 70%" "$(cat "$TTY_LOG" 2>/dev/null)"

: > "$TTY_LOG"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Read", "session_id": "third-theme", "info": {"last_token_usage": {"total_tokens": 220000}, "model_context_window": 258400}}'
assert_contains "Third theme critical context keeps active stage tint" "SetColors=bg=0c0f12" "$(cat "$TTY_LOG" 2>/dev/null)"
assert_contains "Third theme critical context labels token pressure" "Critical Mass CTX 85%" "$(cat "$TTY_LOG" 2>/dev/null)"
assert_not_contains "Third theme critical context does not emergency-wash the pane" "SetColors=bg=4c4c4c" "$(cat "$TTY_LOG" 2>/dev/null)"

: > "$TTY_LOG"
run_hook '{"hook_event_name": "Stop", "session_id": "third-theme"}'
assert_eq "Third theme Stop uses Done sprite" "done" "$(cat "$STAGE_FILE" 2>/dev/null)"
assert_contains "Third theme Stop title uses Done name" "Done" "$(cat "$TTY_LOG" 2>/dev/null)"

: > "$TTY_LOG"
run_hook '{"hook_event_name": "PreToolUse", "tool_name": "Task", "tool_input": {"description": "code review fixture"}, "session_id": "third-theme"}'
assert_eq "Third theme code review uses Review sprite" "review" "$(cat "$STAGE_FILE" 2>/dev/null)"
assert_contains "Third theme review title uses Review name" "Reviewing" "$(cat "$TTY_LOG" 2>/dev/null)"
echo ""

echo "--- Test 5: Visual smoke can render the third theme contact sheet ---"
CONTACT_SHEET="$TMP_ROOT/third-contact-sheet.png"
CONTACT_REPORT="$TMP_ROOT/third-contact-sheet.json"
python3 "$ROOT_DIR/scripts/render-theme-contact-sheet.py" \
    --theme "$THIRD_THEME/theme.json" \
    --sprites-dir "$THIRD_THEME/sprites" \
    --output "$CONTACT_SHEET" \
    --report "$CONTACT_REPORT"

assert_file_exists "Third theme visual smoke writes contact sheet" "$CONTACT_SHEET"
assert_file_exists "Third theme visual smoke writes report" "$CONTACT_REPORT"
assert_eq "Third theme visual smoke covers stages/lifecycle/context" \
    "10" \
    "$(jq -r '.entries | length' "$CONTACT_REPORT")"
assert_eq "Third theme visual smoke has no missing sprite-backed states" \
    "" \
    "$(jq -r '.missing_sprites | join(",")' "$CONTACT_REPORT")"
assert_contains "Third theme visual smoke covers Beta" \
    "stage:Beta:beta:40-50-60" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite // ""):\(.color | join("-"))"] | join(",")' "$CONTACT_REPORT")"
assert_contains "Third theme visual smoke covers Critical Mass" \
    "context:Critical Mass::255-255-255" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite // ""):\(.color | join("-"))"] | join(",")' "$CONTACT_REPORT")"
assert_contains "Third theme visual smoke covers review lifecycle" \
    "review:Reviewing:review:80-120-200" \
    "$(jq -r '[.entries[] | "\(.kind):\(.name):\(.sprite // ""):\(.color | join("-"))"] | join(",")' "$CONTACT_REPORT")"
echo ""

cleanup

echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
