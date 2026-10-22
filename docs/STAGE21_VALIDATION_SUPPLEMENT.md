# Fixed-profile candidate: validation and usage supplement

Status: unpublished0.1.0.pre.2; no release, production, Phase2B or E10 GO.
Baseline main `2c07a83e76c8003d5f7b5ac09a84065f9b3fde3f`.
This repository-only supplement is outside the Gem whitelist. It changes no
library, gemspec, README, LICENSE, SUPPORT_CONTRACT or other package payload.
Validated package SHA256 remains `db0c16c53c63b16468313e25665fe36fecc4978fab050729b4667e6ef384407b`,29696B,13payload files.

## Scope and how to use the result

Read [packaged support contract](SUPPORT_CONTRACT.md) for exact API/input shapes,
fixed limits and dependencies. Its paragraph saying the candidate had not received
a new Linux packaged-Gem run describes its original packaging date. The Stage18
result below supplements that historical statement; it does not rewrite the
packaged bytes or old evidence.

The sole profile is `ap2.checkout.single_merchant_sku` v1, official AP2 commit
`b4587ac1d055888a73b4b21750973cffba961793`, ES256/P256,2hop,3supported
array-disclosure positions, one Merchant/SKU/cart line, USD/EUR/JPY, empty links.
No generic AP2/SD-JWT/Schema fallback, issuance/presentation SDK, Rails integration,
Host payment, nonce consumption, DB/CAS or Receipt implementation is supplied.
MRI4.0.1 with JSON2.19.9,JWT3.3.0,base640.3.0,OpenSSL gem4.0.0,Digest3.2.1 is
fixed. Windows/Intel Mac/other Rubies or engines remain unverified. Actual native
provider/libcrypto observations are not security/backport attestations.

Use `AP2MandateVerifier.verify_research` with exact original Strings and externally
fixed integer verified_at. Trust/selection/Host JSON must be authenticated current
Host inputs independent of the token. Strict byte/depth/shape/duplicate/JOSE checks,
all required signatures/disclosure closure/binding/fixed constraints/time intersection
must succeed before research Evidence v2 exists. Legacy entrypoints remain non-success.
Rejected/unavailable/no result must never authorize anything. Missing dependencies
may prevent require; process failures and caller keyword misuse may raise. Fail closed
means no Evidence/permission is inferred from such failures.

Evidence is deeply immutable in-process output, raw nonce excluded in favor of
verified_nonce_sha256; it is not Host ALLOW or portable JSON authenticity. The
Host must recheck current trust/profile/keys, order/Buyer/Agent/challenge/time and
atomically consume nonce with order CAS before its own authorized action. Genuine
Issuer enrollment, latest-state supply, clocks/live revocation/rollback and payment
permissions are not proved here. Malicious same-process Ruby and substituted trusted
harness/interpreter are outside this threat model.

## Evidence and observed limits

[Machine-readable index](STAGE21_EVIDENCE_INDEX.json) records exact package/file,
input/expected/report hashes, provenance and per-case min/median/max. Hashes of
retained local reports are identifiers, not public download links or attestation.

- [Stage18 Linux run39869876461](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/39869876461),attempt1,main baseline above: success26s/job21s. Actual Gem build/install and ordinary require outside checkout;13payload source/archive/install identities and10loaded libraries match. Source885 regressions are separate from installed52 checks (42fixed comparisons+7legacy+2JSON+1constructor). No artifact upload/rerun.
- The42 comparisons replay existing MBA independently computed30contract+12boundary expectations. Linux did not rerun Python/Schema Oracle. MBA8Schema judgments and historical13cases64judgments remain distinct evidence, not added to885/52.
- Stage19 R1: first FULL verifier call matched but macOS time's sysctl kern.clockrate was denied; RSS absent, stopped without remaining20 calls. Which OS/sandbox rule rejected it is unproved. Old failure is retained.
- Stage19 R2: Owner ran the same time method in ordinary Terminal;7saved inputs×3 serial fresh processes,21matches,3.019693s total, observed child maximum0.242830s. FULL APIwall min/median/max4.575/4.604/5.964ms,CPU4.578/4.609/4.895ms; whole-process peakRSS27.359/27.594/27.766MiB. API interval excludes require/input preparation; peakRSS includes startup/require/helper/input/result work. Darwin RSS bytes convert by1048576. No worst-case, steady-state, concurrency, Linuxresource or production performance guarantee follows.
- Stage20 static audit reconciled current main13payload+gemspec with installed bytes and reviewed evidence. No new concrete defect/hash mismatch identified, not a formal or exhaustive safety proof.

## Gate status and remaining decisions

E00 fixed scope, E02 signatures, E03 supported graph, E06 subset Schema and E08
research Evidence are supported only within the recorded conditions. E01 genuine
trust, E05 operational rotation/rollback, E07 enforced execution/RSS/concurrency
limits, E09 fully independent runtime/environment attestation remain conditional
or unproved. Finite input caps and10s/300s harness limits are not library quotas.
No internal CPU/RSS deadline or parallel limiter exists; Host controls execution.
The old [E00–E10 checklist](PHASE2A_EXIT_GATE_DECISION_CHECKLIST.md) and
[Issue47](https://github.com/cuichangquan/ap2-mandate-verifier/issues/47) are not
automatically PASS/closed by these observations. E10 is Owner-only.

Historical acquisition gaps remain: O1/O3wheel4408169B does not establish metadata-
inclusive10MB; O4received596565B does not establish sent-header-inclusive1MiB.
Stage18 measured3archive bodies176640B and HTTP sent+received179976B, not all
runner/setup/management traffic.128MiB was planning, not measured guarantee.
Logic agreement does not repair accounting gaps. No re-acquisition is proposed.

Next is Owner review of limited prerelease claims and publication scope. This PR
publishes documentation/aggregate synthetic results only, no Gem binary, tag,
Release or RubyGems upload. The retained candidate is not a completed full AP2 SDK.
