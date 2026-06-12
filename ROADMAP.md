# VisualHUD Roadmap

## TMNT Hardening Before New Themes

Current theme priority is TMNT quality, not another branded theme. The goal is
that Codex/TMNT feels as solid as the existing Pokemon/Claude flow before we add
Batman, Power Rangers, or any other skin.

- [x] Source-backed TMNT sprite pack covers every stage, shade, lifecycle, and context sprite in `themes/tmnt/theme.json`.
- [x] TMNT importer strips neutral source mattes and records theme-derived `backdrop_color` so yellow/white/gray stages do not drift to stale neutral panes.
- [x] Generated TMNT contact sheet covers every color/state and reports zero missing sprites.
- [ ] Live visual pass across all TMNT bands: Leo, Mikey, Donnie, Raph, April, Metalhead, Mutagen, Splinter, Krang, Foot Clan, Turtle Power, Shredder, Pizza, Casey.
- [ ] **TMNT per-shade portrait variants** — replace crop-only shade variants with distinct source-backed portraits/poses for bands like Michelangelo orange, Raphael red, Donatello purple, and April yellow.
- [ ] Codex TMNT title/badge/progress presentation should match the clarity of the Claude Pokemon panes, including visible progress state instead of a plain `visualhud (codex)` title when the host permits it.
- [ ] Replace any remaining weak one-off art crops found during the live visual pass with better source-backed crops.
- [ ] **Batman** (parked) — next branded theme candidate after TMNT hardening is visually accepted.
- [x] **Power Rangers** — shipped as colors-only theme; sprite art to be added later.
- [x] **Power Rangers shade-ramp and dwell pass** — MMPR stages now ramp within each ranger/zord color and use balanced colors-only dwell thresholds instead of flashing through unrelated saturated colors during the first tool calls.
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
- [x] Default "colors only" theme (`themes/minimal/`) — no sprites, just progress bar
- [x] Add source-backed TMNT turtle sprite importer for four-panel character-select references
- [x] Add actual source-backed TMNT sprite PNG assets under `themes/tmnt/sprites/` with `manifest.json` provenance
- [x] Extend TMNT source imports beyond the four turtles: April, Metalhead, Mutagen, Splinter, Krang, Foot Clan, Turtle Power, Shredder, Pizza
- [x] Codex macOS repo install — `visualhud install codex --target <repo>` copies a local runtime and preserves existing hooks

## Themes
- [x] **Pokemon** — shipped first-party theme and Claude default
- [x] **TMNT** — shipped first-party theme and Codex default: Leonardo blue, Michelangelo orange, Donatello purple, Raphael red, April yellow, Metalhead gray, Mutagen green, Splinter brown, Krang pink, Foot Clan steel-purple, Turtle Power green
- [x] **Otter Pop** — 6 popsicle flavors by color (Strawberry Short Kook, Sir Isaac Lime, Alexander the Grape, Little Orphan Orange, Louie-Bloo Raspberry, Poncho Punch)
- [x] **TMNT sprite pack** — actual background PNGs for all TMNT stage/lifecycle sprite names
- [ ] **MISSINGNO error sprite** — glitch Pokemon for ERROR/StopFailure state
- [ ] **Pokemon ghost-line extension** — add Gastly/Haunter/Gengar purple overflow only after real theme-local sprites are available; do not ship missing-art references
- [ ] **Batman** (parked) — do after TMNT hardening, not before
- [x] **Power Rangers** — MMPR color-team progression: Red, Blue, Yellow, Pink, Black, Green, White, Gold Rangers, Megazord, Dragonzord, Ultrazord
- [ ] **Sonic** (parked) — speed/progress theme candidate after the bundled-theme install path is boring and repeatable

## Theme System Features
- [ ] **TMNT roster packs** — support selectable packs inside one theme, e.g. `heroes`, `villains`, or `arcade` under `tmnt` instead of separate `tmnt-heroes`/`tmnt-villains` themes
- [ ] **Theme creator workflow** — add a guided `/theme`/`visualhud theme create` flow that scaffolds `themes/<name>/theme.json`, sprite folders, calibration/contact-sheet proof, and agent instructions from `THEMES.md`
- [x] **Theme calibration covers optional lifecycle states** — `visualhud theme calibrate` now includes theme opt-ins for plan, compacting, and subagent states, so colors-only themes like Power Rangers get the same reviewable lifecycle proof as sprite-backed themes.
- [ ] **Mix & match colors** — random palette selection from color pools across themes
- [ ] **Sprite pools** — don't hardcode evolution lines; define pools per color/stage category, random pick each session
- [x] **Easy theme swapping** — `visualhud theme list/current/set/reset`
- [ ] **Theme marketplace** — browse, preview, install community themes (`@visualhud/theme-*`)
- [ ] Per-theme demo scripts with proper sprite art credits
- [ ] **Animated demo asset** — generate a GIF/video of a realistic Codex or Claude task sped up through the default theme's full color/progress cycle for README/npm/GitHub preview

## HUD Features
- [x] **Codex TMNT identity skin** — Codex hook adapter routes events into the theme engine with TMNT selected: TMNT roster while working, Shredder when blocked, Pizza Party when done, and Splinter on session idle
- [x] **Code review lifecycle state** — review/background verification no longer false-advertises done while a review task is still active; `REVIEW_FILE` now persists across `UserPromptSubmit` so a user message during an in-flight Codex/Claude review shell does not flip the next `Stop` to "Your turn"
- [x] **Compact iTerm badge payloads** — keep badge text short so configured bottom-right badges do not dominate the terminal
- [x] **Compact-by-default rendering** — `VISUALHUD_BG` defaults `off`; full-pane sprite background is opt-in via `VISUALHUD_BG=on`. iTerm2 tab bar now sits at the bottom (hero-banner-footer) via `setup-iterm2.sh`
- [x] **Project identity (CwdChanged hook)** — when Claude/Codex `cd`s between projects, VisualHUD resets stage counter and re-themes title to the new project name automatically
- [x] **Session context header (SessionStart hook)** — captures `model` (e.g. `claude-opus-4-7`) into `/private/tmp/claude-cooking-model_*`; on `source=clear` or `source=compact` resets stage/counter/attention/review for a fresh slate
- [x] **Plan-mode visual variant (permission_mode=plan)** — themes can opt in by defining a `.plan` lifecycle state; engine renders it on PreToolUse/UserPromptSubmit while plan mode is active; falls through gracefully when theme has no `.plan`. Pokemon/TMNT/minimal all ship a default `.plan` state.
- [x] **effort.level capture** — engine reads `effort.level` (low/medium/high/xhigh/max) from any payload, persists into `/private/tmp/claude-cooking-effort_*`, and emits as iTerm2 user var `hudEffort` for status-bar / future shade-intensity treatments
- [x] **PostToolUseFailure rollback** — PreToolUse still optimistically counts (backwards compat); PostToolUseFailure decrements counter so failed tool calls don't pollute progression, plus flashes the error state without persisting attention
- [x] **PreCompact / PostCompact hooks** — themes opt into `.compacting` lifecycle state; Pokemon ships `MISSINGNO` badge / glitch purple during compaction (closes the long-standing MISSINGNO error sprite ROADMAP item — repurposed as the natural "glitch moment" sprite)
- [x] **SubagentStart / SubagentStop hooks** — themes opt into `.subagent` lifecycle state; engine renders subagent overlay while a Task subagent is active, restores on stop. Pokemon uses Pikachu (electric helper), TMNT uses Metalhead (robot helper).
- [ ] **Visual regression proof** — scripted/manual screenshot checklist for badge size, color contrast, title text, and background behavior
- [ ] **TDLC: Terminal Development Life Cycle** — if terminal UI testing keeps exceeding normal shell/contact-sheet proof, define a dedicated lifecycle for terminal apps: captured pane screenshots, OCR/color sampling, host-terminal fixture runs, and explicit human-visible acceptance gates.
- [ ] **Session context header** — show session/project/week info in title/badge (skip `/status`)
- [ ] **Project identity** — glance across terminals, know which project each is on
- [x] **Celebratory finished state** — Mew done state keeps Blastoise as the final progress-stage Pokemon
- [x] **Context/token usage alert overlay** — warning at 70%+ and critical at 85%+ via badge/title/user var without overriding stage color/sprite
- [ ] **Ranger Formation window choreography** — `visualhud ranger formation` should activate iTerm2, raise/unminimize all iTerm windows, arrange at most six visible sessions on a single laptop display, and cascade/overlap the rest so solo one-monitor workflows stay manageable.
- [ ] **Voice/dictation workflow docs** — document the recommended macOS setup for using Dictation/Voice Control with Codex/Claude terminals, including double-tap Control dictation and always-on Voice Control tradeoffs.
- [ ] **Claude `/insights` with Fable max** — run `/insights` at least once in this repo using Claude with the Fable model at max reasoning/effort, then record any VisualHUD/agent-workflow findings back into the roadmap or follow-up issues.
- [x] **Cost usage tracking** — engine parses `transcript_path` JSONL out-of-band, sums `input_tokens + cache_creation_input_tokens + cache_read_input_tokens + output_tokens` across all `type:assistant` lines, persists running total under `VISUALHUD_STATE_DIR` / temp state as `claude-cooking-tokens_*`, and emits iTerm2 user var `hudCost` for status-bar consumption. Threshold-based visual warnings by spend are deferred to v1.2.1.
- [ ] **Kindle-style time estimation** — "~2 min left" based on historical sessions
- [ ] **Sound effects** — optional theme-matched sounds on state changes (Pokemon cries, etc.)
- [ ] **Claude Code statusline integration** — customize `/statusline` to show VisualHUD stage/theme info alongside native cost/context data by reading engine state files from the statusline script
- [ ] **Claude Code `/color` + `/rename` integration** — explore programmatic session coloring and naming; `/rename` can be set via `SessionStart` hook's `sessionTitle` output; `/color` is manual-only today

## Distribution
- [x] **One-command Codex repo install** — `npx -y visualhud@latest install codex` installs repo-local hooks, runtime, themes, sprites, and skills
- [ ] **npm publish** — publish or reserve the `visualhud` package after final metadata/license decision
- [x] **iTerm2 setup via CLI** — `visualhud setup iterm2` configures iTerm2 (and `--reset` reverts it)
- [x] **CLI install for Codex on macOS** — repo-local runtime copy, hook merge, theme selection
- [x] **CLI doctor** — `visualhud doctor` reports deps, themes, runtime presence
- [ ] **CLI preview** — `visualhud preview <theme>` still pending
- [x] **Codex on Windows install path** — document supported install targets and ship a title/progress Windows adapter instead of reusing the iTerm2-only background API
- [x] Auto-configure Claude Code hooks in `settings.json` — `visualhud install claude --target <repo>` merges hooks without clobbering existing SDLC/TDD entries

## Platform Support
- [ ] **Other agents** — Cursor, Windsurf, Cline, Aider (pluggable event source)
- [x] **WezTerm adapter** — Windows-friendly live title/status/color/background renderer through `SetUserVar` + Lua config overrides
- [ ] **Other terminals** — Kitty, Ghostty adapters
- [ ] **Windows terminals** — extend Windows Terminal/PowerShell/WSL beyond title/progress with a non-iTerm background strategy
- [ ] **Winamp-style theming** — push every visual capability to the max
