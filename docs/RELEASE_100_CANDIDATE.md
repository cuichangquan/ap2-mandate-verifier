> Historical preparation snapshot. 1.0.0 was subsequently published on
> 2026-11-01 08:13:29.733 UTC; the 102,912-byte official distribution matches
> the retained candidate and all 33 payloads match the release source.
> See [publication](POST_RELEASE_100.md) and [current release/upgrade](RELEASE_100.md).
> Unpublished and pending statements below describe the preparation checkpoint.

# 1.0.0 candidate — historical preparation

**Unpublished candidate. The currently published release is 0.8.0.**
The candidate Gem has version `1.0.0`; that metadata is not a publication record.
The [preparation evidence](evidence/1.0.0_preparation.json) identifies the actual
source, archive, observed checks and remaining gates. A later publication must
identify the exact approved bytes separately.

## Purpose and supported scope

1.0.0 establishes the [public Ruby API](PUBLIC_API.md) and
[1.x compatibility and maintenance policy](POST_RELEASE_MAINTENANCE.md).
It keeps the 0.8.0 runtime implementation and supported Checkout profiles.

| Workflow | Included in the public contract |
| --- | --- |
| Merchant Checkout | Sign and verify the supported original Checkout JWT. |
| Direct human-approved order | Issue, present and verify the Provider-signed exact order. |
| Conditional purchase | Issue Open conditions; generate/present Agent-signed Closed; verify the complete chain with independent current trust, order, challenge and time inputs. |
| Checkout Receipt | Reference the exact final Closed SD-JWT; sign and verify authentic Success/Error outcomes. |

All workflows are plain Ruby. Rails is an integration example. A 1.0.0 SDK
version does not assert coverage of every AP2 feature, certification, application
authorization or payment execution. The adopted official AP2 source stays at
`b4587ac1d055888a73b4b21750973cffba961793`.

## Changes from 0.8.0

- Explicit public API, return/exception, profile/default and persistence contracts.
- Current SDK metadata, security reporting, maintenance and product guidance.
- Aligned 1.0.0 package checks and development lockfile; newly packaged public API,
  input preparation, security and maintenance documentation.
- Independent Python-generated conditional inputs exercised through the public
  complete verifier and Receipt APIs, including installed-Gem mode and signed
  negative controls. Existing internal-boundary comparisons remain separate.

There are no runtime `lib/` changes, profile/default changes, new runtime
dependencies or renamed APIs. Existing `verify_research`, research-named results,
syntax-only `verify`, saved preparation format `"1"` and Evidence v2 remain.
MRI 3.4.12 and 4.0.9 remain the formally supported versions. Installation metadata
`>= 3.4.12, < 4.1` does not certify every version in that range. Runtime pins remain
JSON 2.19.9, JWT 3.3.0, base64 0.3.0, OpenSSL gem 4.0.2 and Digest 3.2.1.

## Migration and candidate inspection

Applications using documented 0.8.0 APIs need no source migration for this
candidate. A dependency such as `~> 0.8.0` does not select 1.0.0. After publication,
use an explicit compatible constraint (for example `~> 1.0`) and update this Gem
in the application's lockfile. Do not treat a successful verification, an
authentic Receipt or successful installation as application purchase permission.

To inspect a prepared local candidate, install its exact file in an isolated
Gem environment whose fixed dependencies are already installed:

```sh
gem install --local --no-document /absolute/path/ap2_mandate_verifier-1.0.0.gem
ruby -rap2_mandate_verifier -e 'puts Gem.loaded_specs.fetch("ap2_mandate_verifier").version'
ruby -e 'spec = Gem::Specification.find_by_name("ap2_mandate_verifier", "= 1.0.0"); load File.join(spec.full_gem_path, "examples/conditional_checkout.rb")'
```

The standalone synthetic example covers Open → Agent Closed → complete
verification → Success/Error Receipt. The application's identity, consent,
key custody, revocation, persistent replay protection and payment integration
remain its responsibility. Unknown execution outcomes remain pending until the
application reconciles them.

## Required release evidence

| Check | Required evidence |
| --- | --- |
| Scope and compatibility | Diff against the 0.8.0 baseline; unchanged runtime code, profile definitions/defaults and five dependency pins; public API/source review. |
| Source regression | Existing 17 suite entry points on both supported MRI versions, preserving individual results without double-counting transitive suites. |
| Exact package | One final archive built after packaged content is fixed; SHA256/size and all payloads matched against source and ordinary installation on both Rubies. |
| Installed behavior | Original saved-input/oracle checks, diagnostics, signing/Direct/multi-item/conditional examples and conditional tests loaded from the installed Gem. |
| Interoperability | Pinned official Python source and recorded dependencies; external signatures, original-wire hashes, supported Schema and complete public verification; signed causal negatives and authentic Success/Error Receipts. |
| Review and repository gates | Independent review of the actual final source, no unresolved substantive P1/P2, applicable branch protection and bounded CI recorded separately from local tests. |
| Publication | Owner approval for the exact source/archive, followed by RubyGems distribution comparison and exact-source public tag/Release. Preparation does not perform these actions. |

The existing Debian-container source/package procedure is
`scripts/check_ruby_compatibility.sh` followed by
`scripts/check_candidate_package.sh OUTPUT_DIR ABSOLUTE_GEM_PATH`.
Pass the **same archive** to each supported Ruby; separately built CI candidates
do not establish byte identity across runtimes.

The conditional interoperability command, from this source checkout, is:

```sh
AP2_INSTALLED=1 AP2_GEM_VERSION=1.0.0 \
AP2_OFFICIAL_ROOT=/absolute/path/to/pinned-ap2 \
PYTHONPATH=/absolute/path/to/pinned-ap2/code/sdk/python \
python test/conditional_interop.py
```

`PATH` must select the supported Ruby, and `GEM_HOME`/`GEM_PATH` must select the
normally installed candidate and fixed dependencies. No product source directory
may be added to Ruby's load path in installed mode. The Python check asserts
official source/Schema location consistency and must be run with the recorded
fixed source and dependency identities. Its supported inline Closed subset does
not include the official helper's selectively disclosed terminal representation.

## Preparation boundary

This work follows the Owner's request to prepare 1.0.0, from main
`7facf5e21699c754eb3e046ee2c653c6ce2c16cf`. Review covers the public contract,
metadata/package checks and the additional independent test; the application's
trust registry and current business state remain independent test inputs.
Existing Issue #101 process and separate legacy research gates are retained.
Unexpected source/dependency drift, secret exposure, unplanned external cost,
inconclusive checks or substantive review findings block release readiness.

Current public distribution remains 0.8.0 until its successor is actually
published and verified. A local pass, review result, PR or candidate artifact is
not a release, real-Issuer attestation or production authorization.
