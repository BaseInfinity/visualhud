---
name: visualhud-theme
description: List, switch, calibrate, and troubleshoot VisualHUD themes in an installed Codex repo. Use when the user asks to change themes, compare Pokemon/TMNT, calibrate colors, or validate theme visuals.
---

# VisualHUD Theme

Theme changes are repo-local and take effect on the next hook.

## Commands

```bash
./.visualhud/visualhud theme list
./.visualhud/visualhud theme current
./.visualhud/visualhud theme set pokemon
./.visualhud/visualhud theme set tmnt
./.visualhud/visualhud theme calibrate tmnt
./.visualhud/visualhud theme calibrate tmnt --json
./.visualhud/visualhud theme calibrate tmnt --live --delay 1
```

## Workflow

1. Use `theme list` and `theme current` before changing anything.
2. Use `theme set <name>` for on-the-fly switching; no Codex restart is required after the first install.
3. Use calibration when a theme has too many states to inspect casually.
4. For visual bugs, classify the issue:
   - Theme JSON points at missing assets.
   - Asset exists but has bad crop/matte/color.
   - iTerm2 background application failed even though colors changed.
   - TUI repaint left stale surfaces until the next delayed reapply.

## Rules

- Pokemon and TMNT are shipped first-party themes.
- Power Rangers is shipped colors-only; validate it like the other bundled JSON themes.
- Batman and Sonic are parked future themes until the theme contract stays boring.
- Do not add placeholder art for missing sprites. Use source-backed assets or park the theme extension.
- Keep context/token pressure as an overlay; it must not erase the active stage color or sprite.
