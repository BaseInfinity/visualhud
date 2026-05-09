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
| Codex Bash guard test | `bash tests/test-codex-bash-guard.sh` |
| Target install test | `bash tests/test-visualhud-install.sh` |
| Skill packaging test | `bash tests/test-visualhud-skills.sh` |
| npm/npx package install test | `bash tests/test-npm-package.sh` |
| npm release automation test | `bash tests/test-npm-release.sh` |
| Theme calibration test | `bash tests/test-theme-calibration.sh` |
| Lint | `shellcheck *.sh` |

## Stack

- Shell scripts tested via bash integration tests (custom assertions)
- Python scripts tested via pytest (when added)
- iTerm2 API calls are mocked (can't run outside iTerm2)

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
  test-visualhud-skills.sh  <- Packaged skill docs + install discovery tests
  test-npm-package.sh       <- npm pack + npx tarball consumer install test
  test-npm-release.sh       <- npm auth/test/dry-run/publish automation test
  test-theme-calibration.sh <- Ordered theme calibration and mocked live walk
  test-<feature>.sh         <- Per-feature test files
  fixtures/                 <- Shared test data
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
