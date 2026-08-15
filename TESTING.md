# Testing Guidelines

## Approach: Strict TDD

1. Write failing test FIRST (RED)
2. Implement feature (GREEN)
3. Run all tests (PASS)
4. Never commit with failing tests

## Test Commands

| Action | Command |
|--------|---------|
| Full suite / publish gate | `npm test` |
| Specific test | `bash tests/<test_name>.sh` |
| Codex adapter test | `bash tests/test-codex-visualhud.sh` |
| Codex git guard test | `bash tests/test-codex-git-guard.sh` |
| Target install test | `bash tests/test-visualhud-install.sh` |
| Skill packaging test | `bash tests/test-visualhud-skills.sh` |
| npm/npx package install test | `bash tests/test-npm-package.sh` |
| npm release automation test | `bash tests/test-npm-release.sh` |
| Theme calibration test | `bash tests/test-theme-calibration.sh` |
| Host/renderer matrix | `npm run test:matrix` |
| Compatibility report | `npm run coverage:matrix` |
| Lint | `shellcheck *.sh` |

## Stack

- Shell scripts tested via bash integration tests (custom assertions)
- Python scripts tested via pytest (when added)
- iTerm2 API calls are mocked (can't run outside iTerm2)
- Semantic transition tests prove stable `WORKING`, explicit `HITL`, review
  completion/failure cleanup, and that tool count is not presented as progress.
- Task-journey integration tests prove profile selection, evidence-driven
  advancement, rollback, overlay preservation, aggregate separation, immediate
  repainting, stale-sprite clearing, read-only completion, and rejection of
  stale concurrent verification after an invalidating edit.
- The versioned compatibility matrix validates every registered VisualHUD host
  event from sanitized Codex and Claude fixtures, then checks semantic output
  through iTerm2, WezTerm, and Windows Terminal renderer encodings.

## Live And Isolated Tests

`npm test` is credential-free and cannot target the developer's active pane.
The suite clears inherited terminal session identifiers, routes fallback output
through `VISUALHUD_TEST_CAPTURE_DIR`, and suppresses the real iTerm2 background
helper unless a test explicitly provides a deterministic double.

Authenticated Sol medium/high smoke sessions, real iTerm2 API assertions, and
Computer Use screenshot review belong to supervised issue #16. They require
explicit cost, credential, timeout, and cleanup boundaries and never run in
default CI.

The supervised iTerm2 canary uses a layered oracle instead of a full-window
golden screenshot:

1. Normal CI proves journey state, renderer output, theme mapping, generation
   ordering, and the pure semantic comparator.
2. `scripts/visualhud-iterm-canary.py probe` reads the exact disposable
   session's effective `hudProgress`, custom tab-title binding, resolved tab
   title, tab color, and background image path through the iTerm2 Python API.
   The resolved title must equal `hudProgress` while the host changes
   `session.name`. Two consecutive samples must match the same expected
   checkpoint fixture. Expectations come from the versioned journey/theme
   input, never from the observed pane.
3. A small screenshot crop proves only what the API cannot: that iTerm2 composed
   the expected title chrome and character pixels. Scrolling transcript,
   timestamps, cursor, and token counters are excluded.

Lossless PNG/state artifacts are the regression evidence. A GIF may be derived
from accepted frames for documentation, but is not itself the test oracle.

## Testing Diamond

```
    /\         <- Few E2E (manual verification in iTerm2)
   /  \
  /    \
 /------\
|        |     <- MANY Integration (real shell execution, temp dirs)
|        |
 \------/
  \    /
   \  /
    \/         <- Few Unit (pure logic: color math, JSON parsing)
```

**Integration tests are the primary focus.** They test real shell behavior with temp dirs for isolation. This gives the best bang for buck — if integration tests pass, the feature works.

## Mocking Rules

| What | Mock? | Why |
|------|-------|-----|
| File system | Use temp dirs | Real I/O, isolated |
| iTerm2 Python API | YES | Can't run in test env |
| iTerm2 escape sequences | YES | No terminal in test |
| Shell commands | NO | Run real commands |
| JSON parsing | NO | Test with bundled Node JSON helper |

**Philosophy:** Minimal mocking. Only mock what you truly can't control (iTerm2 API, terminal escape sequences). Everything else should be real.

## Fixtures

Location: `tests/fixtures/`

Use real fixture data for mock shapes — never guess what the data looks like.

## Test File Organization

```
tests/
  run-all.sh                 <- Full local/publish verification suite
  test-cooking-status.sh    <- Main hook integration tests
  test-codex-visualhud.sh   <- Codex adapter integration tests
  test-journey-state.sh     <- Reversible task-journey integration tests
  test-host-renderer-matrix.sh <- Versioned host/renderer/lifecycle contract
  test-visualhud-skills.sh  <- Packaged skill docs + install discovery tests
  test-npm-package.sh       <- npm pack + npx tarball consumer install test
  test-npm-release.sh       <- npm auth/test/dry-run/publish automation test
  test-theme-calibration.sh <- Ordered theme calibration and mocked live walk
  test-<feature>.sh         <- Per-feature test files
  fixtures/compatibility/   <- Sanitized versioned host payload shapes
```

## Test Code is First-Class

- Test code gets the same quality standards as app code
- Existing test patterns are building blocks — copy good ones, improve bad ones
- Flaky tests are bugs — investigate every failure, don't sweep under the rug

## Test Failure Categories

| Category | Fix |
|----------|-----|
| Test code bug | Fix the test (most common) |
| Application bug | Fix the app — test found a real bug |
| Environment bug | Fix the setup/teardown |

## Lessons Learned

<!-- Add testing gotchas as you discover them -->
