---
name: sdlc
description: Full SDLC workflow for implementing features, fixing bugs, refactoring code, and creating new functionality. Use this skill when implementing, fixing, refactoring, adding features, or building new code.
argument-hint: [task description]
effort: high
---
# SDLC Skill - Full Development Workflow

## Task
$ARGUMENTS

## Full SDLC Checklist

Your FIRST action must be TodoWrite with these steps:

```
TodoWrite([
  // PLANNING PHASE (Plan Mode for non-trivial tasks)
  { content: "Find and read relevant documentation", status: "in_progress", activeForm: "Reading docs" },
  { content: "Assess doc health - flag issues (ask before cleaning)", status: "pending", activeForm: "Checking doc health" },
  { content: "DRY scan: What patterns exist to reuse?", status: "pending", activeForm: "Scanning for reusable patterns" },
  { content: "Blast radius: What depends on code I'm changing?", status: "pending", activeForm: "Checking dependencies" },
  { content: "Restate task in own words - verify understanding", status: "pending", activeForm: "Verifying understanding" },
  { content: "Scrutinize test design - right things tested? Follow TESTING.md?", status: "pending", activeForm: "Reviewing test approach" },
  { content: "Present approach + STATE CONFIDENCE LEVEL", status: "pending", activeForm: "Presenting approach" },
  { content: "Signal ready - user exits plan mode", status: "pending", activeForm: "Awaiting plan approval" },
  // TRANSITION PHASE (After plan mode, before compact)
  { content: "Doc sync: update feature docs if code change contradicts or extends documented behavior", status: "pending", activeForm: "Syncing feature docs" },
  { content: "Request /compact before TDD", status: "pending", activeForm: "Requesting compact" },
  // IMPLEMENTATION PHASE (After compact)
  { content: "TDD RED: Write failing test FIRST", status: "pending", activeForm: "Writing failing test" },
  { content: "TDD GREEN: Implement, verify test passes", status: "pending", activeForm: "Implementing feature" },
  { content: "Run shellcheck lint", status: "pending", activeForm: "Running shellcheck" },
  { content: "Run ALL tests", status: "pending", activeForm: "Running all tests" },
  // REVIEW PHASE
  { content: "DRY check: Is logic duplicated elsewhere?", status: "pending", activeForm: "Checking for duplication" },
  { content: "Self-review: run /code-review", status: "pending", activeForm: "Running code review" },
  { content: "Security review (if warranted)", status: "pending", activeForm: "Checking security implications" },
  // FINAL
  { content: "Present summary: changes, tests", status: "pending", activeForm: "Presenting final summary" }
])
```

## New Pattern & Test Design Scrutiny (PLANNING)

**New design patterns require human approval:**
1. Search first - do similar patterns exist in codebase?
2. If YES and they're good - use as building block
3. If YES but they're bad - propose improvement, get approval
4. If NO (new pattern) - explain why needed, get explicit approval

**Test design scrutiny during planning:**
- Are we testing the right things?
- Does test approach follow TESTING.md philosophies?
- If introducing new test patterns, same scrutiny as code patterns

## Plan Mode Integration

**Use plan mode for:** Multi-file changes, new features, LOW confidence, bugs needing investigation.

**Workflow:**
1. **Plan Mode** (editing blocked): Research -> Write plan file -> Present approach + confidence
2. **Transition** (after approval): Doc sync (update feature docs if code contradicts/extends them) -> Request /compact
3. **Implementation** (after compact): TDD RED -> GREEN -> PASS

**Before TDD, MUST ask:** "Docs updated. Run `/compact` before implementation?"

## Confidence Check (REQUIRED)

Before presenting approach, STATE your confidence. This repo defaults to
maximum-depth reasoning: use `xhigh` in Codex and `/effort max` where Claude
Code exposes that control.

| Level | Meaning | Action | Effort |
|-------|---------|--------|--------|
| HIGH (95%+) | Know exactly what to do | Present approach, proceed after proof is defined | `xhigh` / `/effort max` |
| MEDIUM (<95%) | Solid approach, some uncertainty | Research more, then surface uncertainties | `xhigh` / `/effort max` |
| LOW | Not sure | ASK USER before proceeding | `xhigh` / `/effort max` |
| FAILED 2x | Something's wrong | STOP. ASK USER immediately | `xhigh` / `/effort max` |
| CONFUSED | Can't diagnose why something is failing | STOP. Describe what you tried, ask for help | `xhigh` / `/effort max` |

## Self-Review Loop (CRITICAL)

```
PLANNING -> DOCS -> TDD RED -> TDD GREEN -> Tests Pass -> Self-Review
    ^                                                      |
    |                                                      v
    |                                            Issues found?
    |                                            +-- NO -> Present to user
    |                                            +-- YES v
    +------------------------------------------- Ask user: fix in new plan?
```

**The loop goes back to PLANNING, not TDD RED.** When self-review finds issues:
1. Ask user: "Found issues. Want to create a plan to fix?"
2. If yes -> back to PLANNING phase with new plan doc
3. Then -> docs update -> TDD -> review (proper SDLC loop)

## Test Review (Harder Than Implementation)

During self-review, critique tests HARDER than app code:
1. **Testing the right things?** - Not just that tests pass
2. **Tests prove correctness?** - Or just verify current behavior?
3. **Follow our philosophies (TESTING.md)?**
   - Testing Diamond (integration-heavy)?
   - Minimal mocking (mock external APIs only)?

**Tests are the foundation.** Bad tests = false confidence = production bugs.

## Scope Guard (Stay in Your Lane)

**Only make changes directly related to the task.**

If you notice something else that should be fixed:
- NOTE it in your summary ("I noticed X could be improved")
- DON'T fix it unless asked

## Test Failure Recovery (SDET Philosophy)

**ALL TESTS MUST PASS BEFORE COMMIT**

If tests fail:
1. Identify which test(s) failed
2. Diagnose WHY:
   - Your code broke it? Fix your code (regression)
   - Test is for deleted code? Delete the test
   - Test has wrong assertions? Fix the test
   - Test is "flaky"? Investigate - flakiness is just another word for bug
3. Fix appropriately
4. Run specific test individually first
5. Then run ALL tests
6. Still failing? ASK USER

## DRY Principle

**Before coding:** "What patterns exist I can reuse?"
**After coding:** "Did I accidentally duplicate anything?"

## DELETE Legacy Code

- Legacy code? DELETE IT
- Backwards compatibility? NO - DELETE IT
- "Just in case" fallbacks? DELETE IT

**THE RULE:** Delete old code first. If it breaks, fix it properly.

---

**Full reference:** SDLC.md
