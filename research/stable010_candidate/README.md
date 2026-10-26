# Retained 0.1.0 candidate — source and evidence integration

**Candidate validation completed; RubyGems/Release publication and specific Host production GO remain HOLD.**
This record supplements packaging-time snapshots; it does not rebuild the archive.

## Exact identities

- Candidate: `ap2_mandate_verifier-0.1.0.gem`, **43,008 bytes**, SHA256 `0553645fa6c067dd8d7a7a1a7cdf13799370393e76dc3bc4ba161ab2ca5981b0`.
- Product/source baseline: `a6a303f7fe7bf4ef6b4e24744b0fa23d9580fb61`. Ten product files unchanged; no API or verifier behavior change.
- [Source manifest](SOURCE_MANIFEST.json): original SHA256 `041265abe1dcf486b64147aeed15d6f4955657b1ca01e3f18ab53f7758189eba`.
- Six candidate-source changes are README, SUPPORT_CONTRACT, gemspec, Gemfile.lock, and two package-version assertions. Gemfile and product source are unchanged. Those six files are preserved byte-for-byte from the tested source.
- [Provenance](PROVENANCE.json) distinguishes original and public-copy hashes. The archive itself and workflow input are not committed here.

## Completed observations

| Environment | Observation | Exact evidence / limits |
| --- | --- | --- |
| MBA MRI4.0.9 / arm64-darwin25 | One Gem build; one fresh offline install; 13 payload / 10 loaded / 52 installed checks PASS. Check execution 0.841s, total preparation/execution 348.222s. No download/native build. Temporary install/extraction removed after evidence readback. | [REPORT public copy](results/MBA_R1/REPORT.public.json), [FINAL public copy](results/MBA_R1/FINAL.public.json). Original REPORT SHA256 `36125626d8251895975be043bbac13170c428b0df45750f1e4db5ae5a6ba4742`. Personal task paths replaced, original retained locally. |
| Ubuntu24.04 / x86_64 / MRI4.0.9 | Same archive, fresh offline install, 13 / 10 / 52 PASS. One dispatch / attempt1; JSON native build once, no candidate rebuild. Job19s; candidate audit step2s. | [run40274002891](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/40274002891), [REPORT](results/UBUNTU_R1/REPORT.json), [FINAL](results/UBUNTU_R1/FINAL.json). REPORT SHA256 `fc7a5dcf456739066e775de79679500361650923fe871dc6f8082af2710db064`. 92 emitted files recovered with size/SHA/host-readback agreement. Five run-owned temporary roots removed. |

The MBA REPORT/FINAL and embedded candidate SUPPORT_CONTRACT say Ubuntu NOT_RUN at their creation/packaging time. **That statement is historical, not the current validation status.** The later Ubuntu row above supplies the missing observation without altering tested payload bytes. The same applies to old diagnostic “next step” blockers, which were subsequently addressed by separately approved stages.

The 52 checks replay 42 saved MBA expectations plus seven legacy APIs, two input rejections and one constructor rejection. They are not 52 independent oracles. Historical 885 regressions (including trust/profile147) were reused through source/dependency identity; not rerun. Independent comparisons at Ruby4.0.1 remain historical, not independent Ruby4.0.9/Linux regeneration. Counts are not added together.

## Provider evidence and preserved stops

[DIAGNOSTICS.public.json](DIAGNOSTICS.public.json) preserves D1/D2 failures, D3 limited success, selected component/symbol observations and hashes of original records/source.

- Earlier R1 preflight stopped without specific values; no Gem build/checks/Actions occurred.
- D1: process-wide libcrypto count2 versus expected1; OS dyld images could not be read as ordinary files. This was not proof of a dangerous dedicated provider.
- D2: nine predicates passed; interval also included lazy SHA256-helper loading, so image-change predicate failed. It remains STOP.
- D3: load/hash helper before measurement and bracket exact OpenSSL-handle acquisition; ten identity predicates passed. Four sampled symbol sources matched the dedicated provider. OS dyld hashes and all symbol bindings remain unverified.
- Ubuntu: official Ruby archive hash matched; actual openssl.so path/SHA and libssl/libcrypto mappings were recorded. `libssl3t64:amd64 3.0.13-0ubuntu3.16` ownership/full version, dpkg verification and library checksum agreement passed under the trusted-runner/dpkg boundary; see [USN-8847-1](https://ubuntu.com/security/notices/USN-8847-1).
- JSON2.19.9 official IO-buffer fix/tag/source identity was adopted as static evidence. GHSA-x2f5-4prf-w687 metadata still conflicts; do not relabel it consistent or infer global S3 PASS. Actual JSON native paths/hashes are in the environment records.

## Supply accounting and release boundary

Ubuntu downloaded archive bodies49,276,761B; measured HTTP bodies plus request/response headers49,287,628B. Setup/checkout/input/DNS/TLS and all-wire totals are **not measured**. Disk sample149,720KiB is not physical/all-period peak enforcement. Standard public Ubuntu runner/no artifact or cache upload was checked for incremental cost0; no general billing or resource guarantee follows.

CLI first rejected boolean JSON values locally, before dispatch; run list remained empty. Inputs were encoded as CLI strings, then exactly one dispatch succeeded. No workflow rerun occurred. GitHub input/history privacy or deletion is not promised. Original logs, candidate, source and failure evidence remain locally retained.

S1/S2/S4 concrete conditions and bounded historical evidence were adopted by Owner. S5 package observations are complete for this archive. S6 still requires review of the integrated candidate source's latest HEAD; PR197 reviewed the validation infrastructure only. S7 must separately name artifact/destination/claims/residuals and authorize publication. General AP2/full Schema, real Issuer compatibility, live Host/clock/revocation/payment operation, worst CPU/RSS/concurrency and full Phase2A/Phase2B GO remain outside this evidence.

