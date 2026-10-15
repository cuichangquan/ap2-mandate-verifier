"""Issue #73 A-E03/E04-F: proposed signed six-case fixture BUILDER ONLY.

SOURCE ONLY / NOT RUN / NO APPROVAL B. Generates nothing on import.
Run only after separate Owner approval B with an isolated, SHA-pinned AP2
v0.2.0 SDK and reviewed dependencies. No network, key input, persistent
private key, database, payment, real Issuer, or trusted Host is supported.

Produces EXACTLY two new public-only files:
  --policy  synthetic Host CLAIM (not Host authority)
  --fixture {"ap2_commit": ..., "cases": {ID: {"root": ..., "terminal": ...}}}

The independent O1/O3 oracle must separately verify every original JWS
and whole SD graph. This builder cannot certify itself; its construction
checks cannot substitute for the Ruby same-invocation G3 observer or O2/O4.
DECOY denotes indistinguishable missing-commitment *ambiguity*, not proof
of genuine decoy provenance. No output is safe for production use.
"""
import argparse
import base64
import copy
import hashlib
import json
import os
import stat
import sys

from jwcrypto import jws
from jwcrypto.jwk import JWK

from ap2.sdk.disclosure_metadata import DisclosureMetadata
from ap2.sdk.generated.checkout_mandate import CheckoutMandate
from ap2.sdk.generated.open_checkout_mandate import (
    AllowedMerchants, Item, LineItems, LineItemRequirements, OpenCheckoutMandate,
)
from ap2.sdk.generated.types.checkout import Checkout
from ap2.sdk.generated.types.merchant import Merchant
from ap2.sdk.mandate import MandateClient
from ap2.sdk.sdjwt import common, kb_sd_jwt

PINNED_AP2 = "b4587ac1d055888a73b4b21750973cffba961793"
CASES = ("FULL", "HIDDEN", "UNKNOWN", "DUPLICATE", "EXTRA", "DECOY")
AUD = "checkout-merchant.example"
NONCE = "host-issued-test-challenge-001"
MAX_EPOCH = 4_102_444_800
ALLOWED_PATHS = sorted((
    "$/delegate_payload/0",
    "$/delegate_payload/0/disclosed/constraints/1/allowed/0",
    "$/delegate_payload/0/disclosed/constraints/0/items/0/acceptable_items/0",
))


class Stop(Exception):
    pass


def demand(condition, code):
    if not condition:
        raise Stop(code)


def canonical(obj):
    # Matches the Ruby synthetic Host's sorted-key, compact JSON digest.
    return json.dumps(obj, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=True, allow_nan=False).encode("ascii")


def digest(data):
    return hashlib.sha256(data).digest()


def b64(data):
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def decode64(text):
    demand(isinstance(text, str) and text and
           all(ch.isascii() and (ch.isalnum() or ch in "-_") for ch in text),
           "noncanonical_base64url")
    try:
        raw = base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))
    except (ValueError, base64.binascii.Error) as exc:
        raise Stop("invalid_base64url") from exc
    demand(b64(raw) == text, "noncanonical_base64url")
    return raw


def parsed(encoded):
    # The independent oracle, not this generator, owns duplicate-key checks.
    return json.loads(decode64(encoded))


def public(key):
    pub = json.loads(key.export_public())  # NEVER export private JWK.
    demand(set(pub) == {"crv", "kty", "x", "y"} and
           pub["kty"] == "EC" and pub["crv"] == "P-256" and
           all(isinstance(pub[k], str) and len(pub[k]) == 43
               for k in ("x", "y")), "invalid_public_only_jwk")
    return pub


def sign_json(private_key, payload, protected):
    demand(isinstance(protected, dict) and
           protected.get("alg") == "ES256" and
           protected.get("typ") in ("example+sd-jwt", "kb+sd-jwt", "JWT") and
           set(protected) <= {"alg", "kid", "typ"}, "unsupported_jose")
    message = jws.JWS(canonical(payload))
    message.add_signature(private_key, protected=canonical(protected).decode("ascii"))
    return message.serialize(compact=True)


def pieces(root):
    demand(isinstance(root, str) and root.isascii() and root.endswith("~") and
           len(root) <= 32_768, "invalid_sdk_root")
    members = root.split("~")
    demand(members[-1] == "" and 1 <= len(members[1:-1]) <= 16 and
           len(members[0].split(".")) == 3, "invalid_sdk_root_segments")
    return members[0], members[1:-1]


def read_original(full):
    compact, disclosures = pieces(full)
    header_part, payload_part, _sig = compact.split(".")
    header, payload = parsed(header_part), parsed(payload_part)
    demand(header.get("alg") == "ES256" and
           header.get("typ") == "example+sd-jwt" and
           isinstance(payload.get("delegate_payload"), list) and
           len(payload["delegate_payload"]) == 1, "invalid_sdk_signed_profile")
    root_marker = payload["delegate_payload"][0]
    demand(isinstance(root_marker, dict) and
           set(root_marker) == {"..."}, "invalid_sdk_root_marker")
    mapping = {b64(digest(part.encode("ascii"))): part for part in disclosures}
    demand(len(mapping) == len(disclosures), "duplicate_sdk_disclosure")
    root_part = mapping.get(root_marker["..."])
    demand(root_part is not None, "missing_sdk_mandate")
    root_disc = parsed(root_part)
    demand(isinstance(root_disc, list) and len(root_disc) == 2 and
           isinstance(root_disc[1], dict), "bad_sdk_mandate_disclosure")
    mandate = root_disc[1]
    demand(set(mandate) == {"vct", "cnf", "iat", "exp", "constraints"} and
           len(mandate["constraints"]) == 2, "unsupported_sdk_mandate")
    req, allowed = mandate["constraints"]
    sku_slot = req["items"][0]["acceptable_items"][0]
    merchant_slot = allowed["allowed"][0]
    demand(set(sku_slot) == {"..."} and
           set(merchant_slot) == {"..."} and
           sku_slot["..."] != merchant_slot["..."], "sdk_missing_deep_markers")
    sku_part, merchant_part = mapping.get(sku_slot["..."]), mapping.get(merchant_slot["..."])
    demand(sku_part is not None and merchant_part is not None and
           set(mapping) == {
               root_marker["..."], sku_slot["..."], merchant_slot["..."]
           }, "unsupported_sdk_commitment_count")
    demand(parsed(sku_part)[1] == {"id": "SKU-1", "title": "Research Widget"} and
           parsed(merchant_part)[1] == {
               "id": "merchant-allowed", "name": "Research Merchant"
           }, "wrong_sdk_disclosure_kind")
    return compact, disclosures, header, payload, root_part, sku_part, merchant_part


def fresh_salt():
    return b64(os.urandom(16))


def signed_variant(original, issuer, kind):
    compact, disclosures, header, original_payload, root_part, sku_part, merchant_part = original
    root_disc = copy.deepcopy(parsed(root_part))
    mandate = root_disc[1]
    sku_slot = mandate["constraints"][0]["items"][0]["acceptable_items"][0]
    merchant_slot = mandate["constraints"][1]["allowed"][0]
    retained = list(disclosures)
    if kind == "UNKNOWN":
        # Original signed Root count remains 1. Hidden *object* SD is outside
        # the three authorized array slots. This is a freshly signed variant.
        mandate["_sd"] = [b64(digest(os.urandom(32)))]
    elif kind == "DUPLICATE":
        # Two signed permitted slots now point to the SAME original digest.
        # Reject at G3's repeated-commitment guard, not later schema checks.
        sku_slot["..."] = merchant_slot["..."]
    elif kind == "DECOY":
        # A separately signed, unresolvable permitted commitment. It is
        # indistinguishable from a withheld value: no decoy-origin claim.
        merchant_slot["..."] = b64(digest(os.urandom(32)))
        retained.remove(merchant_part)
    else:
        raise Stop("invalid_signed_variant")

    # Fresh salt for every reissued Root disclosure; genuine Issuer re-sign.
    root_disc[0] = fresh_salt()
    new_root_part = b64(canonical(root_disc))
    payload = copy.deepcopy(original_payload)
    payload["delegate_payload"][0]["..."] = b64(digest(new_root_part.encode("ascii")))
    reissued = sign_json(issuer, payload, header)
    retained[retained.index(root_part)] = new_root_part
    demand(reissued != compact, "unchanged_signed_variant")
    return "~".join([reissued, *retained, ""])


def checkout_payload():
    value = {
        "id": "checkout-001",
        "merchant": {"id": "merchant-allowed", "name": "Research Merchant"},
        "line_items": [{
            "id": "li-1",
            "item": {"id": "SKU-1", "title": "Research Widget", "price": 1200},
            "quantity": 2,
            "totals": [{"type": "subtotal", "amount": 2400},
                       {"type": "total", "amount": 2400}],
        }],
        "status": "ready_for_complete", "currency": "USD",
        "totals": [{"type": "subtotal", "amount": 2400},
                   {"type": "total", "amount": 2400}],
        "links": [],
    }
    Checkout.model_validate(value)  # Pinned SDK shape, not authority proof.
    return value


def host_policy(issuer, agent, merchant, checkout_jwt, epoch):
    data = {
        "tenant_scope": "synthetic-e01s",
        "checkout_use_case": "checkout-research",
        "issuer_ref": "synthetic-e01s-issuer-A",
        "issuer_public_jwk": public(issuer),
        "issuer_thumbprint": b64(digest(canonical(public(issuer)))),
        "profile_ref": "e01s-fixed-a-v1",
        "policy_version": 1, "active": True, "alg": "ES256",
        "not_before": epoch - 60, "not_after": epoch + 1200,
        "freeze_epoch": epoch, "allowed_sd_paths": ALLOWED_PATHS,
        "expected_agent_public_jwk": public(agent),
        "trusted_merchant_public_jwk": public(merchant),
        "host_checkout_jwt": checkout_jwt,
        "expected_aud": AUD, "expected_nonce": NONCE,
        "expected_checkout_id": "checkout-001",
        "expected_merchant_id": "merchant-allowed",
        "expected_currency": "USD", "expected_total_minor": 2400,
    }
    data["policy_digest"] = hashlib.sha256(canonical(data)).hexdigest()
    return data


def make(epoch):
    demand(type(epoch) is int and 61 <= epoch <= MAX_EPOCH - 3600,
           "invalid_synthetic_epoch")
    issuer = JWK.generate(kty="EC", crv="P-256")
    agent = JWK.generate(kty="EC", crv="P-256")
    merchant = JWK.generate(kty="EC", crv="P-256")
    checkout_jwt = sign_json(merchant, checkout_payload(),
                             {"alg": "ES256", "typ": "JWT"})

    # Select synthetic policy PUBLIC keys before creating any Issuer Root.
    policy = host_policy(issuer, agent, merchant, checkout_jwt, epoch)
    mandate = OpenCheckoutMandate(
        constraints=[
            LineItems(items=[LineItemRequirements(
                id="req-1", quantity=2,
                acceptable_items=[Item(id="SKU-1", title="Research Widget")],
            )]),
            AllowedMerchants(allowed=[
                Merchant(id="merchant-allowed", name="Research Merchant")
            ]),
        ],
        cnf={"jwk": public(agent)}, iat=epoch, exp=epoch + 3600,
    )
    sd = DisclosureMetadata(children={
        "constraints": DisclosureMetadata(array_children={
            0: DisclosureMetadata(children={
                "items": DisclosureMetadata(array_children={
                    0: DisclosureMetadata(children={
                        "acceptable_items": DisclosureMetadata(sd_array_indices=[0]),
                    }),
                }),
            }),
            1: DisclosureMetadata(children={
                "allowed": DisclosureMetadata(sd_array_indices=[0]),
            }),
        }),
    })
    full = MandateClient().create(payloads=[mandate], issuer_key=issuer, sd=sd)
    original = read_original(full)
    compact, discs, _header, _payload, _root, _sku, merchant_disc = original

    hidden_disclosures = list(discs)
    hidden_disclosures.remove(merchant_disc)
    hidden = "~".join([compact, *hidden_disclosures, ""])
    extra = b64(canonical([fresh_salt(), {
        "id": "research-unreferenced", "name": "UNUSED"
    }]))
    roots = {
        "FULL": full,
        "HIDDEN": hidden,                    # EXACT same issuer compact JWS
        "UNKNOWN": signed_variant(original, issuer, "UNKNOWN"),
        "DUPLICATE": signed_variant(original, issuer, "DUPLICATE"),
        "EXTRA": "~".join([compact, *discs, extra, ""]),
        "DECOY": signed_variant(original, issuer, "DECOY"),
    }
    demand(set(roots) == set(CASES) and
           pieces(roots["HIDDEN"])[0] == compact and
           pieces(roots["DECOY"])[0] != compact and
           pieces(roots["UNKNOWN"])[0] != compact, "wrong_case_identity")

    closed = CheckoutMandate(
        checkout_jwt=checkout_jwt,
        checkout_hash=b64(digest(checkout_jwt.encode("ascii"))),
        iat=epoch, exp=epoch + 3600,
    )
    full_terminal = kb_sd_jwt.create(
        prev_token=common.parse_token(full), holder_key=agent,
        payload=closed, aud=AUD, nonce=NONCE,
        sd=DisclosureMetadata(), hash_mode="sd_hash",
    ).sd_jwt_issuance
    term_compact, term_disclosures = pieces(full_terminal)
    demand(len(term_disclosures) == 1, "unsupported_closed_disclosure_count")
    hdr, claims, _sig = term_compact.split(".")
    term_header, term_payload = parsed(hdr), parsed(claims)
    demand(term_header.get("typ") == "kb+sd-jwt" and
           isinstance(term_payload, dict) and
           term_payload.get("aud") == AUD and term_payload.get("nonce") == NONCE,
           "unsupported_sdk_terminal")
    cases = {}
    for case_id in CASES:
        root = roots[case_id]
        claim = copy.deepcopy(term_payload)
        claim["sd_hash"] = b64(digest(root.encode("ascii")))
        terminal = "~".join([
            sign_json(agent, claim, term_header), *term_disclosures, ""
        ])
        demand(len(root) <= 32_768 and len(terminal) <= 32_768,
               "oversized_signed_wire")
        cases[case_id] = {"root": root, "terminal": terminal}
    # All six terminal signatures bind their own EXACT original Root wires.
    fixture = {"ap2_commit": PINNED_AP2, "cases": cases}
    return policy, fixture


def exclusive_write(path, obj, cap):
    data = canonical(obj) + b"\n"
    demand(0 < len(data) <= cap and isinstance(path, str) and
           1 <= len(os.fsencode(path)) <= 1024 and "\x00" not in path and
           hasattr(os, "O_NOFOLLOW"), "unsafe_output")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL |
                 os.O_NOFOLLOW, 0o600)
    try:
        demand(stat.S_ISREG(os.fstat(fd).st_mode), "unsafe_output_type")
        with os.fdopen(fd, "wb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
    except Exception:
        # A partial file is NOT proof; external isolation cleans scratch.
        raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--epoch", required=True, type=int)
    parser.add_argument("--policy", required=True)
    parser.add_argument("--fixture", required=True)
    args = parser.parse_args()
    demand(os.path.abspath(args.policy) != os.path.abspath(args.fixture),
           "aliased_output")
    policy, fixture = make(args.epoch)
    # Both outputs are new, under a future approved ephemeral runner tmpdir.
    # No mkdir, no overwrite, no private JWK export, no network, no upload.
    exclusive_write(args.policy, policy, 16_384)
    exclusive_write(args.fixture, fixture, 262_144)
    print("E03/E04 F: public-only builder complete; O1-O5 NOT RUN; Gate HOLD")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # No token, private key, pathname or exception text in log output.
        print("E03/E04 F: STOP/HOLD; fixture construction unverified",
              file=sys.stderr)
        sys.exit(1)
