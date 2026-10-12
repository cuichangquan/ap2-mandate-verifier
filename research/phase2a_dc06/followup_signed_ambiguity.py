"""DC06 follow-up: authenticated repeated commitment and hidden second Open.

Research-only negative examples. The *pinned* AP2 issuer signs every Root
before presentation. Only public keys, JWTs and disclosures reach fixtures.
No generic authorization, payment, or Phase 2-B permission is produced.
"""
import argparse
import copy
import hashlib
import json
import sys
import time
from pathlib import Path

from jwcrypto.jwk import JWK
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

RESEARCH = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(RESEARCH / "phase2a_dc01"),
                str(RESEARCH / "phase2a_dc06"), str(RESEARCH / "p1_3")]
from independent_positive_oracle import (  # noqa: E402
    PINNED_AP2, b64url, decode64, jws_payload, raw_commitment_graph,
    require, segments, strict_json,
)
from generate_and_observe import make_metadata  # noqa: E402
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
from ap2.sdk.sdjwt import common, kb_sd_jwt

NAMES = ("full", "repeated_signed_root_digest",
         "two_signed_open_full", "two_signed_open_hidden")
EXTRA_MERCHANT = "merchant-hidden"


def digest(disclosure):
    return b64url(hashlib.sha256(disclosure.encode("ascii")).digest())


def issued_wire(claims, issuer):
    # Pinned AP2 issuing primitive, not a signature added by test code.
    return common.issue_sd_jwt(
        claims=claims, issuer_key=issuer,
        header_params=common.header_parameters(issuer),
        add_decoy_claims=False, serialization_format="compact",
    ).sd_jwt_issuance


def reachable_disclosures(item, mapping):
    """Digest closure of one actual signed Open array item, no SDK resolver."""
    needed = set()
    def scan(value):
        if isinstance(value, list):
            for part in value:
                scan(part)
        elif isinstance(value, dict):
            if set(value) == {"..."}:
                d = value["..."]
                require(d in mapping and d not in needed, "repeated/unknown digest in first subtree")
                needed.add(d)
                decoded = strict_json(decode64(mapping[d]))
                require(len(decoded) == 2, "non-array first subtree Disclosure")
                scan(decoded[1])
                return
            for k, v in value.items():
                if k == "_sd":
                    require(isinstance(v, list), "bad signed _sd in first subtree")
                    for d in v:
                        require(d in mapping and d not in needed, "missing/duplicate signed object digest")
                        needed.add(d)
                        decoded = strict_json(decode64(mapping[d]))
                        require(len(decoded) == 3, "non-object _sd Disclosure")
                        scan(decoded[2])
                else:
                    scan(v)
    scan(item)
    return needed


def create():
    issuer = JWK.generate(kty="EC", crv="P-256")
    agent = JWK.generate(kty="EC", crv="P-256")
    merchant = JWK.generate(kty="EC", crv="P-256")
    now = int(time.time())
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
        cnf={"jwk": json.loads(agent.export_public())},
        iat=now, exp=now + 3600,
    )
    metadata = make_metadata()
    normal = MandateClient().create(payloads=[mandate], issuer_key=issuer, sd=metadata)
    full_jws, full_disclosures = segments(normal)
    normal_signed = jws_payload(full_jws, json.loads(issuer.export_public()),
                                expected_typ="example+sd-jwt")
    first_marker = normal_signed["delegate_payload"][0]
    require(set(first_marker) == {"..."}, "baseline Open not signed-array disclosed")
    first_digest = first_marker["..."]
    require(first_digest in {digest(s) for s in full_disclosures},
            "baseline signed Open digest not disclosed")

    # Pinned AP2 primitive signs the *whole modified raw claim graph* anew.
    # Original immutable disclosure bytes are reused because their digest is
    # preserved in the freshly issuer-signed array placeholder. This is a
    # synthetic issuer-issued wire, NOT MandateClient facade output.
    repeated_claims = copy.deepcopy(normal_signed)
    repeated_claims["delegate_payload"] = [
        copy.deepcopy(first_marker), copy.deepcopy(first_marker)
    ]
    reissued = issued_wire(repeated_claims, issuer)
    repeated_jws = reissued.split("~", 1)[0]
    repeated_signed = jws_payload(repeated_jws,
                                  json.loads(issuer.export_public()),
                                  expected_typ="example+sd-jwt")
    require(repeated_signed["delegate_payload"] == repeated_claims["delegate_payload"],
            "official AP2 primitive did not sign repeated placeholder")
    repeated_root = "~".join([repeated_jws, *full_disclosures, ""])

    first = common.delegate_claims_from_model(mandate)
    second = copy.deepcopy(first)
    second["constraints"][1]["allowed"][0]["id"] = EXTRA_MERCHANT
    second["constraints"][1]["allowed"][0]["name"] = "Hidden Synthetic Merchant"
    sd_root = DisclosureMetadata(children={
        "delegate_payload": DisclosureMetadata(
            disclose_all=True, all_array_children=metadata,
        ),
    }).apply({"delegate_payload": [first, second]})
    two_full = issued_wire(sd_root, issuer)
    double_jws, double_disclosures = segments(two_full)
    double_signed = jws_payload(double_jws,
                                json.loads(issuer.export_public()),
                                expected_typ="example+sd-jwt")
    delegate = double_signed["delegate_payload"]
    require(len(delegate) == 2 and all(set(m) == {"..."} for m in delegate) and
            delegate[0]["..."] != delegate[1]["..."],
            "second independently signed delegate payload absent")

    mapping = {digest(s): s for s in double_disclosures}
    require(len(mapping) == len(double_disclosures), "unexpected duplicate disclosures")
    first_closure = reachable_disclosures(delegate[0], mapping)
    second_closure = reachable_disclosures(delegate[1], mapping)
    require(delegate[0]["..."] in first_closure and
            delegate[1]["..."] in second_closure and
            not (first_closure & second_closure),
            "independent signed authority digest closures overlap")
    kept = [s for s in double_disclosures if digest(s) in first_closure]
    require(len(kept) == len(first_closure) and len(kept) < len(double_disclosures),
            "did not withhold exactly the second signed Open subtree")
    two_hidden = "~".join([double_jws, *kept, ""])
    require(segments(two_hidden)[0] == double_jws and
            digest(mapping[delegate[1]["..."]]) == delegate[1]["..."] and
            delegate[1]["..."] not in {digest(x) for x in kept},
            "second Issuer-signed Open not genuinely hidden")

    roots = {
        "full": normal,
        "repeated_signed_root_digest": repeated_root,
        "two_signed_open_full": two_full,
        "two_signed_open_hidden": two_hidden,
    }
    host_jwt = merchant_signed_jwt(merchant, checkout_json())
    closed = CheckoutMandate(
        checkout_jwt=host_jwt,
        checkout_hash=b64url(hashlib.sha256(host_jwt.encode("ascii")).digest()),
        iat=now, exp=now + 3600,
    )
    terminals = {
        name: kb_sd_jwt.create(
            prev_token=common.parse_token(root), holder_key=agent,
            payload=closed, aud=AUD, nonce=NONCE,
            sd=DisclosureMetadata(), hash_mode="sd_hash",
        ).sd_jwt_issuance
        for name, root in roots.items()
    }
    f = {
        "case_id": "DC06-FOLLOWUP",
        "ap2_commit": PINNED_AP2,
        "source_boundary": "pinned common.issue_sd_jwt; synthetic raw signed commitment graph, not official mandate facade",
        "roots": roots, "terminals": terminals,
        "trusted_issuer_public_jwk": json.loads(issuer.export_public()),
        "expected_agent_public_jwk": json.loads(agent.export_public()),
        "trusted_merchant_public_jwk": json.loads(merchant.export_public()),
        "expected_aud": AUD, "expected_nonce": NONCE,
        "host_checkout_jwt": host_jwt,
        "expected_checkout_id": "checkout-001",
        "expected_merchant_id": "merchant-allowed",
        "expected_currency": "USD", "expected_total_minor": 2400,
        "original_open_digest": first_digest,
        "second_signed_open_digest": delegate[1]["..."],
        "first_signed_open_digest": delegate[0]["..."],
        "withheld_second_subtree_digests": sorted(second_closure),
        "retained_first_subtree_digests": sorted(first_closure),
    }
    for key in ("trusted_issuer_public_jwk", "expected_agent_public_jwk",
                "trusted_merchant_public_jwk"):
        require("d" not in f[key], "private issuer/Agent/Merchant key forbidden")
    return f


def observe(f, schema_path, merchant_schema_path):
    require(f["case_id"] == "DC06-FOLLOWUP" and
            f["ap2_commit"] == PINNED_AP2, "wrong pinned follow-up input")
    schema = strict_json(Path(schema_path).read_bytes())
    ms = strict_json(Path(merchant_schema_path).read_bytes())
    registry = Registry().with_resource(schema["$id"], Resource.from_contents(schema))
    registry = registry.with_resource(ms["$id"], Resource.from_contents(ms))
    validator = Draft202012Validator(schema, registry=registry)
    checkout = jws_payload(f["host_checkout_jwt"], f["trusted_merchant_public_jwk"],
                           expected_typ="JWT")
    require(checkout["id"] == f["expected_checkout_id"] and
            checkout["merchant"]["id"] == f["expected_merchant_id"] and
            checkout["currency"] == f["expected_currency"] and
            next(t["amount"] for t in checkout["totals"] if t["type"] == "total") ==
            f["expected_total_minor"], "signed Merchant Host Checkout mismatch")

    cases = {}
    for name in NAMES:
        root = f["roots"][name]
        terminal = f["terminals"][name]
        root_jws, disclosures = segments(root)
        payload = jws_payload(root_jws, f["trusted_issuer_public_jwk"],
                              expected_typ="example+sd-jwt")
        require(payload.get("_sd_alg") in (None, "sha-256"), "unknown hash mode")
        items = payload["delegate_payload"]
        require(isinstance(items, list) and len(items) in (1, 2),
                "unsupported signed delegate shape")
        mapping = {digest(s): s for s in disclosures}
        require(len(mapping) == len(disclosures), "duplicate Disclosure bytes")
        require(set(items[0]) == {"..."} and items[0]["..."] in mapping,
                "Issuer did not sign disclosed first Open")
        first_arr = strict_json(decode64(mapping[items[0]["..."]]))
        require(len(first_arr) == 2 and isinstance(first_arr[1], dict),
                "bad signed first Open Disclosure")
        first_open = first_arr[1]
        require(first_open["vct"] == "mandate.checkout.open.1" and
                first_open["cnf"]["jwk"] == f["expected_agent_public_jwk"],
                "first signed Open/Agent mismatch")
        t_jws, t_disclosures = segments(terminal)
        term = jws_payload(t_jws, f["expected_agent_public_jwk"],
                           expected_typ="kb+sd-jwt")
        require(term["sd_hash"] == digest(root) and
                term["aud"] == f["expected_aud"] and
                term["nonce"] == f["expected_nonce"],
                "Agent Terminal signature, sd_hash or Host challenge invalid")
        resolved_terminal, graph_t = raw_commitment_graph(term, t_disclosures)
        require(len(graph_t) == 1 and graph_t[0]["path"] == "$/delegate_payload/0",
                "unexpected signed Terminal graph")
        closed = resolved_terminal["delegate_payload"][0]
        require(closed["checkout_jwt"] == f["host_checkout_jwt"] and
                closed["checkout_hash"] == digest(f["host_checkout_jwt"]),
                "Merchant JWT bytes/hash not Host-bound")

        if name == "full":
            resolved, graph = raw_commitment_graph(payload, disclosures)
            require(len(resolved["delegate_payload"]) == 1 and len(graph) == 3,
                    "FULL authority graph drifted")
            opened = resolved["delegate_payload"][0]
            require(not list(validator.iter_errors(opened)), "FULL Open Schema INVALID")
            cases[name] = {"issuer_agent_merchant": "VALID",
                           "official_first_open_schema": "VALID",
                           "signed_root_cardinality": 1, "graph_commitments": len(graph)}
        elif name == "repeated_signed_root_digest":
            require(len(items) == 2 and items[0] == items[1] and
                    items[0]["..."] == f["original_open_digest"] and
                    digest(mapping[items[0]["..."]]) == items[0]["..."],
                    "Root contains no actual twice-signed digest")
            err = None
            try:
                raw_commitment_graph(payload, disclosures)
            except ValueError as e:
                err = str(e)
            require(err == "repeated signed commitment", "independent repeated digest not detected")
            first_resolved, graph = raw_commitment_graph(
                {"delegate_payload": [items[0]]}, disclosures)
            require(len(first_resolved["delegate_payload"]) == 1 and
                    not list(validator.iter_errors(first_resolved["delegate_payload"][0])),
                    "first Open not genuine Schema VALID")
            cases[name] = {"issuer_agent_merchant": "VALID",
                           "official_first_open_schema": "VALID",
                           "signed_root_cardinality": 2,
                           "same_digest_positions": ["$/delegate_payload/0", "$/delegate_payload/1"],
                           "independent_duplicate": err, "first_graph_commitments": len(graph)}
        else:
            require(len(items) == 2 and items[0]["..."] != items[1]["..."] and
                    items[0]["..."] == f["first_signed_open_digest"] and
                    items[1]["..."] == f["second_signed_open_digest"],
                    "not two separately signed Open commitments")
            first_reachable = reachable_disclosures(items[0], mapping)
            require(first_reachable == set(f["retained_first_subtree_digests"]),
                    "first signed subtree incomplete")
            first_kept = [s for s in disclosures if digest(s) in first_reachable]
            first_resolved, graph = raw_commitment_graph(
                {"delegate_payload": [items[0]]}, first_kept)
            require(len(first_resolved["delegate_payload"]) == 1 and
                    not list(validator.iter_errors(first_resolved["delegate_payload"][0])),
                    "visible first Open Schema INVALID")
            if name == "two_signed_open_full":
                all_resolved, graph_all = raw_commitment_graph(payload, disclosures)
                require(len(all_resolved["delegate_payload"]) == 2 and
                        len(graph_all) == 6, "fully disclosed double authority incomplete")
                second_open = all_resolved["delegate_payload"][1]
                require(not list(validator.iter_errors(second_open)) and
                        second_open["constraints"][1]["allowed"][0]["id"] ==
                        EXTRA_MERCHANT, "second signed Open authority wrong")
                cases[name] = {"issuer_agent_merchant": "VALID",
                               "official_first_open_schema": "VALID",
                               "official_second_open_schema": "VALID",
                               "signed_root_cardinality": 2,
                               "graph_commitments": len(graph_all)}
            else:
                require(items[1]["..."] not in mapping and
                        set(f["withheld_second_subtree_digests"]).isdisjoint(mapping),
                        "second signed Open actually disclosed")
                reason = None
                try:
                    raw_commitment_graph(payload, disclosures)
                except ValueError as e:
                    reason = str(e)
                require(reason == "incomplete_disclosure: signed commitment not disclosed",
                        "independent whole-wire missing signed second authority not detected")
                cases[name] = {"issuer_agent_merchant": "VALID",
                               "official_first_open_schema": "VALID",
                               "official_second_open_schema": "UNAVAILABLE_UNDISCLOSED",
                               "signed_root_cardinality": 2,
                               "signed_second_digest": items[1]["..."],
                               "independent_incomplete": reason,
                               "first_graph_commitments": len(graph)}
    require(segments(f["roots"]["two_signed_open_full"])[0] ==
            segments(f["roots"]["two_signed_open_hidden"])[0] and
            f["terminals"]["two_signed_open_full"] !=
            f["terminals"]["two_signed_open_hidden"],
            "hidden second Root did not retain signed JWS or re-sign Agent")
    return {
        "case_id": "DC06-FOLLOWUP", "pinned_ap2_sha": PINNED_AP2,
        "cases": cases,
        "o1_o4": "ISSUER_AGENT_MERCHANT_SIGNATURES_AND_FULL_FIRST_OPEN_SCHEMA_VERIFIED",
        "o5": "NOT_RUN",
        "scope": "two additional genuinely signed patterns; early structural guard, not generic SD-JWT",
        "phase_2b": "HOLD",
    }


def store(out, f, obs):
    out.mkdir(parents=True, exist_ok=True)
    for name in NAMES:
        jws, ds = segments(f["roots"][name])
        (out / f"{name}-issuer-jws.txt").write_text(jws)
        (out / f"{name}-root.txt").write_text(f["roots"][name])
        (out / f"{name}-terminal.txt").write_text(f["terminals"][name])
        for i, disclosure in enumerate(ds):
            (out / f"{name}-disclosure-{i:02d}.txt").write_text(disclosure)
    (out / "host-merchant-jws.txt").write_text(f["host_checkout_jwt"])
    (out / "public-fixture.json").write_text(json.dumps(f, sort_keys=True, indent=2) + "\n")
    (out / "python-observation.json").write_text(json.dumps(obs, sort_keys=True, indent=2) + "\n")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--fixture", required=True)
    p.add_argument("--schema", required=True)
    p.add_argument("--merchant-schema", required=True)
    p.add_argument("--replay-dir", required=True)
    a = p.parse_args()
    f = create()
    obs = observe(f, a.schema, a.merchant_schema)
    dest = Path(a.fixture)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(f, sort_keys=True, indent=2) + "\n")
    store(Path(a.replay_dir), f, obs)
    for name, entry in obs["cases"].items():
        print(f"DC06 follow-up {name}: signed {entry['issuer_agent_merchant']} "
              f"first Schema {entry['official_first_open_schema']}")
    print("DC06 follow-up: Ruby not yet run; Phase 2-B HOLD")
