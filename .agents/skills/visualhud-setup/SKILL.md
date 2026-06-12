---
name: visualhud-setup
description: Install VisualHUD into a Codex repo on macOS/iTerm2, Windows Terminal, or WezTerm; run platform setup helpers; verify repo-local hooks. Use when the user asks to install, enable, bootstrap, or test VisualHUD in another Codex project.
---

# VisualHUD Setup

Install VisualHUD as a repo-local runtime. Do not install global hooks. Run the
platform setup helper yourself when the selected renderer needs one; do not hand
the user a manual setup step unless a local config merge is ambiguous.

## Workflow

1. Confirm the target is a Git worktree and choose the renderer deliberately.
   - macOS/iTerm2: use `--platform macos`.
   - Windows Terminal/PowerShell: use `--platform windows` for title/progress only.
   - Windows/WezTerm: use `--platform wezterm` when `WEZTERM_PANE` is set, the user asks for colors/backgrounds/sprites on Windows, an existing wrapper already has `VISUALHUD_RENDERER="wezterm"`, or `wezterm` is available and the user did not explicitly ask for Windows Terminal.
2. Install from the VisualHUD source checkout when available:
   ```bash
   ./visualhud install codex --target /path/to/repo --theme pokemon --platform macos
   ```
   On Windows/WezTerm, prefer:
   ```powershell
   ./visualhud install codex --target C:/path/to/repo --theme pokemon --platform wezterm
   pwsh -ExecutionPolicy Bypass -File C:/path/to/repo/.visualhud/setup-wezterm.ps1
   ```
3. If you are already inside an installed runtime in the target repo, repair/reapply with the selected renderer:
   ```bash
   ./.visualhud/visualhud install codex --target "$(git rev-parse --show-toplevel)" --theme pokemon --platform macos
   ```
   For WezTerm from an installed runtime:
   ```powershell
   ./.visualhud/visualhud install codex --target "$(git rev-parse --show-toplevel)" --theme pokemon --platform wezterm
   pwsh -ExecutionPolicy Bypass -File ./.visualhud/setup-wezterm.ps1
   ```
4. If `setup-wezterm.ps1` reports an existing WezTerm config and writes a snippet, inspect the existing config, back it up, and merge the generated snippet yourself when the merge is straightforward. Ask before using `-Force` or replacing user config.
5. Verify:
   ```bash
   ./.visualhud/visualhud theme current
   find .visualhud/themes/pokemon/sprites -maxdepth 1 -type f -name '*.png' | sort
   jq '.hooks | keys' .codex/hooks.json
   ```
6. For WezTerm, also verify `.visualhud/setup-wezterm.ps1`, `.visualhud/wezterm/visualhud.lua`, and `VISUALHUD_RENDERER="wezterm"` in `.codex/hooks/visualhud-codex.sh`.
7. Ask the user to restart Codex or run a tiny task in the target pane. Colors plus background images should update on the next hook for iTerm2/WezTerm; Windows Terminal gets title/progress only.

## Rules

- Default clean Mac Codex installs to Pokemon because it is the most polished first-party theme.
- Preserve existing `.codex/hooks.json` entries and existing `.agents/skills/*`.
- The installed skills live under `.agents/skills/visualhud-*` so Codex can discover them in that repo.
- Do not report setup complete while leaving `setup-wezterm.ps1` or `setup-iterm2.sh` as a manual next step unless permissions or ambiguous user config blocked automation.
- Keep Windows renderer limits explicit: Windows Terminal/PowerShell is title/progress only; WezTerm is the Windows path for live colors/background sprites.
- If colors work but images do not, inspect `.visualhud/themes/<theme>/sprites/` and `set_bg.py` before changing theme JSON.
