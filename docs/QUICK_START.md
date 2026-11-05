# Quick Start: Checkout → Payment → Receipt → monthly limits

[日本語](QUICK_START.ja.md) · [README](../README.md)

Use MRI 3.4.12 or 4.0.9 in your chosen Gem environment. No Rails, account or
production credentials. These examples generate synthetic keys and use fixed
clocks; they do not contact a processor. Ten minutes is a walkthrough target after
Ruby/dependencies are ready, not an installation-time guarantee.

## 1. Install and locate the published examples

```sh
gem install ap2_mandate_verifier --version 1.6.0
AP2_GEM_DIR="$(ruby -e 'puts Gem::Specification.find_by_name("ap2_mandate_verifier", "1.6.0").full_gem_path')"
```

Use the same Ruby for installation and execution. In an existing Bundler app,
pin `gem "ap2_mandate_verifier", "= 1.6.0"`, run `bundle install`, and prefix the
Ruby commands with `bundle exec`. Do not use a Gemfile requiring another version.

## 2. Issue, present and verify Checkout (about 2 minutes)

```sh
ruby "$AP2_GEM_DIR/examples/conditional_checkout.rb"
```

Follow `ConditionalCheckout.issue_open` → registered Agent `issue_closed/present`
→ independent Host input preparation → `InputBuilder.verify` → Checkout Receipt.
The synthetic approval allows A/B × 1 and C × 2. Expected output includes:

```text
Open -> Agent Closed -> merchant evidence: verified=true; rows=3; requirements=2
Receipt Success: authentic=true; purchase_succeeded=true
Receipt Error: authentic=true; purchase_succeeded=false
```

Success and Error are alternative simulated outcomes. Authenticity is separate
from reported business success. Missing Receipt/uncertain effect remains pending.
For exact-order Direct approval, use the [source-only Direct example](../examples/direct_checkout.rb)
with an installed Gem: clone this repository, then `ruby examples/direct_checkout.rb`.
It is not packaged in 1.6.0. [Direct API](BUYER_DIRECT_CHECKOUT.md).

## 3. Add Payment and authenticate its Receipt (about 2 minutes)

```sh
ruby "$AP2_GEM_DIR/examples/payment.rb"
```

This reuses the Checkout example, then builds Direct and conditional Payment
Mandates bound to it. Look for `Direct and conditional Payment: verified` and
`Payment Receipt Success: authentic=true; reported_success=true`, then
`Payment Receipt Error: authentic=true; reported_success=false` (each Payment
mode has both alternative outcomes). No payment is executed. Inspect the file to
see `Payment.details/issue_direct/issue_open/issue_closed/present/verify` and
`PaymentReceipt.sign/verify`. [Payment contract](PAYMENT.md).

## 4. Reuse a long Open across 12 months (about 3 minutes)

The wire-only example needs no database:

```sh
ruby "$AP2_GEM_DIR/examples/long_payment.rb"
```

For **durable cumulative limits**, the optional SQLite reference driver is needed.
It is not a core Gem dependency. In a separate Gem environment, install
`gem install sqlite3 --version 2.10.2`, then:

```sh
ruby "$AP2_GEM_DIR/examples/long_payment_acceptance.rb"
```

Expected: `12 explicit leap-year periods, 12 mock starts, reserved96000JPY within100000JPY`.
The example advances synthetic time through 2028; it does not wait a year or
schedule jobs. One Open pair, twelve fresh proofs, protected authority updates,
8,000 JPY per month, original-Receipt recovery. Temporary databases are deleted
when the process finishes. They are teaching fixtures, not durable production storage.

To compare a **budget-only rejection**, clone this repository and run its new
supplement against the installed Gem (it is not in the published 1.6.0 archive):

```sh
git clone https://github.com/cuichangquan/ap2-mandate-verifier.git
cd ap2-mandate-verifier
ruby examples/long_payment_limits.rb
```

After the twelve-month example, a separate approval reserves 40,000 JPY in January
and February. March's Mandate is cryptographically valid and a third occurrence
is allowed, but 120,000 would exceed 100,000: `acceptance=rejected`, `ticket=false`,
and the ledger remains 80,000 JPY / two reservations. This comparison starts no
processor. Stateless verification alone cannot enforce historical usage.

**Prefer Docker if you do not want local Ruby/SQLite installation:** follow the
[demo's published-Gem Docker route](https://github.com/cuichangquan/ap2-mandate-verifier-demo#readme).
Its documented image is Linux ARM64; other environments are not certified by it.

## Explore, then integrate

| Next question | Runnable installed example | Guide |
| --- | --- | --- |
| Send fewer candidates? | `selective_checkout_payment.rb` | [Selective Checkout](SELECTIVE_CHECKOUT.md) |
| Restrict PISP / execution date? | `payment_policy.rb` | [Policy](PAYMENT_POLICY.md) |
| Recover a lost response? | `payment_acceptance.rb` (SQLite) | [Acceptance](PAYMENT_ACCEPTANCE.md) |
| Short bounded ON_DEMAND usage? | `recurring_payment.rb` | [Recurrence](RECURRING_PAYMENT.md) |

Run these as `ruby "$AP2_GEM_DIR/examples/NAME.rb"`. Sources and fixture-backed
InputBuilder examples outside the archive require a checkout; do not assume all
GitHub examples ship inside the Gem. [Support and dependencies](SUPPORT_CONTRACT.md).

Before integration, replace synthetic authentication/consent, protected approvals,
current trust/order/challenge/time inputs and storage with app-owned services.
Preserve original signed bytes. Keep Provider private keys out of Agent operations.
Use shared durable state, atomic one-use consumption, processor idempotency and
reconciliation. Neither Evidence nor an authentic Receipt establishes settlement.
The long UTC-monthly JPY profile is **not** generic AP2 MONTHLY conformance; see
[precise scope and unsupported combinations](LONG_PAYMENT.md).
