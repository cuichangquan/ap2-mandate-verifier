# Root disclosure check: bounded DC04 profile

`verify_root_disclosures(presentation:, trusted_issuer_public_key_pem:)` checks
the original signed Root and disclosure closure only. A valid result is
`unverified / root_disclosures_verified_only`, always success? false/evidence nil.
It does not return resolved claims or authenticate AP2 authority/Host ALLOW.

This is the exact-three-array-commitments profile from existing DC04/E06-I
research, informed by AP2 v0.2.0 commit
`b4587ac1d055888a73b4b21750973cffba961793` and its sdjwt/common.py. It supports
only an ES256 `example+sd-jwt` Root, independently selected P-256 public PEM,
root keys delegate_payload plus optional string _sd_alg=sha-256, exactly one
delegate_payload entry and two-element array disclosures [salt, object].
Missing _sd_alg defaults to SHA256; explicit null/other algorithms are rejected.
Salts are 8–128 UTF-8 bytes; object-property disclosures are unsupported.

Exactly these three array commitment positions must be encountered:

- delegate_payload[0]
- its disclosed constraints[0].items[0].acceptable_items[0]
- its disclosed constraints[1].allowed[0]

Every original Root field and disclosed subtree is traversed. Unknown marker
positions, object _sd, misplaced .../_sd_alg, malformed or repeated commitments,
duplicate disclosure segments, missing and unused disclosures fail closed.
Visible nested fields are traversed for hidden commitments but their AP2
semantics/unknown constraints are deliberately left to later stages.
No traversal or disclosure decode occurs before original Root signature passes.

Limits: presentation131072 bytes, Root32768, disclosures1–16, each encoded
disclosure8192, expanded containers depth24, nodes2048, Hash32/Array16 entries.
Existing strict UTF-8/JSON/decoded-duplicate rejection is reused. Keys are never
selected from token claims or URLs. No network, database or nonce side effects.

Local validation uses existing Ruby4.0.1/JSON2.18.0/jwt3.3.0/task-local gems.
With GEM_HOME/GEM_PATH pointing to the existing .local-deps/gems plus the
Cellar Ruby gem directory, run the following from the project root:

```sh
ulimit -t 10
bundle exec ruby -e 'ARGV.each { |path| load path }' test/input_boundary_test.rb test/root_signature_test.rb test/root_disclosures_test.rb
```

The latest local run passed input79 + signature74 + disclosure64 =217 cases,
plus syntax10 files. Synthetic six-class cases have separate manual OpenSSL
signature verification and an iterative original-wire graph oracle, with
original presentation SHA256 logged. FULL is complete/unverified; HIDDEN and
DECOY are missing; UNKNOWN is cryptographically complete but unsupported
profile; DUPLICATE reaches repeated-commitment guard; EXTRA is unused input.
Missing disclosure and true Issuer decoy are indistinguishable to this strict
profile and both reject. Test private keys exist in memory only.

This shares Ruby/JSON/OpenSSL with production and is NOT independent Python
O1–O5/official-SDK interoperability or six-case end-to-end AP2 evidence.
No Agent/Merchant/Terminal sd_hash, official Schema, trust enrollment, constraint,
Host, durable original-wire replay or OS-isolation proof is supplied. Historical
DC04 FULL refusal and DC06 early-cardinality rejection remain historical limited
observations; these tests do not relabel their Gate states. Stages5–9 and full
Evidence remain unimplemented; Actions and Gem distribution are not exercised.
