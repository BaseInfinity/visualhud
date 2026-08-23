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

Issue #25's actual Nurse Joy/Blissey overlay is implemented and pushed in
`4edc9c3168be23d29c12e8c846a91b7782180a9b`. iTerm2 receives a deterministic
side-by-side PNG that preserves the decoded journey pixels; WezTerm receives
separate primary, context-panel, and context-character layers. De-escalation
restores the original primary image. The dependency-free compositor accepts the
standard PNG color types, valid bit depths, transparency, and Adam7 input while
bounding file, dimension, decompression, and canvas memory.

Ubuntu run
[`32600695248`](https://github.com/BaseInfinity/visualhud/actions/runs/32600695248)
then exposed a timing-dependent test bug: the pane-token assertion counted an
asynchronous repaint lock as a third pane. That CI failure is the corrective RED.
Commit `cd2f0868ac4d34e3e9362815e6306e691a096640` counts only canonical numeric
token records. Its focused GREEN, managed-hash check, guarded proof, and bounded
Sol High review passed with no P0-P3 findings; replacement Ubuntu run
[`32601734864`](https://github.com/BaseInfinity/visualhud/actions/runs/32601734864)
passed in 6m37s.

The previously retained candidate is stored at
`/Users/stefanayala/visualhud-release-candidates/v1.2.0/20260822-152000/visualhud-1.2.0.tgz`.
It was packed from `cd2f0868ac4d34e3e9362815e6306e691a096640`, has SHA-256
`691dab58a180b0e52b96566b3f1463f7d7678a92340b99e71e14ce8bed95ad18`,
44,673,700 bytes, 90 entries, and 45,057,392 unpacked bytes. Exact-tarball
inspection and its CLI smoke passed. Issue #20 is closed after confirming that
the packaged helper writes top-tab `TabViewType=0` and reset deletes the explicit
preference. Issues #25 and #19 remain open only for continuity through #16's real
iTerm2 canary.

A bounded Fable High consultation confirmed that pane identity and actual screen
pixels are the two non-negotiable live gates. Computer Use could not attach, and
the iTerm2 API disconnected while creating the disposable window; iTerm2 was not
running and the canary repository remained empty, so no candidate install or pane
mutation occurred. Resume by opening iTerm2 with its Python API enabled, record
the maintainer session ID, create and verify a distinct disposable pane, install
the exact retained tarball there, then capture two converged semantic samples and
a real cropped screenshot containing the Nurse Joy/Blissey pixels. Stop on any
identity or visual mismatch. No npm package was published. If Fable is genuinely
unavailable for a future required review, the single fallback reviewer is Opus
4.8 at `xhigh`; reconcile that adapter policy in a later wizard slice rather than
expanding this release candidate.

The contributor-readiness audit is current across all open issues: every issue
has a milestone and a concrete next action, and suitable v1.3/v1.4 tasks are
labelled for outside help. While auditing final release issue #17, the local-only
`v1.2.0` tag was found to point at divergent historical commit
`9101d49516f63c75b89681f87642e506d5fd6c70`; no remote tag or GitHub Release
exists, and npm still reports `0.1.4` as latest. Do not move or push that tag in
this slice.

A corrective release-automation slice is now in progress because the old
`Publish` workflow let any `v*` tag push publish a fresh source repack. The RED
regression is `bash tests/test-npm-release.sh`: it requires both local and OIDC
paths to accept the retained tarball plus its reviewed SHA-256, forbids tag-push
publication, disables npm lifecycle scripts, and forbids a second broad source
proof inside publication. Focused GREEN is 59/59 and managed hashes are
refreshed. The first guarded proof correctly stopped on the release audit's stale
unpacked-size receipt after packaged documentation changed. Focused package
inspection now records 90 entries and 45,061,423 unpacked bytes, and the audit is
corrected. A later replacement proof passed every functional suite and stopped
only at the final ShellCheck gate on SC2016 diagnostics for two intentional
literal `"$candidate"` test assertions. Those assertions now use escaped-dollar
double quotes; focused release automation and ShellCheck must be green before a
fresh replacement proof. Neither failed broad proof was rerun in its session.
The retained tarball contains
the old `scripts/release-npm.sh`, README, TESTING, and ARCHITECTURE, so SHA-256
`691dab58a180b0e52b96566b3f1463f7d7678a92340b99e71e14ce8bed95ad18` is now
rejected and must never be published. Fable authenticated but returned no output
on two bounded consultation attempts; no Fable conclusion is claimed. A fresh
session must re-read this checkpoint, confirm the focused quoting fix,
self-review, and freeze the staged diff from base
`63db845fb1d01436703b66f4cce8484cda1b1e59`, run one replacement guarded proof,
then one bounded Sol High findings-only review with `Do not rerun tests`.
If both are clean, commit and push the correction and watch CI.
After its CI is green, pack and inspect one replacement tarball, update #25/#19/
#16 to that exact SHA, and run the still-pending real iTerm2 canary against it.
This automation correction does not authorize npm publication, tag mutation, or
GitHub Release creation.

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
2. [#19 - Prevent expected iTerm2 process probes from emitting false setup blockers](https://github.com/BaseInfinity/visualhud/issues/19)
3. [#16 - Run a supervised Codex/iTerm2 release-candidate canary](https://github.com/BaseInfinity/visualhud/issues/16)
4. [#17 - Publish and verify VisualHUD v1.2.0](https://github.com/BaseInfinity/visualhud/issues/17)

Issue #25's deterministic gates are complete; replacement packing is pending
the current publication-automation correction and green CI. Issue #19 must be
verified through that exact artifact during #16. Issue #16 requires the
maintainer to inspect the real installed Codex/iTerm2 pixels. Issue #17 remains
last and requires explicit approval because npm versions and release tags are
immutable distribution actions. The rejected candidate with SHA-256
`01b039ca675e9d1cf58135d70ced18a853eafda521b9c3cbb230779a6043fb5f`
must never be published.

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
