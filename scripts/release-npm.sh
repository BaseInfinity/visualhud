#!/bin/bash
# Safe npm release gate for VisualHUD.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MODE="dry-run"
CANDIDATE=""
EXPECTED_SHA256=""

usage() {
    cat <<'EOF'
Usage:
  scripts/release-npm.sh --dry-run --candidate /absolute/path/to/visualhud-1.2.0.tgz --sha256 <accepted-sha256>
  scripts/release-npm.sh --publish --candidate /absolute/path/to/visualhud-1.2.0.tgz --sha256 <accepted-sha256>

Verifies and publishes the exact retained release candidate from a clean worktree:
  1. candidate path, SHA-256, package name, and version
  2. npm auth check
  3. npm publish <candidate> --ignore-scripts --dry-run
  4. optional real npm publish <candidate> + registry verification

The source proof must already be frozen and green. This helper does not repack
the source tree or rerun its broad test suite.
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
        --candidate)
            if [ "$#" -lt 2 ]; then
                printf '%s\n' '--candidate requires a value.' >&2
                exit 2
            fi
            CANDIDATE="$2"
            shift
            ;;
        --sha256)
            if [ "$#" -lt 2 ]; then
                printf '%s\n' '--sha256 requires a value.' >&2
                exit 2
            fi
            EXPECTED_SHA256="$2"
            shift
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

if [ -z "$CANDIDATE" ] || [ -z "$EXPECTED_SHA256" ]; then
    printf '%s\n' '--candidate and --sha256 are required.' >&2
    usage >&2
    exit 2
fi

case "$CANDIDATE" in
    /*) ;;
    *)
        printf 'Candidate path must be absolute: %s\n' "$CANDIDATE" >&2
        exit 1
        ;;
esac

if [ ! -f "$CANDIDATE" ] || [ -L "$CANDIDATE" ]; then
    printf 'Candidate must be a regular, non-symlink file: %s\n' "$CANDIDATE" >&2
    exit 1
fi

if [[ ! "$EXPECTED_SHA256" =~ ^[0-9a-fA-F]{64}$ ]]; then
    printf 'Accepted SHA-256 must contain exactly 64 hexadecimal characters.\n' >&2
    exit 1
fi

EXPECTED_SHA256="$(printf '%s' "$EXPECTED_SHA256" | tr '[:upper:]' '[:lower:]')"
ACTUAL_SHA256="$(shasum -a 256 "$CANDIDATE" | awk '{print $1}')"
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
    printf 'Candidate SHA-256 mismatch: expected %s, got %s.\n' \
        "$EXPECTED_SHA256" "$ACTUAL_SHA256" >&2
    exit 1
fi

if ! CANDIDATE_MANIFEST="$(tar -xOf "$CANDIDATE" package/package.json 2>/dev/null)"; then
    printf 'Candidate does not contain a readable package/package.json: %s\n' "$CANDIDATE" >&2
    exit 1
fi

cd "$ROOT_DIR"

package_name="$(jq -er '.name | select(type == "string" and length > 0)' package.json)"
package_version="$(jq -er '.version | select(type == "string" and length > 0)' package.json)"
candidate_name="$(printf '%s' "$CANDIDATE_MANIFEST" | jq -er '.name | select(type == "string" and length > 0)')"
candidate_version="$(printf '%s' "$CANDIDATE_MANIFEST" | jq -er '.version | select(type == "string" and length > 0)')"

if [ "$candidate_name" != "$package_name" ] || [ "$candidate_version" != "$package_version" ]; then
    printf 'Candidate package identity mismatch: expected %s@%s, got %s@%s.\n' \
        "$package_name" "$package_version" "$candidate_name" "$candidate_version" >&2
    exit 1
fi

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

package_ref="${package_name}@${package_version}"

printf 'Releasing retained %s candidate %s (SHA-256 %s; %s).\n' \
    "$package_ref" "$CANDIDATE" "$ACTUAL_SHA256" "$MODE"

npm publish "$CANDIDATE" --access public --ignore-scripts --dry-run

if [ "$MODE" = "dry-run" ]; then
    printf 'Dry-run complete; no package was published.\n'
    exit 0
fi

npm publish "$CANDIDATE" --access public --ignore-scripts

published_version="$(npm view "$package_ref" version)"
if [ "$published_version" != "$package_version" ]; then
    printf 'Publish verification failed: registry has %s for %s, expected %s.\n' \
        "$published_version" "$package_ref" "$package_version" >&2
    exit 1
fi

printf 'Published %s.\n' "$package_ref"
