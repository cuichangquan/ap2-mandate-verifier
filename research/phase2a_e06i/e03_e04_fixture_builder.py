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
import importlib.abc
import importlib.machinery
import json
import os
from pathlib import Path
import stat
import subprocess
import sys

from jwcrypto import jws
from jwcrypto.jwk import JWK

# AP2 is intentionally NOT imported at module load. A pinned source-only
# importer below must be installed first, before any AP2 code can execute.

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


def git_read(repo, *args, limit=4096):
    """Only bounded, offline Git object reads: no hooks, networks or filters."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update({"GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull,
                "GIT_NO_REPLACE_OBJECTS": "1", "GIT_OPTIONAL_LOCKS": "0",
                "GIT_TERMINAL_PROMPT": "0", "GIT_PAGER": "cat"})
    try:
        p = subprocess.run(
            ["git", "-C", str(repo), "-c", "core.fsmonitor=false",
             "-c", "diff.external=", *args],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, timeout=5, check=False, env=env,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise Stop("sdk_git_unavailable") from exc
    demand(p.returncode == 0 and len(p.stdout) <= limit,
           "sdk_git_mismatch_or_unbounded")
    return p.stdout


def pinned_blob(repo, relative):
    """Verified bytes from the pinned Git *object*, never filesystem or .pyc."""
    name = relative.as_posix()
    demand(name.startswith("code/sdk/python/ap2/") and
           name.endswith(".py") and ".." not in relative.parts,
           "invalid_sdk_module")
    size = git_read(repo, "cat-file", "-s", "HEAD:" + name)
    demand(size.strip().isdigit() and int(size) <= 262144,
           "oversized_sdk_module")
    data = git_read(repo, "show", "HEAD:" + name, limit=262144)
    demand(len(data) == int(size), "changed_sdk_module")
    return data


class PinnedSourceLoader(importlib.abc.Loader):
    """Executes only pinned Git source bytes, ignoring __pycache__ entirely."""
    def __init__(self, root, path, relative):
        self.root, self.path, self.relative = root, path, relative

    def create_module(self, spec):
        return None

    def exec_module(self, module):
        blob = pinned_blob(self.root, self.relative)
        compiled = compile(blob, str(self.path), "exec", dont_inherit=True)
        exec(compiled, module.__dict__)


class PinnedAP2Finder(importlib.abc.MetaPathFinder):
    """No installed SDK wheel, namespace overlay or cached bytecode permitted."""
    def __init__(self, root):
        self.root = root
        self.sdk = root / "code/sdk/python/ap2"
        demand(self.sdk.is_dir(), "missing_pinned_python_sdk")

    def find_spec(self, fullname, path=None, target=None):
        if fullname != "ap2" and not fullname.startswith("ap2."):
            return None
        # ap2 at the pinned commit is a namespace root (no __init__.py).
        if fullname == "ap2":
            spec = importlib.machinery.ModuleSpec(
                fullname, loader=None, is_package=True)
            spec.submodule_search_locations = [str(self.sdk)]
            return spec
        relative_pkg = Path(*fullname.split("."))
        stem = self.root / "code/sdk/python" / relative_pkg
        is_package = False
        source = stem.with_suffix(".py")
        relative = source.relative_to(self.root)
        try:
            pinned_blob(self.root, relative)
        except Stop:
            # A package initializer is a separate pinned object.
            source = stem / "__init__.py"
            relative = source.relative_to(self.root)
            pinned_blob(self.root, relative)
            is_package = True
        spec = importlib.machinery.ModuleSpec(
            fullname, PinnedSourceLoader(self.root, source, relative),
            origin=str(source), is_package=is_package)
        if is_package:
            spec.submodule_search_locations = [str(stem)]
        return spec


def install_pinned_sdk(root_arg):
    """Verify source and install hook BEFORE the first ap2 import."""
    demand(isinstance(root_arg, str) and
           1 <= len(os.fsencode(root_arg)) <= 1024 and "\x00" not in root_arg,
           "invalid_upstream_path")
    demand(not any(n == "ap2" or n.startswith("ap2.")
                   for n in sys.modules), "sdk_preimported")
    try:
        root = Path(root_arg).resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        raise Stop("sdk_source_unavailable") from exc
    demand(root.is_dir() and (root / ".git").exists(),
           "sdk_source_unavailable")
    demand(git_read(root, "rev-parse", "--show-toplevel").decode("ascii").strip()
           == str(root), "sdk_wrong_worktree")
    demand(git_read(root, "rev-parse", "HEAD").decode("ascii").strip()
           == PINNED_AP2, "sdk_wrong_head")
    # Fail closed for tracked edits and index differences. Untracked .pyc
    # cannot affect the source loader because only HEAD Git blobs are compiled.
    git_read(root, "diff", "--no-ext-diff", "--quiet", "HEAD", "--")
    finder = PinnedAP2Finder(root)
    sys.meta_path.insert(0, finder)
    return finder


def import_pinned_sdk():
    """All AP2 imports occur only through the installed HEAD-blob importer."""
    from ap2.sdk.disclosure_metadata import DisclosureMetadata
    from ap2.sdk.generated.checkout_mandate import CheckoutMandate
    from ap2.sdk.generated.open_checkout_mandate import (
        AllowedMerchants, Item, LineItems, LineItemRequirements, OpenCheckoutMandate,
    )
    from ap2.sdk.generated.types.checkout import Checkout
    from ap2.sdk.generated.types.merchant import Merchant
    from ap2.sdk.mandate import MandateClient
    from ap2.sdk.sdjwt import common, kb_sd_jwt
    return (DisclosureMetadata, CheckoutMandate, AllowedMerchants, Item,
            LineItems, LineItemRequirements, OpenCheckoutMandate, Checkout,
            Merchant, MandateClient, common, kb_sd_jwt)


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


def checkout_payload(Checkout):
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


def make(epoch, sdk):
    (DisclosureMetadata, CheckoutMandate, AllowedMerchants, Item,
     LineItems, LineItemRequirements, OpenCheckoutMandate, Checkout,
     Merchant, MandateClient, common, kb_sd_jwt) = sdk
    demand(type(epoch) is int and 61 <= epoch <= MAX_EPOCH - 3600,
           "invalid_synthetic_epoch")
    issuer = JWK.generate(kty="EC", crv="P-256")
    agent = JWK.generate(kty="EC", crv="P-256")
    merchant = JWK.generate(kty="EC", crv="P-256")
    checkout_jwt = sign_json(merchant, checkout_payload(Checkout),
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
        # Pinned KB builder may use wall-clock iat; synthetic G4 clock uses
        # --epoch. Re-sign both iat AND sd_hash under the same Agent key.
        claim["iat"] = epoch
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


def private_output_dir(policy_path, fixture_path):
    """A pre-existing, exclusively-owned 0700 directory is our trust boundary.

    The separately approved future runner must allocate an unshared scratch
    directory first. Untrusted concurrent actors with the *same UID* are
    outside this boundary; shared/group/world-writable directories STOP.
    """
    demand(hasattr(os, "O_DIRECTORY") and hasattr(os, "O_NOFOLLOW"),
           "safe_directory_unavailable")
    paths = (policy_path, fixture_path)
    demand(all(isinstance(p, str) and "\x00" not in p and
               1 <= len(os.fsencode(p)) <= 1024 and
               os.path.isabs(p) for p in paths), "invalid_output_paths")
    parents = [os.path.dirname(p) for p in paths]
    names = [os.path.basename(p) for p in paths]
    demand(parents[0] == parents[1] and names[0] != names[1] and
           all(n not in ("", ".", "..") and "/" not in n for n in names),
           "unsafe_output_locations")
    # Descriptor-scoped writes and cleanup cannot be redirected by renaming
    # the caller's pathname after the original directory is opened.
    fd = os.open(parents[0], os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        st = os.fstat(fd)
        demand(stat.S_ISDIR(st.st_mode) and st.st_uid == os.geteuid() and
               stat.S_IMODE(st.st_mode) == 0o700,
               "untrusted_output_directory")
        return fd, names
    except BaseException:
        os.close(fd)
        raise


def remove_created(dirfd, name, identity):
    """Identity precheck inside private dir; no shared-path cleanup race."""
    if identity is None:
        return
    try:
        st = os.stat(name, dir_fd=dirfd, follow_symlinks=False)
    except FileNotFoundError:
        return
    demand(stat.S_ISREG(st.st_mode) and
           (st.st_dev, st.st_ino) ==
           (identity.st_dev, identity.st_ino), "output_identity_changed")
    os.unlink(name, dir_fd=dirfd)


def exclusive_write(dirfd, name, obj, cap):
    data = canonical(obj) + b"\n"
    demand(0 < len(data) <= cap, "oversized_output")
    handle, identity = None, None
    try:
        handle = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL |
                         os.O_NOFOLLOW, 0o600, dir_fd=dirfd)
        identity = os.fstat(handle)
        demand(stat.S_ISREG(identity.st_mode) and
               identity.st_nlink == 1 and identity.st_uid == os.geteuid(),
               "unsafe_output_type")
        pos = 0
        while pos < len(data):
            n = os.write(handle, data[pos:])
            demand(n > 0, "output_write_failed")
            pos += n
        os.fsync(handle)
        os.close(handle)
        handle = None
        return identity
    except BaseException:
        if handle is not None:
            os.close(handle)
            handle = None
        remove_created(dirfd, name, identity)
        raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--epoch", required=True, type=int)
    parser.add_argument("--upstream-root", required=True,
                        help="locally available pristine pinned official AP2 worktree")
    parser.add_argument("--policy", required=True)
    parser.add_argument("--fixture", required=True)
    args = parser.parse_args()
    # Establish *both* trust boundaries before importing executable AP2 code
    # and before any signing key is generated.
    finder = install_pinned_sdk(args.upstream_root)
    directory, names = private_output_dir(args.policy, args.fixture)
    try:
        sdk = import_pinned_sdk()
        demand(sys.meta_path[0] is finder, "sdk_import_guard_removed")
        policy, fixture = make(args.epoch, sdk)
        first, second = None, None
        try:
            first = exclusive_write(directory, names[0], policy, 16_384)
            second = exclusive_write(directory, names[1], fixture, 262_144)
            os.fsync(directory)
        except BaseException:
            # Roll back BOTH created files, including directory fsync failure.
            # Never remove pre-existing entries; first-error remains STOP.
            remove_created(directory, names[1], second)
            remove_created(directory, names[0], first)
            raise
    finally:
        os.close(directory)
    print("E03/E04 F: public-only builder complete; O1-O5 NOT RUN; Gate HOLD")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # No token, private key, pathname or exception text in log output.
        print("E03/E04 F: STOP/HOLD; fixture construction unverified",
              file=sys.stderr)
        sys.exit(1)
