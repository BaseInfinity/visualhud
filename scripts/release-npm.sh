#!/bin/bash
# Safe npm release gate for VisualHUD.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MODE="dry-run"

usage() {
    cat <<'EOF'
Usage:
  scripts/release-npm.sh --dry-run
  scripts/release-npm.sh --publish

Runs the full release gate from a clean worktree:
  1. npm auth check
  2. npm test
  3. npm publish --dry-run
  4. optional real npm publish + registry verification
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run)
            MODE="dry-run"
            ;;
        --publish)
            MODE="publish"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

cd "$ROOT_DIR"

if [ -n "$(git status --porcelain)" ]; then
    printf 'Worktree is dirty; commit or stash changes before release.\n' >&2
    exit 1
fi

if ! npm whoami >/dev/null 2>&1; then
    printf 'npm auth is not available. Run npm login, then retry.\n' >&2
    exit 1
fi

export NPM_CONFIG_CACHE="${VISUALHUD_RELEASE_NPM_CACHE:-${NPM_CONFIG_CACHE:-${TMPDIR:-/tmp}/visualhud-npm-cache}}"
export npm_config_cache="$NPM_CONFIG_CACHE"
unset NPM_CONFIG_DRY_RUN npm_config_dry_run || true
mkdir -p "$NPM_CONFIG_CACHE"

package_name="$(jq -r '.name' package.json)"
package_version="$(jq -r '.version' package.json)"
package_ref="${package_name}@${package_version}"

printf 'Releasing %s (%s).\n' "$package_ref" "$MODE"

npm test
npm publish --access public --dry-run

if [ "$MODE" = "dry-run" ]; then
    printf 'Dry-run complete; no package was published.\n'
    exit 0
fi

npm publish --access public

published_version="$(npm view "$package_ref" version)"
if [ "$published_version" != "$package_version" ]; then
    printf 'Publish verification failed: registry has %s for %s, expected %s.\n' \
        "$published_version" "$package_ref" "$package_version" >&2
    exit 1
fi

printf 'Published %s.\n' "$package_ref"
