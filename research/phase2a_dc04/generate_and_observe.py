"""DC04: authentic signed nested single-element SD-JWT disclosures (research-only).

Distinct negative variants:
- permitted Merchant allowed[0] withheld
- required SKU acceptable_items[0] withheld
The issuer-signed Root is byte-for-byte identical in full and both negatives.
The Agent re-signs a matching Terminal per presentation. Private keys are
ephemeral and never exported; public-only fixtures are for offline research.
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

RESEARCH = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RESEARCH / "phase2a_dc01"))
sys.path.insert(0, str(RESEARCH / "p1_3"))
from independent_positive_oracle import (  # noqa: E402
    PINNED_AP2, b64url, decode64, jws_payload,
    raw_commitment_graph, require, segments, strict_json,
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

MERCHANT_PATH = "$/delegate_payload/0/disclosed/constraints/1/allowed/0"
SKU_PATH = "$/delegate_payload/0/disclosed/constraints/0/items/0/acceptable_items/0"
ROOT_PATH = "$/delegate_payload/0"
EXPECTED_ROOT_PATHS = {(ROOT_PATH, "array"), (MERCHANT_PATH, "array"), (SKU_PATH, "array")}
VARIANTS = ("full", "hidden_merchant_element", "hidden_sku_element")


def generate():
    issuer = JWK.generate(kty="EC", crv="P-256")
    agent = JWK.generate(kty="EC", crv="P-256")
    merchant_key = JWK.generate(kty="EC", crv="P-256")
    now = int(time.time())
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
        cnf={"jwk": json.loads(agent.export_public())},
        iat=now, exp=now + 3600,
    )
    # The exact-1 Merchant and exact-1 acceptable SKU are SD array elements.
    # The entire enclosing constraint objects remain visible in every
    # presentation. This differs fundamentally from DC02 and DC03.
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
    full = MandateClient().create(
        payloads=[mandate], issuer_key=issuer, sd=metadata,
    )
    original_jws, disclosures = segments(full)
    print("DC04 official signed Root protected JOSE:", json.dumps(
        strict_json(decode64(original_jws.split(".")[0])), sort_keys=True))
    require(3 <= len(disclosures) <= 16, "nested issuer SD fixture not generated")
    by_target = {}
    for disc in disclosures:
        item = strict_json(decode64(disc))
        if isinstance(item, list) and len(item) == 2 and isinstance(item[1], dict):
            claim = item[1]
            if claim.get("id") == "merchant-allowed" and claim.get("name") == "Research Merchant":
                require("hidden_merchant_element" not in by_target, "duplicate merchant elem")
                by_target["hidden_merchant_element"] = disc
            if claim.get("id") == "SKU-1" and claim.get("title") == "Research Widget":
                require("hidden_sku_element" not in by_target, "duplicate SKU elem")
                by_target["hidden_sku_element"] = disc
    require(set(by_target) == set(VARIANTS[1:]), "SDK did not issue both SD array-element disclosures")
    merchant_jwt = merchant_signed_jwt(merchant_key, checkout_json())
    checkout = CheckoutMandate(
        checkout_jwt=merchant_jwt,
        checkout_hash=b64url(hashlib.sha256(merchant_jwt.encode("ascii")).digest()),
        iat=now, exp=now + 3600,
    )
    roots = {"full": full}
    terminals = {}

    for name in VARIANTS[1:]:
        omitted = by_target[name]
        partial = [d for d in disclosures if d != omitted]
        require(len(partial) == len(disclosures) - 1, "wrong SD omission cardinality")
        roots[name] = "~".join([original_jws, *partial, ""])

    for name in VARIANTS:
        terminals[name] = kb_sd_jwt.create(
            prev_token=common.parse_token(roots[name]), holder_key=agent,
            payload=checkout, aud=AUD, nonce=NONCE,
            sd=DisclosureMetadata(), hash_mode="sd_hash",
        ).sd_jwt_issuance

    fixture = {
        "ap2_commit": PINNED_AP2,
        "fixture_origin": "pinned official AP2 v0.2 MandateClient.create / kb_sd_jwt.create",
        "trusted_issuer_public_jwk": json.loads(issuer.export_public()),
        "expected_agent_public_jwk": json.loads(agent.export_public()),
        "trusted_merchant_public_jwk": json.loads(merchant_key.export_public()),
        "roots": roots,
        "terminals": terminals,
        "host_checkout_jwt": merchant_jwt,
        "expected_aud": AUD, "expected_nonce": NONCE,
        "expected_checkout_id": "checkout-001",
        "expected_merchant_id": "merchant-allowed",
        "expected_currency": "USD", "expected_total_minor": 2400,
        "omitted_digests": {
            k: b64url(hashlib.sha256(v.encode("ascii")).digest()) for k, v in by_target.items()
        },
    }
    # Additional *genuinely issuer-signed* layout negatives. These must not
    # be confused with unsigned JSON edits or mutations of Root's JWS bytes.
    # In the first case, constraints[1] itself is SD-disclosed, moving the
    # nested Merchant element to a non-allowlisted signed-wire path.
    unexpected_sd = DisclosureMetadata(children={
        "constraints": DisclosureMetadata(
            sd_array_indices=[1],
            array_children=metadata.children["constraints"].array_children,
        ),
    })
    unexpected_root = MandateClient().create(
        payloads=[mandate], issuer_key=issuer, sd=unexpected_sd,
    )
    # The official issuer also supports adding cryptographic decoy digests.
    # Our fixed profile cannot distinguish their authority and must HOLD.
    decoy_root = sd_jwt.create(
        payload=mandate, issuer_key=issuer, sd=metadata, add_decoy_claims=True,
    ).sd_jwt_issuance
    fixture["additional_signed_negatives"] = {}
    for kind, root in (("unexpected_nested_path", unexpected_root),
                       ("issuer_decoy", decoy_root)):
        terminal = kb_sd_jwt.create(
            prev_token=common.parse_token(root), holder_key=agent,
            payload=checkout, aud=AUD, nonce=NONCE,
            sd=DisclosureMetadata(), hash_mode="sd_hash",
        ).sd_jwt_issuance
        fixture["additional_signed_negatives"][kind] = {
            "root": root, "terminal": terminal,
        }
    for key in ("trusted_issuer_public_jwk", "expected_agent_public_jwk", "trusted_merchant_public_jwk"):
        require(isinstance(fixture[key], dict) and "d" not in fixture[key], "secret JWK detected")
    return fixture


def verify_and_observe(f, schema_path, merchant_schema_path):
    require(f["ap2_commit"] == PINNED_AP2, "unpinned official AP2")
    original, original_disc = segments(f["roots"]["full"])
    signed = jws_payload(original, f["trusted_issuer_public_jwk"])
    require(set(signed) <= {"delegate_payload", "_sd_alg"}, "unsupported signed Root siblings")
    resolved, graph = raw_commitment_graph(signed, original_disc)
    require(len(graph) == 3 and {(x["path"], x["kind"]) for x in graph} == EXPECTED_ROOT_PATHS,
            "not exact fixed-Issuer 3-commitment layout")
    opened = resolved["delegate_payload"][0]
    require(set(opened) == {"vct", "constraints", "cnf", "iat", "exp"}, "unknown Open claims")
    require(opened["vct"] == "mandate.checkout.open.1", "wrong Open type")
    require(opened["cnf"]["jwk"] == f["expected_agent_public_jwk"], "untrusted Agent key")
    require(isinstance(opened["iat"], int) and isinstance(opened["exp"], int)
            and opened["iat"] <= int(time.time()) < opened["exp"]
            and opened["exp"] - opened["iat"] <= 7200, "invalid issuer time")
    require([c["type"] for c in opened["constraints"]] ==
            ["checkout.line_items", "checkout.allowed_merchants"], "wrong authority layout")
    require(len(opened["constraints"][0]["items"]) == 1 and
            len(opened["constraints"][0]["items"][0]["acceptable_items"]) == 1 and
            opened["constraints"][0]["items"][0]["acceptable_items"][0]["id"] == "SKU-1",
            "invalid fully disclosed SKU control")
    require(len(opened["constraints"][1]["allowed"]) == 1 and
            opened["constraints"][1]["allowed"][0]["id"] == f["expected_merchant_id"],
            "invalid fully disclosed Merchant control")

    issuer_public = JWK.from_json(json.dumps(f["trusted_issuer_public_jwk"]))
    checkout_jwt = f["host_checkout_jwt"]
    checkout = jws_payload(checkout_jwt, f["trusted_merchant_public_jwk"], expected_typ="JWT")
    require(checkout["id"] == f["expected_checkout_id"] and
            checkout["merchant"]["id"] == f["expected_merchant_id"] and
            checkout["currency"] == f["expected_currency"] and
            next(x["amount"] for x in checkout["totals"] if x["type"] == "total") ==
            f["expected_total_minor"], "signed Merchant checkout/Host mismatch")

    control_open = None
    partial_opens = {}
    outcomes = {}
    for kind in VARIANTS:
        root, terminal = f["roots"][kind], f["terminals"][kind]
        issuer_jws, disclosures = segments(root)
        require(issuer_jws == original, "Issuer JWS mutated in negative")
        require(jws_payload(issuer_jws, f["trusted_issuer_public_jwk"]) == signed,
                "invalid Issuer signature")
        term_jws, term_discs = segments(terminal)
        term_signed = jws_payload(term_jws, f["expected_agent_public_jwk"], expected_typ="kb+sd-jwt")
        require(term_signed.get("sd_hash") ==
                b64url(hashlib.sha256(root.encode("ascii")).digest()), "wrong signed sd_hash")
        require(term_signed.get("aud") == f["expected_aud"]
                and term_signed.get("nonce") == f["expected_nonce"]
                and isinstance(term_signed.get("iat"), int)
                and "issuer_jwt_hash" not in term_signed, "invalid signed Agent binding")
        term_resolved, term_graph = raw_commitment_graph(term_signed, term_discs)
        require(len(term_graph) == 1 and term_graph[0]["path"] == ROOT_PATH
                and term_graph[0]["kind"] == "array", "unexpected Terminal commitment")
        closed = term_resolved["delegate_payload"][0]
        require(closed["checkout_jwt"] == checkout_jwt and
                closed["checkout_hash"] == b64url(hashlib.sha256(checkout_jwt.encode("ascii")).digest()),
                "closed Merchant JWT/hash differs")
        verified = verify_chain(
            [common.parse_token(root), common.parse_token(terminal)],
            public_key_provider=lambda _token: issuer_public,
            expected_aud=f["expected_aud"], expected_nonce=f["expected_nonce"],
        )
        require(len(verified) == 2, "official SDK chain not verified")
        presented_open = verified[0]
        if kind == "full":
            require(presented_open == opened, "official vs independent fully resolved control differs")
            _, resolved_graph = raw_commitment_graph(signed, disclosures)
            require(len(resolved_graph) == 3, "control unsigned/missing commitments")
            control_open = presented_open
            outcomes[kind] = {"issuer_agent_merchant_crypto": "VALID", "completeness": "COMPLETE"}
        else:
            missing = f["omitted_digests"][kind]
            target = MERCHANT_PATH if kind == "hidden_merchant_element" else SKU_PATH
            require(len(disclosures) == len(original_disc) - 1, "non-single missing Disclosure")
            removed = [d for d in original_disc
                       if b64url(hashlib.sha256(d.encode("ascii")).digest()) == missing]
            require(len(removed) == 1 and removed[0] not in disclosures, "missing digest wrong")
            require([d for d in original_disc if d not in removed] == disclosures,
                    "a second Disclosure was tampered")
            expected_claim = strict_json(decode64(removed[0]))
            require(len(expected_claim) == 2 and isinstance(expected_claim[1], dict)
                    and expected_claim[1]["id"] == ("merchant-allowed" if kind == "hidden_merchant_element" else "SKU-1"),
                    "wrong signed element omitted")
            matched = [g for g in graph if g["path"] == target
                       and g["digest_sha256"] == missing and g["kind"] == "array"]
            require(len(matched) == 1, "not committed to correct nested element path")
            error = None
            try:
                raw_commitment_graph(signed, disclosures)
            except ValueError as exc:
                error = str(exc)
            require(error == "incomplete_disclosure: signed commitment not disclosed",
                    "not rejected by independent signed-wire completeness")
            require(presented_open["constraints"][0]["type"] == "checkout.line_items" and
                    presented_open["constraints"][1]["type"] == "checkout.allowed_merchants",
                    "entire constraint hidden instead of nested element")
            if kind == "hidden_merchant_element":
                require(presented_open["constraints"][1]["allowed"] == [], "not hidden only Merchant[0]")
                require(len(presented_open["constraints"][0]["items"][0]["acceptable_items"]) == 1,
                        "changed visible SKU as well")
            else:
                require(presented_open["constraints"][0]["items"][0]["acceptable_items"] == [],
                        "not hidden only SKU[0]")
                require(len(presented_open["constraints"][1]["allowed"]) == 1,
                        "changed Merchant visible element as well")
            partial_opens[kind] = presented_open
            outcomes[kind] = {"issuer_agent_merchant_crypto": "VALID",
                              "hidden_commitment_path": target,
                              "hidden_digest_sha256": missing,
                              "raw_wire_reason": error}

    schema = strict_json(Path(schema_path).read_bytes())
    ms = strict_json(Path(merchant_schema_path).read_bytes())
    registry = Registry().with_resource(schema["$id"], Resource.from_contents(schema))
    registry = registry.with_resource(ms["$id"], Resource.from_contents(ms))
    validator = Draft202012Validator(schema, registry=registry)
    for kind, presented_schema_open in (("full", control_open), *partial_opens.items()):
        errors = list(validator.iter_errors(presented_schema_open))
        outcomes[kind]["official_open_schema"] = "INVALID" if errors else "VALID"
        outcomes[kind]["official_schema_error_validators"] = [e.validator for e in errors]
        outcomes[kind]["official_schema_error_paths"] = ["/".join(str(x) for x in e.path) for e in errors]
    require(outcomes["full"]["official_open_schema"] == "VALID", "invalid full fixture")
    require(f["terminals"]["full"] != f["terminals"]["hidden_merchant_element"]
            and f["terminals"]["full"] != f["terminals"]["hidden_sku_element"],
            "Terminals not independently re-signed")

    # Independent signatures and holder binding for additional negatives.
    # The unexpected location has a completely disclosed, schema-valid Open;
    # failure must be attributable to the issuer-signed commitment location.
    extra_observations = {}
    for kind, pair in f["additional_signed_negatives"].items():
        raw_root, raw_term = pair["root"], pair["terminal"]
        signed_extra = jws_payload(segments(raw_root)[0], f["trusted_issuer_public_jwk"])
        signed_term = jws_payload(
            segments(raw_term)[0], f["expected_agent_public_jwk"],
            expected_typ="kb+sd-jwt",
        )
        require(signed_term.get("sd_hash") ==
                b64url(hashlib.sha256(raw_root.encode("ascii")).digest()),
                "extra signed Terminal not bound to exact Root")
        require(signed_term.get("aud") == f["expected_aud"] and
                signed_term.get("nonce") == f["expected_nonce"],
                "extra signed Terminal wrong audience/nonce")
        if kind == "unexpected_nested_path":
            extra_open, extra_graph = raw_commitment_graph(
                signed_extra, segments(raw_root)[1])
            require(len(extra_graph) >= 4 and
                    {(x["path"], x["kind"]) for x in extra_graph} != EXPECTED_ROOT_PATHS and
                    any(x["path"] == "$/delegate_payload/0/disclosed/constraints/1"
                        for x in extra_graph), "extra issuer-signed path not produced")
            require(extra_open["delegate_payload"][0] == opened,
                    "unexpected-path control changed Open semantics")
            extra_observations[kind] = {
                "crypto": "VALID", "signed_path": "extra constraints/1",
                "open_same_as_full": True,
            }
        else:
            # The decoy must be a signed commitment, not an unused fabricated
            # disclosure. This independent policy never ignores unknown _sd.
            def has_sd(obj):
                if isinstance(obj, dict):
                    return "_sd" in obj or any(has_sd(x) for x in obj.values())
                if isinstance(obj, list):
                    return any(has_sd(x) for x in obj)
                return False
            require(has_sd(signed_extra), "official decoy not emitted")
            extra_observations[kind] = {
                "crypto": "VALID", "signed_decoy_present": True,
            }

    return {
        "case_id": "DC04", "pinned_ap2_sha": PINNED_AP2,
        "o1_o2": "ALL_THREE_VARIANTS_CRYPTO_VALID_AND_UPSTREAM_CHAIN_VALID",
        "o3_full_signed_commitments": 3,
        "o3_full_unresolved": 0,
        "o3_hidden_unresolved_each": 1,
        "o3_commitment_paths": sorted(x["path"] for x in graph),
        "o4_o3_variants": outcomes,
        "o5_legacy_ruby": "NOT_RUN_YET",
        "additional_genuine_signed_negatives": extra_observations,
        "conclusion_before_o5": "O1_O4_ONLY_NOT_A_DC04_SECURITY_PASS",
        "evidence_boundary": "research-only synthetic signed nested element examples; no business ALLOW, no Phase2-B Gate proof",
    }


def save_artifacts(directory, f, obs):
    directory.mkdir(parents=True, exist_ok=True)
    for kind in VARIANTS:
        root, terminal = f["roots"][kind], f["terminals"][kind]
        jws, disclosures = segments(root)
        terminal_jws, tdisclosures = segments(terminal)
        (directory / f"{kind}-root-jws.txt").write_text(jws)
        (directory / f"{kind}-root-sdjwt.txt").write_text(root)
        (directory / f"{kind}-terminal-jws.txt").write_text(terminal_jws)
        (directory / f"{kind}-terminal-sdjwt.txt").write_text(terminal)
        (directory / f"{kind}-chain.txt").write_text(root.removesuffix("~") + "~~" + terminal)
        for i, value in enumerate(disclosures):
            (directory / f"{kind}-root-disclosure-{i:02d}.txt").write_text(value)
        for i, value in enumerate(tdisclosures):
            (directory / f"{kind}-terminal-disclosure-{i:02d}.txt").write_text(value)
    for kind, pair in f["additional_signed_negatives"].items():
        (directory / f"{kind}-root-sdjwt.txt").write_text(pair["root"])
        (directory / f"{kind}-terminal-sdjwt.txt").write_text(pair["terminal"])
    (directory / "merchant-jwt.txt").write_text(f["host_checkout_jwt"])
    (directory / "public-fixture.json").write_text(json.dumps(f, indent=2, sort_keys=True) + "\n")
    (directory / "python-observation.json").write_text(json.dumps(obs, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--fixture", required=True)
    p.add_argument("--schema", required=True)
    p.add_argument("--merchant-schema", required=True)
    p.add_argument("--replay-dir", required=True)
    args = p.parse_args()
    f = generate()
    observations = verify_and_observe(f, args.schema, args.merchant_schema)
    destination = Path(args.fixture)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(f, indent=2, sort_keys=True) + "\n")
    save_artifacts(Path(args.replay_dir), f, observations)
    print("DC04 O1–O4 synthetic signed full/hidden-Merchant-element/hidden-SKU-element observed")
    for kind in VARIANTS:
        print(kind, "official schema:", observations["o4_o3_variants"][kind]["official_open_schema"])
    print("WARNING: Ruby O5 still needed; standalone negative rejection is not a DC04 PASS")
