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

1. [#16 - Run a supervised Codex/iTerm2 release-candidate canary](https://github.com/BaseInfinity/visualhud/issues/16)
2. [#17 - Publish and verify VisualHUD v1.2.0](https://github.com/BaseInfinity/visualhud/issues/17)

Issue #16 requires the maintainer to inspect the real installed Codex/iTerm2
experience. Issue #17 remains last and requires explicit approval because npm
versions and release tags are immutable distribution actions.

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

1. [#12 - Add a guided theme-pack picker with visual and sound lanes](https://github.com/BaseInfinity/visualhud/issues/12)
2. [#4 - Use Slowpoke or Psyduck for reconnect states](https://github.com/BaseInfinity/visualhud/issues/4)
3. [#14 - Add a Stardew Valley-inspired farm journey theme pack](https://github.com/BaseInfinity/visualhud/issues/14)
4. [#13 - Add stable theme demos after theme-pack UX is complete](https://github.com/BaseInfinity/visualhud/issues/13)

Demos remain last so they capture stable picker, sound, lifecycle, and theme-pack
behavior rather than immediately becoming stale.

## Priority 3 - Expand v1.4.0

### v1.4.0 - Host and Platform Parity

[View milestone](https://github.com/BaseInfinity/visualhud/milestone/3)
[Release documentation gate](RELEASE_CHECKLIST.md)

1. [#3 - Detect missing WezTerm and explain Windows renderer support](https://github.com/BaseInfinity/visualhud/issues/3)
2. [#18 - Add Claude Code task-journey parity after Codex stabilization](https://github.com/BaseInfinity/visualhud/issues/18)

Existing Windows Terminal and WezTerm behavior remains regression-covered, but
new Windows feature work is intentionally behind the macOS/iTerm2 release and
theme UX milestones. Claude keeps its current adapter until the Codex journey
contract is proven and the host-specific mapping in #18 is implemented.

Ideas are not release commitments until they become GitHub issues and are
assigned to a milestone.
