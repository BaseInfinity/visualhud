# VisualHUD Roadmap

GitHub issues are the source of truth for actionable work. GitHub milestones define release scope, this file records milestone priority and the active release goal, and GitHub Releases record what shipped after a milestone closes.

## Active Goal

### v1.2.0 - Release Readiness

[View milestone](https://github.com/BaseInfinity/visualhud/milestone/2)

Ship the existing VisualHUD `1.2.0` source as a reliable, diagnosable npm and GitHub release. Keep implementation work limited to these milestone issues:

- [#10 - Make Codex HUD state and HITL semantics unambiguous](https://github.com/BaseInfinity/visualhud/issues/10)
- [#11 - Add a host, model, and renderer regression matrix](https://github.com/BaseInfinity/visualhud/issues/11)
- [#9 - Make silent failures diagnosable](https://github.com/BaseInfinity/visualhud/issues/9)
- [#7 - Resolve Claude Code TUI rendering conflicts](https://github.com/BaseInfinity/visualhud/issues/7)
- [#5 - Apply or explicitly block the iTerm2 setup helper](https://github.com/BaseInfinity/visualhud/issues/5)
- [#3 - Detect missing WezTerm and explain renderer support](https://github.com/BaseInfinity/visualhud/issues/3)
- [#2 - Clarify restart requirements and Windows renderer limits](https://github.com/BaseInfinity/visualhud/issues/2)

## Completion Criteria

1. Every issue in the active milestone is closed with its acceptance criteria verified.
2. `npm test` passes from a clean release candidate.
3. The release dry-run and package inspection pass.
4. The `v1.2.0` tag points at the intended release commit and is visible on GitHub.
5. `npm view visualhud version` reports `1.2.0`.
6. GitHub has release notes for `v1.2.0`.

## Next

### v1.3.0 - Theme and UX

[View milestone](https://github.com/BaseInfinity/visualhud/milestone/1)

- [#4 - Use Slowpoke or Psyduck for reconnect states](https://github.com/BaseInfinity/visualhud/issues/4)

Additional work enters this milestone only after it has a scoped GitHub issue with acceptance criteria.

## Later

[Review unmilestoned issues](https://github.com/BaseInfinity/visualhud/issues?q=is%3Aopen+is%3Aissue+no%3Amilestone)

Ideas are not release commitments until they become GitHub issues and are assigned to a milestone.
