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

The proof-aware review hardening slice is committed and pushed as
`b1ba40ca641aa92248eca80f0a406fe8cac955c8`. Its replacement guarded proof passed
on the frozen candidate and the bounded Sol High review returned no findings. No
npm package was published.

The Linux CI correction is committed and pushed as
`f52ae10bd96bf5706df4922c6dd0bc0c33ecf0bf`. Its frozen guarded proof passed,
the corrective Sol High review returned no P0-P3 findings, and
[Ubuntu/Node 24 run 32595505328](https://github.com/BaseInfinity/visualhud/actions/runs/32595505328)
passed in 5m19s. Issue #22 is closed with the schema, current-generation review
frame, local proof, and CI evidence. No replacement release tarball was packed
and npm was not published.

The Pokemon critical-context investigation also confirmed that the active stage
colors can change while Nurse Joy/Blissey is never rendered in the live HUD.
Issue #25 is now the active blocker. It records the accepted product contract:
preserve the journey character as the primary visual and render Nurse
Joy/Blissey as a distinct critical-context overlay, removing it cleanly on
de-escalation. Renderer inspection confirmed that iTerm2 exposes one background
image slot while WezTerm supports layered backgrounds. A bounded Fable
consultation rejected replacing the primary sprite and confirmed that runtime
PNG dependencies are unacceptable. The RED regression first failed on the
missing compositor. The current GREEN candidate now renders actual source-backed
alert art: iTerm2 receives a deterministic side-by-side PNG whose primary region
preserves every decoded journey pixel, while WezTerm receives a distinct scoped
color and character layer. De-escalation restores the original primary path.
Focused evidence is green for the new overlay contract, iTerm bridge, lifecycle,
WezTerm, theme docs, installed runtime, package consumer, review workflow,
ShellCheck, and Python compilation. The first frozen proof passed. Its bounded
Sol High review found one P2 portability gap: valid third-party grayscale, RGB,
indexed, alpha, or Adam7 PNG assets could silently lose their iTerm context
overlay. A targeted RED reproduced the failure, and the dependency-free decoder
now accepts the standard PNG color types, valid bit depths, transparency, and
Adam7 input. The replacement review then found a P2 memory-exhaustion path for
extreme third-party dimensions/compression; its targeted RED now requires early
dimension rejection and bounded decompression. The focused GREEN now covers both
limits. A bounded Fable
consultation was attempted for that narrow design choice but returned no advice
because it exhausted its single allowed turn. The release audit's
90-file/45,057,392-byte package metadata and finalized managed-file hashes are
current. The next step is to freeze the self-reviewed corrected candidate for
its final replacement guarded proof and bounded Sol High review;
no npm package was published. If Fable is genuinely unavailable for a future required review,
the single fallback reviewer is Opus 4.8 at `xhigh`; reconcile that adapter policy
in a later wizard slice rather than expanding this release candidate.

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

1. [#25 - Render Nurse Joy/Blissey as an honest critical-context overlay](https://github.com/BaseInfinity/visualhud/issues/25)
2. [#20 - Preserve the iTerm2 top tab bar during VisualHUD setup](https://github.com/BaseInfinity/visualhud/issues/20)
3. [#19 - Prevent expected iTerm2 process probes from emitting false setup blockers](https://github.com/BaseInfinity/visualhud/issues/19)
4. [#16 - Run a supervised Codex/iTerm2 release-candidate canary](https://github.com/BaseInfinity/visualhud/issues/16)
5. [#17 - Publish and verify VisualHUD v1.2.0](https://github.com/BaseInfinity/visualhud/issues/17)

Issue #25 blocks replacement candidate packing so its visual contract is
exercised once, not discovered after another supervised canary. Issue #20
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
9. Every remaining open GitHub issue has current status, milestone, dependencies, and a contributor-ready next action before the release milestone closes.

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
