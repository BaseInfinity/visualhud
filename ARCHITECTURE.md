# VisualHUD Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────┐
│ Claude Code / Codex                                      │
│  ├── Hook Events (PreToolUse, Stop, UserPromptSubmit)   │
│  ├── Permission events                                   │
│  └── settings.json / .codex/hooks.json                   │
└──────────────┬──────────────────────────────────────────┘
               │ JSON on stdin
               ▼
┌─────────────────────────────────────────────────────────┐
│ visualhud-codex.sh / visualhud-claude.sh                  │
│  └── Normalize host events to VisualHUD engine events     │
└──────────────┬──────────────────────────────────────────┘
               │ JSON on stdin
               ▼
┌─────────────────────────────────────────────────────────┐
│ engine.sh (theme-driven VisualHUD engine)                │
│  ├── Reads event type + tool count                       │
│  ├── Calculates stage (logarithmic progression)          │
│  ├── Reads selected theme JSON                           │
│  ├── Sets iTerm2 visuals (escape sequences)              │
│  └── Calls set_bg.py for background images               │
└──────────────┬──────────────────────────────────────────┘
               │
    ┌──────────┼──────────┐
    ▼          ▼          ▼
┌────────┐ ┌────────┐ ┌────────┐
│ iTerm2 │ │ State  │ │set_bg  │
│ Escape │ │ Files  │ │.py     │
│ Seqs   │ │(/tmp/) │ │(Python)│
└────────┘ └────────┘ └────────┘
    │                      │
    ▼                      ▼
┌─────────────────────────────────────────────────────────┐
│ iTerm2 Terminal                                          │
│  ├── Tab color          (OSC 6;1;bg + SetColors=tab)     │
│  ├── Background tint    (OSC 1337;SetColors=bg=)         │
│  ├── Selection surface  (OSC 1337;SetColors=selbg=)      │
│  ├── Neutral UI surface (OSC 1337;SetColors=black=)      │
│  ├── Muted UI surface   (OSC 1337;SetColors=br_black=)   │
│  ├── Cursor color       (OSC 1337;SetColors=curbg=)      │
│  ├── Title bar          (OSC 0; + SetUserVar hudProgress)│
│  ├── Badge              (colored square progress bar)    │
│  └── Background image   (iTerm2 Python API)              │
└─────────────────────────────────────────────────────────┘
```

## Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `engine.sh` | repo root | Theme-driven hook engine — receives normalized events and drives all visuals |
| `visualhud-codex.sh` | `.codex/hooks/` | Codex adapter — maps Codex hook events into `engine.sh` and selects the TMNT theme |
| `visualhud-claude.sh` | `.claude/hooks/` | Claude adapter — maps Claude hook events into `engine.sh` and selects the Pokemon theme |
| `set_bg.py` | repo root | Python bridge to iTerm2 API for per-session background images |
| `themes/<theme>/theme.json` | repo theme dirs | Theme stages, colors, badges, and sprite names |
| `themes/<theme>/sprites/` | repo theme dirs | Theme-local PNG sprite packs, preferred by `engine.sh` when present |
| `sprites/` | repo root or `~/.claude/hooks/sprites/` | Legacy global PNG sprite fallback |
| `scripts/import-tmnt-sprites.py` | repo root | Crops a source-backed four-panel TMNT character-select reference into theme-local sprite PNGs plus `manifest.json` provenance |
| `demo.sh` | repo root | Interactive demo of all 11 stages + attention states |
| `setup-iterm2.sh` | repo root | Configures iTerm2 defaults for VisualHUD |
| `diagnose.py` | repo root | Diagnostic tool for troubleshooting |

## State Management

- **Per-session isolation** via `ITERM_SESSION_ID`
- State files in `/private/tmp/` with session-keyed filenames
- Tool call counter: `/private/tmp/claude-cooking-counter_${SESSION_KEY}`
- Current stage/sprite marker: `/private/tmp/claude-cooking-stage_${SESSION_KEY}`
- Context/token alert marker: `/private/tmp/claude-cooking-context_${SESSION_KEY}`
- Active code-review/background-verification marker: `/private/tmp/claude-cooking-review_${SESSION_KEY}`

## 11-Stage Progression (Logarithmic)

The default Pokemon theme preserves the original progression:

| Stage | Calls | Pokemon | Color |
|-------|-------|---------|-------|
| 1 | 1-2 | Charmander | Red |
| 2 | 3-5 | Charmeleon | Red |
| 3 | 6-12 | Charizard | Red |
| 4 | 13-25 | Pikachu | Yellow |
| 5 | 26-45 | Raichu | Yellow |
| 6 | 46-75 | Bulbasaur | Green |
| 7 | 76-120 | Ivysaur | Green |
| 8 | 121-180 | Venusaur | Green |
| 9 | 181-280 | Squirtle | Blue |
| 10 | 281-400+ | Wartortle | Blue |
| 11 | Stop | Blastoise | Blue (done) |

## Attention States

| State | Trigger | Sprite | Visual |
|-------|---------|--------|--------|
| BLOCKED | `permission_prompt` notification | Snorlax | Dark/muted colors |
| REVIEW | Code-review/background-verification task starts | Wartortle | Non-final review state |
| ERROR | `StopFailure` event | Warning | Red warning |
| DONE | `Stop` or `idle_prompt` | Blastoise | Blue done state |

Codex maps `PermissionRequest` to the `permission_prompt` notification and maps
`SessionStart` to the done state so a new Codex session starts idle.

The Codex TMNT theme uses the same stage thresholds with a wider character/color
spectrum: Leonardo blue, Michelangelo orange, Donatello purple, Raphael red,
April yellow, Metalhead gray, Mutagen green, Splinter brown, Krang pink, Foot
Clan steel-purple, and Turtle Power green. BLOCKED maps to Shredder, DONE maps
to Pizza Party, REVIEW maps to Splinter Review, and idle maps to Splinter.

## Context Alerts

Context usage is an ambient overlay, not a task-progress stage. When the engine
can read token/context data from the hook payload or a matching Codex session
JSONL file, it shows `CTX nn%` at 70%+ and switches to critical at 85%+.
Warning and critical overlays update badge/title/user-var text while preserving the selected theme stage color and sprite.
Theme configs can provide their own alert identity and colors through
`context_alerts`; those colors are metadata for reports/future non-destructive
indicators, not a replacement for the active stage surface palette. Pokemon
maps high context to Pokemon Center/Nurse Joy, while TMNT maps critical context
to Casey Jones.

## Key Technical Decisions

- **Escape sequences over API**: Direct iTerm2 escape sequences for speed (tab color, title, badge, selection/background/neutral surface palette). Python API only for background images (no escape sequence equivalent).
- **Logarithmic scaling**: Tool calls don't map linearly to progress. Early calls feel fast, later stages are earned.
- **File-based state**: Simple, no dependencies, naturally per-session via env var.
- **SetUserVar**: "Claude-proof" title that Claude Code can't overwrite with its own title.
- **Delayed reapply**: Adapters set `VISUALHUD_REAPPLY_DELAY=0.12` by default so the engine re-emits title/color variables shortly after hook exit. This prevents Codex/Claude TUI repaints from leaving stale prompt-box or tab chrome colors.

## Deployment

Local only. Source lives in the repo. Codex reads `.codex/hooks.json` and
`.codex/hooks/visualhud-codex.sh`; Claude Code reads `.claude/settings.json` and
`.claude/hooks/visualhud-claude.sh`. Each adapter points at the same repo-local
engine but can choose a different default theme.

Theme selection precedence is `VISUALHUD_THEME > repo-local active theme file > VISUALHUD_DEFAULT_THEME > pokemon`.
The active theme file is written by `./visualhud theme set <name>`, so a running
pane can switch themes on the next hook without restarting Codex or Claude.

## Theme Engine

The current theme engine reads `theme.json` with `jq`, supports multiple themes,
and prefers theme-local sprite assets before falling back to legacy global
sprites. Stage entries declare `color_family` and `shades`; the engine chooses
the active shade from the current tool-call position inside that stage band, so
Michelangelo can stay Michelangelo while orange advances across multiple steps.
Stages may also declare `shade_sprites` to swap character art per shade, such as
Raphael red variants matching the red ramp.
If a selected theme sprite is missing, the engine sends an empty background image
path to `set_bg.py` so stale art from a previous theme does not remain visible.
See `ROADMAP.md` for remaining install, asset-pack, and marketplace work.

TMNT sprite art must be source-backed. `scripts/import-tmnt-sprites.py` accepts a
four-panel character-select source image and crops the turtle panels into
`themes/tmnt/sprites/` with a manifest recording source and crop coordinates.
For character-focused crops, the importer strips neutral corner mattes and fills
transparent backdrop areas from the active theme color or shade, recorded as
`backdrop_color` in the manifest.
The repo intentionally does not ship generated placeholder TMNT art.
