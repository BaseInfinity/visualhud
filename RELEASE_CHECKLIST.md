# Release Documentation Gate

Run this gate for every release candidate after implementation is complete and
before supervised acceptance, tagging, or publication. Theme demo production is
separate work tracked in GitHub issue #13; this gate verifies any media that is
already present without requiring new demos.

## Standing Checklist

### Automated

- [ ] `bash tests/test-theme-system.sh` passes against the candidate checkout.
- [ ] `bash tests/test-npm-package.sh` passes against the candidate checkout.
- [ ] The README names the candidate package version and current install/update commands.
- [ ] Host and renderer tiers, restart behavior, themes, and journey profiles are documented.
- [ ] README media has descriptive alt text and every local media target exists.
- [ ] Canonical npm, GitHub release, issue, and limitation references are present.
- [ ] The README has no obsolete embedded roadmap or deprecated Codex command.
- [ ] `npm pack --dry-run --json --ignore-scripts` contains no raw source or video assets.
- [ ] `npm test` passes, which includes the documentation audit.
- [ ] Retain the one accepted `visualhud-<version>.tgz` outside the worktree and record its absolute path, SHA-256, byte size, entry count, unpacked size, and source commit.
- [ ] Run `scripts/release-npm.sh --dry-run --candidate <absolute-tarball> --sha256 <accepted-sha256>` against that exact retained file.

### Maintainer Review

- [ ] Compare documented behavior with the candidate implementation and compatibility matrix.
- [ ] Open each external package, release, issue, and limitation link.
- [ ] Inspect screenshots or demos for stale UI and meaningful alternative text.
- [ ] Document unresolved redistribution or attribution limitations and the issue that owns publication clearance.
- [ ] Record exceptions, deferred demo work, package size, and the exact implementation commit.
- [ ] Complete the supervised canary before publication when the release milestone requires it.
- [ ] Confirm a tag push cannot publish; treat the manual `Publish` workflow dispatch (tag plus accepted SHA-256) as an explicit immutable-publication action.
- [ ] Confirm exact-tarball dry-run and publication use `--ignore-scripts`, so `prepublishOnly` cannot rerun or mutate the frozen candidate.

## Release Record

Create one file under `docs/release-audits/` named `v<version>-rc.md`. Record the
candidate status, implementation commit, automated proof, manual review, package inspection,
deferred work, and remaining supervised gates. A documentation PASS does not
mean the release has been published.

Record the exact audited implementation commit before publication. When the
record is part of that implementation commit, use one evidence-only follow-up
commit to replace `Candidate commit: PENDING`; do not mix product changes into
that follow-up.
