# VisualHUD Roadmap

GitHub issues are the source of truth for actionable work. GitHub milestones define release scope.
This file records milestone priority and the active release goal, and GitHub
Releases record what shipped. Release artifacts are published and verified before the milestone closes.

Only open issues are listed here. Every open issue belongs to one release
milestone, and issues within each milestone are ordered by execution priority.
Closed work remains available in GitHub issues and Releases.

## Priority 1 - Ship v1.2.0

### v1.2.0 - Release Readiness

[View milestone](https://github.com/BaseInfinity/visualhud/milestone/2)
[Release documentation gate](RELEASE_CHECKLIST.md)

## Active Goal

Produce a verified VisualHUD `1.2.0` release candidate before distributing it.
Implementation and deterministic proof can run unattended. Real-terminal
acceptance and immutable publication remain separate supervised slices.

### Current Corrective SDLC Checkpoint

Resume the staged review-workflow candidate from base commit
`7400f7c24b91ffb8fc348e2ff1a2a2d08b02eebb`; it is not committed or published.
The original three final-review blockers now have focused regressions and fixes:
review receipts hash the exact patch bytes sent to reviewers, forced termination
still reaches reviewer descendants after the direct child exits, and managed-file
hashes are refreshed. The 2026-08-16 guarded `npm test` proof passed but has
expired and must not be reused.

The interrupted Sol High review was recovered from its local session record. It
reported one P1 (the neutral-directory Sol subprocess needs
`--skip-git-repo-check`) and one P2 (Fable certification must reject model
substitution). RED/GREEN coverage for both findings passes, and the managed
hashes are refreshed. This candidate is eligible to commit only after one fresh
replacement guarded proof and one clean, bounded Sol High review of that exact
frozen tree; use the proof receipt and Git history as the completion record. Do
not publish npm. If Fable is genuinely unavailable, the single fallback reviewer
is Opus 4.8 at `xhigh`; reconcile that adapter policy in a later wizard slice
rather than expanding this candidate.

The first clean acceptance attempt exposed one final guard-contract defect: the
documented standalone same-worktree `git -C <absolute-worktree> commit` form was
classified as a foreign repository. A focused regression and fail-closed fix now
allow one absolute `-C` only when it resolves to the same physical proven
repository; foreign targets and compound repository switches remain blocked. The
completion commit is valid only when Git history follows a fresh guarded proof
and clean Sol High review that include this final delta.

The bounded Sol High review of that candidate then found a P1 in the narrow
`git -C` exception: an executable command substitution could switch to a foreign
repository before the same-worktree command ran. RED regressions now cover both
command and process substitutions, the exception declines every executable
substitution before the recursive foreign-context checks run, and the focused
guard suite passes 21/21. The previous proof is superseded. Freeze this corrected
tree, refresh its managed hash, run one replacement guarded proof, and obtain a
clean corrective Sol High verdict before committing or pushing.

### Unattended Overnight Scope

The unattended implementation and documentation slices are complete. Their
acceptance evidence remains in the v1.2 GitHub issues, commits, and release
audit. The remaining release work is deliberately supervised.

Never publish npm, create a release tag, create a GitHub Release, close the
milestone, or run the real-pane canary inside the unattended scope. Stop and
leave exact evidence if the same problem fails twice, credentials or interactive
approval are required, the active worktree cannot be preserved, or an issue's
acceptance criteria remain materially ambiguous.

### Supervised Release Scope

These slices begin only after the unattended release candidate is green:

1. [#22 - Fix Linux CI WezTerm journey-stage regression](https://github.com/BaseInfinity/visualhud/issues/22)
2. [#20 - Preserve the iTerm2 top tab bar during VisualHUD setup](https://github.com/BaseInfinity/visualhud/issues/20)
3. [#19 - Prevent expected iTerm2 process probes from emitting false setup blockers](https://github.com/BaseInfinity/visualhud/issues/19)
4. [#16 - Run a supervised Codex/iTerm2 release-candidate canary](https://github.com/BaseInfinity/visualhud/issues/16)
5. [#17 - Publish and verify VisualHUD v1.2.0](https://github.com/BaseInfinity/visualhud/issues/17)

Issue #22 blocks all candidate work until Linux CI is green. Issue #20
invalidates the candidate with SHA-256
`01b039ca675e9d1cf58135d70ced18a853eafda521b9c3cbb230779a6043fb5f`;
it must never be published. Issues #20 and #19 must both be verified in a new
candidate before issue #16 resumes. Issue #16 requires the maintainer to inspect
the real installed Codex/iTerm2 experience. Issue #17 remains last and requires
explicit approval because npm versions and release tags are immutable
distribution actions.

## Completion Criteria

1. Every issue in the active milestone is closed with its acceptance criteria verified.
2. `npm test` passes from a clean release candidate without repainting the developer's active terminal pane.
3. Configured non-publishing candidate CI passes for the release candidate.
4. The release documentation audit passes and README commands, renderer support, screenshots, and limitations match the release.
5. The release dry-run and package inspection pass.
6. The supervised Codex/iTerm2 canary passes and the maintainer accepts its visual evidence.
7. The `v1.2.0` tag points at the intended release commit and GitHub has release notes for `v1.2.0`.
8. `npm view visualhud version` reports `1.2.0` after a fresh consumer install is verified.

A release milestone is not complete until the npm registry and GitHub release
both expose the verified release version.

## Priority 2 - Build v1.3.0

### v1.3.0 - Theme and UX

[View milestone](https://github.com/BaseInfinity/visualhud/milestone/1)
[Release documentation gate](RELEASE_CHECKLIST.md)

1. [#23 - Show active GitHub issue and milestone progress in the HUD](https://github.com/BaseInfinity/visualhud/issues/23)
2. [#24 - Learn per-repository checkpoint ETA ranges](https://github.com/BaseInfinity/visualhud/issues/24)
3. [#4 - Use Slowpoke or Psyduck for reconnect states](https://github.com/BaseInfinity/visualhud/issues/4)
4. [#12 - Add a guided theme-pack picker with visual and sound lanes](https://github.com/BaseInfinity/visualhud/issues/12)
5. [#14 - Add a Stardew Valley-inspired farm journey theme pack](https://github.com/BaseInfinity/visualhud/issues/14)
6. [#13 - Add stable theme demos after theme-pack UX is complete](https://github.com/BaseInfinity/visualhud/issues/13)

Authoritative issue and milestone context comes first, followed by reconnect
semantics, because delivery and status clarity are core Codex UX. Demos remain
last so they capture stable picker, sound, lifecycle, and theme-pack behavior
rather than immediately becoming stale.

## Priority 3 - Expand v1.4.0

### v1.4.0 - Host and Platform Parity

[View milestone](https://github.com/BaseInfinity/visualhud/milestone/3)
[Release documentation gate](RELEASE_CHECKLIST.md)

1. [#21 - Audit VisualHUD against Codex SDLC Wizard/Harness v1.0](https://github.com/BaseInfinity/visualhud/issues/21)
2. [#18 - Add Claude Code task-journey parity after Codex stabilization](https://github.com/BaseInfinity/visualhud/issues/18)
3. [#3 - Detect missing WezTerm and explain Windows renderer support](https://github.com/BaseInfinity/visualhud/issues/3)

Existing Windows Terminal and WezTerm behavior remains regression-covered, but
new Windows feature work is intentionally behind the macOS/iTerm2 release and
theme UX milestones. Issue #21 starts only after the requested stable upstream
v1.0 boundary. Claude keeps its current adapter until that Codex journey
contract is proven and the host-specific mapping in #18 is implemented.

Ideas are not release commitments until they become GitHub issues and are
assigned to a milestone.
