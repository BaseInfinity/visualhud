---
name: visualhud-update
description: Refresh an installed VisualHUD runtime in a Codex repo while preserving local hooks, active theme, and existing skills. Use when the user asks to update, sync, refresh, or repair VisualHUD.
---

# VisualHUD Update

Refresh VisualHUD without clobbering local choices.

## Workflow

1. Read the active theme before updating:
   ```bash
   ./.visualhud/visualhud theme current
   ```
2. Prefer updating from the VisualHUD source checkout:
   ```bash
   ./visualhud install codex --target /path/to/repo --theme "$(cat /path/to/repo/.visualhud/theme)" --platform macos
   ```
3. If only the installed runtime is available, repair hooks/skills with:
   ```bash
   ./.visualhud/visualhud install codex --target "$(git rev-parse --show-toplevel)" --theme "$(./.visualhud/visualhud theme current)" --platform macos
   ```
4. Verify:
   ```bash
   ./.visualhud/visualhud theme current
   ./.visualhud/visualhud theme list
   jq '.hooks | keys' .codex/hooks.json
   ```

## Rules

- Preserve the active theme unless the user explicitly asks to switch.
- Preserve unrelated `.codex/hooks.json` entries and unrelated `.agents/skills/*`.
- Do not use legacy global hook folders or global Codex hooks as a source of truth.
- If a bundled theme references a missing sprite, treat that as a VisualHUD source bug, not a target-repo customization.
