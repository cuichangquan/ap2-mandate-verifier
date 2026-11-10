# 1.6.1 patch release preparation

## Scope and status

This record prepares the patch following [PR #256](https://github.com/cuichangquan/ap2-mandate-verifier/pull/256).
The Owner requested distribution of the newly bundled Ruby integration and crash-recovery example.
The Owner will execute the final RubyGems push and complete MFA; the agent prepares and verifies the archive and commands only.
The SDK `lib/` implementation, public APIs, runtime dependency pins and Ruby requirements are unchanged.
The package includes the CLI, two helpers and English/Japanese guides already reviewed in #256.
The sample remains synthetic and Linux/Docker-validated; it grants no production or real-payment authority.
The legacy published examples and the public **1.6.0** archive audits remain unchanged.

**Candidate, not published:** registry publication, tag and GitHub Release are pending.
Do not infer publication from this document, a green CI run, version metadata, or a merge.
The current public baseline remains [1.6.0](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/POST_RELEASE_160.md).

## Required evidence and gates

- Build one exact 1.6.1 archive in the fixed MRI 4.0.9 Docker builder with `SOURCE_DATE_EPOCH=1794319977`, repeat the build byte-for-byte, and record SHA256/size.
- Run source and ordinary installed-package regressions on MRI 3.4.12 and 4.0.9 using that **same archive**, including the separate-process integration/recovery suite.
- Compare every payload file among source, extracted archive and actual installed files; verify metadata, dependency pins and no native extension or secret fixture.
- Keep public-1.6.0 tests pinned to 1.6.0. Candidate tests explicitly pass `AP2_GEM_VERSION=1.6.1`; do not weaken version identity checks to a range.
- Obtain independent Codex review on the latest PR HEAD, resolve substantive findings, and pass the required CI and repository merge conditions. No auto-merge; at most three workflow runs, attempt 1, for this PR.
- After merge, verify the reviewed and merged trees match and the fixed-builder merged-source archive is byte-identical.
- Present the final archive identity and verification to the Owner. Only explicit OwnerGO for those final bytes permits **one** publication attempt.
- Inspect the registry before publishing and after any uncertain outcome. Never blindly retry a push, overwrite a version, or create a replacement artifact under the same approval.
- Verify actual registry bytes/metadata and ordinary installation before creating the annotated tag and non-prerelease GitHub Release at the released source commit. Preserve the archive and public evidence.

No merge/push workflow publishes or deploys. No direct Mac installation, credentials disclosure,
new persistent access, real payment, production database or demo deployment is included.
