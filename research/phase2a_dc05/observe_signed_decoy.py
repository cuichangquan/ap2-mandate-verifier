"""DC05 O1-O4: genuine official-Issuer decoy ambiguity on raw signed wire.

Research only; do not treat SDK-resolved Open or JSON Schema VALID as
proof that every signed authority-bearing commitment was disclosed.
Uses the public-only synthetic fixture minted by the pinned DC04 generator.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

from jwcrypto.jwk import JWK
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

RESEARCH = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RESEARCH / "phase2a_dc01"))
from independent_positive_oracle import (  # noqa: E402
    PINNED_AP2, b64url, decode64, jws_payload, raw_commitment_graph,
    require, segments, strict_json,
)
from ap2.sdk.sdjwt import common
from ap2.sdk.sdjwt.chain import verify_chain


def inspect_signed_graph(signed_payload, disclosures):
    """Starting at verified top-level JWS payload, traverse reachable
    issuer-signed graph without looking at the SDK's resolved dict.
    Enumerate _sd digests even when SDK quietly treats them as decoys.
    This must not assume all unpresented digests are harmless decoys.
    """
    mapping = {}
    for disc in disclosures:
        pair = strict_json(decode64(disc))
        require(isinstance(pair, list) and len(pair) == 2 and
                isinstance(pair[0], str) and len(pair[0]) >= 8,
                "unsupported DC05 Disclosure shape")
        digest = b64url(hashlib.sha256(disc.encode("ascii")).digest())
        require(digest not in mapping, "duplicate disclosed hash")
        mapping[digest] = pair[1]

    visited = set()
    commitments = []

    def consume(digest, path, kind):
        require(isinstance(digest, str) and len(digest) == 43,
                "unsupported signed commitment digest")
        present = digest in mapping
        require(digest not in visited, "duplicated signed digest")
        visited.add(digest)
        commitments.append({
            "path": path, "kind": kind, "digest_sha256": digest,
            "presented": present,
        })
        return mapping.get(digest) if present else None

    def walk(node, path, depth):
        require(depth < 30, "over-depth signed graph")
        if isinstance(node, dict):
            require(len(node) <= 32, "oversized signed dict")
            require("..." not in node, "stray unsigned placeholder")
            if "_sd" in node:
                digests = node["_sd"]
                require(isinstance(digests, list), "malformed signed _sd")
                for index, digest in enumerate(digests):
                    child = consume(digest, f"{path}/_sd/{index}", "object")
                    if child is not None:
                        walk(child, f"{path}/_sd/{index}/disclosed", depth + 1)
            for key, value in node.items():
                if key != "_sd":
                    walk(value, f"{path}/{key}", depth + 1)
        elif isinstance(node, list):
            require(len(node) <= 16, "oversized signed array")
            for index, item in enumerate(node):
                here = f"{path}/{index}"
                if isinstance(item, dict) and "..." in item:
                    require(set(item) == {"..."}, "malformed array placeholder")
                    child = consume(item["..."], here, "array")
                    if child is not None:
                        walk(child, here + "/disclosed", depth + 1)
                else:
                    walk(item, here, depth + 1)
    walk(signed_payload, "$", 0)
    require(set(mapping) == {x["digest_sha256"] for x in commitments if x["presented"]},
            "unused disclosure")
    return commitments


def check_terminal(fixture, root, terminal):
    t_jws, t_discs = segments(terminal)
    agent_signed = jws_payload(t_jws, fixture["expected_agent_public_jwk"],
                               expected_typ="kb+sd-jwt")
    require(agent_signed.get("sd_hash") ==
            b64url(hashlib.sha256(root.encode("ascii")).digest()),
            "invalid Agent binding to decoy presentation")
    require(agent_signed.get("aud") == fixture["expected_aud"] and
            agent_signed.get("nonce") == fixture["expected_nonce"],
            "Host audience/nonce mismatch")
    term_open, term_graph = raw_commitment_graph(agent_signed, t_discs)
    require(len(term_graph) == 1 and term_graph[0]["path"] == "$/delegate_payload/0",
            "invalid signed Terminal layout")
    closed = term_open["delegate_payload"][0]
    checkout_jwt = fixture["host_checkout_jwt"]
    require(closed["checkout_jwt"] == checkout_jwt and
            closed["checkout_hash"] ==
            b64url(hashlib.sha256(checkout_jwt.encode("ascii")).digest()),
            "Host Checkout JWT/hash mismatch")
    return {"status": "VALID", "terminal_graph": len(term_graph)}


def main(args):
    fixture = strict_json(Path(args.fixture).read_bytes())
    require(fixture["ap2_commit"] == PINNED_AP2, "wrong official AP2 source")
    roots, terminals = fixture["roots"], fixture["terminals"]
    decoy_pair = fixture["additional_signed_negatives"]["issuer_decoy"]
    full_jws, full_disc = segments(roots["full"])
    decoy_jws, decoy_disc = segments(decoy_pair["root"])
    full_signed = jws_payload(full_jws, fixture["trusted_issuer_public_jwk"])
    decoy_signed = jws_payload(decoy_jws, fixture["trusted_issuer_public_jwk"])

    full_resolved, full_graph = raw_commitment_graph(full_signed, full_disc)
    full_open = full_resolved["delegate_payload"][0]
    full_scan = inspect_signed_graph(full_signed, full_disc)
    require(len(full_graph) == 3 and len(full_scan) == 3 and
            all(x["presented"] and x["kind"] == "array" for x in full_scan),
            "FULL is not the exact positively disclosed control")
    # Fail closed on decoy rather than attempting to invent a Disclosure.
    decoy_scan = inspect_signed_graph(decoy_signed, decoy_disc)
    residual = [c for c in decoy_scan if not c["presented"]]
    require(len(residual) >= 1 and
            all(c["kind"] == "object" and "/_sd/" in c["path"] for c in residual),
            "official signed decoy did not leave unresolved object digests")
    require(all(c["kind"] != "object" for c in full_scan),
            "positive unexpectedly contains object commitments")
    oracle_failure = ""
    try:
        raw_commitment_graph(decoy_signed, decoy_disc)
    except ValueError as exc:
        oracle_failure = str(exc)
    require(oracle_failure == "incomplete_disclosure: signed commitment not disclosed",
            "independent whole signed-wire oracle failed to detect residual")

    full_terminal = check_terminal(fixture, roots["full"], terminals["full"])
    decoy_terminal = check_terminal(fixture, decoy_pair["root"], decoy_pair["terminal"])
    merchant = jws_payload(fixture["host_checkout_jwt"],
                           fixture["trusted_merchant_public_jwk"], expected_typ="JWT")
    require(merchant["id"] == fixture["expected_checkout_id"] and
            merchant["merchant"]["id"] == fixture["expected_merchant_id"] and
            merchant["currency"] == fixture["expected_currency"],
            "Merchant signature valid but Host checkout context mismatched")
    require(next(x["amount"] for x in merchant["totals"] if x["type"] == "total")
            == fixture["expected_total_minor"], "wrong Host signed checkout amount")
    issuer = JWK.from_json(json.dumps(fixture["trusted_issuer_public_jwk"]))
    def upstream(root, terminal):
        return verify_chain(
            [common.parse_token(root), common.parse_token(terminal)],
            public_key_provider=lambda _token: issuer,
            expected_aud=fixture["expected_aud"],
            expected_nonce=fixture["expected_nonce"],
        )
    sdk_full = upstream(roots["full"], terminals["full"])
    sdk_decoy = upstream(decoy_pair["root"], decoy_pair["terminal"])
    require(len(sdk_full) == 2 and len(sdk_decoy) == 2,
            "official SDK failed a genuine decoy Chain")
    # Valid fully disclosed Open remains the business semantics even while
    # a decoy digest is invisible to the presentation: not completeness!
    require(sdk_full[0] == full_open and sdk_decoy[0] == full_open,
            "Issuer signed decoy changed effective Open")

    schema = strict_json(Path(args.schema).read_bytes())
    merchant_schema = strict_json(Path(args.merchant_schema).read_bytes())
    reg = Registry().with_resource(schema["$id"], Resource.from_contents(schema))
    reg = reg.with_resource(merchant_schema["$id"], Resource.from_contents(merchant_schema))
    validator = Draft202012Validator(schema, registry=reg)
    full_errors = list(validator.iter_errors(sdk_full[0]))
    decoy_errors = list(validator.iter_errors(sdk_decoy[0]))
    require(not full_errors and not decoy_errors,
            "FULL/decoy official presented schema not both VALID")

    result = {
        "case_id": "DC05",
        "pinned_ap2_sha": PINNED_AP2,
        "fixture_origin": "official sd_jwt.create(add_decoy_claims=True), ephemeral authentic keys",
        "o1_issuer_signatures": "BOTH_VALID",
        "o2_agent_merchant_signatures_binding": "BOTH_VALID",
        "terminal_full": full_terminal,
        "terminal_decoy": decoy_terminal,
        "o3_full_commitments": full_scan,
        "o3_decoy_commitments": decoy_scan,
        "o3_decoy_residual_paths": [c["path"] for c in residual],
        "o3_decoy_residual_count": len(residual),
        "o3_independent_completeness_rejection": oracle_failure,
        "o4_official_schema_control": "VALID",
        "o4_official_schema_decoy_presented": "VALID",
        "o4_official_sdk_resolved_open_same": True,
        "o5_ruby_candidate": "NOT_RUN_IN_PYTHON",
        "oracle": "DEC05_REQUIRES_RUBY_ATTRIBUTABLE_REJECT",
        "ambiguity": "The signed digest alone does not disclose whether its hidden preimage was a decoy or an authority-bearing claim. Host policy rejects unknown commitment positions.",
        "non_go": "No general decoy exemption or business ALLOW; Phase 2-B HOLD",
    }
    p = Path(args.report)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print("DC05 O1/O2 genuine Issuer/Agent/Merchant signatures and binding: VALID")
    print("DC05 O3 unresolved signed decoy digests:", len(residual),
          "paths:", result["o3_decoy_residual_paths"])
    print("DC05 O4 actual presented official Open Schema FULL=VALID / decoy=VALID")
    print("DC05: SDK-resolved Open equality does not prove signed-wire completeness")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--fixture", required=True)
    p.add_argument("--schema", required=True)
    p.add_argument("--merchant-schema", required=True)
    p.add_argument("--report", required=True)
    main(p.parse_args())
