"""E01-S: only three genuinely signed synthetic Issuer A/B cases (research only).

Never export private signing keys. The frozen Host policy is written BEFORE
the official SDK issues any Root. This is synthetic process-order evidence,
not a real Host enrollment, trusted-clock, or issuer-identity attestation.
"""
import argparse
import hashlib
import json
import os
import sys
import time
from pathlib import Path

from jwcrypto.jwk import JWK
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

RESEARCH = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RESEARCH / "phase2a_dc01"))
sys.path.insert(0, str(RESEARCH / "p1_3"))
from independent_positive_oracle import (  # noqa: E402
    PINNED_AP2, b64url, jws_payload, raw_commitment_graph,
    require, segments, strict_json,
)
from generate_merchant_checkout import (  # noqa: E402
    AUD, NONCE, checkout_json, merchant_signed_jwt,
)
from ap2.sdk.disclosure_metadata import DisclosureMetadata  # noqa: E402
from ap2.sdk.generated.checkout_mandate import CheckoutMandate  # noqa: E402
from ap2.sdk.generated.open_checkout_mandate import (  # noqa: E402
    AllowedMerchants, Item, LineItems, LineItemRequirements, OpenCheckoutMandate,
)
from ap2.sdk.generated.types.merchant import Merchant  # noqa: E402
from ap2.sdk.mandate import MandateClient  # noqa: E402
from ap2.sdk.sdjwt import common, kb_sd_jwt  # noqa: E402
from ap2.sdk.sdjwt.chain import verify_chain  # noqa: E402

CASE_IDS = ("IP01", "IP02", "IP03")
ROOT_PATH = "$/delegate_payload/0"
MERCHANT_PATH = "$/delegate_payload/0/disclosed/constraints/1/allowed/0"
SKU_PATH = "$/delegate_payload/0/disclosed/constraints/0/items/0/acceptable_items/0"
EXTRA_PATH = "$/delegate_payload/0/disclosed/constraints/1"
ALLOWED = {ROOT_PATH, MERCHANT_PATH, SKU_PATH}


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("ascii")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def thumbprint(public):
    require(isinstance(public, dict) and set(public) == {"kty", "crv", "x", "y"},
            "noncanonical public EC JWK")
    require(public["kty"] == "EC" and public["crv"] == "P-256", "unsupported issuer key")
    return b64url(hashlib.sha256(canonical({k: public[k] for k in ("crv", "kty", "x", "y")})).digest())


def public(key):
    result = json.loads(key.export_public())
    require("d" not in result, "private JWK in public export")
    return result


def freeze_policy(path, issuer_a, agent, merchant, merchant_jwt, now):
    # This standalone file is the sole synthetic Host authority. Never derive
    # allowed keys or grammar from per-case token data after this point.
    policy = {
        "tenant_scope": "synthetic-e01s",
        "checkout_use_case": "checkout-research",
        "issuer_ref": "synthetic-e01s-issuer-A",
        "issuer_public_jwk": public(issuer_a),
        "issuer_thumbprint": thumbprint(public(issuer_a)),
        "profile_ref": "e01s-fixed-a-v1",
        "policy_version": 1,
        "active": True,
        "alg": "ES256",
        "not_before": now - 60,
        "not_after": now + 1200,
        "freeze_epoch": now,
        "allowed_sd_paths": sorted(ALLOWED),
        "expected_agent_public_jwk": public(agent),
        "trusted_merchant_public_jwk": public(merchant),
        "host_checkout_jwt": merchant_jwt,
        "expected_aud": AUD,
        "expected_nonce": NONCE,
        "expected_checkout_id": "checkout-001",
        "expected_merchant_id": "merchant-allowed",
        "expected_currency": "USD",
        "expected_total_minor": 2400,
    }
    policy["policy_digest"] = digest(canonical(policy))
    path.parent.mkdir(parents=True, exist_ok=True)
    # Write and fsync prior to *any* issuer Root issuance.
    with path.open("wb") as stream:
        stream.write(canonical(policy) + b"\n")
        stream.flush()
        os.fsync(stream.fileno())
    require(digest(canonical({k: v for k, v in policy.items() if k != "policy_digest"}))
            == policy["policy_digest"], "unfrozen Host policy digest")
    return policy


def issue_three_cases(issuer_a, issuer_b, agent, merchant_jwt, now):
    mandate = OpenCheckoutMandate(
        constraints=[
            LineItems(items=[LineItemRequirements(
                id="req-1", quantity=2,
                acceptable_items=[Item(id="SKU-1", title="Research Widget")],
            )]),
            AllowedMerchants(allowed=[Merchant(
                id="merchant-allowed", name="Research Merchant",
            )]),
        ],
        cnf={"jwk": public(agent)}, iat=now, exp=now + 3600,
    )
    metadata = DisclosureMetadata(children={
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
    alternate = DisclosureMetadata(children={
        "constraints": DisclosureMetadata(
            sd_array_indices=[1],
            array_children=metadata.children["constraints"].array_children,
        ),
    })
    client = MandateClient()
    roots = {
        "IP01": client.create(payloads=[mandate], issuer_key=issuer_a, sd=metadata),
        "IP02": client.create(payloads=[mandate], issuer_key=issuer_b, sd=metadata),
        "IP03": client.create(payloads=[mandate], issuer_key=issuer_a, sd=alternate),
    }
    checkout = CheckoutMandate(
        checkout_jwt=merchant_jwt,
        checkout_hash=b64url(hashlib.sha256(merchant_jwt.encode("ascii")).digest()),
        iat=now, exp=now + 3600,
    )
    terminals = {}
    for case_id in CASE_IDS:
        terminals[case_id] = kb_sd_jwt.create(
            prev_token=common.parse_token(roots[case_id]), holder_key=agent,
            payload=checkout, aud=AUD, nonce=NONCE,
            sd=DisclosureMetadata(), hash_mode="sd_hash",
        ).sd_jwt_issuance
    return roots, terminals


def validate_three(fixture, policy, schema_path, merchant_schema_path):
    require(fixture["ap2_commit"] == PINNED_AP2, "unpinned official AP2")
    schema = strict_json(Path(schema_path).read_bytes())
    merchant_schema = strict_json(Path(merchant_schema_path).read_bytes())
    registry = Registry().with_resource(schema["$id"], Resource.from_contents(schema))
    registry = registry.with_resource(merchant_schema["$id"], Resource.from_contents(merchant_schema))
    validator = Draft202012Validator(schema, registry=registry)

    root_controls = {}
    observed = {}
    checkout_jwt = policy["host_checkout_jwt"]
    checkout = jws_payload(checkout_jwt, policy["trusted_merchant_public_jwk"], expected_typ="JWT")
    require(checkout["id"] == policy["expected_checkout_id"]
            and checkout["merchant"]["id"] == policy["expected_merchant_id"]
            and checkout["currency"] == policy["expected_currency"]
            and next(x["amount"] for x in checkout["totals"] if x["type"] == "total")
            == policy["expected_total_minor"], "Merchant checkout Host mismatch")
    for case_id in CASE_IDS:
        root = fixture["roots"][case_id]
        terminal = fixture["terminals"][case_id]
        signer = fixture["candidate_issuer_public_jwks"][case_id]
        original_root, disclosures = segments(root)
        require(len(root.encode("ascii")) <= 32768 and len(disclosures) <= 16, "Root resource cap")
        actual_signed = jws_payload(original_root, signer, expected_typ="example+sd-jwt")
        require(set(actual_signed) <= {"delegate_payload", "_sd_alg"}, "unknown Root claim")
        resolved, graph = raw_commitment_graph(actual_signed, disclosures)
        root_paths = [g["path"] for g in graph]
        require(len(root_paths) == len(set(root_paths)), "duplicate signed slot")
        require(not any(g["kind"] != "array" for g in graph), "object SD slot prohibited")
        require("d" not in signer and thumbprint(signer) ==
                fixture["candidate_issuer_thumbprints"][case_id], "candidate signer mismatch")
        require(thumbprint(signer) ==
                (policy["issuer_thumbprint"] if case_id != "IP02" else thumbprint(
                    fixture["issuer_b_public_jwk"])), "bad case signer")
        opened = resolved["delegate_payload"][0]
        require(opened["cnf"]["jwk"] == policy["expected_agent_public_jwk"], "Root Agent mismatch")
        require(opened["iat"] == policy["freeze_epoch"]
                and opened["exp"] - opened["iat"] == 3600, "bad Root validity")

        term_jws, term_discs = segments(terminal)
        term_signed = jws_payload(term_jws, policy["expected_agent_public_jwk"], expected_typ="kb+sd-jwt")
        require(term_signed["sd_hash"] == b64url(hashlib.sha256(root.encode("ascii")).digest())
                and term_signed["aud"] == policy["expected_aud"]
                and term_signed["nonce"] == policy["expected_nonce"]
                and isinstance(term_signed["iat"], int)
                and "issuer_jwt_hash" not in term_signed, "invalid Terminal binding")
        closed_root, closed_graph = raw_commitment_graph(term_signed, term_discs)
        require(len(closed_graph) == 1 and closed_graph[0]["path"] == ROOT_PATH,
                "unsupported Terminal SD structure")
        closed = closed_root["delegate_payload"][0]
        require(closed["checkout_jwt"] == checkout_jwt and
                closed["checkout_hash"] == b64url(hashlib.sha256(checkout_jwt.encode("ascii")).digest()),
                "invalid Merchant Checkout JWT/hash")
        require(closed["iat"] == opened["iat"] and closed["exp"] == opened["exp"],
                "invalid Open-to-Closed time binding")

        issuer_public = JWK.from_json(json.dumps(signer))
        upstream = verify_chain(
            [common.parse_token(root), common.parse_token(terminal)],
            public_key_provider=lambda _token: issuer_public,
            expected_aud=policy["expected_aud"], expected_nonce=policy["expected_nonce"],
        )
        require(len(upstream) == 2 and upstream[0] == opened,
                "official chain and independent Root differ")
        errors = list(validator.iter_errors(opened))
        require(not errors, "BLOCKED_OFFICIAL_SHAPE: " + case_id + " " +
                ",".join(e.validator for e in errors))
        root_controls[case_id] = opened
        observed[case_id] = {
            "O1_issuer_signature": "VALID_WITH_CASE_SIGNER",
            "O2_agent_merchant_checkout_binding": "VALID",
            "O3_original_root_disclosure_completeness": "VALID_WITH_ALL_DISCLOSURES",
            "O3_signed_paths": root_paths,
            "O4_official_open_schema": "VALID",
            "signer_thumbprint": thumbprint(signer),
            "root_jws_sha256": digest(original_root.encode("ascii")),
            "root_wire_sha256": digest(root.encode("ascii")),
            "root_bytes": len(root.encode("ascii")),
        }
    require(root_controls["IP01"] == root_controls["IP02"] == root_controls["IP03"],
            "Open semantics changed across Issuer/layout cases")
    require(set(observed["IP01"]["O3_signed_paths"]) == ALLOWED and
            set(observed["IP02"]["O3_signed_paths"]) == ALLOWED, "control SD grammar mismatch")
    require(EXTRA_PATH in observed["IP03"]["O3_signed_paths"] and
            set(observed["IP03"]["O3_signed_paths"]) != ALLOWED,
            "not a truly alternate A-signed SD grammar")
    require(observed["IP01"]["signer_thumbprint"] ==
            observed["IP03"]["signer_thumbprint"] == policy["issuer_thumbprint"],
            "IP03 signer differs from A")
    require(observed["IP02"]["signer_thumbprint"] != policy["issuer_thumbprint"],
            "IP02 unexpectedly Host trusted")
    return observed


def main():
    p = argparse.ArgumentParser()
    for option in ("fixture", "policy", "report", "schema", "merchant-schema"):
        p.add_argument("--" + option, required=True)
    args = p.parse_args()
    issuer_a, issuer_b, agent, merchant = (JWK.generate(kty="EC", crv="P-256") for _ in range(4))
    now = int(time.time())
    merchant_jwt = merchant_signed_jwt(merchant, checkout_json())
    # Host policy FIRST, before all signed Root issuance.
    policy = freeze_policy(Path(args.policy), issuer_a, agent, merchant, merchant_jwt, now)
    roots, terminals = issue_three_cases(issuer_a, issuer_b, agent, merchant_jwt, now)
    candidates = {"IP01": public(issuer_a), "IP02": public(issuer_b), "IP03": public(issuer_a)}
    fixture = {
        "case_id": "E01-S", "ap2_commit": PINNED_AP2,
        "policy_digest": policy["policy_digest"],
        "candidate_issuer_public_jwks": candidates,
        "candidate_issuer_thumbprints": {k: thumbprint(v) for k, v in candidates.items()},
        "issuer_b_public_jwk": public(issuer_b),
        "roots": roots, "terminals": terminals,
    }
    require(set(fixture["roots"]) == set(fixture["terminals"]) == set(CASE_IDS),
            "out of scope E01-S case")
    for jwk in (*candidates.values(), policy["issuer_public_jwk"],
                policy["expected_agent_public_jwk"], policy["trusted_merchant_public_jwk"]):
        require("d" not in jwk and set(jwk) == {"crv", "kty", "x", "y"},
                "private or malformed JWK")
    observed = validate_three(fixture, policy, args.schema, args.merchant_schema)
    for case_id in CASE_IDS:
        case_size = len(canonical({
            "root": roots[case_id], "terminal": terminals[case_id],
            "candidate": candidates[case_id], "Host": policy,
        }))
        require(case_size <= 131072, "oversized entire case")
    Path(args.fixture).write_bytes(canonical(fixture) + b"\n")
    Path(args.report).write_bytes(canonical({
        "case_id": "E01-S", "pinned_ap2_sha": PINNED_AP2,
        "policy_digest": policy["policy_digest"],
        "oracles": observed,
        "O5_Ruby": "NOT_RUN",
        "boundary": "synthetic research only; Host trust provenance and Phase 2-B unproven",
    }) + b"\n")
    print("E01-S O1-O4 independent genuinely signed oracles VALID; O5 NOT RUN")


if __name__ == "__main__":
    main()
