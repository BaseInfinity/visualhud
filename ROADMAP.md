# VisualHUD Roadmap

## TMNT Hardening Before New Themes

Current theme priority is TMNT quality, not another branded theme. The goal is
that Codex/TMNT feels as solid as the existing Pokemon/Claude flow before we add
Batman, Power Rangers, or any other skin.

- [x] Source-backed TMNT sprite pack covers every stage, shade, lifecycle, and context sprite in `themes/tmnt/theme.json`.
- [x] TMNT importer strips neutral source mattes and records theme-derived `backdrop_color` so yellow/white/gray stages do not drift to stale neutral panes.
- [x] Generated TMNT contact sheet covers every color/state and reports zero missing sprites.
- [ ] Live visual pass across all TMNT bands: Leo, Mikey, Donnie, Raph, April, Metalhead, Mutagen, Splinter, Krang, Foot Clan, Turtle Power, Shredder, Pizza, Casey.
- [ ] Codex TMNT title/badge/progress presentation should match the clarity of the Claude Pokemon panes, including visible progress state instead of a plain `visualhud (codex)` title when the host permits it.
- [ ] Replace any remaining weak one-off art crops found during the live visual pass with better source-backed crops.
- [ ] **Batman** (parked) — next branded theme candidate after TMNT hardening is visually accepted.
- [ ] **Power Rangers** (parked) — future color-team theme candidate after TMNT hardening and third-theme scaffolding are stable.
- [ ] **Sonic** (parked) — future speed/progress theme candidate after TMNT hardening, installer, and Windows renderer tracks are stable.
- [ ] Windows Terminal/PowerShell stays a separate renderer track; do not mix that portability work into TMNT theme quality.

## Theme Engine
Repo-local theme swapping exists. The remaining work is install/runtime sync and real sprite art assets.

- [x] `engine.sh` — reads `theme.json`, replaces hardcoded if/elif chain
- [x] `theme.json` schema — stages, colors, sprites per theme
- [x] Port current Pokemon impl to `themes/pokemon/theme.json`
- [x] Codex adapter defaults to TMNT through `.codex/hooks/visualhud-codex.sh` while preserving repo-local theme switching
- [x] TMNT theme data swaps stage sprite names, badges, and colors through the engine
- [x] Theme-local sprite lookup — prefer `themes/<theme>/sprites/*.png`, then fallback to legacy global sprites
- [ ] Default "colors only" theme (no sprites, just progress bar)
- [x] Add source-backed TMNT turtle sprite importer for four-panel character-select references
- [x] Add actual source-backed TMNT sprite PNG assets under `themes/tmnt/sprites/` with `manifest.json` provenance
- [x] Extend TMNT source imports beyond the four turtles: April, Metalhead, Mutagen, Splinter, Krang, Foot Clan, Turtle Power, Shredder, Pizza
- [x] Codex macOS repo install — `visualhud install codex --target <repo>` copies a local runtime and preserves existing hooks

## Themes
- [x] **Pokemon** — shipped first-party theme and Claude default
- [x] **TMNT** — shipped first-party theme and Codex default: Leonardo blue, Michelangelo orange, Donatello purple, Raphael red, April yellow, Metalhead gray, Mutagen green, Splinter brown, Krang pink, Foot Clan steel-purple, Turtle Power green
- [ ] **Otter Pop** — 6 popsicle flavors by color (Strawberry Short Kook, Sir Isaac Lime, Alexander the Grape, Little Orphan Orange, Louie-Bloo Raspberry, Poncho Punch)
- [x] **TMNT sprite pack** — actual background PNGs for all TMNT stage/lifecycle sprite names
- [ ] **MISSINGNO error sprite** — glitch Pokemon for ERROR/StopFailure state
- [ ] **Pokemon ghost-line extension** — add Gastly/Haunter/Gengar purple overflow only after real theme-local sprites are available; do not ship missing-art references
- [ ] **Batman** (parked) — do after TMNT hardening, not before
- [ ] **Power Rangers** (parked) — color-team theme candidate after TMNT hardening and theme authoring docs are stable
- [ ] **Sonic** (parked) — speed/progress theme candidate after the bundled-theme install path is boring and repeatable

## Theme System Features
- [ ] **TMNT roster packs** — support selectable packs inside one theme, e.g. `heroes`, `villains`, or `arcade` under `tmnt` instead of separate `tmnt-heroes`/`tmnt-villains` themes
- [ ] **Mix & match colors** — random palette selection from color pools across themes
- [ ] **Sprite pools** — don't hardcode evolution lines; define pools per color/stage category, random pick each session
- [x] **Easy theme swapping** — `visualhud theme list/current/set/reset`
- [ ] **Theme marketplace** — browse, preview, install community themes (`@visualhud/theme-*`)
- [ ] Per-theme demo scripts with proper sprite art credits

## HUD Features
- [x] **Codex TMNT identity skin** — Codex hook adapter routes events into the theme engine with TMNT selected: TMNT roster while working, Shredder when blocked, Pizza Party when done, and Splinter on session idle
- [x] **Code review lifecycle state** — review/background verification no longer false-advertises done while a review task is still active
- [x] **Compact iTerm badge payloads** — keep badge text short so configured bottom-right badges do not dominate the terminal
- [ ] **Visual regression proof** — scripted/manual screenshot checklist for badge size, color contrast, title text, and background behavior
- [ ] **TDLC: Terminal Development Life Cycle** — if terminal UI testing keeps exceeding normal shell/contact-sheet proof, define a dedicated lifecycle for terminal apps: captured pane screenshots, OCR/color sampling, host-terminal fixture runs, and explicit human-visible acceptance gates.
- [ ] **Session context header** — show session/project/week info in title/badge (skip `/status`)
- [ ] **Project identity** — glance across terminals, know which project each is on
- [ ] **Celebratory finished state** — Hall of Fame / Elite 4 victory beyond Blastoise
- [x] **Context/token usage alert overlay** — warning at 70%+ and critical at 85%+ via badge/title/user var without overriding stage color/sprite
- [ ] **Cost usage tracking** — visual warnings approaching rate/credit limits
- [ ] **Kindle-style time estimation** — "~2 min left" based on historical sessions
- [ ] **Sound effects** — optional theme-matched sounds on state changes (Pokemon cries, etc.)

## Distribution
- [ ] **One-command install** — `npx visualhud` sets up hooks, sprites, iTerm2 config
- [x] **CLI install for Codex on macOS** — repo-local runtime copy, hook merge, theme selection
- [ ] **CLI tool** — theme switching/install exists; `visualhud doctor/preview` still pending
- [ ] **Codex on Windows install path** — document supported install targets and build a Windows adapter instead of reusing the iTerm2-only background API
- [ ] Auto-configure Claude Code hooks in `settings.json`

## Platform Support
- [ ] **Other agents** — Cursor, Windsurf, Cline, Aider (pluggable event source)
- [ ] **Other terminals** — Kitty, WezTerm, Ghostty adapters
- [ ] **Windows terminals** — Windows Terminal/PowerShell/WSL support with a non-iTerm background strategy
- [ ] **Winamp-style theming** — push every visual capability to the max
