---
name: visualhud-feedback
description: Capture VisualHUD bugs, install failures, theme ideas, and terminal-renderer gaps with privacy-first evidence. Use when the user asks to file feedback or record a VisualHUD issue.
---

# VisualHUD Feedback

Capture feedback locally first, then decide whether to publish it.

## Privacy

- Do not scan source code without explicit user permission.
- Do not read `.env`, credentials, private business docs, or unrelated app code.
- It is safe to inspect VisualHUD-owned files: `.visualhud/`, `.codex/hooks.json`, `.agents/skills/visualhud-*`, and screenshots the user provides.

## Workflow

1. Classify the report: install, update, theme, renderer, docs, or future theme.
2. Record local evidence under:
   ```text
   .visualhud/feedback/
   ```
3. Include:
   - Target OS and terminal host.
   - Codex or Claude.
   - Active theme from `.visualhud/visualhud theme current`.
   - Whether colors changed.
   - Whether background images changed.
   - Screenshot reference if provided.
4. If the issue belongs upstream, create or prepare a GitHub issue only after the user approves.

## Rules

- Missing sprites are source-package bugs.
- Colors working but images missing usually means either missing local sprites or an iTerm2 `set_bg.py`/session-targeting issue.
- Windows Terminal/PowerShell is a known renderer gap, not a failed macOS install.
