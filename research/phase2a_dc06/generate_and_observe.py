"""DC06 genuinely Issuer-signed unknown authority layouts, fixed profile ONLY.

Pinned official AP2 signing primitives issue every modified signed Root.
The Ruby verifier never imports fixture claims as trusted without JWS checks.
All signing secrets are ephemeral and deliberately not returned/saved.
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
sys.path[:0] = [str(RESEARCH / "phase2a_dc01"), str(RESEARCH / "p1_3")]
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
from ap2.sdk.sdjwt import common, kb_sd_jwt

VARIANTS = (
    "full", "signed_root_sibling", "signed_nested_unknown",
    "signed_nested_sd_full", "signed_nested_sd_hidden",
)
UNKNOWN_KEY = "future_authority_policy"
EXPECTED_PATHS = {
    "$/delegate_payload/0",
    "$/delegate_payload/0/disclosed/constraints/1/allowed/0",
    "$/delegate_payload/0/disclosed/constraints/0/items/0/acceptable_items/0",
}


def make_metadata(extra_nested_sd=False):
    return DisclosureMetadata(children={
        "constraints": DisclosureMetadata(array_children={
            0: DisclosureMetadata(children={
                "items": DisclosureMetadata(array_children={
                    0: DisclosureMetadata(children={
                        "acceptable_items": DisclosureMetadata(sd_array_indices=[0]),
                    }),
                }),
            }),
            1: DisclosureMetadata(
                sd_keys=[UNKNOWN_KEY] if extra_nested_sd else [],
                children={"allowed": DisclosureMetadata(sd_array_indices=[0])},
            ),
        }),
    })


def create_fixture():
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
            AllowedMerchants(allowed=[Merchant(
                id="merchant-allowed", name="Research Merchant",
            )]),
        ],
        cnf={"jwk": json.loads(agent.export_public())},
        iat=now, exp=now + 3600,
    )
    metadata = make_metadata()
    full = MandateClient().create(payloads=[mandate], issuer_key=issuer, sd=metadata)
    base = common.delegate_claims_from_model(mandate)

    def issue_modified(claims, meta, extra_claims=None):
        transformed = common.selectively_disclosable_claims(
            claims, meta, extra_claims=extra_claims,
        )
        return common.issue_sd_jwt(
            claims=transformed, issuer_key=issuer,
            header_params=common.header_parameters(issuer),
            add_decoy_claims=False, serialization_format="compact",
        ).sd_jwt_issuance

    # This Root sibling is not naturally emitted by MandateClient.create.
    # Official pinned SD-JWT signing primitives issue and authenticate it.
    sibling = issue_modified(
        copy.deepcopy(base), metadata,
        extra_claims={"future_root_authority": {"scope": "unknown"}},
    )
    nested = copy.deepcopy(base)
    nested["constraints"][1][UNKNOWN_KEY] = {"scope": "new-merchant-rule"}
    nested_visible = issue_modified(nested, metadata)
    nested_sd_full = issue_modified(nested, make_metadata(extra_nested_sd=True))
    sd_jws, sd_disc = segments(nested_sd_full)
    hidden_segments = [
        d for d in sd_disc
        if (lambda entry: isinstance(entry, list) and len(entry) == 3
            and entry[1] == UNKNOWN_KEY)(strict_json(decode64(d)))
    ]
    require(len(hidden_segments) == 1, "official signed object SD disclosure not emitted")
    hidden_root = "~".join([
        sd_jws, *(d for d in sd_disc if d != hidden_segments[0]), "",
    ])
    require(len(segments(hidden_root)[1]) == len(sd_disc) - 1, "non-single withholding")

    roots = {
        "full": full, "signed_root_sibling": sibling,
        "signed_nested_unknown": nested_visible,
        "signed_nested_sd_full": nested_sd_full,
        "signed_nested_sd_hidden": hidden_root,
    }
    signed_merchant = merchant_signed_jwt(merchant, checkout_json())
    closed = CheckoutMandate(
        checkout_jwt=signed_merchant,
        checkout_hash=b64url(hashlib.sha256(signed_merchant.encode("ascii")).digest()),
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
        "case_id": "DC06", "ap2_commit": PINNED_AP2,
        "fixture_origin": "official AP2 v0.2 SDK MandateClient/common.issue_sd_jwt",
        "roots": roots, "terminals": terminals,
        "trusted_issuer_public_jwk": json.loads(issuer.export_public()),
        "expected_agent_public_jwk": json.loads(agent.export_public()),
        "trusted_merchant_public_jwk": json.loads(merchant.export_public()),
        "expected_aud": AUD, "expected_nonce": NONCE,
        "host_checkout_jwt": signed_merchant,
        "expected_checkout_id": "checkout-001",
        "expected_merchant_id": "merchant-allowed",
        "expected_currency": "USD", "expected_total_minor": 2400,
        "hidden_authority_disclosure_sha256": b64url(
            hashlib.sha256(hidden_segments[0].encode("ascii")).digest()),
    }
    require(set(f["roots"]) == set(VARIANTS), "wrong signed case count")
    for key in ("trusted_issuer_public_jwk", "expected_agent_public_jwk",
                "trusted_merchant_public_jwk"):
        require("d" not in f[key], "private JWK forbidden")
    return f


def observe(f, schema_path, merchant_schema_path):
    require(f["ap2_commit"] == PINNED_AP2, "unpinned upstream")
    signed_merchant = jws_payload(
        f["host_checkout_jwt"], f["trusted_merchant_public_jwk"],
        expected_typ="JWT",
    )
    require(signed_merchant["id"] == f["expected_checkout_id"]
            and signed_merchant["merchant"]["id"] == f["expected_merchant_id"]
            and signed_merchant["currency"] == f["expected_currency"]
            and next(x["amount"] for x in signed_merchant["totals"]
                     if x["type"] == "total") == f["expected_total_minor"],
            "Merchant signed Host Checkout mismatch")
    schema = strict_json(Path(schema_path).read_bytes())
    ms = strict_json(Path(merchant_schema_path).read_bytes())
    registry = Registry().with_resource(schema["$id"], Resource.from_contents(schema))
    registry = registry.with_resource(ms["$id"], Resource.from_contents(ms))
    validator = Draft202012Validator(schema, registry=registry)

    cases = {}
    for name in VARIANTS:
        root, terminal = f["roots"][name], f["terminals"][name]
        root_jws, disclosures = segments(root)
        issuer_claims = jws_payload(root_jws, f["trusted_issuer_public_jwk"])
        header = strict_json(decode64(root_jws.split(".")[0]))
        require(header.get("alg") == "ES256" and header.get("typ") == "example+sd-jwt",
                "Root JOSE signed profile mismatch")
        t_jws, t_disclosures = segments(terminal)
        signed_terminal = jws_payload(
            t_jws, f["expected_agent_public_jwk"], expected_typ="kb+sd-jwt",
        )
        require(signed_terminal.get("sd_hash") ==
                b64url(hashlib.sha256(root.encode("ascii")).digest()),
                "Agent Terminal not bound to exact signed Root wire")
        require(signed_terminal.get("aud") == f["expected_aud"] and
                signed_terminal.get("nonce") == f["expected_nonce"],
                "invalid Host audience/nonce")
        resolved_terminal, t_graph = raw_commitment_graph(
            signed_terminal, t_disclosures)
        require(len(t_graph) == 1 and t_graph[0]["path"] == "$/delegate_payload/0",
                "unsupported Terminal commitment")
        closed = resolved_terminal["delegate_payload"][0]
        require(closed["checkout_jwt"] == f["host_checkout_jwt"] and
                closed["checkout_hash"] == b64url(hashlib.sha256(
                    f["host_checkout_jwt"].encode("ascii")).digest()),
                "Merchant Checkout JWT/hash not Host-bound")

        signed_path = None
        if name == "signed_nested_sd_hidden":
            # Genuine hidden signed digest; do NOT fill from FULL before Schema.
            require(segments(f["roots"]["signed_nested_sd_full"])[0] == root_jws,
                    "hidden case changed signed Issuer JWS")
            reason = None
            try:
                raw_commitment_graph(issuer_claims, disclosures)
            except ValueError as e:
                reason = str(e)
            require(reason == "incomplete_disclosure: signed commitment not disclosed",
                    "signed missing field did not cause independent incomplete-disclosure")
            signed_path = "$/delegate_payload/0/disclosed/constraints/1/_sd"
            # Official presented schema must be obtained from the real partial
            # presentation instead of pre-filling the missing signed value.
            from jwcrypto.jwk import JWK
            from ap2.sdk.sdjwt.chain import verify_chain
            presented = verify_chain(
                [common.parse_token(root), common.parse_token(terminal)],
                public_key_provider=lambda _t: JWK.from_json(
                    json.dumps(f["trusted_issuer_public_jwk"])),
                expected_aud=f["expected_aud"], expected_nonce=f["expected_nonce"],
            )[0]
            errors = list(validator.iter_errors(presented))
            cases[name] = {
                "issuer_agent_merchant_signatures": "VALID",
                "raw_completeness": reason,
                "signed_unknown_path": signed_path,
                "official_schema_presented": "INVALID" if errors else "VALID",
                "official_schema_error_validators": [e.validator for e in errors],
                "signed_root_jws_sha256": hashlib.sha256(root_jws.encode("ascii")).hexdigest(),
            }
            continue

        resolved, graph = raw_commitment_graph(issuer_claims, disclosures)
        require(len(graph) == 3 and {g["path"] for g in graph} == EXPECTED_PATHS,
                "mutated case did not preserve known signed array graph")
        opened = resolved["delegate_payload"][0]
        errors = list(validator.iter_errors(opened))
        if name == "full":
            require(not errors, "normal control official Open Schema invalid")
            require(set(resolved) <= {"delegate_payload", "_sd_alg"},
                    "control unexpected Root sibling")
            require(set(opened) == {"vct", "constraints", "cnf", "iat", "exp"},
                    "control unexpected Open field")
        elif name == "signed_root_sibling":
            require("future_root_authority" in issuer_claims and
                    resolved["delegate_payload"][0]["constraints"] ==
                    cases["full"]["opened_constraints"],
                    "signed extra Root claim did not preserve normal Open authority")
            signed_path = "$/future_root_authority"
        else:
            require(UNKNOWN_KEY in opened["constraints"][1],
                    "unknown nested authority field not issued and signed")
            signed_path = "$/delegate_payload/0/disclosed/constraints/1/" + UNKNOWN_KEY
            if name == "signed_nested_sd_full":
                require(len(disclosures) == 4, "hidden object SD not fully revealed")
        cases[name] = {
            "issuer_agent_merchant_signatures": "VALID",
            "official_schema_presented": "INVALID" if errors else "VALID",
            "official_schema_error_validators": [e.validator for e in errors],
            "signed_unknown_path": signed_path,
            "signed_root_jws_sha256": hashlib.sha256(root_jws.encode("ascii")).hexdigest(),
            "full_graph_count": len(graph),
        }
        if name == "full":
            cases[name]["opened_constraints"] = opened["constraints"]
    # A full-disclosure signed unknown object and its hidden variant MUST
    # have same signed Root JWS but different exact Root bytes/Terminal hash.
    require(f["roots"]["signed_nested_sd_full"] !=
            f["roots"]["signed_nested_sd_hidden"], "negative did not hide disclosure")
    require(f["terminals"]["signed_nested_sd_full"] !=
            f["terminals"]["signed_nested_sd_hidden"], "Agent did not re-sign on withheld field")
    require(cases["full"]["official_schema_presented"] == "VALID",
            "positive precondition invalid")

    return {
        "case_id": "DC06", "pinned_ap2_sha": PINNED_AP2,
        "oracle_boundary": "genuine issuer-signed unknown claims; not post-signature JSON tampering",
        "o1_o2": "ALL_CASES_VALID_SIGNATURES_AND_BINDING",
        "o3_o4_cases": cases,
        "o5_ruby": "NOT_YET_RUN",
        "not_run": [
            "truly repeated issuer-signed digest/placeholder",
            "second hidden delegate_payload authority candidate",
        ],
        "outcome_before_o5": "NOT_DC06_SECURITY_PASS",
        "phase_2b": "HOLD",
    }


def save(directory, f, observation):
    directory.mkdir(parents=True, exist_ok=True)
    for name in VARIANTS:
        root, terminal = f["roots"][name], f["terminals"][name]
        jws, disclosures = segments(root)
        (directory / f"{name}-root-jws.txt").write_text(jws)
        (directory / f"{name}-root-sdjwt.txt").write_text(root)
        (directory / f"{name}-terminal-sdjwt.txt").write_text(terminal)
        for i, disclosure in enumerate(disclosures):
            (directory / f"{name}-disclosure-{i:02d}.txt").write_text(disclosure)
    (directory / "merchant-jwt.txt").write_text(f["host_checkout_jwt"])
    (directory / "synthetic-public-fixture.json").write_text(
        json.dumps(f, sort_keys=True, indent=2) + "\n")
    (directory / "python-oracle.json").write_text(
        json.dumps(observation, sort_keys=True, indent=2) + "\n")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--fixture", required=True)
    p.add_argument("--schema", required=True)
    p.add_argument("--merchant-schema", required=True)
    p.add_argument("--replay-dir", required=True)
    args = p.parse_args()
    f = create_fixture()
    obs = observe(f, args.schema, args.merchant_schema)
    path = Path(args.fixture)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(f, sort_keys=True, indent=2) + "\n")
    save(Path(args.replay_dir), f, obs)
    print("DC06 O1/O2 genuinely signed issuer/Agent/Merchant chains checked")
    for key, value in obs["o3_o4_cases"].items():
        print(key, "Schema", value["official_schema_presented"],
              "signed unknown:", value["signed_unknown_path"])
    print("DC06 O5 Ruby not run; CI green is NOT gate pass")
