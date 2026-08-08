# VisualHUD Roadmap

GitHub issues are the source of truth for actionable work. GitHub milestones define release scope, this file records milestone priority and the active release goal, and GitHub Releases record what shipped. Release artifacts are published and verified before the milestone closes.

Only open issues are listed here. Within each milestone, issues are ordered by execution priority; closed work remains available in GitHub issues and Releases.

## Priority 1 - Ship v1.2.0

### v1.2.0 - Release Readiness

[View milestone](https://github.com/BaseInfinity/visualhud/milestone/2)

## Active Goal

Ship the existing VisualHUD `1.2.0` source as a reliable, diagnosable npm and GitHub release. Work through these release blockers in order:

1. [#10 - Make Codex HUD state and HITL semantics unambiguous](https://github.com/BaseInfinity/visualhud/issues/10)
2. [#11 - Add a host, model, and renderer regression matrix](https://github.com/BaseInfinity/visualhud/issues/11)
3. [#9 - Make silent failures diagnosable](https://github.com/BaseInfinity/visualhud/issues/9)
4. [#5 - Apply or explicitly block the iTerm2 setup helper](https://github.com/BaseInfinity/visualhud/issues/5)
5. [#7 - Resolve Claude Code TUI rendering conflicts](https://github.com/BaseInfinity/visualhud/issues/7)
6. [#2 - Clarify restart requirements and Windows renderer limits](https://github.com/BaseInfinity/visualhud/issues/2)
7. [#3 - Detect missing WezTerm and explain renderer support](https://github.com/BaseInfinity/visualhud/issues/3)

## Completion Criteria

1. Every issue in the active milestone is closed with its acceptance criteria verified.
2. `npm test` passes from a clean release candidate.
3. Configured non-publishing candidate CI passes for the release candidate.
4. The release documentation audit passes and README commands, renderer support, screenshots, and limitations match the release.
5. The release dry-run and package inspection pass.
6. The `v1.2.0` tag points at the intended release commit and GitHub has release notes for `v1.2.0`.
7. `npm view visualhud version` reports `1.2.0`.

A release milestone is not complete until the npm registry and GitHub release both expose the verified release version.

## Priority 2 - Build v1.3.0

### v1.3.0 - Theme and UX

[View milestone](https://github.com/BaseInfinity/visualhud/milestone/1)

1. [#12 - Add a guided theme-pack picker with visual and sound lanes](https://github.com/BaseInfinity/visualhud/issues/12)
2. [#4 - Use Slowpoke or Psyduck for reconnect states](https://github.com/BaseInfinity/visualhud/issues/4)
3. [#14 - Add a Stardew Valley-inspired farm journey theme pack](https://github.com/BaseInfinity/visualhud/issues/14)
4. [#13 - Add stable theme demos and a release documentation audit](https://github.com/BaseInfinity/visualhud/issues/13)

Additional work enters this milestone only after it has a scoped GitHub issue with acceptance criteria.

## Later

[Review unmilestoned issues](https://github.com/BaseInfinity/visualhud/issues?q=is%3Aopen+is%3Aissue+no%3Amilestone)

Ideas are not release commitments until they become GitHub issues and are assigned to a milestone.
