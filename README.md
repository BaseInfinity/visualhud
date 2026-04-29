# VisualHUD

A themeable visual status engine for Claude Code, Codex, and iTerm2.

Watch your terminal transform in real-time as your agent works — colors shift, backgrounds swap, and tab titles update to show exactly where things stand. Ship with themes or build your own.

## Install

VisualHUD is local-first. This repo carries its own hook config, engine, themes,
and sprite assets; it does not install a global Codex/Claude hook unless you add
one yourself.

### 1. Configure iTerm2

Run this once on macOS:

```bash
./setup-iterm2.sh
```

If iTerm2 is already open, quit iTerm2 after running the setup and reopen it.
This enables tab colors, per-pane background images, the iTerm2 Python API, and
the `hudProgress` tab-title variable.

### 2. Use With Codex

Codex is already wired in this repo through:

```text
.codex/hooks.json
.codex/hooks/visualhud-codex.sh
```

Start or restart Codex from this repo. The Codex adapter defaults to the TMNT
theme and routes lifecycle events into `engine.sh`.

To switch the repo-local default for future hooks:

```bash
./visualhud theme list
./visualhud theme set pokemon
./visualhud theme current
```

The selection is written to the repo-local active theme file and is picked up on
the next hook; no Codex restart is required. `VISUALHUD_THEME=<name>` remains an
explicit one-process override:

```bash
VISUALHUD_THEME=pokemon codex
```

### 3. Install Into Another Codex Repo On macOS

From this VisualHUD repo, install a repo-local copy into any other Git worktree:

```bash
./visualhud install codex --target /path/to/other-repo --theme tmnt
```

The installer writes a hidden runtime under the target repo:

```text
/path/to/other-repo/
  .codex/hooks.json
  .codex/hooks/visualhud-codex.sh
  .visualhud/
    engine.sh
    set_bg.py
    visualhud
    themes/
```

Existing Codex hooks are preserved; the VisualHUD hook is appended once and
reinstalling is idempotent. Restart Codex in the target repo after first install.

Switch themes inside the installed repo with the copied runtime CLI:

```bash
cd /path/to/other-repo
./.visualhud/visualhud theme list
./.visualhud/visualhud theme set pokemon
./.visualhud/visualhud theme set tmnt
```

Pokemon and TMNT are bundled first-party themes in the installed runtime. Sonic
is parked as a future first-party theme candidate after the installer and
Windows renderer tracks are stable.

### 4. Use With Claude Code

Claude Code is wired separately through:

```text
.claude/settings.json
.claude/hooks/visualhud-claude.sh
```

Start or restart Claude Code from this repo. The Claude adapter defaults to the
Pokemon theme and preserves the existing SDLC/TDD hooks.

To use TMNT for this repo, run:

```bash
./visualhud theme set tmnt
```

The next hook picks up the selected theme. To override only one Claude process:

```bash
VISUALHUD_THEME=tmnt claude
```

### 5. Verify

Run the contract tests before calling an install or theme change done:

```bash
bash tests/test-visualhud-cli.sh
bash tests/test-visualhud-install.sh
bash tests/test-theme-system.sh
bash tests/test-theme-calibration.sh
bash tests/test-codex-visualhud.sh
bash tests/test-claude-visualhud.sh
bash tests/test-cooking-status.sh
```

For visual changes, also review a screenshot, generated contact sheet, or a
calibration walk. Shell tests prove hook output and state transitions; they do
not prove aesthetics by themselves.

Generate the full ordered calibration list when a theme has too many visual
states to inspect ad hoc:

```bash
./visualhud theme calibrate tmnt
./visualhud theme calibrate tmnt --json
```

From a real iTerm2 pane, walk the same cycle one step at a time and correct
specific step numbers:

```bash
./visualhud theme calibrate tmnt --live --delay 1
./visualhud theme calibrate tmnt --live --pause
```

### Windows Status

Windows Terminal/PowerShell renderer is not supported yet. The theme JSON
contract is portable, but the current background-image renderer uses the iTerm2
Python API, so Windows needs a separate terminal renderer instead of reusing
`set_bg.py`. The Codex installer fails explicitly on `--platform windows` until
that renderer exists.

## How It Works

Claude Code and Codex fire lifecycle hooks on prompt, tool use, permission request, and stop events. VisualHUD intercepts those hooks and drives iTerm2's appearance through a progression of **stages** — each with its own colors, background image, and title.

```
Hook fires → adapter normalizes event → counter increments → stage advances → iTerm2 updates
```

Each iTerm2 session is isolated via `ITERM_SESSION_ID`, so multiple Claude
windows don't stomp each other.

Review work is a separate lifecycle state from done. If a Codex/Claude code
review or background verification task is still running, VisualHUD shows the
theme's `review` state and keeps `done`/Blastoise/Pizza Party reserved for when
that review task completes.

## Themes

A theme is a directory with a config file and optional assets:

```
themes/
  pokemon/
    theme.json
    sprites/
      charmander.png
      charmeleon.png
      ...
  tmnt/
    theme.json
    sprites/
      tmnt-leonardo.png
      tmnt-michelangelo.png
      ...
  custom/
    theme.json
```

### Theme Config (theme.json)

See [THEMES.md](THEMES.md) for the complete contract and required tests.

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
  "review": { "sprite": "review", "badge": "REV", "name": "Reviewing", "stage": 2, "color": [80, 120, 200] },
  "done": {
    "sprite": "done",
    "badge": "DONE",
    "name": "Done",
    "stage": 3,
    "color": [40, 100, 255]
  },
  "idle": { "sprite": "idle", "badge": "IDLE", "name": "Idle", "stage": 3, "color": [40, 100, 255] },
  "error": { "sprite": "error", "badge": "ERROR", "name": "Error", "color": [255, 40, 40] },
  "context_alerts": {
    "warning": { "min_percent": 70, "badge": "WARN", "name": "Context High", "color": [255, 190, 40] },
    "critical": { "min_percent": 85, "badge": "CRIT", "name": "Context Critical", "color": [255, 255, 255] }
  }
}
```

### Default Theme: Progress Bar

No images needed — just a smooth color gradient that acts as a visual progress bar: red (just started) through yellow/green (making progress) to blue (done). It's a progress bar, not a health bar — the color tracks how far along the task is, not how "healthy" anything is. Works out of the box.

## Landscape — What Else Is Out There?

We researched the space. Nothing does what VisualHUD does.

| Tool | Changes Terminal Appearance | Driven by Process State | Configurable Themes | Multi-Terminal |
|---|---|---|---|---|
| **VisualHUD (this)** | bg + tab color + images + title | Claude Code hooks | Yes (theme.json) | Goal |
| [claude-code-iterm2-tab-status](https://github.com/JasperSui/claude-code-iterm2-tab-status) | Tab title emoji only | Claude Code hooks | No (3 hardcoded states) | No |
| [aiterm](https://github.com/Data-Wise/aiterm) | Profile switch | Directory-based (cd) | No | Yes (6 terminals) |
| [classmethod.jp blog](https://dev.classmethod.jp/en/articles/change-iterm2-background-color-when-claude-code-launches/) | Background color | Start/stop only | No (2 hardcoded states) | No |
| [Zestful](https://zestful.dev/) | Separate overlay | Claude Code hooks | No | N/A |
| [C.H.U.D.](https://github.com/realjbmangum/chud) | Separate Electron window | Claude Code hooks | No | N/A |
| [ccstatusline](https://github.com/sirmalloc/ccstatusline) | Statusline text | Claude Code API | Yes (text themes) | N/A |
| [claude-hud](https://github.com/jarrodwatts/claude-hud) | Statusline text | Claude Code API | No | N/A |

**The gap:** Existing tools either change appearance but not based on process state (aiterm, sshbg), or react to process state through overlays / statuslines / tab emoji — not the terminal itself. Nobody ships a configurable state machine that drives full terminal appearance through hook lifecycle events.

**Complementary tools we could integrate with:**
- **ccstatusline / claude-hud** — they handle the statusline, we handle the terminal chrome
- **aiterm** — they set a baseline profile per project, we modulate it during runtime
- **agent-notify** — they do audio/push notifications, we do visual

**Terminal escape code references for multi-terminal support:**
- iTerm2: `OSC 1337;SetColors`, tab color via `OSC 6;1;bg`, Python API for background images
- Kitty: `kitten @ set-colors`, background via `kitten @ set-background-image`
- WezTerm: Lua `set_config_overrides` for colors and background
- Ghostty: `SIGUSR2` config reload for theme switching
- tmux: status bar styling via `set-option`

## What Works Today

VisualHUD is repo-local and functional for Codex, Claude Code, and iTerm2:

**Working:**
- Tab color changes via iTerm2 escape sequences (`OSC 6;1;bg` and `SetColors=tab`) with per-session isolation.
- Background, selection, cursor, and muted UI surface colors update through `OSC 1337;SetColors`.
- Window/tab title, badge text, and `hudProgress`/`hudContext` user vars update from hook lifecycle state.
- Background images update through the iTerm2 Python API (`LocalWriteOnlyProfile`) for the active terminal session.
- `PreToolUse`, `UserPromptSubmit`, `Notification`, `PermissionRequest`, `Stop`, `StopFailure`, and `SessionStart` are mapped into the engine by repo-local adapters.
- Theme stages use `color_family` plus `shades`, so a character can keep the same sprite while the terminal chrome advances through multiple color steps.
- Pokemon and TMNT both ship source-backed sprite packs and theme JSON.
- Context/token pressure is an ambient overlay: warning and critical label the state while preserving the active stage color/sprite.

**Current hooks:**
- `.codex/hooks/visualhud-codex.sh` maps Codex events into `engine.sh` and defaults to TMNT.
- `.claude/hooks/visualhud-claude.sh` maps Claude Code events into `engine.sh` and defaults to Pokemon.
- Both adapters set `VISUALHUD_REAPPLY_DELAY=0.12` by default to reapply title/color after TUI repaint.

**Known limitations:**
- iTerm2 is the only complete renderer today; Windows Terminal/PowerShell needs a separate renderer.
- Background images are static only; sprite animation is parked until a terminal adapter supports it cleanly.
- Badge content is text/emoji only because iTerm2 does not support image badges.
- Snapshot/restore of the original terminal profile is still planned.

**Tested and confirmed:**
- Background image per-session isolation works via `ITERM_SESSION_ID` UUID extraction.
- GIF backgrounds do not animate in iTerm2; frame cycling works, but low-res source GIFs are not good enough for full-screen backgrounds.
- iTerm2 does not support images in badges or corners: badges are text/emoji only, status bar icons are tiny, and inline images scroll with text.
- Pokemon HOME sprites and source-backed TMNT panel crops work as static backgrounds.

## Sprite Animation

Themes can offer both static and animated sprites. Two approaches, depending on terminal support:

### Approach 1: Native GIF Background

Set an animated GIF directly as the background image. If the terminal animates it natively, this is zero-effort animation.

| Terminal | Animated GIF Background | Status |
|----------|------------------------|--------|
| **WezTerm** | Natively supported | Confirmed working |
| **iTerm2** | First frame only, no animation | **Confirmed not supported (2026-03-22)** |
| **Kitty** | Graphics protocol has frame support | Untested |
| **Ghostty** | PNG/JPEG only, no GIF | Not supported |

Test script: `./test-gif-background.sh`

### Approach 2: Frame Cycling

Extract GIF frames to individual PNGs, cycle them as background images via the Python API. **Tested on iTerm2: animation is smooth, but source sprites are too low-res (48-133px) for 4K displays.** Would need high-res source art (512px+) to look good.

- Charmander: 69 frames, 30ms intervals (~33 FPS) — smooth animation confirmed
- Source quality is the bottleneck, not the cycling mechanism
- No open-source high-res animated Pokemon sprites exist (all game sprites are pixel art < 133px)
- AI upscaling produces blurry results on pixel art at this scale

Test script: `./test-frame-cycling.sh`

**Status: Parked.** The frame cycling mechanism works. Revisit when high-res animated source art is available or AI upscaling improves.

### Theme Config with Animation

Animation is parked until a terminal adapter supports it cleanly. A future
theme extension should keep the current stage contract and add animation fields
beside `"sprite"` instead of replacing the base sprite.

```json
{
  "stages": [
    {
      "name": "Charmander",
      "max": 2,
      "sprite": "charmander",
      "color": [255, 60, 60],
      "badge": "FIRE",
      "animated_sprite": "charmander-run"
    }
  ]
}
```

Engine support for `animated_sprite` is not implemented yet. Add a failing test
before making that contract real.

## Color Shades

Theme stages can define multiple `"shades"` for the same character. The engine
chooses a shade from the current tool-call position inside that stage's range,
so the sprite stays stable while the terminal chrome visibly advances:

```
Michelangelo (max 5)
tool 3 -> [255, 125, 25]
tool 4 -> [255, 150, 48]
tool 5 -> [255, 175, 70]
```

This is deliberate stage-local shading rather than cross-stage interpolation.
Stages can also define `"shade_sprites"` with one sprite per shade when the art
should advance with the color. TMNT uses this for character-color variants, and
future themes such as Batman and Power Rangers should use the same
JSON-plus-sprites contract instead of changing `engine.sh`.

## Token Usage Indicator (Separate from Task Progress)

Task completion (stage progression) is the **main visual driver** — background, tab color, images.

Token/context usage is a **separate ambient indicator** that doesn't interfere with the main visual:
- Badge/title suffix surfaces only when it matters (`CTX 70%+` warning, `CTX 85%+` critical)
- The task stage color, cursor, and sprite stay intact; context labels must not gray-wash or emergency-wash the pane
- Themes can name those alerts: Pokemon uses Pokemon Center/Nurse Joy, TMNT uses Casey Jones for critical context
- Codex can derive context percent from hook payload token data or a matching session JSONL token-count event

These are independent axes: you can be on stage 3 (Charizard) with low token usage, or stage 1 (Charmander) with high token usage.

## TMNT Source Art Import

The TMNT skin is only visually complete once real source images exist on disk.
Chat attachments are not repo files, so place a four-panel character-select
reference at:

```
assets/source/tmnt/character-select.png
```

Then generate source-backed sprite assets:

```
python3 scripts/import-tmnt-sprites.py \
  --source assets/source/tmnt/character-select.png \
  --output-dir themes/tmnt/sprites \
  --source-label "tmnt-character-select-reference"
```

The importer writes `tmnt-leonardo.png`, `tmnt-michelangelo.png`,
`tmnt-donatello.png`, `tmnt-raphael.png`, and `manifest.json` with crop
provenance. Do not ship generated placeholder TMNT art; source-backed PNGs must
include the manifest.

For character-focused one-off assets, the importer strips neutral corner mattes
from source images and renders transparent areas over the matching theme color.
The generated manifest records that color as `backdrop_color`, which prevents
yellow April, white Casey, or other stage families from drifting back to gray.

## Key Bugs We Fixed

Documenting these so we don't repeat them:

1. **`ITERM_SESSION_ID` format mismatch** — The env var is `w0t0p0:UUID` but the iTerm2 Python API's `session.session_id` is just `UUID`. Must strip the prefix: `sid.split(":")[-1]`. This caused background images to silently never match any session.

2. **iTerm2 Python API connection** — Requires "Enable Python API" in iTerm2 Preferences > General > Magic. Without it, all Python API calls fail silently if errors are suppressed.

3. **Badge positioning** — `badge_top_margin` is pixel-based, which breaks on different window sizes. Fix: dynamically calculate from window height on each stage change (`rows * cell_height * 0.85`).

4. **Cross-window contamination** — Original implementation used TTY device for session isolation, which doesn't work in hook sandbox context (`ps` is blocked, `tty` returns garbage). Fix: use `ITERM_SESSION_ID` env var which is always inherited by child processes.

5. **Badge disappears on resize/different monitors** — `badge_top_margin` is pixel-based (not percentage). When the window is shorter than the margin value, the badge goes off-screen. Moving windows between monitors with different sizes makes it worse. Dynamic recalculation in `set_bg.py` helps but only fires on stage transitions, not on resize. **Needs a resize listener in v0.1.**

## Status

**Pre-release.** Repo-local Codex and Claude Code hook wiring works on iTerm2.
Windows Terminal/PowerShell support is tracked separately because it needs a
non-iTerm2 renderer.

---

## Ideas Borrowed From the Ecosystem

Deep-dived every project above and pulled the best patterns:

| Idea | Stolen From | Why It's Good |
|------|-------------|---------------|
| Snapshot/restore terminal state on exit | JasperSui | Clean teardown — save tab color, title, badge before we touch anything, restore when Claude stops |
| "Needs attention" state via `Notification` hook | JasperSui | We only use PreToolUse/Stop — missing the "waiting for permission" state entirely |
| Stale PID cleanup for orphaned state files | JasperSui | Dead sessions shouldn't leave ghost state files around |
| Auto-contrast color adjustment | JasperSui | If theme color is too close to tab's existing color, auto-pick a visible alternative |
| Terminal abstraction layer (per-terminal module) | aiterm | Each terminal (iTerm2, Kitty, Ghostty, WezTerm) gets its own adapter with same interface |
| Context health thresholds (green <70%, yellow 70-84%, red 85%+) | ccstatusline | Modulate visual intensity based on context window usage |
| DI pattern for testing (no heavy mocks) | claude-hud | Inject deps, test cleanly |
| Config priority: env vars > config file > defaults | JasperSui | Standard, flexible, zero-surprise |
| Hot-reload config on file mtime change | JasperSui | Change theme without restarting Claude |
| Focus-to-dismiss attention state | JasperSui | Attention clears when user looks at the tab |
| Multi-agent priority display (highest alert wins) | Zestful | When running multiple sessions, show the most urgent state |

---

## Roadmap

### Now — Extract & Polish (v0.1)

Core engine + themeable + works reliably:

**Done:**
- [x] Per-session isolation via `ITERM_SESSION_ID` (UUID extraction)
- [x] Background images matched to correct session (fixed `w0t0p0:UUID` → `UUID`)
- [x] Badge emoji per-stage (🔥⚡🌿💧) with text progress bar at top-right
- [x] Badge position fixed: top-right with zero margins (no more disappearing on resize)
- [x] `setup-iterm2.sh` — automated iTerm2 settings configuration
- [x] Cursor color uses iTerm2-native `SetColors=curbg=` instead of unsupported `OSC 12`
- [x] Pokemon HOME sprites (512x512) — crisp on 4K
- [x] 11 stages with complete evolution lines (Raichu added)
- [x] Demo script (`demo.sh`) for testing all features
- [x] Confirmed: GIF backgrounds don't animate in iTerm2, frame cycling works but needs hi-res source art
- [x] Confirmed: iTerm2 badges are text/emoji only, no images

**Current focus — Harden the theme engine:**

The theme engine is now data-driven: `engine.sh` reads `theme.json`, advances
stage counters, applies stage shades, resolves sprite paths, and drives iTerm2.
Pokemon and TMNT live under `themes/`, and both Codex and Claude use repo-local
adapters.

Next hardening work:
- Replace any weak TMNT one-off cover-art states with character-focused source art.
- Add the next branded theme candidates, Batman and Power Rangers, as JSON/sprite packs that prove third-theme parity without engine changes.
- Add a terminal-renderer abstraction for Windows Terminal/PowerShell, Kitty, WezTerm, and Ghostty.
- Add snapshot/restore so VisualHUD can return terminal chrome to its original state.
- Add a CLI installer/doctor once the repo-local contract is stable.

**Then — Polish:**
- [ ] **Window border integration (JankyBorders)** — colored border around iTerm2 window that changes with stage progression:
  - Uses JankyBorders (`brew install borders`) with `apply-to=<window-id>` for per-window support
  - Border color matches current stage (red → yellow → green → blue)
  - Border thickness increases as task progresses (thin at start, thick at done)
  - Done state: thick border stays in final color as persistent visual indicator
  - Supports multiple iTerm2 windows simultaneously (each gets its own border color based on its session state)
  - Replaces any current janky border solution entirely
  - Get window ID via macOS Accessibility API or yabai, pass to `borders apply-to=<wid> active_color=0xffRRGGBB width=N`
  - Supports gradient (`gradient(top_left=...,bottom_right=...)`) and glow (`glow(0xAARRGGBB)`) effects
  - Requires macOS 14.0+ (Sonoma)
- [ ] **Snapshot/restore** — save terminal state before first hook, restore on Stop
- [ ] **"Needs attention" state** — hook into `Notification` event for `permission_prompt`
- [ ] **Stale state cleanup** — auto-remove state files for dead sessions
- [ ] **Config priority** — env vars > `~/.visualhud/config.json` > defaults

### Release — Easy Install & Switch (v1.0)

What makes it a real tool people can actually use:

- [ ] CLI: `visualhud install`, `visualhud theme list`, `visualhud theme set <name>`
- [ ] CLI: `visualhud theme preview` — cycle through stages in current terminal
- [ ] CLI: `visualhud doctor` — validate setup (terminal, hooks, theme, permissions)
- [ ] Auto-configure Claude Code hooks in `settings.json`
- [ ] Validate theme configs on install
- [ ] Uninstall / reset terminal to defaults
- [ ] Support custom stage counts (some tasks are 5 tool calls, some are 50)
- [ ] **Hot-reload config** — change theme.json mid-session, picks up on next hook
- [ ] **Auto-contrast** — if theme color clashes with existing tab color, auto-adjust
- [ ] **Terminal abstraction** — iTerm2 adapter first, then Kitty/WezTerm/Ghostty adapters
- [ ] **Context health modulation** — intensify visuals as context window fills (70%/85% thresholds)
- [ ] **macOS notifications + sound** — optional `afplay` on stage transitions or attention
- [ ] Plugin marketplace distribution (Claude Code `/plugin install`)
- [ ] README with install instructions, screenshots, GIFs
- [ ] Pre-built theme packs (Nord, Dracula, Gruvbox color palettes as themes)

### Big Brain Ideas

Things that would be sick but aren't urgent:

- [ ] **Theme builder CLI** — interactive wizard to define stages, pick colors, assign images
- [ ] **Community themes** — repo of user-contributed themes, `visualhud theme install <github-url>`
- [ ] **Sound effects** — play a short sound on stage transitions (evolution sound, anyone?)
- [ ] **Adaptive stage count** — auto-scale stages based on historical tool-call patterns per project
- [ ] **Multi-tool awareness** — different visuals for Read vs Write vs Bash vs Agent
- [ ] **Multi-agent priority** — when multiple Claude sessions run, surfaces the most urgent state
- [ ] **Focus-to-dismiss** — attention state auto-clears when user focuses the tab (iTerm2 FocusMonitor API)
- [ ] **Team themes** — shared theme configs via dotfiles repo
- [ ] **Image generation** — AI-generate theme assets from a prompt ("medieval RPG progression")
- [ ] **Stats dashboard** — track cooking sessions, average tool calls, time per stage
- [ ] **tmux support** — status bar integration for tmux users
- [ ] **Unix socket IPC** — replace file-based state with socket for sub-millisecond updates
- [ ] **iOS companion** — push notifications + Dynamic Island for mobile awareness
- [ ] **Context-aware themes** — auto-switch theme based on project type (production = red safety theme)
- [ ] **OSC 8 hyperlinks** — clickable links in terminal output
- [ ] **ModelIntelligence score** — visual indicator of estimated quality as context fills
