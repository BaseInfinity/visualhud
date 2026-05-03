# VisualHUD Themes

Themes are repo-local JSON packs that drive VisualHUD without changing
`engine.sh`. The default install path is `themes/<theme-name>/theme.json` plus
optional `themes/<theme-name>/sprites/*.png` files.

## Local-First Scope

Codex uses this repo's `.codex/hooks.json` and `.codex/hooks/visualhud-codex.sh`.
That means themes apply only when Codex is running in this repo unless another
repo explicitly installs the same hook wiring. This avoids global cross-repo
collisions.

Runtime state is still per terminal pane. VisualHUD keys `/private/tmp` state by
`ITERM_SESSION_ID`, so multiple panes can run different stages without sharing
counters or current sprite markers.

Theme selection is repo-local by default. `./visualhud theme set <name>` writes
the repo-local active theme file, and `./visualhud theme current` reports that
active override when one exists. Clean installs into other Codex repos write
Pokemon as the active theme by default. Without an active file, adapters may
supply their own fallback theme: this repo's Codex adapter falls back to TMNT,
Claude falls back to Pokemon, and the bare CLI falls back to Pokemon. Use
`VISUALHUD_THEME=<name>` only when you want an explicit one-process override.

Windows Codex support is a separate portability track. The theme JSON contract
should stay reusable, but Windows Terminal/PowerShell needs a different renderer
because the current background-image bridge uses the iTerm2 Python API.

## Required Theme Shape

```json
{
  "name": "Example Theme",
  "progress_bar": ["A", "B", "C"],
  "stages": [
    {
      "max": 2,
      "sprite": "alpha",
      "badge": "A",
      "name": "Alpha",
      "color_family": "blue",
      "color": [10, 20, 30],
      "shades": [[10, 20, 30], [20, 35, 55]]
    },
    {
      "max": 5,
      "sprite": "beta",
      "badge": "B",
      "name": "Beta",
      "color_family": "orange",
      "color": [40, 50, 60],
      "shades": [[40, 50, 60], [65, 75, 85], [85, 95, 110]],
      "shade_sprites": ["beta", "beta-warm", "beta-hot"]
    },
    {
      "max": 999999,
      "sprite": "gamma",
      "badge": "C",
      "name": "Gamma",
      "color_family": "green",
      "color": [70, 80, 90],
      "shades": [[70, 80, 90], [90, 110, 120]]
    }
  ],
  "blocked": { "sprite": "blocked", "badge": "BLOCK", "name": "Blocked", "color": [80, 75, 95] },
  "done": { "sprite": "done", "badge": "DONE", "name": "Done", "stage": 3, "color": [40, 100, 255] },
  "idle": { "sprite": "idle", "badge": "IDLE", "name": "Idle", "stage": 3, "color": [40, 100, 255] },
  "error": { "sprite": "error", "badge": "ERROR", "name": "Error", "color": [255, 40, 40] },
  "context_alerts": {
    "warning": { "min_percent": 70, "badge": "WARN", "name": "Context High", "color": [255, 190, 40] },
    "critical": { "min_percent": 85, "badge": "CRIT", "name": "Context Critical", "color": [255, 255, 255] }
  }
}
```

## Contract

- `stages` are ordered by ascending `"max"` thresholds.
- Each stage needs `"sprite"`, `"badge"`, `"name"`, `"color_family"`, RGB `"color"`, and either `"shades"` or `"color_family_singleton": true`.
- `"shades"` is the within-stage color ramp. The engine chooses a shade from the current tool-call position inside that stage range, so a character can keep the same sprite while the terminal color breathes across multiple calls.
- `"shade_sprites"` is optional. When present, it must have the same length as `"shades"` and lets a stage swap sprite art per shade while keeping one character family. For branded character themes, shade sprites should be distinct portraits or clearly different source-backed poses, not just crop-only zooms of the same art.
- `progress_bar` is the shared visual progress strip shown in the terminal title. Keep it a compact health/progress-style visual sequence; do not use character initials there. Theme identity belongs in stage badges, names, sprites, colors, and optional `shade_sprites`.
- Use `"color_family_singleton": true` only for a deliberate one-color stage; do not use it as a shortcut for branded character themes.
- `blocked`, `review`, `done`, `idle`, and `error` are mandatory lifecycle states.
- review is not done: use it for code review/background verification that is
  still running after the main answer appears complete. It must have its own
  non-final title/color/sprite so `done` remains reserved for work that is
  actually ready for the user's next action.
- Lifecycle colors are semantic terminal states. They may reuse lifecycle sprite
  identity, but their terminal color should communicate state clearly and avoid
  accidental overlap with an unrelated progress band. For example, TMNT can use
  Pizza Party art for `done` while using Turtle Power green as the done surface
  color instead of April/yellow.
- RGB channel values must be integers from `0` through `255`.
- `context_alerts.warning` starts at a lower `min_percent` than `critical`.
- Context alerts are ambient: warning and critical both update badge/title/user-var text while preserving the selected theme stage color and sprite.
- `context_alerts` colors describe alert identity for reports/future non-destructive indicators; they must not replace the active stage surface palette.
- Sprite names resolve to `themes/<theme>/sprites/<sprite>.png` first, then legacy global sprites.
- Missing sprite files clear stale background art instead of silently showing the last theme's image.

## Sprite Assets

Theme sprites are optional for generic/internal themes, but branded or character
themes must be source-backed. For TMNT, `themes/tmnt/sprites/manifest.json`
records provenance for every shipped sprite. Do not ship generated placeholders
as final theme art.

Character-focused source crops must not leak source-page neutral corner mattes
into the terminal. Importers should strip those mattes and render the sprite over
the theme stage/shade color. TMNT records that derived color as
`backdrop_color` in `manifest.json`, so regenerated assets keep matching the
JSON color ramp instead of drifting to gray.

Use `scripts/render-theme-contact-sheet.py` to create a visual smoke sheet for a
theme. The report must have no `missing_sprites` for sprite-backed states.

For theme calibration, use `./visualhud theme calibrate <name>` to review every
stage, shade, lifecycle state, and context overlay in deterministic order. Use
`--json` for correction notes keyed by step number, and use `--live --delay 1`
or `--live --pause` from a real iTerm2 pane for one-by-one visual review.

## Adding A Third Theme

1. Add `themes/<name>/theme.json` using the schema above.
2. Add optional `themes/<name>/sprites/<sprite>.png` assets.
3. Run the theme-system tests before touching the engine.
4. Select the theme with `./visualhud theme set <name>`; use
   `VISUALHUD_THEME=<name>` only for a one-process override.

A new theme should not require changing `engine.sh`. If it does, the theme system
is too narrow and needs a small contract change plus tests.

## SDLC Gates

Theme work follows TDD:

1. RED: add or update a failing assertion in `tests/test-theme-system.sh`,
   `tests/test-cooking-status.sh`, or a focused new test.
2. GREEN: make the smallest implementation or docs change.
3. PASS: run the required proof set.

Required proof for theme changes:

```bash
bash tests/test-theme-system.sh
bash tests/test-theme-calibration.sh
bash tests/test-cooking-status.sh
bash tests/test-codex-visualhud.sh
bash tests/test-claude-visualhud.sh
shellcheck *.sh tests/*.sh .codex/hooks/*.sh .claude/hooks/*.sh
jq empty themes/*/theme.json themes/tmnt/sprites/manifest.json
python3 -m py_compile scripts/import-tmnt-sprites.py scripts/render-theme-contact-sheet.py scripts/theme-calibration-steps.py
git diff --check
```

Visual changes also need human-visible proof: a screenshot or generated contact
sheet reviewed before calling the appearance done.
