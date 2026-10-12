"""DC01-only synthetic signed positive oracle. No payments, no production API.

Independent signed-wire traversal uses the original issuer JWS payload, not
the AP2 SDK's resolved payload or Ruby verifier's resolver. All keys are public.
Run only against the fixed AP2 v0.2.0 source and transient synthetic fixtures.
"""
import argparse
import base64
import hashlib
import json
import re
import time
from pathlib import Path

from jwcrypto import jws
from jwcrypto.jwk import JWK
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

PINNED_AP2 = "b4587ac1d055888a73b4b21750973cffba961793"
B64 = re.compile(r"^[A-Za-z0-9_-]+$")


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def b64url(data):
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def decode64(s):
    require(isinstance(s, str) and B64.fullmatch(s) is not None, "noncanonical base64url")
    data = base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))
    require(b64url(data) == s, "noncanonical base64url")
    return data


def strict_json(data):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, "duplicate signed JSON key")
            result[key] = value
        return result
    return json.loads(data, object_pairs_hook=pairs, parse_constant=lambda x: require(False, "nonfinite JSON"))


def jws_payload(compact, public_jwk, expected_typ=None):
    parts = compact.split(".")
    require(len(parts) == 3 and all(parts), "invalid compact JWS")
    header = strict_json(decode64(parts[0]))
    payload = strict_json(decode64(parts[1]))
    require(isinstance(header, dict) and isinstance(payload, dict), "nonobject signed JOSE")
    require(header.get("alg") == "ES256", "non-ES256 JWS")
    require(not (set(header) & {"jwk", "jku", "x5c", "x5u", "crit"}), "untrusted JOSE parameters")
    if expected_typ is not None:
        require(header.get("typ") == expected_typ, "unexpected JWS typ")
    verifier = jws.JWS()
    verifier.deserialize(compact)
    verifier.verify(JWK.from_json(json.dumps(public_jwk)))
    return payload


def segments(wire):
    require(isinstance(wire, str) and wire.endswith("~") and len(wire) <= 32768, "bad SD-JWT serialization")
    parts = wire.split("~")
    require(len(parts) >= 3 and parts[-1] == "", "missing disclosures or bad delimiter")
    require(1 <= len(parts[1:-1]) <= 16 and all(parts[1:-1]), "invalid disclosure count")
    return parts[0], parts[1:-1]


def raw_commitment_graph(signed_payload, disclosures):
    """Traverse the WHOLE signed root payload before deciding allowed paths."""
    mapping = {}
    for part in disclosures:
        decoded = strict_json(decode64(part))
        require(isinstance(decoded, list) and len(decoded) in (2, 3), "malformed Disclosure")
        require(isinstance(decoded[0], str) and len(decoded[0]) >= 8, "bad Disclosure salt")
        if len(decoded) == 3:
            require(isinstance(decoded[1], str), "invalid object Disclosure key")
        digest = b64url(hashlib.sha256(part.encode("ascii")).digest())
        require(digest not in mapping, "duplicate Disclosure digest")
        mapping[digest] = decoded

    seen = set()
    graph = []

    def consume(digest, path, kind):
        require(isinstance(digest, str), "non-string commitment")
        graph.append({"path": path, "kind": kind, "digest_sha256": digest})
        require(digest in mapping, "incomplete_disclosure: signed commitment not disclosed")
        require(digest not in seen, "repeated signed commitment")
        seen.add(digest)
        return mapping[digest]

    def resolve(value, path):
        if isinstance(value, list):
            out = []
            for idx, item in enumerate(value):
                here = f"{path}/{idx}"
                if isinstance(item, dict) and set(item) == {"..."}:
                    disclosed = consume(item["..."], here, "array")
                    require(len(disclosed) == 2, "wrong array-element Disclosure")
                    out.append(resolve(disclosed[1], here + "/disclosed"))
                else:
                    out.append(resolve(item, here))
            return out
        if isinstance(value, dict):
            out = {}
            for key, item in value.items():
                if key == "_sd":
                    continue
                require(key != "...", "unsupported stray signed array placeholder")
                out[key] = resolve(item, path + "/" + key)
            if "_sd" in value:
                sd = value["_sd"]
                require(isinstance(sd, list), "bad _sd digest list")
                for digest in sd:
                    disclosed = consume(digest, path + "/_sd", "object")
                    require(len(disclosed) == 3, "wrong object-property Disclosure")
                    name = disclosed[1]
                    require(name not in out and name not in ("_sd", "..."), "duplicate/unsupported disclosed property")
                    out[name] = resolve(disclosed[2], path + "/" + name)
            return out
        return value

    resolved = resolve(signed_payload, "$")
    require(len(seen) == len(mapping), "unused Disclosure")
    return resolved, graph


def save_artifacts(folder, fixture, root, root_jws, root_disclosures, terminal, terminal_jws, terminal_disclosures, merchant):
    folder.mkdir(parents=True, exist_ok=True)
    records = []

    def store(name, raw):
        require(isinstance(raw, str) and raw.isascii(), "non-ASCII replay wire")
        data = raw.encode("ascii")
        filename = f"{name}.txt"
        (folder / filename).write_bytes(data)
        records.append({"path": filename, "sha256": hashlib.sha256(data).hexdigest(), "byte_length": len(data)})

    store("root-jws", root_jws)
    for i, disclosure in enumerate(root_disclosures):
        store(f"root-disclosure-{i:02d}", disclosure)
    store("root-sdjwt", root)
    store("terminal-jws", terminal_jws)
    for i, disclosure in enumerate(terminal_disclosures):
        store(f"terminal-disclosure-{i:02d}", disclosure)
    store("terminal-sdjwt", terminal)
    store("merchant-jwt", merchant)
    store("chain", root.removesuffix("~") + "~~" + terminal)
    # Entire input is strictly synthetic and contains public JWKs and signed
    # wires; private key material MUST NOT be present before saving.
    require(not any(isinstance(v, dict) and "d" in v for k, v in fixture.items() if "jwk" in k), "private JWK in input")
    require("PRIVATE KEY" not in json.dumps(fixture), "private key in input")
    (folder / "synthetic-fixture.json").write_text(json.dumps(fixture, indent=2, sort_keys=True) + "\n")
    data = (folder / "synthetic-fixture.json").read_bytes()
    records.append({"path": "synthetic-fixture.json", "sha256": hashlib.sha256(data).hexdigest(), "byte_length": len(data)})
    manifest = {"source": "synthetic official AP2 v0.2 P1-3 generator", "pinned_ap2_sha": PINNED_AP2, "files": records,
                "issuer_public_jwk": fixture["trusted_issuer_public_jwk"],
                "agent_public_jwk": fixture["expected_agent_public_jwk"],
                "merchant_public_jwk": fixture["trusted_merchant_public_jwk"],
                "host_expected_aud": fixture["expected_aud"], "host_expected_nonce": fixture["expected_nonce"],
                "host_checkout_id": fixture["expected_checkout_id"], "host_merchant_id": fixture["expected_merchant_id"],
                "host_expected_currency": fixture["expected_currency"], "host_total_minor": fixture["expected_total_minor"]}
    (folder / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return manifest


def run(args):
    fixture = strict_json(Path(args.fixture).read_bytes())
    require(fixture["ap2_commit"] == PINNED_AP2, "wrong pinned AP2 commit")
    root, terminal, merchant = (fixture["root_open_sdjwt"], fixture["valid_terminal"], fixture["host_checkout_jwt"])
    root_jws, root_disclosures = segments(root)
    terminal_jws, terminal_disclosures = segments(terminal)
    require(len(root) <= 32768 and len(terminal) <= 32768, "oversized tokens")

    # O1 / O2 signatures use jwcrypto directly; no AP2 resolved dicts.
    root_signed = jws_payload(root_jws, fixture["trusted_issuer_public_jwk"])
    require(set(root_signed) <= {"delegate_payload", "_sd", "_sd_alg"}, "unknown signed root sibling claim")
    root_resolved, root_graph = raw_commitment_graph(root_signed, root_disclosures)
    # Candidate A requires a versioned, EXACT issuer commitment layout, not
    # merely a zero-residual disclosure graph. Even a *fully disclosed* new
    # root-level _sd or nested placeholder is unsupported. The two allowed
    # array paths come from the narrowly pinned P1-3 issuer metadata:
    # delegate_payload[0] and constraints[1] (allowed Merchants).
    allowed_root_commitments = {
        ("$/delegate_payload/0", "array"),
        ("$/delegate_payload/0/disclosed/constraints/1", "array"),
    }
    observed_root_commitments = {(x["path"], x["kind"]) for x in root_graph}
    require(len(root_graph) == len(allowed_root_commitments) and
            observed_root_commitments == allowed_root_commitments,
            "unsupported_profile: unknown signed Root commitment path or kind")
    require(set(root_resolved) <= {"delegate_payload", "_sd_alg"}, "unknown resolved root claim")
    require(root_resolved.get("_sd_alg") in (None, "sha-256"), "unsupported SD hash algorithm")
    require(len(root_resolved.get("delegate_payload", [])) == 1, "not exactly one signed Open")
    opened = root_resolved["delegate_payload"][0]
    require(isinstance(opened, dict) and set(opened) == {"vct", "constraints", "cnf", "iat", "exp"}, "unknown Open claim layout")
    require(opened["vct"] == "mandate.checkout.open.1", "wrong signed mandate type")
    require(isinstance(opened["iat"], int) and isinstance(opened["exp"], int), "bad Open time")
    require(opened["iat"] <= int(time.time()) < opened["exp"], "Open outside validity window")
    require(opened["exp"] - opened["iat"] <= 7200, "Open TTL over research bound")
    agent = opened["cnf"]["jwk"]
    require(agent == fixture["expected_agent_public_jwk"], "Host agent key mismatch")
    terminal_signed = jws_payload(terminal_jws, agent, expected_typ="kb+sd-jwt")
    require(terminal_signed.get("sd_hash") == b64url(hashlib.sha256(root.encode("ascii")).digest()),
            "invalid Terminal sd_hash")
    require("issuer_jwt_hash" not in terminal_signed, "unexpected alternative hash mode")
    require(terminal_signed.get("aud") == fixture["expected_aud"], "Terminal aud mismatch")
    require(terminal_signed.get("nonce") == fixture["expected_nonce"], "Terminal nonce mismatch")
    require(isinstance(terminal_signed.get("iat"), int), "Terminal iat missing")
    term_resolved, terminal_graph = raw_commitment_graph(terminal_signed, terminal_disclosures)
    # Terminal has exactly one SD-wrapped Closed payload in this subset.
    require(len(terminal_graph) == 1 and
            (terminal_graph[0]["path"], terminal_graph[0]["kind"]) ==
            ("$/delegate_payload/0", "array"),
            "unsupported_profile: unknown signed Terminal commitment layout")
    require(len(term_resolved.get("delegate_payload", [])) == 1, "invalid terminal delegate_payload")
    closed = term_resolved["delegate_payload"][0]
    require(isinstance(closed, dict) and closed.get("vct") == "mandate.checkout.1", "invalid Closed mandate")
    require(closed.get("checkout_jwt") == merchant, "Host merchant JWT bytes mismatch")
    require(closed.get("checkout_hash") == b64url(hashlib.sha256(merchant.encode("ascii")).digest()),
            "wrong Host checkout_hash")
    checkout = jws_payload(merchant, fixture["trusted_merchant_public_jwk"], expected_typ="JWT")
    require(checkout.get("id") == fixture["expected_checkout_id"], "wrong Checkout ID")
    require(checkout.get("merchant", {}).get("id") == fixture["expected_merchant_id"], "wrong Merchant ID")
    require(checkout.get("currency") == fixture["expected_currency"], "wrong currency")

    # O4: pinned official schema + separate tighter supported subset.
    schema = strict_json(Path(args.schema).read_bytes())
    merchant_schema = strict_json(Path(args.merchant_schema).read_bytes())
    registry = Registry().with_resource(schema["$id"], Resource.from_contents(schema))
    registry = registry.with_resource(merchant_schema["$id"], Resource.from_contents(merchant_schema))
    errors = list(Draft202012Validator(schema, registry=registry).iter_errors(opened))
    require(not errors, "official Open Checkout Schema INVALID: " + "; ".join(str(e) for e in errors[:3]))
    constraints = opened["constraints"]
    require(isinstance(constraints, list) and len(constraints) == 2, "wrong constraint cardinality")
    by_type = {c["type"]: c for c in constraints}
    require(set(by_type) == {"checkout.allowed_merchants", "checkout.line_items"}, "wrong constraint types")
    allowed = by_type["checkout.allowed_merchants"]
    required = by_type["checkout.line_items"]
    require(set(allowed) == {"type", "allowed"} and len(allowed["allowed"]) == 1, "wrong merchant profile")
    require(set(allowed["allowed"][0]) == {"id", "name"}, "unknown signed merchant field")
    require(allowed["allowed"][0]["id"] == fixture["expected_merchant_id"], "wrong permitted merchant")
    require(set(required) == {"type", "items"} and len(required["items"]) == 1, "wrong line item profile")
    requirement = required["items"][0]
    require(set(requirement) == {"id", "quantity", "acceptable_items"}, "unknown signed required item field")
    require(isinstance(requirement["id"], str) and requirement["quantity"] == 2, "wrong requirement fields")
    require(len(requirement["acceptable_items"]) == 1, "wrong acceptable items")
    sku = requirement["acceptable_items"][0]
    require(set(sku) == {"id", "title"} and sku["id"] == "SKU-1", "wrong SKU profile")
    require(len(checkout["line_items"]) == 1 and checkout["line_items"][0]["quantity"] == 2, "wrong cart count")
    require(checkout["line_items"][0]["item"]["id"] == sku["id"], "cart SKU mismatch")
    require(next(t["amount"] for t in checkout["totals"] if t["type"] == "total") ==
            fixture["expected_total_minor"], "Host expected amount mismatch")

    dest = Path(args.artifacts)
    manifest = save_artifacts(dest, fixture, root, root_jws, root_disclosures, terminal,
                              terminal_jws, terminal_disclosures, merchant)
    result = {"case_id": "DC01", "pinned_ap2_sha": PINNED_AP2,
              "o1_issuer_jws": "PASS", "o2_agent_terminal_sd_hash_merchant": "PASS",
              "o3_signed_root_whole_graph": "PASS", "o4_official_schema": "VALID",
              "o4_local_profile": "PASS", "root_commitments": root_graph,
              "terminal_commitments": terminal_graph, "root_unresolved_count": 0,
              "manifest_sha256": hashlib.sha256((dest / "manifest.json").read_bytes()).hexdigest(),
              "o5_ruby": "NOT_RUN_IN_PYTHON", "outcome": "O1_O4_FEASIBILITY_ONLY",
              "evidence_boundary": "synthetic signed positive only; NOT business ALLOW or DC02-DC05"}
    (dest / "python-observation.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print("DC01 O1–O4 independent synthetic signed-wire feasibility: PASS")
    print("Root signed commitments:", len(root_graph), "Terminal:", len(terminal_graph))
    print("WARNING: synthetic only, O5 separate; Host ALLOW/nonce-CAS/HC06 NOT TESTED")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--fixture", required=True)
    p.add_argument("--schema", required=True)
    p.add_argument("--merchant-schema", required=True)
    p.add_argument("--artifacts", required=True)
    run(p.parse_args())
