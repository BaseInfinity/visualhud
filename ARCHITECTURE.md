# VisualHUD Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────┐
│ Claude Code / Codex                                      │
│  ├── Hook Events (PreToolUse, PostToolUse, Stop, etc.)   │
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
│  ├── Reads normalized lifecycle events                   │
│  ├── Applies reversible task-checkpoint transitions       │
│  ├── Keeps tool count as internal telemetry              │
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
│  ├── Badge              (semantic state label)           │
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
| `scripts/visualhud-iterm-canary.py` | repo root | Supervised semantic probe/comparator for the effective iTerm2 session profile |
| `themes/<theme>/theme.json` | repo theme dirs | Theme stages, colors, badges, and sprite names |
| `themes/<theme>/sprites/` | repo theme dirs | Theme-local PNG sprite packs, preferred by `engine.sh` when present |
| `sprites/` | repo root or `~/.claude/hooks/sprites/` | Legacy global PNG sprite fallback |
| `scripts/import-tmnt-sprites.py` | repo root | Crops a source-backed four-panel TMNT character-select reference into theme-local sprite PNGs plus `manifest.json` provenance |
| `demo.sh` | repo root | Interactive demo of all 11 stages + attention states |
| `setup-iterm2.sh` | repo root | Configures iTerm2 defaults for VisualHUD |
| `setup-wezterm.ps1` | repo root | Installs the WezTerm Lua module and creates a default WezTerm config when safe |
| `wezterm/visualhud.lua` | repo root | WezTerm renderer module that reacts to VisualHUD user vars and applies per-window overrides |
| `diagnose.py` | repo root | Diagnostic tool for troubleshooting |

## State Management

- **Per-session isolation** via `ITERM_SESSION_ID`, `WT_SESSION`, or hook payload `session_id`
- State files live under `VISUALHUD_STATE_DIR` or `${TMPDIR:-/tmp}` with session-keyed filenames
- Tool call counter: `claude-cooking-counter_${SESSION_KEY}`
- Current stage/sprite marker: `claude-cooking-stage_${SESSION_KEY}`
- Context/token alert marker: `claude-cooking-context_${SESSION_KEY}`
- Active code-review/background-verification marker: `claude-cooking-review_${SESSION_KEY}`
- Current task journey: `visualhud-journey_${SESSION_KEY}_${PROJECT_KEY}.json`
- Journey transition history: `visualhud-journey-history_${SESSION_KEY}_${PROJECT_KEY}.jsonl`
- Secondary plan/milestone status: `visualhud-aggregate_${SESSION_KEY}_${PROJECT_KEY}`
- Delayed renderer retries are superseded per stable terminal pane identity,
  not per logical hook session. Native pane identifiers are preferred;
  otherwise the engine resolves the actual terminal device behind aliases such
  as `/dev/tty` before falling back to the render-target path. A literal
  `/dev/tty` alias is resolved through the parent process tree so distinct
  fallback panes do not collapse onto one ownership key. Journey and aggregate
  state remain isolated by session and project. The Codex adapter claims that
  pane before any external JSON parsing and passes an explicit `guarded`,
  `unguarded`, or `suppressed` result into the engine, so an older
  classification or translation cannot silently register again and reclaim a
  newer pane frame. Claim records include the originating event class and the
  payload session, even when multiple Codex sessions share one native pane. An
  atomically published per-pane owner record locks the ownership check plus the
  complete terminal and background frame. The iTerm2 background helper must
  finish before that frame ownership is released, so title, colors, and
  character art cannot come from different generations. Meanwhile,
  delayed work that lost ownership continues nonvisual lifecycle bookkeeping
  but cannot repaint the pane. Loop warnings use the same ownership gate.
  Dead or malformed file-lock records are reclaimed after a short observation
  cycle. Empty legacy lock directories are reclaimed, while unknown nonempty
  directories are preserved and trigger one unguarded best-effort frame. An
  unguarded event never schedules delayed repaint retries; if claim storage
  recovers, it serializes its one frame against the recovered lock and is
  suppressed when that lock records a newer owner. Live lock
  contention is different from unavailable storage: the contending event is
  suppressed rather than emitting an overlapping frame.

  Lock-serialized aggregate lifecycles, such as overlapping subagent starts and
  stops, make a fresh reconciliation claim after mutating their marker set.
  Stale subagent reconciliation may supersede only another subagent-class claim
  from the same logical session; a different session or unrelated newer
  lifecycle event remains authoritative. The visible
  frame therefore follows serialized aggregate state rather than the order in
  which the original hook processes happened to start.

Renderer state payloads use a stable cross-runtime schema. `stage` is a JSON
string because theme and host adapters treat checkpoint identifiers as labels;
`progress_percent` is a JSON number. iTerm2, WezTerm, and Windows Terminal must
preserve those types across supported Node versions.

## Codex Task Journey

The Codex-first task journey is driven by trustworthy task and SDLC checkpoints. Each filled top-bar block
represents one named checkpoint with a matching theme stage, color, and
character when the selected visual lane provides one. Tool activity may animate
the current checkpoint, but it cannot advance task completion.

The visible journey is reversible. When tests, review, or CI invalidate earlier
work, later blocks clear and the active stage returns to the checkpoint that
must be repeated. HITL and transient errors are overlays: they preserve the
task's current checkpoint unless the resulting decision or failure actually
invalidates completed work.

The initial built-in profiles are:

- `codex-default`: a coarse understand, plan, implement, verify, review, done
  journey for repos without structured SDLC evidence.
- `sdlc`: the richer intake, discovery, plan, TDD, implementation, targeted
  tests, full suite, self-review, final-review, proof, done journey.
- `release`: an SDLC journey extended with the repository's configured build,
  CI, publish/deploy, and smoke gates.

Profiles are repo- and task-specific. A repository can use the SDLC profile for
normal changes and the release profile only for an actual release. Repositories
without CI skip CI gates instead of simulating them. Local implementation,
tests, and review precede pull-request creation; configured CI/CD begins after
the pull request exists. A proof-invalidating CI failure moves the task journey back
to the appropriate implementation or verification checkpoint, after which local
proof and CI run again. A transient CI infrastructure or authentication failure remains at the CI gate
with an error overlay because it does not invalidate completed work. A post-CI
human or model review is optional repository policy rather than a universal
completion requirement; merge, deploy, and smoke gates appear only when the
selected journey requires them.

Task journey and milestone progress are separate scopes. The top tab answers
where the current issue or task is in its delivery journey. An aggregate such as
`Tasks 2/4` or `Milestone v1.2.0 2/7` answers how many plan items or GitHub issues
are complete and belongs in a secondary status surface. Milestone counts must
come from GitHub or another authoritative tracker and must never advance the
current task's character journey.

The tab title is task-first and width-aware. It prioritizes checkpoint blocks,
`current/total STATE`, and semantic overlays; project and aggregate metadata are
added only when the pane has room. Character, host, model, effort, token, and
context branding do not displace task state. The engine detects the controlling
TTY width when possible; `VISUALHUD_TITLE_WIDTH` is an explicit override.
The iTerm2 background helper pins the exact session profile's custom title to
`user.hudProgress` and the containing tab title to
`currentSession.user.hudProgress`. The tab-scoped binding keeps a later
host-written `session.name` spinner from replacing the task-first title. These
are session/tab-local changes, not mutations of an unrelated pane or the
user's underlying profile.

The Codex wrapper selects `sdlc` when it finds repo-local SDLC evidence and
`codex-default` otherwise. `VISUALHUD_JOURNEY_PROFILE=release` selects the
release journey for an actual release slice; `off` disables journey mode. The
engine also accepts normalized `journey_checkpoint`, `journey_outcome`, and
`journey_aggregate` fields from adapters.

Normal `started` and `passed` evidence is monotonic: routine discovery or plan
bookkeeping after implementation cannot rewind the journey. Starting a new
source edit invalidates later verification and returns to implementation;
starting a test-only edit returns to TDD RED. Ignored
`.visualhud/feedback/**` patches and GitHub issue bookkeeping are journey-neutral,
while mixed patches use the strictest relevant classification. Other backward movement requires
`failed`, `finding`, `invalidated`, or an expected TDD RED signal. The
final-review gate advances only from explicit clean-review evidence; a zero exit
status without a clean result preserves the active review checkpoint. The
bundled CLI records gates that cannot be inferred safely from local hooks, such
as `visualhud journey set ci passed --profile release`; publish and smoke use the
same command shape. A completed task clears its task-scoped aggregate before the
next prompt initializes a new journey. The selected profile remains attached to
an in-flight journey so ordinary repo-default hooks cannot reinterpret
release-only checkpoints. iTerm2, Windows Terminal, and WezTerm all derive CLI
and hook state from the same pane-stable session identity.

Claude Code journey mapping is intentionally deferred. Claude has a different host
lifecycle and may need a different adapter mapping while preserving the same
journey semantics.

## Activity And Calibration

Codex journey mode renders the current task checkpoint. Without a selected
journey, normal agent activity renders the theme's stable `working` state. The
tool-call counter is telemetry, not completion, and therefore does not drive
ordinary colors, sprites, titles, or determinate progress indicators. The historical
11-stage logarithmic progression remains available to deterministic theme
calibration and explicit legacy mode.

## 11-Stage Calibration Progression (Logarithmic)

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
| 10 | 281-400 | Wartortle | Blue |
| 11 | 401+ | Blastoise | Blue |

## Attention States

| State | Trigger | Sprite | Visual |
|-------|---------|--------|--------|
| HITL | `permission_prompt` notification | Snorlax | Explicit approval-required title and iTerm2 notification |
| CHECK | Host-provided permission preflight | Pikachu | Neutral permission-check title; no HITL notification |
| REVIEW | Code-review/background-verification task starts | Alakazam | Non-final review state |
| ERROR | `StopFailure` event | Psyduck | Red warning |
| DONE | `Stop` or review `TaskCompleted` | Mew | Completed state |
| IDLE | `idle_prompt` notification | Eevee | Waiting state |

Codex maps `PermissionRequest` to a correlated `permission_prompt` because Codex exposes no later prompt-shown event. Stable content-derived keys survive Codex's changing event identifier shape, and a lock-protected pending set retains overlapping requests. Matching tool lifecycle events clear only their request without allowing unrelated concurrent tools to hide the remaining HITL state. The adapter also maps
`SessionStart` to an idle rendering so a new Codex session does not look like active work, and maps
object-shaped `PostToolUse` responses with an explicit failure status to the
engine's `PostToolUseFailure` event. Codex unified shell responses expose raw
output without an exit status, so VisualHUD forwards completion without guessing
failure from shell text. A foreground review-shaped `PostToolUse` with explicit object-shaped
success evidence is normalized to the engine's `TaskCompleted` event so the
review marker clears; unknown/raw results and commands with an asynchronous
review shell segment remain in review, and failed review/plan calls do
not decrement unrelated activity telemetry. Codex does not register
Claude-only lifecycle names such as `TaskCompleted`, `CwdChanged`, or
`PostToolUseFailure` directly.

Journey evidence is accepted only for an actual foreground command. Merely
reading a test-runner path cannot create verification evidence. Started tool
operations record the current journey generation under their stable request
key; an implementation or test edit increments that generation, so an older
concurrent test or review completion cannot revalidate changed code. A coarse
Codex read-only turn may complete on `Stop` only while its latest transition is
still understanding/discovery evidence.

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
maps high context to Pokemon Center/Chansey and critical context to Nurse
Joy/Blissey, while TMNT maps critical context to Casey Jones.

## Key Technical Decisions

- **Renderer split**: iTerm2 uses direct escape sequences for tab color, title, badge, selection/background/neutral surface palette and the Python API for background images. Windows Terminal/PowerShell uses title plus `OSC 9;4` progress status. WezTerm receives a `visualhudState` user var and applies per-window colors/backgrounds through Lua `window:set_config_overrides()`.
- **Semantic default**: Codex uses an evidence-driven task journey when its wrapper selects a profile. Ordinary work without a journey is stable and indeterminate. Logarithmic stages are retained for calibration and explicit legacy mode only.
- **File-based state**: Simple, no dependencies, naturally per-session via env var.
- **SetUserVar**: "Claude-proof" title that Claude Code can't overwrite with its own title.
- **Delayed reapply**: Adapters can set `VISUALHUD_REAPPLY_DELAY` for one compatibility retry or `VISUALHUD_REAPPLY_DELAYS` for a bounded retry sequence. Codex uses `0.12 0.50`, so title/color variables paint immediately and twice more across its redraw window; background restoration still runs only on the first retry to avoid image churn. Claude retains the single `0.12` retry.

### Compatibility And Test Isolation

`docs/compatibility-matrix.v1.json` is the machine-readable host, renderer,
lifecycle, and model-lane contract. Sanitized fixtures exercise every event
that actually invokes a VisualHUD adapter. Renderable lifecycle fixtures pass
through each host adapter and the real engine for iTerm2, WezTerm, and Windows
Terminal; failures name the exact host, renderer, event, model, and effort lane.

The full deterministic suite clears inherited `ITERM_SESSION_ID`, `WT_SESSION`,
and `WEZTERM_PANE`. When a test does not provide an explicit capture target,
`VISUALHUD_TEST_CAPTURE_DIR` forces terminal control output into a temporary
file and disables the default iTerm2 background API helper. Tests may still
provide an explicit `VISUALHUD_TTY` or `VISUALHUD_SET_BG` double for focused
renderer assertions. This boundary applies only to tests and prevents routine
`npm test` runs from repainting the developer's active pane.

Codex is the host protocol; Sol model and effort selections are compatibility
lanes within Codex. Authenticated model and real-pane testing remain outside
default CI and are tracked as a supervised release canary.

## Deployment

Local only. Source lives in the repo. Codex reads `.codex/hooks.json` and
`.codex/hooks/visualhud-codex.sh`; Claude Code reads `.claude/settings.json` and
`.claude/hooks/visualhud-claude.sh`. Each adapter points at the same repo-local
engine but can choose a different default theme.

Theme selection precedence is `VISUALHUD_THEME > repo-local active theme file > VISUALHUD_DEFAULT_THEME > pokemon`.
The active theme file is written by `./visualhud theme set <name>`, so a running
pane can switch themes on the next hook without restarting Codex or Claude.

## Theme Engine

The current theme engine reads `theme.json` through the bundled Node JSON
helper, supports multiple themes, and prefers theme-local sprite assets before
falling back to legacy global sprites. Stage entries declare `color_family` and
`shades`; the engine chooses the active shade from the current tool-call
position inside that stage band, so Michelangelo can stay Michelangelo while
orange advances across multiple steps.
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
