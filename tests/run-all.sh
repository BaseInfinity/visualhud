#!/bin/bash
# Full VisualHUD verification suite used before publish/commit.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

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

bash tests/test-state-dir-portability.sh
bash tests/test-visualhud-cli.sh
bash tests/test-visualhud-install.sh
bash tests/test-visualhud-install-global.sh
bash tests/test-windows-runtime-no-jq.sh
bash tests/test-wezterm-renderer.sh
bash tests/test-visualhud-skills.sh
bash tests/test-npm-package.sh
bash tests/test-npm-release.sh
node tests/test-pokemon-theme-lifecycle.js
bash tests/test-theme-system.sh
bash tests/test-theme-calibration.sh
bash tests/test-codex-visualhud.sh
bash tests/test-cooking-status.sh
bash tests/test-claude-visualhud.sh
bash tests/test-codex-git-guard.sh

shellcheck_normalized visualhud ./*.sh scripts/*.sh tests/*.sh .codex/hooks/*.sh .claude/hooks/*.sh engine.sh
jq empty .codex/hooks.json .claude/settings.json themes/pokemon/theme.json themes/tmnt/theme.json themes/tmnt/sprites/manifest.json package.json
PYTHONPYCACHEPREFIX="${PYTHONPYCACHEPREFIX:-/tmp/visualhud-pycache}" \
    python3 -m py_compile scripts/import-tmnt-sprites.py scripts/render-theme-contact-sheet.py scripts/theme-calibration-steps.py
git diff --check

if find scripts -path '*/__pycache__/*' -type f | grep -q .; then
    printf 'Generated Python bytecode found under scripts/; remove __pycache__ before shipping.\n' >&2
    exit 1
fi
