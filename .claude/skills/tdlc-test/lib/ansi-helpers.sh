#!/bin/bash
# Sourceable bash helpers for asserting on raw PTY captures produced by pty-run.py.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/ansi-helpers.sh"
#   pty_run --out "$CAP" -- ./engine.sh < some-input
#   assert_ansi_contains "$CAP" $'\e[31m'              # raw red SGR present
#   assert_text_contains "$CAP" "RED"                  # human-readable text present
#   snapshot_assert "$CAP" engine-renders-badge        # diff vs ./snapshots/<name>.txt

set -uo pipefail

# ---- locate the harness ----------------------------------------------------

TDLC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TDLC_SKILL_DIR="$(dirname "$TDLC_LIB_DIR")"
TDLC_SNAPSHOTS_DIR="${TDLC_SNAPSHOTS_DIR:-$TDLC_SKILL_DIR/snapshots}"

# Run the PTY harness. Forwards all args. Always honor a per-test timeout via TDLC_TIMEOUT.
pty_run() {
    if [[ -n "${TDLC_TIMEOUT:-}" ]]; then
        "$TDLC_LIB_DIR/pty-run.py" --timeout "$TDLC_TIMEOUT" "$@"
    else
        "$TDLC_LIB_DIR/pty-run.py" "$@"
    fi
}

# ---- counters --------------------------------------------------------------

TDLC_PASS=${TDLC_PASS:-0}
TDLC_FAIL=${TDLC_FAIL:-0}

_tdlc_pass() { TDLC_PASS=$((TDLC_PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
_tdlc_fail() { TDLC_FAIL=$((TDLC_FAIL + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; printf '        %s\n' "$2"; }

tdlc_summary() {
    local total=$((TDLC_PASS + TDLC_FAIL))
    printf '\n%s/%s passed' "$TDLC_PASS" "$total"
    [[ "$TDLC_FAIL" -gt 0 ]] && { printf ' — \033[31m%s failed\033[0m\n' "$TDLC_FAIL"; return 1; }
    printf ' \033[32m✓\033[0m\n'
}

# ---- ANSI manipulation -----------------------------------------------------

# strip_ansi <file> -> stdout
# Removes CSI sequences (\e[...letter), OSC sequences (\e]...\a or \e]...\e\\),
# and lone control chars that don't affect rendered text.
strip_ansi() {
    local file="$1"
    # CSI: ESC [ ... <final byte 0x40-0x7E>
    # OSC: ESC ] ... BEL  or  ESC ] ... ESC \
    # Also drops SS3 ESC O <char>, plain ESC c (reset), and \r
    LC_ALL=C perl -pe '
        s/\e\[[0-?]*[ -\/]*[@-~]//g;
        s/\e\][^\a\e]*(?:\a|\e\\)//g;
        s/\eO.//g;
        s/\ec//g;
        s/\r//g;
    ' "$file"
}

# ---- assertions ------------------------------------------------------------

# assert_ansi_contains <file> <byte-pattern> [label]
# Looks for the literal byte sequence in the raw capture (ANSI included).
# Example: assert_ansi_contains "$CAP" $'\e[31m' "red SGR"
assert_ansi_contains() {
    local file="$1" pat="$2" label="${3:-ansi contains $(printf '%q' "$pat")}"
    if LC_ALL=C grep -F -q -- "$pat" "$file"; then
        _tdlc_pass "$label"
    else
        _tdlc_fail "$label" "pattern not found in $file"
    fi
}

# assert_text_contains <file> <text> [label]
# Strips ANSI first, then greps for the human-visible text.
assert_text_contains() {
    local file="$1" needle="$2" label="${3:-text contains \"$2\"}"
    if strip_ansi "$file" | LC_ALL=C grep -F -q -- "$needle"; then
        _tdlc_pass "$label"
    else
        _tdlc_fail "$label" "\"$needle\" not in stripped output of $file"
    fi
}

# assert_text_matches <file> <regex> [label]
# Strips ANSI first, then matches a regex (extended).
assert_text_matches() {
    local file="$1" pat="$2" label="${3:-text matches /$2/}"
    if strip_ansi "$file" | LC_ALL=C grep -E -q -- "$pat"; then
        _tdlc_pass "$label"
    else
        _tdlc_fail "$label" "regex /$pat/ did not match stripped output of $file"
    fi
}

# assert_exit_code <expected> <actual> [label]
assert_exit_code() {
    local want="$1" got="$2" label="${3:-exit code is $1}"
    if [[ "$got" == "$want" ]]; then
        _tdlc_pass "$label"
    else
        _tdlc_fail "$label" "expected exit $want, got $got"
    fi
}

# ---- snapshots -------------------------------------------------------------

# snapshot_assert <file> <name>
# Compares strip_ansi(<file>) against snapshots/<name>.txt.
# If the snapshot does not exist, it is created and the assertion passes (golden).
# Set TDLC_UPDATE_SNAPSHOTS=1 to overwrite all existing snapshots.
snapshot_assert() {
    local file="$1" name="$2" label="snapshot $2"
    local golden="$TDLC_SNAPSHOTS_DIR/$name.txt"
    mkdir -p "$TDLC_SNAPSHOTS_DIR"

    if [[ ! -f "$golden" ]] || [[ "${TDLC_UPDATE_SNAPSHOTS:-0}" == "1" ]]; then
        strip_ansi "$file" > "$golden"
        _tdlc_pass "$label (recorded)"
        return 0
    fi

    local actual
    actual="$(mktemp)"
    strip_ansi "$file" > "$actual"
    if diff -q "$golden" "$actual" >/dev/null 2>&1; then
        _tdlc_pass "$label"
        rm -f "$actual"
    else
        local d
        d="$(diff -u "$golden" "$actual" | head -40)"
        _tdlc_fail "$label" "snapshot drift (run with TDLC_UPDATE_SNAPSHOTS=1 to accept):
$d"
        rm -f "$actual"
    fi
}
