#!/bin/bash
# tdlc-test: end-to-end smoke test for the PTY harness + ANSI assertions.
#
# Proves three things at once:
#   1. The PTY harness captures real escape sequences (not stripped by tty detection).
#   2. assert_ansi_contains finds raw byte patterns.
#   3. assert_text_contains works after strip_ansi.
#   4. snapshot_assert records on first run, diffs on subsequent runs.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/ansi-helpers.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

CAP="$TMP/capture.bin"

# Run a command that emits red + bold-cyan + a bell.
pty_run --out "$CAP" --timeout 3 -- bash -c '
    printf "\033[31mRED\033[0m\n"
    printf "\033[1;36mCYAN BOLD\033[0m\n"
    printf "plain line\n"
'
exit_code=$?

assert_exit_code 0 "$exit_code" "wrapped bash exits 0"

# Raw ANSI bytes
assert_ansi_contains "$CAP" $'\e[31m'   "red SGR present"
assert_ansi_contains "$CAP" $'\e[1;36m' "bold cyan SGR present"
assert_ansi_contains "$CAP" $'\e[0m'    "reset SGR present"

# Human-readable text after stripping ANSI
assert_text_contains "$CAP" "RED"        "RED text rendered"
assert_text_contains "$CAP" "CYAN BOLD"  "CYAN BOLD text rendered"
assert_text_contains "$CAP" "plain line" "plain line rendered"

# Regex
assert_text_matches "$CAP" "^RED$"      "RED appears on its own line"

# Snapshot — records on first run, diffs after that
snapshot_assert "$CAP" "ansi-roundtrip"

tdlc_summary
