# VisualHUD

A themeable visual status engine for Claude Code + iTerm2.

Watch your terminal transform in real-time as Claude works — colors shift, backgrounds swap, and tab titles update to show exactly where things stand. Ship with themes or build your own.

## How It Works

Claude Code fires hooks on every tool use (`PreToolUse`) and when it stops (`Stop`). VisualHUD intercepts those hooks and drives iTerm2's appearance through a progression of **stages** — each with its own colors, background image, and title.

```
Hook fires → counter increments → stage advances → iTerm2 updates
```

Each iTerm2 session is isolated via `ITERM_SESSION_ID`, so multiple Claude windows don't stomp each other.

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
  healthbar/
    theme.json
  cyberpunk/
    theme.json
    backgrounds/
      ...
```

### Theme Config (theme.json)

```jsonc
{
  "name": "Pokemon Evolution",
  "description": "Fire → Electric → Grass → Water progress bar",
  "stages": [
    {
      "name": "Charmander",
      "at": 1,           // trigger at this tool-call count
      "color": [255, 60, 60],
      "title": "Charmander",
      "badge": "🔥",    // badge emoji shown in bottom-right
      "image": "sprites/charmander.png"
    },
    {
      "name": "Charmeleon",
      "at": 4,
      "color": [255, 100, 50],
      "title": "Charmeleon",
      "badge": "🔥",
      "image": "sprites/charmeleon.png"
    }
    // ...9 more stages
  ],
  "done": {
    "name": "Blastoise",
    "color": [40, 100, 255],
    "title": "Blastoise",
    "badge": "💧",
    "image": "sprites/blastoise.png"
  },
  "blend": 0.15,
  "tint_ratio": 0.3
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

The current implementation lives in `~/.claude/hooks/` and is fully functional:

**Working:**
- Tab color changes via iTerm2 escape sequences (`OSC 6;1;bg`) — per-session, no cross-window bleed
- Background tint color via `OSC 1337;SetColors=bg=` — per-session
- Cursor color via `OSC 12` — per-session
- Window/tab title with emoji via `OSC 0` — per-session
- Background images via iTerm2 Python API (`LocalWriteOnlyProfile`) — per-session
- Badge emoji matching current stage type (🔥⚡🌿💧) — dynamically positioned at bottom-right based on window size
- Per-session isolation via `ITERM_SESSION_ID` env var (UUID extraction — `w0t0p0:UUID` → `UUID`)
- Stage progression (11 stages + done, 3 tool calls each = 33 tool calls to done):
  - 🔥 Charmander → Charmeleon → Charizard (red → orange → gold)
  - ⚡ Pikachu → Raichu (yellow → amber)
  - 🌿 Bulbasaur → Ivysaur → Venusaur (light green → dark green)
  - 💧 Squirtle → Wartortle → Blastoise/done (light blue → deep blue)
- Every evolution line is complete — it's a progress bar from red (start) to blue (done)

**Current hooks:**
- `PreToolUse` — increments counter, advances stage
- `Stop` — sets final state (Blastoise), resets counter

**Assets:**
- 11 static PNGs (512x512, Pokemon HOME 3D renders from PokeAPI) — used as backgrounds, look great on 4K
- 7 animated GIFs (45-106px, 29-69 frames, 30-40ms timing) — not used (too low-res for backgrounds)

**Known limitations:**
- No "needs attention" state (missing `Notification` hook)
- No snapshot/restore of original terminal state
- No smooth color blending between stages (hard jumps)
- Background images are static only (no sprite animation — see Sprite Animation section)
- iTerm2 only
- Badge is text/emoji only — no images in badge (iTerm2 limitation)

**Tested and confirmed (2026-03-22):**
- Background image per-session isolation works via `ITERM_SESSION_ID` UUID extraction
- GIF backgrounds do NOT animate in iTerm2 (first frame only)
- Frame cycling (rapidly swapping PNGs) works smoothly but source GIFs are too low-res (48-133px) for full-screen backgrounds on 4K
- Badge emoji (🔥⚡🌿💧) works per-stage, dynamically positioned at ~85% window height
- No high-res animated Pokemon sprites exist in open source (Showdown, PokeAPI, fan projects all cap at ~133px)
- iTerm2 does NOT support images in badges or corners: badges are text/emoji only, status bar icons max 16x17px, inline images scroll with text
- AI upscaling (Real-ESRGAN) failed to build; pixel art upscaling (nearest-neighbor, LANCZOS) insufficient for 4K
- Pokemon HOME sprites (512x512, PokeAPI) look great as static backgrounds on 4K

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

```jsonc
{
  "stages": [
    {
      "name": "Charmander",
      "at": 1,
      "color": [255, 60, 60],
      "image": "sprites/charmander.png",         // static fallback
      "animated_image": "sprites/charmander.gif", // animated (if supported)
      "emoji": "🔥"
    }
  ]
}
```

Engine picks `animated_image` if the terminal supports it, falls back to `image`.

## Color Blending

Colors blend smoothly between stages rather than jumping. The engine interpolates RGB values based on tool-call count relative to stage boundaries:

```
Stage 1 (at: 1)  color: [255, 60, 60]   Charmander red
   ↕ smooth blend
Stage 2 (at: 3)  color: [255, 100, 50]  Charmeleon orange
   ↕ smooth blend
Stage 3 (at: 6)  color: [255, 150, 40]  Charizard gold
```

At tool call 2 (halfway between stage 1 and 2), the color would be `[255, 80, 55]` — a blend of Charmander red and Charmeleon orange. Background images still swap at stage boundaries.

## Token Usage Indicator (Separate from Task Progress)

Task completion (stage progression) is the **main visual driver** — background, tab color, images.

Token/context usage is a **separate ambient indicator** that doesn't interfere with the main visual:
- Badge or small indicator (bottom-right or top-right of terminal)
- Surfaces only when it matters (warning at 70%+, critical at 85%+)
- Could use iTerm2 badge (`OSC 1337;SetBadgeFormat=`) or a subtle background tint shift

These are independent axes: you can be on stage 3 (Charizard) with low token usage, or stage 1 (Charmander) with high token usage.

## Key Bugs We Fixed

Documenting these so we don't repeat them:

1. **`ITERM_SESSION_ID` format mismatch** — The env var is `w0t0p0:UUID` but the iTerm2 Python API's `session.session_id` is just `UUID`. Must strip the prefix: `sid.split(":")[-1]`. This caused background images to silently never match any session.

2. **iTerm2 Python API connection** — Requires "Enable Python API" in iTerm2 Preferences > General > Magic. Without it, all Python API calls fail silently if errors are suppressed.

3. **Badge positioning** — `badge_top_margin` is pixel-based, which breaks on different window sizes. Fix: dynamically calculate from window height on each stage change (`rows * cell_height * 0.85`).

4. **Cross-window contamination** — Original implementation used TTY device for session isolation, which doesn't work in hook sandbox context (`ps` is blocked, `tty` returns garbage). Fix: use `ITERM_SESSION_ID` env var which is always inherited by child processes.

5. **Badge disappears on resize/different monitors** — `badge_top_margin` is pixel-based (not percentage). When the window is shorter than the margin value, the badge goes off-screen. Moving windows between monitors with different sizes makes it worse. Dynamic recalculation in `set_bg.py` helps but only fires on stage transitions, not on resize. **Needs a resize listener in v0.1.**

## Status

**Pre-release.** Currently a set of hook scripts in `~/.claude/hooks/`. This README is the blueprint.

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

**Next — Build the theme engine (this is the big one):**

The theme engine replaces the hardcoded Pokemon stages in `cooking-status.sh` with a generic engine that reads `theme.json`. This is what makes VisualHUD a real tool instead of a one-off script.

1. **Move hook scripts + sprites into this repo** — copy `cooking-status.sh`, `set_bg.py`, and sprites from `~/.claude/hooks/` into `~/visualhud/`. The repo becomes the source of truth.

2. **Theme engine (`engine.sh`)** — a shell script that:
   - Reads `theme.json` with `jq` (stages, colors, images, badges)
   - Accepts `cooking` or `cooked` mode (same as current)
   - Increments counter, looks up current stage from config
   - Drives iTerm2 escape sequences + Python API (same as current, just data-driven)
   - This replaces the hardcoded if/elif chain with a config lookup

3. **Pokemon theme (`themes/pokemon/`)** — port current implementation:
   ```
   themes/pokemon/
     theme.json        # 11 stages + done, colors, badge emojis
     sprites/           # 11 HOME PNGs (512x512)
       charmander.png
       charmeleon.png
       ...
   ```

4. **Default progress bar theme (`themes/progressbar/`)** — colors only, no images:
   ```
   themes/progressbar/
     theme.json        # stages with colors only, no image field
   ```
   Red → yellow → green → blue gradient. Works on any terminal, no Python API needed.

5. **`install.sh`** — symlinks the engine + active theme into `~/.claude/hooks/`:
   ```bash
   # Sets active theme and wires up Claude Code hooks
   visualhud/install.sh pokemon    # or: install.sh progressbar
   ```
   Creates symlinks so Claude Code hooks point to the engine, and the engine knows which theme to load.

6. **`theme.json` schema** — finalize the config format:
   ```jsonc
   {
     "name": "Pokemon Evolution",
     "description": "Fire → Electric → Grass → Water progress bar",
     "terminal": "iterm2",           // which adapter to use
     "blend": 0.15,                  // background image opacity
     "tint_ratio": 0.3,              // how much color tints the background
     "stages": [
       {
         "name": "Charmander",
         "at": 3,                    // tool calls to trigger this stage
         "color": [255, 60, 60],
         "title": "Charmander",
         "badge": "🔥",
         "image": "sprites/charmander.png"  // optional
       }
       // ...more stages
     ],
     "done": {
       "name": "Blastoise",
       "color": [40, 100, 255],
       "title": "Blastoise",
       "badge": "💧",
       "image": "sprites/blastoise.png"
     }
   }
   ```

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
