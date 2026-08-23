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
preference. That candidate was later rejected by the publication correction
described below.

An earlier bounded Fable High consultation identified pane identity and actual
screen pixels as the two non-negotiable live gates. Those gates are now complete
against the accepted replacement candidate as recorded below; no npm package was
published. If Fable is genuinely unavailable for a future required review, the
single fallback reviewer is Opus 4.8 at `xhigh`; reconcile that adapter policy in
a later wizard slice rather than expanding this release candidate.

The contributor-readiness audit is current across all open issues: every issue
has a milestone and a concrete next action, and suitable v1.3/v1.4 tasks are
labelled for outside help. While auditing final release issue #17, the local-only
`v1.2.0` tag was found to point at divergent historical commit
`9101d49516f63c75b89681f87642e506d5fd6c70`; no remote tag or GitHub Release
exists, and npm still reports `0.1.4` as latest. Do not move or push that tag in
this slice.

The exact-artifact publication correction is committed and pushed as
`785a801281e57527eb00c5acf8883ca0c966b510`. Both local and OIDC paths now accept
one retained tarball plus its reviewed SHA-256, tag pushes have no publication
authority, npm lifecycle scripts are disabled during dry-run and publication,
and publication does not rerun the broad source proof. The replacement guarded
proof passed. Sol High was unavailable because its account limit was exhausted;
Fable failed closed on model substitution, so the single policy fallback ran as
exact `claude-opus-4-8` at `xhigh` and certified the frozen candidate with no
P0/P1 findings. Ubuntu/Node 24 run
[`32609262351`](https://github.com/BaseInfinity/visualhud/actions/runs/32609262351)
passed in 5m56s.

One replacement candidate was packed from that commit at
`/Users/stefanayala/visualhud-release-candidates/v1.2.0/20260822-180700/visualhud-1.2.0.tgz`.
Its SHA-256 is
`fa3c6c20270ad32880347082d4abe242e306e96605c7a94c09798aff7eede4f1`; it is
44,674,846 bytes with 90 entries and 45,061,423 unpacked bytes. Static package
inspection, embedded-helper equality, the compatibility report, and a disposable
consumer install passed. The authenticated exact-artifact helper dry-run stopped
safely because npm auth is currently unavailable; nothing was published. The
previous candidate SHA-256
`691dab58a180b0e52b96566b3f1463f7d7678a92340b99e71e14ce8bed95ad18` remains
rejected and must never be published.

The replacement tarball was installed from inside disposable iTerm2 session
`A3438E22-7342-4097-BBE3-0E0CE05D0B40`, positively disjoint from maintainer
session `137009C7-6396-4672-83AA-CCBEA585AF8D`. The real install emitted no false
settings blocker. Two semantic samples converged on `Nurse Joy CTX 85%` and the
same generated context composite; two real-window PNG captures were byte-identical
with SHA-256
`e767ad8bf8c8e504d4957ff1fcef922746a8acf889d0a602385ff71b53fecb37`, and visual
inspection confirmed the Blissey overlay pixels beside the journey character.
De-escalation removed the overlay and restored packaged `charmander.png`. The
overlay and installer issues are closed.

After Codex capacity returned, the exact candidate's bounded Sol Medium lane
passed startup, one forward implementation transition, repository/session
isolation, and cleanup in disposable session
`1D82F24D-05F0-4CF2-B3F5-24F7DB66B84A`; its inspected real-window PNG has SHA-256
`02f2365fd7308b3da7d7930c5695acc6882a243e9a1f7b72256231edd4f3ec13`. The Sol
High lane then exposed a real adapter blocker in disposable session
`5D700266-BB0E-454A-AA15-E014BE077613`: title, color, sprite, rollback, full test,
review, proof, and HITL preservation all rendered consistently through the proof
checkpoint (`11/12 PROOF`), but successful terminal outcomes never advanced and
`12/12 DONE` was unreachable. Codex 0.147 emits successful PostToolUse responses
as strings; the adapter recognized success only from structured response objects.
The sanitized live-shape RED is stored in
`tests/fixtures/compatibility/codex-0.147-post-tool-use.json`. The minimum fix
preserves explicit string-failure safeguards while accepting terminal success;
focused adapter, journey (106/106), host/renderer (346/346), and compatibility
checks are green. The first guarded proof reached package inspection and stopped
on its stale unpacked-size receipt after the final helper comment changed the
package by 159 bytes. The next fresh-session replacement proof passed package
inspection, then the live fixture exposed one remaining clean-review parser
gap: `No P0-P3 findings` cleared the review lifecycle but did not emit
`final_review:passed`. That exact assertion is the corrective RED; the minimum
priority-range parser fix makes the focused adapter suite green at 167/167.
The resulting package-receipt RED reported 91 files and 45,062,882 unpacked
bytes; that managed receipt is refreshed and its focused package check is green
at 60/60. The next fresh-session proof then made every product, adapter, journey,
renderer, package, and git-guard suite green before stopping at the late
proof-workflow integrity check: the finalized `ARCHITECTURE.md` hash had not
been refreshed after documenting the raw-string contract. That exact stale-hash
failure is the corrective RED; the manifest now records SHA-256
`04d4e8cff33bcc58e9598e05a68fa2c57ed19554c966379742dccc1d98f082f3`.
The fresh-session replacement proof passed on frozen tree
`a25a40ff37592d21974beb32b90a20bf00c6c7bf`. Its sole bounded Sol High review
then found one P2: arbitrary raw output without one of the narrow failure
phrases could still manufacture passing verification evidence, including the
repository's own `Results: ... 1 failed` format. The exact regression failed at
167/168 before implementation and was strengthened during self-review to include
an earlier green sub-suite followed by a failing aggregate. Raw strings now
reject any explicit failure before considering positive clean-test or
completed-review evidence, and the focused adapter suite passes at 168/168. The
package receipt was refreshed again at 91 files and 45,063,687 unpacked bytes;
its focused check passes at 60/60. That review finding invalidates the prior
frozen tree and proof. Freeze this correction, then run one replacement proof
and one replacement bounded Sol High review.

The replacement proof passed on frozen tree
`d3be89f30271634b829c43c51bfb828f57612ca8`, but its bounded Sol High review
found P1/P2 follow-ups: an early clean sub-suite could still hide an
unrecognized late lint/diff failure, and failure wording inside a completed
review finding could suppress the finding itself. Four exact assertions formed
the next RED at 167/171. Verification now requires terminal suite/proof evidence,
`tests/run-all.sh` emits its success marker only after all late checks pass, and
completed review clean/finding grammar is parsed before generic failure text.
The focused adapter suite passes at 173/173, including the real terminal suite
marker and proof receipt. The finalized package receipt is 91 files and
45,065,498 unpacked bytes.

The resulting proof passed on frozen tree
`686ca9619d79e550f5f410f555900eb0a54bf219`; its Sol High review found two P2
portability gaps: Node TAP places duration metadata after `# fail 0`, the other
supported direct runners use distinct terminal summaries, and proof paths may
contain spaces. The runner-matrix/spaced-path RED failed at 172/177. Terminal
success parsing now covers Node TAP, pytest, Cargo, Go, shell/VisualHUD summaries,
and spaced proof receipts; the focused adapter suite passes at 177/177. Its
package receipt was 91 files and 45,067,271 unpacked bytes.

The resulting proof passed on frozen tree
`aea0731aa1c0a33446ae4527b967aa1df10db484`; its Sol High review found a P1
mixed-review precedence defect plus P2 quiet-pytest and cached-Go variants. The
exact RED failed at 177/181. Completed findings still outrank failure words inside
their own text, but clean review evidence can no longer outrank a later explicit
failure; quiet pytest and cached Go summaries are accepted as terminal success.
The focused adapter suite passes at 181/181, and the current package receipt is
91 files and 45,068,692 unpacked bytes. Freeze, prove, and review this replacement
before committing.

The resulting proof passed on frozen tree
`805f6f6ee11af0408cdedb49420fd834ead511c1`; its Sol High review found two P2
gaps: passing error-handling tests could be vetoed by their intentional diagnostic
text, and shipped shell tests use `Results: PASS`, equal-count, `All ... tests
passed`, and terminal `PASS:` formats. The exact RED failed at 183/186. Recognized
terminal test/proof receipts now outrank earlier diagnostic-looking fixture output,
and every shipped terminal format is covered; the focused adapter suite passes at
186/186. Its package receipt was 91 files and 45,070,605 unpacked bytes.

The resulting proof passed on frozen tree
`606a053d9696badc0c5f697ab4e8b941ecc92675`; its Sol High review found two P1
false-certification paths: mixed terminal summaries such as `1 failed, 3 passed`
matched the generic pass grammar, and partial review clearance such as `No P0
findings` was treated as globally clean. The exact RED failed at 186/190. Mixed
failed summaries are rejected, and review success now requires unqualified clean
output or the complete `P0-P3` range. The focused adapter suite passes at 190/190.
Its package receipt was 91 files and 45,071,959 unpacked bytes.

The resulting proof passed on frozen tree
`5cff0b0e2fd692d2933e23be8c99fc7ddd46a33b`; its Sol High review found two P1
shell false-certification paths: unequal `20/21 passed` counts were accepted, and
a trailing assertion-level `PASS:` could impersonate a suite receipt after a
`set -e` abort. The exact RED failed at 190/192. Count receipts now require equal
passed/total values, and `PASS:` is restricted to the exact shipped single-line
Node lifecycle runner. The focused adapter suite passes at 192/192; the current
package receipt is 91 files and 45,072,804 unpacked bytes. Freeze, prove, and
review this replacement before committing. The old candidate SHA-256
`fa3c6c20270ad32880347082d4abe242e306e96605c7a94c09798aff7eede4f1` is now
rejected: freeze and prove this correction, review, commit, pass CI, pack one
replacement candidate, then rerun only the Sol High lane against it.
Separately restore npm authentication and run the exact helper dry-run before
requesting explicit publication approval. This state does not authorize npm
publication, tag mutation, or GitHub Release creation.

That replacement proof passed on frozen tree
`bfd228ff28ab360af8b692771fe57f7c28163bf8`; its Sol High review found two P1
raw-response false positives: a proof receipt could be accepted from a proof
command followed by a silent failing shell segment, and a Node TAP footer with
`# cancelled 1` could pass because it also reported `# fail 0`. The exact RED
failed at 192/194. Proof receipts now require a single direct foreground proof
command, and complete TAP footers require zero cancellations. The focused
adapter suite passes at 194/194; the finalized package receipt is 91 files and
45,074,082 unpacked bytes. Freeze, prove, and review this replacement before
committing, then continue the same replacement-candidate and supervised
acceptance sequence above.

Live maintainer feedback after that earlier overlay evidence reported that the
theme colors changed but no Nurse Joy/Blissey character was visible. That
acceptance discrepancy required the replacement exact-artifact iTerm2 journey
to inspect the context character explicitly before issue or milestone closure.

The proof for tree `cf0a823a4a996c5029c1988e50a144580f0684d4` passed, but
its Sol High review found a P1 pytest-cov false positive and a P2 over-broad TAP
cancellation veto. A missed pytest coverage threshold can precede an otherwise
green test-count footer, while earlier captured `# cancelled 1` fixture text
must not override a later complete TAP footer reporting `# cancelled 0`. The
exact RED failed at 194/196. Explicit pytest coverage-gate failures now veto the
pytest summary, and cancellation is scoped to the complete terminal TAP footer;
the focused adapter suite passes at 196/196. The finalized package receipt is 91
files and 45,075,328 unpacked bytes. Freeze, prove, and review this replacement
before committing.

The proof for tree `0d804a4a794781f34528f9642128653fbe527e96` passed, but
its Sol High review found one P1 remaining compound-command path: `npm test &&
false` can leave the successful suite receipt as the last output even though the
overall command fails silently. The exact RED failed at 196/197. Raw test
completion now requires a single foreground shell segment, matching the proof
command authority rule, while structured responses retain their explicit exit
status. The focused adapter suite passes at 197/197. The finalized package
receipt is 91 files and 45,076,124 unpacked bytes. Freeze, prove, and review this
replacement before commit.

The proof for tree `e10590a5f0daf46a77e49109778a2d33f000b720` passed, but
its Sol High review found three remaining raw-output trust defects: package or
shell wrappers could inherit child-runner receipts, failure-qualified shell
summaries could match loose pass grammar, and a finding followed by a separate
review failure could clear review. Four exact assertions formed RED at 197/201.
The first command-aware receipt implementation remained 197/201 because its new
review helper referenced a nonexistent parser; replacing that call with the
existing finding parser improved the second focused attempt to 199/201 but left
two review assertions failing. Per the two-attempt stop rule, do not continue
parser edits or verification until the maintainer authorizes one more corrective
attempt. No commit, push, replacement artifact, npm publication, tag, or GitHub
Release was created from this candidate.

The active-goal continuation authorized one further corrective attempt. The two
remaining failures came from an impossible word boundary after the closing `]`
in the `[P0]`-`[P3]` finding-line filter. Removing that boundary lets failure
words on the finding line remain finding content while a later standalone review
failure still blocks completion. The command-aware wrapper/runner receipts and
failure-qualified shell-summary regressions also remain green. The focused
adapter suite now passes at 201/201. The finalized package receipt is 91 files
and 45,079,082 unpacked bytes. Freeze one replacement proof and one bounded Sol
High review before commit.

Pre-freeze self-review then found two related trust gaps: `All 4 of 5 tests
passed` still matched the generic shell prose receipt, and finding JSON on one
line could hide a later standalone review failure. Their exact RED failed at
201/203. Shell prose success is now restricted to the exact shipped
context-overlay receipt, and structured findings bypass text failure scanning
only when the entire raw response is valid finding JSON. The focused adapter
suite passes at 203/203. The finalized package receipt is 91 files and
45,080,241 unpacked bytes. Freeze one replacement proof and bounded Sol High
review before commit.

The proof for tree `fc92e11d6dd6c141bc4be1a181da8d55945ac96d` passed. Its
Sol High review found one P2 compatibility gap: the existing command classifier
supports `py.test`, but runner-specific receipt dispatch recognized only
`pytest`. The exact alias RED failed at 203/204; mapping `py.test` to the pytest
receipt parser makes the focused adapter suite pass at 204/204. The finalized
package receipt is 91 files and 45,080,611 unpacked bytes. Freeze one replacement
proof and bounded Sol High review before commit.

The proof for tree `7c4179b8ab8d0d6d03dce311f9bf75c67dd318d3` passed. Its
Sol High review found two P1 loose-grammar paths: inconclusive prose containing
`no P0-P3 findings` could match clean-review evidence, and a shell line prefixed
with `command failed;` could still match an equal pass count. Their exact RED
failed at 204/206. Clean-review text now requires an affirmative standalone
result line, and equal-count shell receipts require the exact shipped `===
Results: ... ===` shape. The focused adapter suite passes at 206/206. The
finalized package receipt is 91 files and 45,081,438 unpacked bytes. Freeze one
replacement proof and bounded Sol High review before commit.

The proof for tree `9786f02c7db647672793e368bb229094fded258c` passed. Its
Sol High review found a P1 wrapper-ownership false positive and a P2 structured
review false negative: an arbitrary shell wrapper could inherit a supported
child script's terminal receipt before failing silently, while exact clean
review JSON with `findings: []` could be rejected when its explanation discussed
failure handling. Their exact RED failed three assertions in the 206-test
adapter suite. Raw shell receipts are now limited to the known VisualHUD scripts
and each script's own terminal marker, while an exact structured review document
with any findings array treats its remaining fields as review content. The
focused adapter suite passes at 209/209. The finalized package receipt is 91
files and 45,082,787 unpacked bytes. Freeze one replacement proof and bounded
Sol High review before commit.

The proof for tree `0f45963244773ad91cc65d91b3aa8d962d5116e1` passed. Its
Sol High review found two P1 ownership gaps: a script outside the repository
whose basename was `git-guard.cjs` could impersonate a proof receipt, and the
initial shell ownership allowlist left most documented direct VisualHUD test
commands terminal-unknown. Their exact RED failed at 209/211. Proof completion
now requires the exact repo-relative `.codex/hooks/git-guard.cjs` path, and every
shipped direct shell suite is allowlisted by exact `tests/` path and its own
terminal receipt family. The focused adapter suite passes at 211/211. The
finalized package receipt is 91 files and 45,084,596 unpacked bytes. Freeze one
replacement proof and bounded Sol High review before commit.

The proof for tree `75ab895827f89544759d55af4979a5e375fa28b6` passed. Its
Sol High review found three P1 raw-receipt trust paths: an arbitrary Node wrapper
could inherit TAP or the custom lifecycle marker, a repo-owned proof invocation
without `--reviewed` could advance despite producing an unusable stamp, and
mixed prose containing an empty-findings JSON line could falsely certify a clean
review. Their exact RED failed at 211/214. Node TAP is now bound to `node --test`,
the custom marker to the exact shipped lifecycle script, proof to the exact
reviewed invocation, and empty structured findings to a whole-response JSON
document. The focused adapter suite passes at 214/214. The finalized package
receipt is 91 files and 45,086,572 unpacked bytes. Freeze one replacement proof
and bounded Sol High review before commit.

The proof for tree `76cb1e76a0b5ffc97bda2109b4ca2fac78fb0630` passed. Its
Sol High review found a P1 contradictory structured-review path and a P2
runner-scope regression: empty findings could outrank an explicit incorrect/error
envelope, while captured pytest coverage diagnostics vetoed valid receipts from
other runners. Their exact RED failed at 214/217. Clean structured reviews now
require a whole-response empty findings document with no negative verdict,
failed status, or explicit error, and the coverage-threshold veto applies only
to pytest. The focused adapter suite passes at 217/217. The finalized package
receipt is 91 files and 45,089,461 unpacked bytes. Freeze one replacement proof
and bounded Sol High review before commit.

The proof for tree `c51ddc5c050838a75582710f560032b3b87bae93` passed. Its
Sol High review found a P1 multiline shell-comment bypass plus two P2 gaps:
commands after a comment were hidden from the single-command authority check,
structured findings could outrank an explicit process error, and shell options
before an allowlisted script hid its ownership. Four exact assertions formed RED
at 217/221. Raw completion now rejects non-whitespace commands after a shell
comment, structured process failures block both clean and finding completion,
and ordinary shell options are skipped conservatively before exact script-path
matching. The focused adapter suite passes at 221/221. The finalized package
receipt is 91 files and 45,092,387 unpacked bytes. Freeze one replacement proof
and bounded Sol High review before commit.

Pre-freeze self-review then found one related ownership gap: `bash -s
tests/test-codex-visualhud.sh` reads standard input instead of executing the
named file, so it could impersonate an allowlisted script receipt. Its exact RED
failed at 221/222. Shell standard-input mode is now rejected for raw receipt
ownership while ordinary executable shell options remain supported; the focused
adapter suite passes at 222/222. The finalized managed-file hash is refreshed,
and the package receipt is 91 files and 45,092,775 unpacked bytes.

That final receipt correction is committed and pushed as
`dac5d4a62b8a978d5c3787c032f0aa1b7575d7f4`. Frozen tree
`5361348c07e4ad85bea8c3258bcf4c6384a2a3fd` passed its one guarded proof, its
one bounded Sol High review returned no P0-P3 findings, and
[Ubuntu/Node 24 run 32637312548](https://github.com/BaseInfinity/visualhud/actions/runs/32637312548)
passed in 6m14s.

The one retained replacement candidate is
`/Users/stefanayala/visualhud-release-candidates/v1.2.0/20260823-044944/visualhud-1.2.0.tgz`.
Its SHA-256 is
`319cc1472d8e7bd35d140b8b31038d05460eb8876c7079b5739dd4f4284ea174`;
it is 44,679,940 bytes with 91 entries and 45,092,775 unpacked bytes. Static
inspection, embedded-helper equality, the packed compatibility report, a
disposable install, and packaged doctor all passed.

The exact tarball then completed the bounded Sol High journey in disposable
iTerm2 session `82B1157B-A11E-4AF8-B029-D379249122F2`, distinct from maintainer
session `137009C7-6396-4672-83AA-CCBEA585AF8D`. Forward progress, expected RED,
rollback, authoritative full-suite advancement, the single review, guarded
proof, HITL preservation, and stable `12/12 DONE` all rendered coherently. Two
consecutive critical-context samples agreed on `Nurse Joy CTX 85%` and the same
live iTerm2 background target. The exact generated Mew-plus-Blissey composite
was visually inspected and preserved with SHA-256
`e72f565423a40cc5d35393ebaac0886cf04a363237400079c837456278bcb26d`.
De-escalation removed the overlay and restored packaged `mew.png`; the disposable
window was closed and the maintainer session was reprobed successfully. Issue
#16 is complete. No npm package, tag, or GitHub Release was published.

A subsequent asset-provenance completion audit rejected that retained artifact
as a distribution input. It contains 55 packaged branded PNGs: specifically,
53 theme sprites plus two contact sheets. All 18 packaged Pokemon sprites
byte-for-byte match PokeAPI HOME files at their corresponding 512x512 numbered
sources.
PokeAPI invites application use and labels the repository CC0, but its license
also states that the image contents are copyrighted by The Pokémon Company,
limits its waiver to rights held by the affirmer, and disclaims third-party
clearance. The TMNT manifest proves crop provenance and one source is labeled
CC-BY-SA, while most entries still lack asset-specific license and notice
fields. Exact provenance is therefore stronger than the first audit recorded,
but the historical package still lacks a complete distribution/notice ledger.
Candidate SHA-256
`319cc1472d8e7bd35d140b8b31038d05460eb8876c7079b5739dd4f4284ea174` is
therefore QUARANTINED and must not be published. Its successful canary remains
valid historical evidence about VisualHUD behavior, not publication authority.

Preserve all current assets while completing exact source/hash and notice
verification. Add a package-visible Pokemon manifest, audit each TMNT source at
asset level, satisfy applicable attribution or share-alike conditions, and
exclude or replace only files that remain unsupported. Branded subject matter
alone is not a removal criterion, while public availability or open-source
hosting alone is not a public-domain receipt. The replacement candidate is
required because the historical tarball does not contain the finalized
manifests and notices.

The local release helper and manual GitHub publish workflow now reject that
quarantined SHA, along with the three earlier rejected candidates, before npm
access or artifact download. The publication prohibition is therefore an
executable gate rather than prose alone.

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

The supervised canary is complete. One open release slice remains:

1. [#17 - Publish and verify VisualHUD v1.2.0](https://github.com/BaseInfinity/visualhud/issues/17)

Issue #17 now begins with an evidence-preserving asset audit: bind every
packaged PNG to its exact hash, source, license or permission record, and
required notice; retain files whose conditions can be satisfied; and exclude
or replace only files that remain unsupported. Then build a new candidate with
the finalized manifests/notices and repeat exact-artifact proof.
No published Git history rewrite is inferred; that would be a separate
destructive decision requiring explicit authorization. The immediate gate is
not registry access: npm authentication is secondary. It becomes actionable
only after a distributable replacement candidate exists. Publication, tag
work, and GitHub Release
creation remain behind explicit maintainer approval because those distribution
actions are immutable. Rejected candidate SHA-256 values
`01b039ca675e9d1cf58135d70ced18a853eafda521b9c3cbb230779a6043fb5f`,
`691dab58a180b0e52b96566b3f1463f7d7678a92340b99e71e14ce8bed95ad18`, and
`fa3c6c20270ad32880347082d4abe242e306e96605c7a94c09798aff7eede4f1`, plus
quarantined SHA-256
`319cc1472d8e7bd35d140b8b31038d05460eb8876c7079b5739dd4f4284ea174`,
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
