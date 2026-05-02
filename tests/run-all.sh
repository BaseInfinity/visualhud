#!/bin/bash
# Full VisualHUD verification suite used before publish/commit.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

bash tests/test-visualhud-cli.sh
bash tests/test-visualhud-install.sh
bash tests/test-visualhud-skills.sh
bash tests/test-npm-package.sh
bash tests/test-npm-release.sh
bash tests/test-theme-system.sh
bash tests/test-theme-calibration.sh
bash tests/test-codex-visualhud.sh
bash tests/test-cooking-status.sh
bash tests/test-claude-visualhud.sh
bash tests/test-codex-bash-guard.sh

shellcheck visualhud ./*.sh scripts/*.sh tests/*.sh .codex/hooks/*.sh .claude/hooks/*.sh engine.sh
jq empty .codex/hooks.json .claude/settings.json themes/pokemon/theme.json themes/tmnt/theme.json themes/tmnt/sprites/manifest.json package.json
PYTHONPYCACHEPREFIX="${PYTHONPYCACHEPREFIX:-/tmp/visualhud-pycache}" \
    python3 -m py_compile scripts/import-tmnt-sprites.py scripts/render-theme-contact-sheet.py scripts/theme-calibration-steps.py
git diff --check

if find scripts -path '*/__pycache__/*' -type f | grep -q .; then
    printf 'Generated Python bytecode found under scripts/; remove __pycache__ before shipping.\n' >&2
    exit 1
fi
