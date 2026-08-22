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

After focused checks and self-review, run required broad verification through
the proof-stamping command for the git gate:

```bash
node .codex/hooks/git-guard.cjs prove --reviewed
```

If cross-model review is required, wait for a clean Sol review and then run the bounded Fable High reviewer over the same frozen candidate:

```bash
node .codex/hooks/fable-review.cjs --base <ref> --consent-subscription-quota
```

This consumes Claude subscription quota and refuses API-key or alternate-provider authentication.

When policy requires Sol High and Fable High to reconcile their independent
reviews, run the single bounded gate over the same frozen candidate:

```bash
node .codex/hooks/dual-review.cjs --base <ref> --consent-subscription-quota
```

Clean agreement stops immediately. A verdict split receives exactly one
verbatim structured cross-feed round; the gate then emits one joint receipt and
stops. It never permits a third reviewer exchange.

For this repository, the manifest resolves the complete maintainer suite to
`npm test`. Run and stamp that suite once with:

```bash
node .codex/hooks/git-guard.cjs prove --reviewed
```

Do not run `npm test` immediately before this command; the proof-stamping
invocation already runs it.

If setup has not detected proof commands yet, pass them explicitly:

```bash
node .codex/hooks/git-guard.cjs prove --reviewed --check "npm test"
```

The stamp is stored at `.codex-sdlc/proof.json`, expires after four hours, and is
tied to the current worktree content. The file is ignored by Git. Guarded commit
and push commands reject unrelated repository contexts and require a fresh proof
from the target worktree.
