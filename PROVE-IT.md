# Prove It

This is the pre-commit proof gate.

## Minimum Questions

1. What changed?
2. What exact check proves it?
3. What command or action produced the proof?
4. What risk still remains?

## By Task Type

### Code changes

- Targeted test added or updated
- Test run completed
- Relevant command output captured

### Setup or environment repair

- Bootstrap or health check re-run
- Versions and paths confirmed
- Broken state is gone

### Auth or tenant work

- Correct account used
- Intended scopes requested
- Connection state confirmed

### Browser workflow

- Use Playwright or a manual browser check
- Capture the visible outcome

### Desktop-only workflow

- Run the desktop/manual validation
- Do not claim browser E2E covers it if it does not

### Visual HUD changes

- Automated tests must cover hook routing, state files, and generated payloads
- A human-visible iTerm2 screenshot/manual check is required before calling visual appearance done
- Do not claim shell tests prove layout, badge size, contrast, or background aesthetics

## Commit Gate

Do not commit until you can answer:

- The failing state is real
- The passing state is real
- The proof is recent
- The diff matches the proof

Codex commit/push hooks enforce this with an ignored repo-local proof record at
`.codex-sdlc/proof.json`. After staging the intended changes and completing
self-review, run:

```bash
node .codex/hooks/git-guard.cjs prove --reviewed
```

The proof command runs the checks configured in `.codex-sdlc/manifest.json` and
binds the result to the current Git index and workspace fingerprint. It refuses
to stamp staged tracked content that differs from the tested worktree, and any
subsequent index or workspace change makes the proof stale.
