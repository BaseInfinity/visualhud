---
name: visualhud-update
description: Refresh an installed VisualHUD runtime in a Codex repo while preserving local hooks, active theme, existing renderer setup, and existing skills. Use when the user asks to update, sync, refresh, or repair VisualHUD.
---

# VisualHUD Update

Refresh VisualHUD without clobbering local choices.

## Workflow

1. Read the active theme before updating:
   ```bash
   ./.visualhud/visualhud theme current
   ```
2. Read the currently installed renderer and preserve it instead of hard-coding macOS:
   ```bash
   sed -n 's/.*VISUALHUD_RENDERER="\([^"]*\)".*/\1/p' .codex/hooks/visualhud-codex.sh | head -1
   ```
   Use `macos` only when no `VISUALHUD_RENDERER` is present and the host is iTerm2/macOS. Use `wezterm` when the wrapper says `VISUALHUD_RENDERER="wezterm"` or the user asks to keep live Windows colors/backgrounds.
3. Prefer updating from the VisualHUD source checkout:
   ```bash
   ./visualhud install codex --target /path/to/repo --theme "$(cat /path/to/repo/.visualhud/theme)" --platform macos
   ```
   The macOS install command reapplies the iTerm2 helper automatically and
   reports whether visuals are ready now, pending a normal restart, or blocked.
   For a WezTerm install, use the preserved renderer and rerun the platform helper yourself:
   ```powershell
   ./visualhud install codex --target C:/path/to/repo --theme "$(cat C:/path/to/repo/.visualhud/theme)" --platform wezterm
   pwsh -ExecutionPolicy Bypass -File C:/path/to/repo/.visualhud/setup-wezterm.ps1
   ```
4. If only the installed runtime is available, repair hooks/skills with:
   ```bash
   ./.visualhud/visualhud install codex --target "$(git rev-parse --show-toplevel)" --theme "$(./.visualhud/visualhud theme current)" --platform macos
   ```
   Use `--platform wezterm` instead when preserving a WezTerm install, then run `pwsh -ExecutionPolicy Bypass -File ./.visualhud/setup-wezterm.ps1`.
5. If `setup-wezterm.ps1` reports an existing WezTerm config and writes a snippet, inspect the existing config, back it up, and merge the generated snippet yourself when the merge is straightforward. Ask before using `-Force` or replacing user config.
6. Verify:
   ```bash
   ./.visualhud/visualhud theme current
   ./.visualhud/visualhud theme list
   jq '.hooks | keys' .codex/hooks.json
   ```

## Rules

- Preserve the active theme unless the user explicitly asks to switch.
- Preserve the active renderer unless the user explicitly asks to switch.
- Preserve unrelated `.codex/hooks.json` entries and unrelated `.agents/skills/*`.
- Do not use legacy global hook folders or global Codex hooks as a source of truth.
- Do not report a WezTerm update complete until `setup-wezterm.ps1` has been run or an ambiguous local config merge has been surfaced as the blocker.
- Do not add a separate iTerm2 helper command after a successful macOS update; use the install command's platform-helper status.
- If a bundled theme references a missing sprite, treat that as a VisualHUD source bug, not a target-repo customization.
