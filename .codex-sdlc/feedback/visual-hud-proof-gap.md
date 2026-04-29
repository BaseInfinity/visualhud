# Feedback: Visual HUD Proof Gap

## Type

Improvement / bug report

## Description

The SDLC workflow allowed a visual HUD feature to be described as working after
hook/state tests passed, even though the user-visible art assets were missing
and the rendered terminal UI was unacceptable.

## Local Context

- Product area: VisualHUD theme engine and Codex hook adapter
- User expectation: TMNT skin should swap actual character images, not only
  colors, badges, and stage names
- Observed failure: `themes/tmnt/theme.json` referenced TMNT sprite names, but
  `themes/tmnt/sprites/*.png` did not exist
- Follow-up failure: generated placeholder panels were added to make tests pass,
  but they did not satisfy the user requirement for real TMNT character-select
  art
- Observed failure: shell tests passed while iTerm2 rendered an oversized badge
  and stale/non-TMNT background art

## Evidence

- Added RED test: `tests/test-cooking-status.sh` Test 25 now fails when any
  sprite referenced by the TMNT theme lacks a real PNG asset
- Added proof rule: `PROVE-IT.md` now says visual HUD changes require a
  screenshot/manual check before claiming visual appearance is done

## What Should Change

- Wizard-generated SDLC guidance should distinguish implementation proof from
  user-visible visual proof for UI/HUD/desktop work
- For visual themes, setup should require tests that referenced assets exist,
  not only that theme metadata references names
- For visual asset packs, setup should require provenance/source manifest checks
  so generated placeholders cannot masquerade as finished assets
- For terminal/desktop UI changes, the proof checklist should require a
  screenshot or manual visual validation before final handoff
- Wizard docs should warn that mocked terminal/iTerm behavior cannot prove
  layout, badge size, contrast, or background aesthetics
