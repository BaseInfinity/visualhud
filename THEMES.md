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
  "working": { "sprite": "worker", "badge": "WORK", "name": "WORKING", "color": [60, 120, 200] },
  "permission": { "sprite": "worker", "badge": "CHECK", "name": "Permission check", "color": [120, 140, 180] },
  "blocked": { "sprite": "blocked", "badge": "HITL", "name": "Approval required", "color": [80, 75, 95] },
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
- Fast-start themes with early thresholds like `2`, `5`, and `12` must use shade ramps. Without them, high-contrast themes flash through saturated colors in the first few tool calls instead of feeling like progress.
- Colors-only themes with many unrelated hue families should use balanced dwell thresholds instead of the sprite-backed fast-start curve. Without character art, the terminal color carries the whole state, so equal dwell keeps one color from flashing past while another lingers.
- `"shade_sprites"` is optional. When present, it must have the same length as `"shades"` and lets a stage swap sprite art per shade while keeping one character family. For branded character themes, shade sprites should be distinct portraits or clearly different source-backed poses, not just crop-only zooms of the same art.
- `progress_bar` is the shared visual progress strip and checkpoint track used by the Codex task journey, explicit calibration, and legacy progression. In journey mode each visible block maps to a named checkpoint; generic tool activity cannot add blocks. It is not shown for indeterminate lifecycle states. Keep it compact and do not use character initials there.
- Use `"color_family_singleton": true` only for a deliberate one-color stage or slower-progressing generic theme; do not use it as a shortcut for branded character themes.
- `working` is mandatory and represents stable, indeterminate agent activity. Its sprite, color, badge, and title must not change merely because another tool ran.
- `permission`, `blocked`, `review`, `done`, `idle`, and `error` are mandatory lifecycle states.
- `permission` is a neutral pre-decision check. It must not claim that human action is required.
- `blocked` is the human-in-the-loop state. Its badge or name must say `HITL` explicitly so approval cannot be confused with ordinary work or an error.
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
- Context alerts are ambient: warning and critical update badge/title/user-var text while preserving the selected theme stage color and primary sprite.
- When `context_alerts.<level>.sprite` resolves to source-backed PNG art, iTerm2 renders it in a deterministic side-by-side composite and WezTerm renders it as a separate right-side layer. The dependency-free iTerm compositor accepts the standard grayscale, RGB, indexed, grayscale-alpha, and RGBA PNG color types, including Adam7 interlacing. Each input is limited to 64 MiB, 4096 pixels per dimension, and 4,194,304 total pixels; the combined canvas is limited to 8,388,608 pixels so a theme asset cannot exhaust hook memory. De-escalation must restore the unmodified primary image path.
- `context_alerts` colors are scoped behind the context character; they must not replace the active stage surface palette.
- Sprite names resolve to `themes/<theme>/sprites/<sprite>.png` first, then legacy global sprites.
- Missing sprite files clear stale background art instead of silently showing the last theme's image.
- With full-pane backgrounds enabled, Codex journey checkpoints select matching theme sprites. Outside journey mode, ordinary work keeps the `working` sprite. Backgrounds change on checkpoint or lifecycle transitions, not as a tool-count animation.

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
