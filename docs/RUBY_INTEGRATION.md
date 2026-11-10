# Ruby application integration and restart recovery

[日本語](RUBY_INTEGRATION.ja.md) · [Quick Start](QUICK_START.md) · [Acceptance contract](PAYMENT_ACCEPTANCE.md)

Start here to connect application records, conditional Checkout, Payment, durable
acceptance and an original-bound Receipt. The runnable entry is
[`examples/ruby_integration.rb`](../examples/ruby_integration.rb), with application
input preparation in [`integration/inputs.rb`](../examples/integration/inputs.rb).
It uses synthetic actors and a SQLite mock processor, without Rails, A2A, external
accounts or real payments. It is an integration demonstrator, **not a production
authorization backend**.

## 1. Run with Docker and the published Gem

Prerequisite: an existing Docker installation. No Ruby or SQLite installation on
the host is needed. From a fresh repository checkout:

```sh
git clone https://github.com/cuichangquan/ap2-mandate-verifier.git
cd ap2-mandate-verifier
docker build -f examples/integration/Dockerfile -t ap2-ruby-integration .
docker volume create ap2-ruby-integration-state
docker run --rm --network none -v ap2-ruby-integration-state:/state ap2-ruby-integration init /state/happy
docker run --rm --network none -v ap2-ruby-integration-state:/state ap2-ruby-integration run /state/happy success
docker run --rm --network none -v ap2-ruby-integration-state:/state ap2-ruby-integration inspect /state/happy
```

Build downloads Ruby/dependencies; the sample runs without networking. The image
uses Ruby 4.0.9, published `ap2_mandate_verifier = 1.6.0` and optional
`sqlite3 = 2.10.2`. The new example source comes from this checkout, **not from the
published 1.6.0 Gem archive**. Verify the installed SDK path/version independently:

```sh
docker run --rm --network none --entrypoint ruby ap2-ruby-integration -rap2_mandate_verifier -e 's = Gem.loaded_specs.fetch("ap2_mandate_verifier"); puts "gem=#{s.version}; path=#{s.full_gem_path}"'
```

The SDK path must be the installed Gem directory, not this repository's `lib`.
Do not add `-Ilib` or set `RUBYLIB` when claiming a published-Gem run. Existing
`conditional_checkout.rb`, `payment.rb` and `payment_acceptance.rb` are already
Gem-only examples. Follow the [Quick Start](QUICK_START.md) to locate them.
This new CLI and its helper files are included in the next source-built Gem
candidate. A candidate may still report `1.6.0` before a release decision; its
artifact/source provenance is different from the published archive. Do not claim
that installing public 1.6.0 alone supplies this CLI.

Once that candidate has been installed in an isolated Ruby environment with the
optional SQLite driver, no repository is needed to run its packaged CLI:

```sh
AP2_GEM_DIR="$(ruby -e 'puts Gem::Specification.find_by_name("ap2_mandate_verifier").full_gem_path')"
test -f "$AP2_GEM_DIR/examples/ruby_integration.rb"
ruby "$AP2_GEM_DIR/examples/ruby_integration.rb" init /tmp/ap2-integration-new
ruby "$AP2_GEM_DIR/examples/ruby_integration.rb" run /tmp/ap2-integration-new success
```

The `test` is a packaging check, not a fallback to another source. Use a new
destination; do not remove an old state directory to make `init` succeed.
Until a new version is published, the Docker/repository route above is the
reproducible public route. Publication and the next version are separate decisions.

All example time is virtual: the initial epoch is **1,800,000,000**, never the
wall clock. Mandate/challenge expiry is +60 seconds; the delayed Receipt uses
+120 seconds within a separately pinned Receipt window. Re-running in a later
calendar year does not unexpectedly expire the happy path. Production must use
an independent current trusted clock.

Expected happy-path meaning: acceptance produces the first Ticket; fresh `start`
allows one mock dispatch; the authenticated Success Receipt finalizes
`receipt_success`. The persisted mock execution count is **1**. This is not proof
of real settlement. `inspect` exposes a safe summary, not raw signing material.

## 2. Actually terminate, then recover in another process

Use a different directory for each independent synthetic scenario. `init` refuses
an existing directory. All other commands require the existing `app.json`,
`acceptance.sqlite3` and `processor.sqlite3`; they never repair loss by bootstrap.

```sh
docker run --rm --network none -v ap2-ruby-integration-state:/state ap2-ruby-integration init /state/crash
docker run --rm --network none -v ap2-ruby-integration-state:/state ap2-ruby-integration run /state/crash crash-after-charge
# Expected exit status: 75. The original Ruby process has ended.
docker run --rm --network none -v ap2-ruby-integration-state:/state ap2-ruby-integration recover /state/crash
docker run --rm --network none -v ap2-ruby-integration-state:/state ap2-ruby-integration inspect /state/crash
docker run --rm --network none -v ap2-ruby-integration-state:/state ap2-ruby-integration retry /state/crash
docker run --rm --network none -v ap2-ruby-integration-state:/state ap2-ruby-integration retry /state/crash resigned
docker run --rm --network none -v ap2-ruby-integration-state:/state ap2-ruby-integration inspect /state/crash
```

Run the recovery command even though the crash command is deliberately nonzero;
do not join them with `&&`. Each `docker run` launches a separate Ruby process.
The named volume survives `--rm`. Before recovery the SDK record is `pending`
and the durable mock has one execution/result. Recovery looks up the original
processor key, verifies its signed original-bound Receipt, and reaches
`receipt_success` without dispatch. Both retries return the original record with
**no Ticket**; the durable mock count stays **1**. A re-signature is not a new
business occurrence and does not replace the first signed bytes.

The older [`payment_acceptance.rb`](../examples/payment_acceptance.rb) opens a
second Store in the **same Ruby process**, retaining an in-memory mock result.
It teaches the coordinator API but does not demonstrate process restart or a
persisted processor result. Read this CLI first for restart integration, then the
older example for the smaller API-focused comparison.

## 3. Where application inputs come from

Never derive trusted approval, order or keys from received Mandate assertions.
The synthetic bootstrap supplies both sides only to make this example standalone.

| Input | Application owner / independent source | What to retain and recheck |
| --- | --- | --- |
| Approval and purchase conditions | Authenticated buyer consent / protected approval backend | Approved candidates, quantities, amounts, currency, allowed payment instrument and exact grant; current active/revoked status |
| Canonical order | Merchant order DB | Tenant, buyer/account, order ID/version, merchant, audience, exact Checkout and expected totals; current order before start |
| Current trust | Protected issuer/Agent/merchant registry | Identity, purpose, key selector, public key, activity, validity and policy version; reload current registry, never trust a JWT header as authority |
| Challenge | Host challenge/nonce service | Saved `InputBuilder.prepare` record, bindings, nonce, audience and expiry; `restore` against fresh inputs, with atomic current consumption in production |
| Expected Payment | Approved order and payment choice | Amount, currency, payee, instrument and Checkout binding, independent of incoming Payment |
| Stable business scope | Authenticated application workflow | Tenant, merchant, operation, approval, occurrence and order IDs; preserve across every retry/restart |
| Original signed wires | First successfully reserved attempt | Exact Checkout/Open/Closed bytes and Receipt reference, never regenerated for recovery |
| Processor identity/result | Acceptance record and processor | Original processor key plus durable query/result data; never allocate a replacement key on timeout |
| Receipt context | Protected enrollment / processor contract | Pinned issuer, public key, expected payment ID, original Closed reference and independent time window |

`InputBuilder.prepare` creates the saved challenge. At verification/start the
example reloads the protected fixture records, selects trust, calls `restore`
and `inputs`, then passes complete raw verification inputs to the existing SDK.
Restoring a record or loading a stored Result/Evidence is **not current
verification**. The coordinator verifies again; the real application must also
recheck authoritative current authorization and consume nonce/order state atomically.

The private directory (0700) and `app.json` (0600) hold synthetic signing keys,
trusted application inputs, saved challenge and exact first wires. The two SQLite
files hold the acceptance ledger and mock processor results. Protect and retain
the entire state set; do not commit it, print it, or share it as logs. The example
prints no private keys, reusable signed wires, nonce or Ticket values. Production
needs secret storage, access control, retention, encryption and backup policy.

The CLI prints one JSON summary per completed command. For example, the happy
path includes these fields (runtime metadata is omitted here):

```json
{"event":"finished","sdk_state":"receipt_success","ticket":false,"mock_dispatches":1,"receipt_authentic":true,"reported_outcome":"Success"}
```

`ticket` is only a boolean, never the capability. `sdk_version`, `sdk_load`,
`ruby` and `fixture_clock` identify the runtime; the route above should report
`1.6.0`, `installed_gem`, `4.0.9` and `1800000000`. Crash output carries
`simulated_process_exit: 75`. Missing query results report
`event: operator_reconciliation_required` and `result: unknown`; the SDK may
still say `pending`. That distinction does not authorize dispatch.

## 4. State transitions and recovery decisions

```text
protected approval + raw verification
  -> reserved (first caller receives opaque Ticket)
       -> fresh start + fenced CAS -> processing (lookup reports pending)
       |                               -> receipt_success
       |                               -> receipt_error
       |                               -> unknown -> verified reconciliation -> receipt_success/error
       -> invalid current inputs: no dispatch

retry / re-sign / process restart -> lookup original record; no new Ticket
missing/corrupt storage -> stop; never initialize a replacement ledger
```

`reserved` and `processing` are internal phases; a later lookup/retry reports
`pending` for an unfinished record. Only the original opaque Ticket can attempt
fresh `start`. Losing that capability in a process crash does not mint another.

For each row below, run `init /state/NAME`, then `run /state/NAME SCENARIO`, using
the same Docker command prefix above. Run `recover /state/NAME` and `inspect`
afterwards. A scenario directory is one protected synthetic occurrence, not a
way to allocate new authority for a retry.

| Scenario | Expected durable state / mock count | Safe next step |
| --- | --- | --- |
| `success` | `receipt_success` / 1 | Read final original outcome; no dispatch on retry |
| `error` | `receipt_error` / 1 | Authentic reported Error; not proof of no charge, no automatic retry |
| `pause-before-start` | Same-process reopen retains Ticket; completes / 1 | Fresh current inputs permit start; this is not a crash recovery |
| `expired-before-start` | No start / 0; reservation remains unfinished | Stop on expired challenge/Mandate; no replacement Ticket or automatic release |
| `crash-before-start` | Exit 75; `pending` / 0 | New process can inspect, but lost Ticket cannot be restored; operator reconciliation |
| `crash-after-start` | Exit 75; `pending` / 0 | No Receipt; preserve pending, even if mock count is zero |
| `crash-after-charge` | Exit 75; `pending` / 1, stored signed Receipt | `recover` reaches `receipt_success` / 1 without another dispatch |
| `unknown` | `unknown` / 1, no Receipt | Recovery preserves unknown; query original key and escalate unresolved outcome |
| `delayed` | `unknown` / 1 with later Receipt | `recover` at +120 verifies original Receipt window and reaches `receipt_success` / 1 |

Zero observed calls, missing Receipt, elapsed time, `pending`, `unknown`, or an
authentic Error Receipt never authorize a new payment or release the occurrence.
The mock records its effect and result in one local transaction; this **does not
prove distributed exactly-once behavior** for a real processor.

## 5. Replace the fixtures before production

1. Replace synthetic approval and keys with authenticated consent, protected
   issuance and a current trust registry. Replace JSON order records with the
   authoritative order service. Do not enroll a grant from an incoming flag.
2. Integrate current grant, order, nonce and occurrence checks with the same
   authoritative reservation/start CAS. A fixture snapshot and a check in one DB
   followed by a CAS in another do not prove production authorization atomicity.
3. Replace the mock with a PSP adapter whose idempotency/query contract is known.
   Retain the first processor key and original signed wires. Persist outcomes
   without logging reusable material. Use a trusted current clock, not this fixture.
4. Automate only read/query plus authenticated original-bound reconciliation when
   the result is available. Verify Receipt signature, issuer, payment ID, original
   reference and Receipt window. A valid signature with a different reference is
   rejected; never attach that Receipt to a re-signed replacement instruction.
5. Escalate lost Ticket, missing result, storage loss/corruption, rollback, trust
   rotation or conflicting evidence to the application operator. Stop dispatch,
   reconcile the original transaction with the PSP, and follow an explicit
   business recovery policy. Do not delete the ledger or manufacture a new ID.

Keep five questions separate: **Was the Mandate verified? Does the application
currently authorize execution? Did the processor execute? Is the Receipt
authentic? What result does it report?** A Success report alone is not settlement
proof. [Payment acceptance](PAYMENT_ACCEPTANCE.md) defines the API/storage
contract and remaining durability limits.
