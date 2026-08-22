#!/bin/bash
# Full VisualHUD verification suite used before publish/commit.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
SUITE_CAPTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/visualhud-suite-capture.XXXXXX")"

cleanup() {
    rm -rf "$SUITE_CAPTURE_ROOT"
}
trap cleanup EXIT

run_isolated() {
    env -u ITERM_SESSION_ID -u WT_SESSION -u WEZTERM_PANE \
        -u VISUALHUD_TTY -u VISUALHUD_SET_BG -u VISUALHUD_SET_BG_LOG \
        -u VISUALHUD_RENDERER -u VISUALHUD_BG \
        VISUALHUD_TEST_CAPTURE_DIR="$SUITE_CAPTURE_ROOT" \
        "$@"
}

shellcheck_normalized() {
    local tmp_lint status file
    local normalized=()

    tmp_lint=$(mktemp -d "${TMPDIR:-/tmp}/visualhud-shellcheck.XXXXXX")
    status=0

    for file in "$@"; do
        mkdir -p "$tmp_lint/$(dirname "$file")"
        tr -d '\r' < "$file" > "$tmp_lint/$file"
        normalized+=("$tmp_lint/$file")
    done

    shellcheck "${normalized[@]}" || status=$?
    rm -rf "$tmp_lint"
    return "$status"
}

run_isolated bash tests/test-state-dir-portability.sh
run_isolated bash tests/test-visualhud-cli.sh
run_isolated bash tests/test-visualhud-install.sh
run_isolated bash tests/test-visualhud-install-global.sh
run_isolated bash tests/test-windows-runtime-no-jq.sh
run_isolated bash tests/test-wezterm-renderer.sh
run_isolated bash tests/test-host-renderer-matrix.sh
run_isolated bash tests/test-iterm-canary.sh
run_isolated bash tests/test-visualhud-skills.sh
run_isolated bash tests/test-npm-package.sh
run_isolated bash tests/test-npm-release.sh
run_isolated node tests/test-pokemon-theme-lifecycle.js
run_isolated bash tests/test-theme-system.sh
run_isolated bash tests/test-context-overlay.sh
run_isolated bash tests/test-theme-calibration.sh
run_isolated bash tests/test-codex-visualhud.sh
run_isolated bash tests/test-journey-state.sh
run_isolated bash tests/test-cooking-status.sh
run_isolated bash tests/test-claude-visualhud.sh
run_isolated bash tests/test-codex-git-guard.sh
run_isolated bash tests/test-review-workflow.sh

shellcheck_normalized visualhud ./*.sh scripts/*.sh tests/*.sh .codex/hooks/*.sh .claude/hooks/*.sh engine.sh
jq empty .codex/hooks.json .claude/settings.json themes/pokemon/theme.json themes/tmnt/theme.json themes/tmnt/sprites/manifest.json package.json
PYTHONPYCACHEPREFIX="${PYTHONPYCACHEPREFIX:-/tmp/visualhud-pycache}" \
    python3 -m py_compile set_bg.py scripts/import-tmnt-sprites.py \
        scripts/render-theme-contact-sheet.py scripts/theme-calibration-steps.py \
        scripts/visualhud-iterm-canary.py scripts/visualhud_context_overlay.py
git diff --check

if find scripts -path '*/__pycache__/*' -type f | grep -q .; then
    printf 'Generated Python bytecode found under scripts/; remove __pycache__ before shipping.\n' >&2
    exit 1
fi
