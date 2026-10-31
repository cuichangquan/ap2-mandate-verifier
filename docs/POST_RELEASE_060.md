# 0.6.0 publication and post-release verification

Owner approved publication and ran RubyGems push in their own Terminal.
Registry publication time: **2026-10-31 11:50:18.664 UTC**.
Official metadata/archive verification: **2026-10-31 11:51:54 UTC**, PASS.
The [publication receipt](evidence/0.6.0_publication.json) records exact archive,
candidate and all 22 payload/source matches, name/version and fixed dependencies.
The agent did not push, rebuild or modify the published Gem.

- Published source: `baee59a603d08123adc0af50e57c8710ea62f4f9`.
- Gem size: **56,832 bytes**.
- SHA256: `ff669a62717f91b2295b3cea1b68c6c4143c490d98df071fd322ad4b0007195d`.
- [RubyGems](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.6.0).
- [Release text](RELEASE_060.md); tag `v0.6.0` is to identify the published source,
  independently of later documentation/demo commits.

## Fresh post-release measurements

After Owner's separate post-release maintenance approval, the published-guides
Dockerfile was changed to acquire the **official 0.6.0 archive**, verify its
size/SHA256 and install it normally with the same five fixed dependencies.
No local Gem build or source-library overlay is used by this check.

Existing official Ruby bookworm bases, Linux arm64:

| MRI | New image | Offline installed-Gem result |
| --- | --- | --- |
| 3.4.12 | `8a81c00efb5f70249f9c7b1424ae975cfbe95138cc459c26b0e30367faa0d211` | PASS |
| 4.0.9 | `c53618f29aedc343b571a4c240f3d769f405fea301a72c82184896b558ae893c` | PASS |

Both runs newly executed English/Japanese README Quick Starts, the complete
merchant-signing example, the complete multi-item lifecycle, and the exact
short Ruby snippet in the Release text. They checked signed Checkout structure,
full verification/Evidence and authentic Success/Error outcome predicates.
[Logs](evidence/published060-guides/) contain the measured outputs. Earlier
candidate measurements remain historical evidence and are not counted as these
new published-Gem observations.

Commands, from the repository root, for each formal MRI:

```sh
docker build --build-arg RUBY_VERSION=3.4.12 -t ap2-published060-guides:3.4.12 \
  -f .github/published-guides.Dockerfile .github
docker run --rm --network=none --cpus=2 --memory=768m --pids-limit=128 \
  -v "$PWD:/src:ro" -w /src ap2-published060-guides:3.4.12 \
  timeout 120 ruby scripts/check_published_guides.rb
```

Repeat with `4.0.9`. The applicable PR CI uses this same published-Gem path for
documentation-only changes. Final PR/review/CI/tree identities and the separate
official-Gem demo fresh build/browser results are recorded in the completion
report and PR comments rather than inventing a source self-reference here.

Product `lib`, gemspec, runtime dependency pins and old profile are unchanged.
There is no claim of general AP2 conformance: the supported profile's
[SDK differences](MULTI_ITEM_INTEROP.md) remain explicit. Real Issuer enrollment,
production trust/revocation, Host atomic nonce/order operations, payments,
production GO, public Web deployment and worst-case/concurrent performance
remain NOT_RUN/out of scope. No new Mac installation or shared cache cleanup.
