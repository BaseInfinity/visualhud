<!-- SDLC Wizard Version: 1.20.0 -->
<!-- Setup Date: 2026-03-31 -->
<!-- Completed Steps: step-0.2, step-0.4, step-1, step-2, step-3, step-4, step-5, step-6, step-7, step-8, step-9, step-10 -->
<!-- Git Workflow: Solo -->

# SDLC - Development Workflow

See `AGENTS.md`, `SDLC-LOOP.md`, and `.agents/skills/sdlc/SKILL.md` for the enforced checklist.

## Workflow Overview

1. **Planning Mode** -> Research, present approach + confidence, get approval
2. **Transition** -> Update/sync docs, request /compact
3. **Implementation** -> TDD RED -> GREEN -> PASS
4. **Review** -> Self-review (/code-review), present summary

## Confidence Levels

| Level | Meaning | Action | Effort |
|-------|---------|--------|--------|
| HIGH (95%+) | Know exactly what to do | Proceed after proof is defined | `xhigh` (default) |
| MEDIUM (<95%) | Solid approach, some uncertainty | Research more, then surface uncertainty | `xhigh` (default) |
| LOW | Not sure | ASK USER before proceeding | `xhigh` |
| FAILED 2x | Something's wrong | STOP. ASK USER immediately | `xhigh` |
| CONFUSED | Can't diagnose why failing | STOP. Describe what tried | `xhigh` |

## Context Management

| | `/compact` | `/clear` |
|---|---|---|
| When | Continuing same task, need room | Switching to unrelated task |
| Preserves | Summary of decisions + progress | Nothing (fresh start) |
| Use after | Planning -> before implementation | Committing a PR, starting new feature |

## Lessons Learned

<!-- Add gotchas as you discover them -->
