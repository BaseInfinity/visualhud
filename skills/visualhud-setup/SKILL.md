---
name: visualhud-setup
description: Install VisualHUD into a Codex repo on macOS/iTerm2, verify repo-local hooks, and keep setup local-first. Use when the user asks to install, enable, bootstrap, or test VisualHUD in another Codex project.
---

# VisualHUD Setup

Install VisualHUD as a repo-local runtime. Do not install global hooks.

## Workflow

1. Confirm the target is a Git worktree and the host is macOS/iTerm2.
2. Install from the VisualHUD source checkout when available:
   ```bash
   ./visualhud install codex --target /path/to/repo --theme pokemon --platform macos
   ```
3. If you are already inside an installed runtime in the target repo, repair/reapply with:
   ```bash
   ./.visualhud/visualhud install codex --target "$(git rev-parse --show-toplevel)" --theme pokemon --platform macos
   ```
4. Verify:
   ```bash
   ./.visualhud/visualhud theme current
   find .visualhud/themes/pokemon/sprites -maxdepth 1 -type f -name '*.png' | sort
   jq '.hooks | keys' .codex/hooks.json
   ```
5. Ask the user to restart Codex or run a tiny task in the target pane. Colors plus background images should update on the next hook.

## Rules

- Default clean Mac Codex installs to Pokemon because it is the most polished first-party theme.
- Preserve existing `.codex/hooks.json` entries and existing `.agents/skills/*`.
- The installed skills live under `.agents/skills/visualhud-*` so Codex can discover them in that repo.
- Windows Terminal/PowerShell renderer is not supported yet; do not pretend setup is complete on Windows.
- If colors work but images do not, inspect `.visualhud/themes/<theme>/sprites/` and `set_bg.py` before changing theme JSON.
