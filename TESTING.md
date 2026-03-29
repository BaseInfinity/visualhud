# Testing Guidelines

See `.claude/skills/testing/SKILL.md` for TDD philosophy.

## Test Commands

- All tests: `bash tests/run_all.sh`
- Specific test: `bash tests/<test_name>.sh`
- Lint shell scripts: `shellcheck *.sh`

## Stack

- Shell scripts tested via bash integration tests
- Python scripts tested via pytest (when added)
- iTerm2 API calls are mocked (can't run outside iTerm2)

## Fixtures

Location: `tests/fixtures/`

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

## Mocking Rules

| What | Mock? | Why |
|------|-------|-----|
| File system | Use temp dirs | Real I/O, isolated |
| iTerm2 Python API | YES | Can't run in test env |
| Shell commands | NO | Run real commands |
| jq / JSON parsing | NO | Test with real jq |

## Lessons Learned

<!-- Add testing gotchas as you discover them -->
