---
name: tdlc-test
description: Test terminal/TUI output by running commands inside a real PTY and asserting on the actual rendered ANSI/escape sequences. Use when integration tests with mocked escape codes can't catch rendering bugs (visualhud engine output, white-rabbit game loop, badge/cooking-status hooks). Lighter than computer-use; heavier than unit tests. Prototype skill — case study #1 for a possible TDLC sibling in xdlc.
argument-hint: <feature or path under test>
effort: medium
---

# TDLC Test Skill — Terminal Use Development Lifecycle (prototype)

## Task

$ARGUMENTS

## Status

Prototype. Case study #1 toward an xdlc sibling tentatively named **TDLC** (Terminal Use Development Lifecycle). Per the xdlc rule (skills first → wizard later), this lives project-local in visualhud until a second TUI repo (white-rabbit is the obvious next candidate) adopts it. Tracked in `~/xdlc/README.md` Parking Lot.

## When to use this skill

You have a terminal program whose **rendering** matters — escape sequences, colors, cursor moves, redraw behavior — and the existing integration tests can't catch rendering bugs because they mock the escape sequences (see `~/visualhud/TESTING.md` "Mocking Rules"). Examples:

- `engine.sh` emits a badge / cooking status; you want to assert the actual SGR bytes hit stdout.
- A TUI game loop (white-rabbit) renders a frame; you want a snapshot of what the user sees.
- A hook adapter writes through to a terminal; you want to verify it doesn't strip color when a real PTY is attached.

## When NOT to use

- **Pure data plumbing** (JSON in / JSON out from a hook): the existing integration test pattern in `tests/test-*.sh` is fine.
- **Unit logic** (color math, string parsing): unit-test it directly, no PTY.
- **Visual cursor positioning over time** (e.g. a falling-code game where you need to assert "the 'M' was at row 3 col 7 at t=1.2s"): that's computer-use territory (CUDLC), not TDLC.

If you reach for this skill but realize the existing integration tests cover the case after stripping the mock, prefer the existing pattern. TDLC is for the rendering gap, not a replacement.

## Harness API

All paths relative to this skill (`~/visualhud/.claude/skills/tdlc-test/`).

### `lib/pty-run.py`

```
pty-run.py --out CAPTURE.bin [--timeout 10] [--input "keystrokes\n"] [--cols 120] [--rows 30] -- COMMAND [ARGS...]
```

Spawns COMMAND in a real PTY (so `isatty()` returns true), feeds optional keystrokes, captures **raw bytes** including ANSI, exits with the wrapped command's exit code. Output is written to CAPTURE.bin.

### `lib/ansi-helpers.sh` (source it)

```bash
source ~/visualhud/.claude/skills/tdlc-test/lib/ansi-helpers.sh

pty_run --out "$CAP" -- ./engine.sh < input.json    # convenience wrapper
assert_exit_code 0 $?                               # check exit
assert_ansi_contains  "$CAP" $'\e[31m'              # raw byte pattern
assert_text_contains  "$CAP" "Cooking"              # human-visible text (ANSI stripped)
assert_text_matches   "$CAP" "^badge: [0-9]+$"      # extended regex, ANSI stripped
snapshot_assert       "$CAP" engine-renders-badge   # diff vs snapshots/<name>.txt
tdlc_summary                                        # prints PASS/FAIL totals, exits non-zero if any FAIL
```

Snapshot behavior:
- First run records `snapshots/<name>.txt` (PASS as "recorded").
- Subsequent runs diff against the golden.
- `TDLC_UPDATE_SNAPSHOTS=1` overwrites all goldens (use after intentional rendering changes).

## Sandbox note (Claude Code on macOS)

Claude Code's default Bash sandbox blocks `/dev/ptmx`, so the harness fails with `out of pty devices`. When invoking these tests through Claude Code, use `dangerouslyDisableSandbox: true` on the Bash call. When the user runs them in a normal terminal, no special handling is needed.

## Quick start

```bash
# Verify the harness works on this machine.
bash ~/visualhud/.claude/skills/tdlc-test/examples/test-ansi-roundtrip.sh
```

Should print "9/9 passed ✓". The example covers: PTY capture of real ANSI, raw-byte assertions, text-after-strip assertions, regex match, and snapshot record/diff.

## Writing your first TDLC test

```bash
#!/bin/bash
set -uo pipefail
source ~/visualhud/.claude/skills/tdlc-test/lib/ansi-helpers.sh

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CAP="$TMP/capture.bin"

# Run engine.sh with a fake event, capture what it actually emits.
echo '{"event":"PreToolUse","tool":"Bash"}' | pty_run --out "$CAP" --timeout 5 -- ./engine.sh

assert_exit_code 0 $?
assert_ansi_contains "$CAP" $'\e]1337;'        # iTerm2 OSC sequence (badge / status)
assert_text_contains "$CAP" "Cooking"
snapshot_assert       "$CAP" engine-pretooluse-bash

tdlc_summary
```

Drop in `~/visualhud/tests/`, run with `bash tests/<name>.sh`. Lives alongside the existing integration tests.

## Earned rules so far

None — this is prototype day one. As bugs surface during real use, append discovered rules here. The first second-consumer adoption (white-rabbit) earns the framework-graduation gate per xdlc; until then, this is a single-case-study skill.

## Open questions for v0.2

- Does the Python PTY approach scale to long-running TUI processes (white-rabbit's game loop), or do we need an event-driven harness?
- Snapshot diffing on TUIs that include timestamps / animation frames — need a sanitizer hook?
- Cross-platform: do we care about Linux + macOS day one, or stay macOS-only until xdlc graduation?
