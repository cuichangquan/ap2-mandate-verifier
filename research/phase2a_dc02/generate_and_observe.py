"""DC02: issuer-authentic hidden allowed_merchants with independently re-signed Agent terminal.

Synthetic research only, pinned AP2 v0.2.0. This is NOT a verifier API, Gem,
authorization, replay/Host/HC06 proof, or general AP2 conformance claim.
No signing private key leaves this Python process.
"""
import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

from jwcrypto.jwk import JWK
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "phase2a_dc01"))
sys.path.insert(0, str(ROOT / "p1_3"))
from independent_positive_oracle import (  # noqa: E402
    PINNED_AP2, b64url, decode64, jws_payload, raw_commitment_graph,
    require, segments, strict_json,
)
from generate_merchant_checkout import (  # noqa: E402
    checkout_json, merchant_signed_jwt, AUD, NONCE,
)
from ap2.sdk.disclosure_metadata import DisclosureMetadata
from ap2.sdk.generated.checkout_mandate import CheckoutMandate
from ap2.sdk.generated.open_checkout_mandate import (
    AllowedMerchants, Item, LineItems, LineItemRequirements, OpenCheckoutMandate,
)
from ap2.sdk.generated.types.merchant import Merchant
from ap2.sdk.mandate import MandateClient
from ap2.sdk.sdjwt import common, kb_sd_jwt, sd_jwt
from ap2.sdk.sdjwt.chain import verify_chain


ROOT_PATH = "$/delegate_payload/0"
HIDDEN_PATH = "$/delegate_payload/0/disclosed/constraints/1"
EXPECTED_GRAPH = {(ROOT_PATH, "array"), (HIDDEN_PATH, "array")}


def generate():
    issuer = JWK.generate(kty="EC", crv="P-256")
    agent = JWK.generate(kty="EC", crv="P-256")
    merchant = JWK.generate(kty="EC", crv="P-256")
    now = int(time.time())
    open_model = OpenCheckoutMandate(
        constraints=[
            LineItems(items=[LineItemRequirements(
                id="req-1",
                acceptable_items=[Item(id="SKU-1", title="Research Widget")],
                quantity=2,
            )]),
            AllowedMerchants(allowed=[Merchant(
                id="merchant-allowed", name="Research Merchant",
            )]),
        ],
        cnf={"jwk": json.loads(agent.export_public())},
        iat=now, exp=now + 3600,
    )
    full = MandateClient().create(
        payloads=[open_model], issuer_key=issuer,
        sd=DisclosureMetadata(children={
            "constraints": DisclosureMetadata(sd_array_indices=[1]),
        }),
    )
    issuer_jws, discs = segments(full)
    merchant_discs = []
    for part in discs:
        decoded = strict_json(decode64(part))
        if (isinstance(decoded, list) and len(decoded) == 2
                and isinstance(decoded[1], dict)
                and decoded[1].get("type") == "checkout.allowed_merchants"):
            merchant_discs.append(part)
    require(len(merchant_discs) == 1, "invalid fixture: must issue EXACT one Merchant constraint disclosure")
    removed = merchant_discs[0]
    partial_discs = [part for part in discs if part != removed]
    require(len(partial_discs) == len(discs) - 1, "fixture disclosure count mismatch")
    hidden = "~".join([issuer_jws, *partial_discs, ""])
    signed_checkout = merchant_signed_jwt(merchant, checkout_json())
    closed = CheckoutMandate(
        checkout_jwt=signed_checkout,
        checkout_hash=b64url(hashlib.sha256(signed_checkout.encode("ascii")).digest()),
        iat=now, exp=now + 3600,
    )

    def terminal(root):
        # Re-sign for each different disclosed Root. Never reuse a stale
        # sd_hash (otherwise a bad hash could give a false security PASS).
        return kb_sd_jwt.create(
            prev_token=common.parse_token(root), holder_key=agent,
            payload=closed, aud=AUD, nonce=NONCE,
            sd=DisclosureMetadata(), hash_mode="sd_hash",
        ).sd_jwt_issuance

    fixture = {
        "ap2_commit": PINNED_AP2,
        "fixture_origin": "official pinned AP2 MandateClient.create + KB SDJWT create; synthetic-only JWK",
        "trusted_issuer_public_jwk": json.loads(issuer.export_public()),
        "expected_agent_public_jwk": json.loads(agent.export_public()),
        "trusted_merchant_public_jwk": json.loads(merchant.export_public()),
        "root_full": full, "root_hidden_merchant": hidden,
        "terminal_full": terminal(full),
        "terminal_hidden": terminal(hidden),
        "host_checkout_jwt": signed_checkout,
        "expected_aud": AUD, "expected_nonce": NONCE,
        "expected_checkout_id": "checkout-001",
        "expected_merchant_id": "merchant-allowed",
        "expected_currency": "USD", "expected_total_minor": 2400,
        "omitted_disclosure_digest": b64url(hashlib.sha256(removed.encode("ascii")).digest()),
    }
    require("PRIVATE KEY" not in json.dumps(fixture), "key material in fixture")
    for name, value in fixture.items():
        if name.endswith("_jwk"):
            require(isinstance(value, dict) and "d" not in value, "private signing key in fixture")
    return fixture


def verify_and_observe(fixture, schema_path, merchant_schema_path):
    require(fixture["ap2_commit"] == PINNED_AP2, "AP2 source mismatch")
    full, hidden = fixture["root_full"], fixture["root_hidden_merchant"]
    issuer_key = fixture["trusted_issuer_public_jwk"]
    full_jws, full_discs = segments(full)
    hidden_jws, hidden_discs = segments(hidden)
    require(full_jws == hidden_jws, "Issuer signed JWT changed (false negative)")
    require(len(full_discs) == len(hidden_discs) + 1, "wrong number of hidden disclosures")
    # O1: verify actual original Issuer JWS, never trust a self-asserted kid.
    signed = jws_payload(full_jws, issuer_key)
    require(jws_payload(hidden_jws, issuer_key) == signed, "Issuer JWS invalid")
    # O3: independent raw-root full graph, including root-level unknown _sd.
    full_open_wire, graph = raw_commitment_graph(signed, full_discs)
    require({(x["path"], x["kind"]) for x in graph} == EXPECTED_GRAPH
            and len(graph) == 2, "unsupported signed commitment profile")
    require(set(signed) <= {"delegate_payload", "_sd_alg"}, "unsupported Root signed sibling")
    full_open = full_open_wire["delegate_payload"][0]
    require(isinstance(full_open, dict)
            and set(full_open) == {"vct", "cnf", "constraints", "iat", "exp"},
            "unsupported issuer Open claims")
    require(full_open["vct"] == "mandate.checkout.open.1", "wrong signed Open")
    require(full_open["cnf"]["jwk"] == fixture["expected_agent_public_jwk"], "Agent trust mismatch")
    require(full_open["iat"] <= int(time.time()) < full_open["exp"]
            and full_open["exp"] - full_open["iat"] <= 7200, "invalid Root time")
    missing = fixture["omitted_disclosure_digest"]
    target = [x for x in graph if x["path"] == HIDDEN_PATH and x["kind"] == "array"]
    require(len(target) == 1 and target[0]["digest_sha256"] == missing,
            "omitted digest not bound to signed merchant constraint")
    removed = [d for d in full_discs if b64url(hashlib.sha256(d.encode("ascii")).digest()) == missing]
    require(len(removed) == 1 and removed[0] not in hidden_discs,
            "not exactly the signed Merchant constraint disclosure")
    require([d for d in full_discs if d not in removed] == hidden_discs,
            "another disclosure also changed")
    merchant_constraint = strict_json(decode64(removed[0]))[1]
    require(merchant_constraint.get("type") == "checkout.allowed_merchants"
            and len(merchant_constraint.get("allowed", [])) == 1,
            "hidden disclosure is not the issuer-signed permitted Merchant constraint")

    # The independent walker must reject the authentic issuer-signed hidden
    # commitment specifically, rather than accept visible constraints only.
    independent_reason = None
    try:
        raw_commitment_graph(signed, hidden_discs)
    except ValueError as exc:
        independent_reason = str(exc)
    require(independent_reason == "incomplete_disclosure: signed commitment not disclosed",
            "not rejected by independent signed-wire completeness oracle")

    # O2: verify BOTH real Agent signatures, sd_hash for each distinct root,
    # fixed aud/nonce and the one Merchant JWT (the same signed checkout).
    merchant_jwt = fixture["host_checkout_jwt"]
    checkout = jws_payload(merchant_jwt, fixture["trusted_merchant_public_jwk"], expected_typ="JWT")
    require(checkout["id"] == fixture["expected_checkout_id"]
            and checkout["merchant"]["id"] == fixture["expected_merchant_id"]
            and checkout["currency"] == fixture["expected_currency"],
            "Host Merchant Checkout mismatch")
    terminal_graphs = {}
    for variant, root, terminal in (
        ("control_full", full, fixture["terminal_full"]),
        ("hidden_merchant", hidden, fixture["terminal_hidden"]),
    ):
        term_jws, term_discs = segments(terminal)
        signed_term = jws_payload(term_jws, fixture["expected_agent_public_jwk"], expected_typ="kb+sd-jwt")
        require(signed_term.get("sd_hash") ==
                b64url(hashlib.sha256(root.encode("ascii")).digest()),
                f"{variant}: stale or invalid sd_hash")
        require("issuer_jwt_hash" not in signed_term, "unsupported hash mode")
        require(signed_term.get("aud") == fixture["expected_aud"]
                and signed_term.get("nonce") == fixture["expected_nonce"]
                and isinstance(signed_term.get("iat"), int), "Agent binding invalid")
        resolved_term, term_graph = raw_commitment_graph(signed_term, term_discs)
        require(len(term_graph) == 1
                and term_graph[0]["path"] == "$/delegate_payload/0"
                and term_graph[0]["kind"] == "array", "unknown Terminal disclosure layout")
        closed = resolved_term["delegate_payload"][0]
        require(closed.get("checkout_jwt") == merchant_jwt
                and closed.get("checkout_hash") ==
                b64url(hashlib.sha256(merchant_jwt.encode("ascii")).digest()),
                "Merchant JWT/hash not bound")
        terminal_graphs[variant] = term_graph

    # AP2 SDK chain validates signatures for control AND hidden presentations.
    # A signature failure cannot count as a completeness rejection.
    issuer_public = JWK.from_json(json.dumps(issuer_key))
    control_chain = verify_chain(
        [common.parse_token(full), common.parse_token(fixture["terminal_full"])],
        public_key_provider=lambda _tok: issuer_public,
        expected_aud=fixture["expected_aud"], expected_nonce=fixture["expected_nonce"],
    )
    hidden_chain = verify_chain(
        [common.parse_token(hidden), common.parse_token(fixture["terminal_hidden"])],
        public_key_provider=lambda _tok: issuer_public,
        expected_aud=fixture["expected_aud"], expected_nonce=fixture["expected_nonce"],
    )
    require(len(control_chain) == len(hidden_chain) == 2, "official AP2 signed chain invalid")
    # This is the official resolved payload, used for schema O4 ONLY. It is
    # NOT the independent authority-completeness oracle.
    partial_open = hidden_chain[0]
    require(set(c["type"] for c in partial_open.get("constraints", [])) ==
            {"checkout.line_items"}, "hidden Merchant unexpectedly visible")
    require(set(c["type"] for c in control_chain[0].get("constraints", [])) ==
            {"checkout.line_items", "checkout.allowed_merchants"}, "control incomplete")

    # O4: distinguish official JSON Schema validity from local constraint
    # completeness (partial has only line_items, so official contains VALID).
    schema = strict_json(Path(schema_path).read_bytes())
    merch = strict_json(Path(merchant_schema_path).read_bytes())
    registry = Registry().with_resource(schema["$id"], Resource.from_contents(schema))
    registry = registry.with_resource(merch["$id"], Resource.from_contents(merch))
    validator = Draft202012Validator(schema, registry=registry)
    control_errors = list(validator.iter_errors(control_chain[0]))
    partial_errors = list(validator.iter_errors(partial_open))
    require(not control_errors and not partial_errors,
            "DC02 fixture invalid official Open Schema (wrong rejection cause)")
    require(full_open == control_chain[0], "independent vs official control resolution differs")
    require(len(control_chain[0]["constraints"]) == 2
            and len(partial_open["constraints"]) == 1, "wrong visible constraint count")
    require(fixture["terminal_full"] != fixture["terminal_hidden"],
            "Terminal not re-signed for altered disclosure presentation")
    return {
        "case_id": "DC02",
        "pinned_ap2_sha": PINNED_AP2,
        "o1_issuer_signature_full": "PASS",
        "o1_issuer_signature_hidden": "PASS",
        "o2_merchant_signature": "PASS",
        "o2_both_agent_signatures_and_sd_hash": "PASS",
        "o2_upstream_verify_chain_both": "PASS",
        "o3_control_root_commitments": 2,
        "o3_control_root_unresolved": 0,
        "o3_hidden_root_unresolved": 1,
        "o3_hidden_path": HIDDEN_PATH,
        "o3_reason": independent_reason,
        "o4_control_schema": "VALID",
        "o4_hidden_presentation_schema": "VALID",
        "o4_partial_issuer_profile": "REJECT",
        "o4_visible_constraint_types": ["checkout.line_items"],
        "o5_ruby": "PENDING_SEPARATE_OBSERVER",
        "outcome": "CRYPTO_VALID_HIDDEN_AUTHORITY_OBSERVED_AWAITING_RUBY",
        "evidence_boundary": "synthetic 2-hop issuer layout only; no Host ALLOW, DC03-DC05 or full Phase2-B",
    }


def save_replay(out, fixture, obs):
    out.mkdir(parents=True, exist_ok=True)
    for kind in ("full", "hidden"):
        root = fixture["root_full"] if kind == "full" else fixture["root_hidden_merchant"]
        terminal = fixture["terminal_full"] if kind == "full" else fixture["terminal_hidden"]
        rjws, rdiscs = segments(root)
        tjws, tdiscs = segments(terminal)
        (out / f"{kind}-root-jws.txt").write_text(rjws)
        (out / f"{kind}-root-sdjwt.txt").write_text(root)
        (out / f"{kind}-terminal-jws.txt").write_text(tjws)
        (out / f"{kind}-terminal-sdjwt.txt").write_text(terminal)
        (out / f"{kind}-chain.txt").write_text(root.removesuffix("~") + "~~" + terminal)
        for i, disc in enumerate(rdiscs):
            (out / f"{kind}-root-disclosure-{i:02d}.txt").write_text(disc)
        for i, disc in enumerate(tdiscs):
            (out / f"{kind}-terminal-disclosure-{i:02d}.txt").write_text(disc)
    (out / "merchant-jwt.txt").write_text(fixture["host_checkout_jwt"])
    (out / "fixture-public.json").write_text(json.dumps(fixture, indent=2, sort_keys=True) + "\n")
    (out / "python-observation.json").write_text(json.dumps(obs, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixture", required=True)
    parser.add_argument("--schema", required=True)
    parser.add_argument("--merchant-schema", required=True)
    parser.add_argument("--replay-dir", required=True)
    args = parser.parse_args()
    fixture = generate()
    obs = verify_and_observe(fixture, args.schema, args.merchant_schema)
    p = Path(args.fixture)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(fixture, indent=2, sort_keys=True) + "\n")
    save_replay(Path(args.replay_dir), fixture, obs)
    print("DC02: Issuer, Agent and Merchant signatures VALID for both full and hidden presentations")
    print("DC02: signed Merchant constraint digest OMITTED; independent completeness REJECT")
    print("DC02: official Open Schema VALID for both; local fixed Issuer profile REJECT for hidden")
