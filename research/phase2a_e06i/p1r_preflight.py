"""P1-R metadata planning only. No payload downloads, installation or runtime PASS."""
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import runpy
import signal
import socket
import ssl
import subprocess
import sys
import tempfile
import time
import tomllib
import urllib.parse

BASE = Path(__file__).resolve().parent
REPO = BASE.parents[1]
REPORT = {"scope": "METADATA_PREFLIGHT_ONLY_RUNTIME_UNPROVEN", "missing": [],
          "full_environment_total_bytes": None, "payload_downloads": 0,
          "install_build_docker_fixture_runs": 0}
USED = 0
CONTRACT = None


def need(ok, reason):
    if not ok:
        raise ValueError(reason)


def encoded(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=True, separators=(",", ":")).encode()


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def positive(value):
    return type(value) is int and 0 < value < 2**53


def document(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            need(key not in result, "DUPLICATE_JSON")
            result[key] = value
        return result
    return json.loads(raw, object_pairs_hook=pairs)


def now_before(value):
    need(dt.datetime.now(dt.timezone.utc) < dt.datetime.fromisoformat(value.replace("Z", "+00:00")),
         "EXPIRED")


def url_parts(url):
    need(len(url) <= 8192 and all(32 < ord(c) < 127 for c in url), "URL")
    u = urllib.parse.urlsplit(url)
    need(u.scheme == "https" and u.username is None and u.password is None and
         u.port is None and not u.fragment and u.hostname, "URL")
    return u


def request(url, cap, *, token=None, method="GET", data=b"", redirect=False):
    """Direct TLS HTTP/1.1, no proxy/retry/redirect. Bound header before parsing."""
    global USED
    u = url_parts(url)
    need(url in CONTRACT["metadata_urls"] or redirect, "UNAPPROVED_URL")
    if redirect:
        need(re.fullmatch(CONTRACT["artifact_redirect_host_regex"], u.hostname) is not None,
             "ARTIFACT_REDIRECT_HOST")
        need(token is None and method == "GET", "CREDENTIAL_REDIRECT")
    need(0 < cap <= CONTRACT["body_limit"] - USED, "BODY_BUDGET")
    deadline = time.monotonic() + 45
    context = ssl.create_default_context()
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    with socket.create_connection((u.hostname, 443), timeout=5) as plain:
        with context.wrap_socket(plain, server_hostname=u.hostname) as conn:
            def receive(n):
                remaining = deadline - time.monotonic()
                need(remaining > 0, "RESPONSE_TIMEOUT")
                conn.settimeout(min(5, remaining))
                return conn.recv(n)

            path = u.path + ("?" + u.query if u.query else "")
            headers = {"Host": u.hostname, "User-Agent": "issue73-p1r-metadata-preflight",
                       "Connection": "close", "Accept-Encoding": "identity",
                       "Accept": "application/json, application/vnd.oci.image.index.v1+json, "
                                 "application/vnd.oci.image.manifest.v1+json, "
                                 "application/vnd.docker.distribution.manifest.list.v2+json, "
                                 "application/vnd.docker.distribution.manifest.v2+json"}
            if token is not None:
                need(u.hostname in ("api.github.com", "registry-1.docker.io"), "AUTH_HOST")
                need(re.fullmatch(r"[A-Za-z0-9_.~+/=-]{1,16384}", token) is not None, "TOKEN")
                headers["Authorization"] = "Bearer " + token
            if data:
                headers.update({"Content-Type": "application/json", "Content-Length": str(len(data))})
            conn.sendall((method + " " + path + " HTTP/1.1\r\n" +
                          "".join(k + ": " + v + "\r\n" for k, v in headers.items()) +
                          "\r\n").encode("ascii") + data)
            head = bytearray()
            while not head.endswith(b"\r\n\r\n"):
                need(len(head) < 8192, "HEADER_LIMIT")
                part = receive(1)
                need(part, "HEADER_EOF")
                head.extend(part)
            lines = bytes(head).decode("iso-8859-1").split("\r\n")
            match = re.fullmatch(r"HTTP/1\.[01] ([0-9]{3}) [^\r\n]*", lines[0])
            need(match is not None, "HTTP_STATUS")
            status = int(match[1])
            parsed = {}
            for line in lines[1:-2]:
                key, colon, value = line.partition(":")
                need(colon and re.fullmatch(r"[A-Za-z0-9-]+", key), "HEADER_SYNTAX")
                key = key.lower()
                need(not any(ord(c) < 32 for c in value.strip()), "HEADER_SYNTAX")
                need(key not in parsed or key not in ("location", "content-length",
                     "transfer-encoding", "content-encoding"), "HEADER_DUPLICATE")
                parsed.setdefault(key, value.strip())
            need(parsed.get("content-encoding", "identity") == "identity", "ENCODING")
            need(not ("content-length" in parsed and "transfer-encoding" in parsed), "FRAMING")
            body = bytearray()

            def take(n):
                need(n <= cap - len(body) and USED + n <= CONTRACT["body_limit"], "BODY_LIMIT")
                result = bytearray()
                while len(result) < n:
                    piece = receive(min(n - len(result), 65536))
                    need(piece, "BODY_EOF")
                    result.extend(piece)
                return bytes(result)

            def line():
                result = bytearray()
                while not result.endswith(b"\r\n"):
                    need(len(head) + len(result) < 8192, "TRAILER_LIMIT")
                    piece = receive(1)
                    need(piece, "CHUNK_EOF")
                    result.extend(piece)
                head.extend(result)
                return bytes(result)

            if "transfer-encoding" in parsed:
                need(parsed["transfer-encoding"] == "chunked", "TRANSFER_ENCODING")
                for _ in range(20000):
                    chunk = line()
                    need(re.fullmatch(rb"[0-9a-fA-F]{1,8}\r\n", chunk) is not None, "CHUNK")
                    size = int(chunk, 16)
                    if size == 0:
                        need(line() == b"\r\n", "TRAILERS")
                        break
                    body.extend(take(size))
                    need(receive(1) == b"\r" and receive(1) == b"\n", "CHUNK_CRLF")
                else:
                    raise ValueError("CHUNK_COUNT")
            elif "content-length" in parsed:
                need(re.fullmatch(r"[0-9]{1,16}", parsed["content-length"]), "CONTENT_LENGTH")
                body.extend(take(int(parsed["content-length"])))
            else:
                raise ValueError("UNKNOWN_BODY_LENGTH")
            USED += len(body)
            need(USED <= CONTRACT["body_limit"], "BODY_BUDGET")
            return status, parsed, bytes(body)


def get(url, cap, token=None):
    status, headers, raw = request(url, cap, token=token)
    need(status == 200, "METADATA_HTTP")
    return raw


def pinned(path, blob):
    raw = path.read_bytes()
    need(len(raw) < 600000 and hashlib.sha1(
        b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest() == blob, "SOURCE_BLOB")
    return raw


def child(args, work, env=None, seconds=120):
    with tempfile.TemporaryFile() as out:
        proc = subprocess.run(args, stdin=subprocess.DEVNULL, stdout=out, stderr=out,
                              env=env, timeout=seconds, check=False)
        out.seek(0)
        raw = out.read(262145)
    need(len(raw) <= 262144 and proc.returncode == 0, "AUTHENTICATION_OR_ORACLE")
    return raw


def debian(zip_raw, work):
    replay = runpy.run_path(str(BASE / "p1m_saved_artifact_replay.py"))
    archive = work / "saved.zip"
    archive.write_bytes(zip_raw)
    saved = work / "originals"
    replay["extract_saved"](archive, saved)
    candidate = (BASE / "p1m_debian_dependency_closure.py").read_bytes()
    script = work / "verify.sh"
    script.write_bytes(replay["signature_script"](
        REPO / ".github/workflows/phase2a-p1-h4-metadata.yml", candidate))
    child(["bash", str(script)], work, dict(os.environ, P1M_SAVED=str(saved)), 90)
    paths = [saved / (name + ".Packages.xz") for name in ("main", "security")]
    stdout = child([sys.executable, "-I", "-B", str(BASE / "p1m_independent_oracle.py"),
                    str(BASE / "p1m_debian_dependency_closure.py"), *map(str, paths)], work, seconds=210)
    need(b"P1M_ORACLE=METADATA_CANDIDATE_MATCH\n" in stdout, "ORACLE_MATCH")
    report = document(next(line.split(b"=", 1)[1] for line in stdout.splitlines()
                           if line.startswith(b"P1M_DEPENDENCY_GRAPH=")))
    need(report["candidates"][1] == {"version": "3.11.2-6+deb12u9", "candidate_nodes": 38,
                                    "graph_sha256": CONTRACT["u9_graph_sha256"]}, "FIXED_GRAPH")
    # Export using the reviewed Oracle's line reader/comparator, not a new resolver.
    oracle = runpy.run_path(str(BASE / "p1m_independent_oracle.py"))
    inventory, aliases, names = {}, {}, {}
    for path, (origin, _, digest) in zip(paths, oracle["INPUTS"]):
        for item in oracle["records"](path):
            key = tuple(item[f] for f in oracle["FIELDS"][:3])
            inventory[key] = item
            aliases.setdefault(key, set()).add((origin, digest, item["filename"]))
            names.setdefault(key[0], set()).add(key)
    fixed = {name: (name, "3.11.2-6+deb12u9", "amd64") for name in oracle["ROOTS"]}
    selected, todo = set(), list(fixed.values())
    compare = oracle["compare"]
    while todo:
        key = todo.pop()
        if key in selected:
            continue
        selected.add(key)
        need(len(selected) <= 38, "EXPORT_NODE_LIMIT")
        for group in oracle["relationship_groups"](inventory[key], ("depends", "pre-depends")):
            target = None
            for name, op, wanted in group:
                if name not in fixed:
                    options = sorted(names.get(name, ()))
                    best = None
                    for option in options:
                        if best is None or compare(option[1], best[1]) > 0:
                            best = option
                    fixed[name] = best
                option = fixed[name]
                if option:
                    result = 0 if op is None else compare(option[1], wanted)
                    if op is None or {"<<": result < 0, "<=": result <= 0, "=": result == 0,
                                      ">=": result >= 0, ">>": result > 0}[op]:
                        target = option
                        break
            need(target is not None, "EXPORT_DEPENDENCY")
            todo.append(target)
    manifest = [[*key, sorted(aliases[key]), *[inventory[key].get(field, "") for field in
                 ("size", "sha256", "depends", "pre-depends", "provides", "conflicts", "breaks")]]
                for key in sorted(selected)]
    # Digest uses the original graph serialization order, not sorted JSON keys.
    need(len(manifest) == 38 and sha(json.dumps(manifest, ensure_ascii=True,
         separators=(",", ":")).encode()) == CONTRACT["u9_graph_sha256"], "EXPORT_GRAPH_DIGEST")
    items = []
    for row in manifest:
        # Prefer the authenticated security origin where present; retain all aliases.
        chosen = sorted(row[3], key=lambda a: (a[0] != "security", a))[0]
        items.append({"package": row[0], "version": row[1], "architecture": row[2],
                      "filename": chosen[2], "origin": chosen[0], "aliases": row[3],
                      "size": int(row[4]), "sha256": row[5],
                      "prospective_url": CONTRACT["debian_payload_bases"][chosen[0]] + chosen[2]})
    REPORT["cpython_candidate"] = {"count": 38, "graph_sha256": CONTRACT["u9_graph_sha256"],
                                  "items": items, "bytes": sum(i["size"] for i in items),
                                  "scope": "CPYTHON_CANDIDATE_ONLY_NOT_CONTAINER_INVENTORY"}
    need(encoded(items) == encoded(CONTRACT["expected_cpython_items"]), "EXPORT_FIXED_ITEMS")


def artifacts(token, work):
    spec = CONTRACT["saved_artifact"]
    meta = document(get(spec["url"], 4096, token))
    for field in ("id", "size_in_bytes", "expires_at", "digest"):
        need(meta[field] == spec[field], "ARTIFACT_METADATA")
    need(meta["expired"] is False and meta["workflow_run"]["id"] == 38851173209 and
         meta["workflow_run"]["head_sha"] == "55dccb98507316044187e48843aef754cd0b5c57",
         "ARTIFACT_PROVENANCE")
    status, headers, _ = request(spec["url"] + "/zip", 4096, token=token)
    need(status == 302 and "location" in headers, "ARTIFACT_REDIRECT")
    status, _, raw = request(headers["location"], spec["size_in_bytes"], redirect=True)
    need(status == 200 and len(raw) == spec["size_in_bytes"] and
         "sha256:" + sha(raw) == spec["digest"], "ARTIFACT_BYTES")
    debian(raw, work)


def oci():
    spec = CONTRACT["oci"]
    REPORT["metadata_progress"] = {"role": "oci_fixed_metadata"}
    auth = document(get(spec["auth_url"], 32768))
    token = auth.get("token")
    need(isinstance(token, str) and 0 < auth.get("expires_in", 0) <= 3600, "REGISTRY_TOKEN")
    index_raw = get(spec["index_url"], 131072, token)
    need("sha256:" + sha(index_raw) == spec["index_digest"], "OCI_INDEX_DIGEST")
    index = document(index_raw)
    matches = [i for i in index["manifests"] if i.get("platform", {}).get("os") == "linux"
               and i.get("platform", {}).get("architecture") == "amd64"
               and not i.get("platform", {}).get("variant")]
    need(len(matches) == 1 and matches[0]["digest"] == spec["manifest_digest"], "OCI_PLATFORM")
    raw = get(spec["manifest_url"], 131072, token)
    need(positive(matches[0]["size"]) and len(raw) == matches[0]["size"] and
         "sha256:" + sha(raw) == spec["manifest_digest"], "OCI_MANIFEST")
    manifest = document(raw)
    config = manifest["config"]
    need(re.fullmatch(r"sha256:[a-f0-9]{64}", config["digest"]) and
         positive(config["size"]) and config["size"] <= 131072, "OCI_CONFIG_DESCRIPTOR")
    # Content-addressed config endpoint is the only dynamic registry path allowed.
    REPORT["oci"] = {"index_digest": spec["index_digest"], "manifest_digest": spec["manifest_digest"],
                     "config": config, "layers": manifest["layers"],
                     "payloads_fetched": 0, "installed_inventory": "UNPROVEN"}
    need(len(manifest["layers"]) <= 32, "OCI_LAYER_COUNT")
    for layer in manifest["layers"]:
        need(positive(layer["size"]) and re.fullmatch(r"sha256:[a-f0-9]{64}", layer["digest"]),
             "OCI_LAYER_DESCRIPTOR")
    REPORT["oci"]["layer_bytes"] = sum(i["size"] for i in manifest["layers"])
    config_url = spec["config_url_prefix"] + config["digest"]
    CONTRACT["metadata_urls"].append(config_url)
    status, _, config_raw = request(config_url, 131072, token=token)
    # No registry CDN redirects: unknown transfer host is a concrete STOP.
    REPORT["oci"]["config_http_status"] = status
    if status != 200:
        REPORT["missing"].append("OCI_CONFIG_BYTES_NOT_VERIFIED_NO_CDN_REDIRECT_ALLOWED")
    need(status == 200, "OCI_CONFIG_REDIRECT_OR_HTTP")
    need(len(config_raw) == config["size"] and "sha256:" + sha(config_raw) == config["digest"],
         "OCI_CONFIG_DIGEST")
    metadata = document(config_raw)
    need(metadata["architecture"] == "amd64" and metadata["os"] == "linux", "OCI_CONFIG_PLATFORM")
    need("RUBY_VERSION=3.3.12" in metadata["config"]["Env"], "OCI_RUBY_VERSION")
    need(len(manifest["layers"]) <= 32, "OCI_LAYER_COUNT")
    for layer in manifest["layers"]:
        need(positive(layer["size"]) and re.fullmatch(r"sha256:[a-f0-9]{64}", layer["digest"]),
             "OCI_LAYER_DESCRIPTOR")
    need(len(metadata["rootfs"]["diff_ids"]) == len(manifest["layers"]), "OCI_ROOTFS")
    REPORT["oci"] = {"index_digest": spec["index_digest"], "manifest_digest": spec["manifest_digest"],
                     "config": config, "layers": manifest["layers"],
                     "layer_bytes": sum(i["size"] for i in manifest["layers"]),
                     "payloads_fetched": 0, "installed_inventory": "UNPROVEN"}


def packages():
    a11 = document((BASE / "a11_pinned_inputs.json").read_bytes())
    lock = get(CONTRACT["upstream_lock"]["url"], 600000)
    need(len(lock) == CONTRACT["upstream_lock"]["size"] and
         sha(lock) == CONTRACT["upstream_lock"]["sha256"], "UPSTREAM_LOCK")
    upstream = tomllib.loads(lock.decode())
    wheels = []
    for item in a11["python_wheel_archives"]["items"]:
        REPORT["metadata_progress"] = {"role": "wheel", "filename": item["filename"]}
        url = "https://pypi.org/pypi/" + item["name"] + "/" + item["version"] + "/json"
        meta = document(get(url, 262144))
        matches = [f for f in meta["urls"] if f["filename"] == item["filename"]]
        need(len(matches) == 1, "WHEEL_FILENAME")
        chosen = matches[0]
        need(chosen["digests"]["sha256"] == item["sha256"] and
             positive(chosen["size"]) and chosen["packagetype"] == "bdist_wheel" and
             chosen.get("yanked") is False, "WHEEL_METADATA")
        location = url_parts(chosen["url"])
        need(location.hostname == "files.pythonhosted.org" and
             urllib.parse.unquote(location.path).endswith("/" + item["filename"]),
             "WHEEL_PROSPECTIVE_URL")
        locked = [p for p in upstream["package"] if p["name"] == item["name"] and
                  p["version"] == item["version"]]
        need(len(locked) == 1 and any(w["hash"] == "sha256:" + item["sha256"] and
             urllib.parse.unquote(urllib.parse.urlsplit(w["url"]).path).endswith("/" + item["filename"])
             and ("size" not in w or w["size"] == chosen["size"])
             for w in locked[0].get("wheels", [])), "WHEEL_LOCK")
        wheels.append({**item, "size": chosen["size"], "size_source": "OFFICIAL_PYPI_VERSION_JSON",
                       "prospective_url": chosen["url"]})
    REPORT["wheels"] = {"items": wheels, "bytes": sum(i["size"] for i in wheels)}
    gems = []
    for item in a11["ruby_gem_archives"]["items"]:
        REPORT["metadata_progress"] = {"role": "gem", "filename": item["filename"]}
        url = "https://rubygems.org/api/v2/rubygems/" + item["name"] + "/versions/" + item["version"] + ".json"
        meta = document(get(url, 65536))
        need(meta["name"] == item["name"] and meta["version"] == item["version"] and
             meta["sha"] == item["sha256"], "GEM_METADATA")
        size = meta.get("size")
        need(size is None or positive(size), "GEM_SIZE")
        if size is None:
            REPORT["missing"].append("RUBYGEMS_ARCHIVE_SIZE:" + item["filename"])
        need(meta.get("gem_uri") == "https://rubygems.org/gems/" + item["filename"], "GEM_PROSPECTIVE_URL")
        gems.append({**item, "size": size, "prospective_url": meta["gem_uri"]})
    REPORT["gems"] = {"items": gems, "bytes": (sum(i["size"] for i in gems)
                                             if all(i["size"] is not None for i in gems) else None)}


def main():
    global CONTRACT
    CONTRACT = document((BASE / "p1r_input_contract.json").read_bytes())
    need(sys.platform == "linux" and os.environ.get("GITHUB_RUN_ATTEMPT") == "1", "ENVIRONMENT")
    resource.setrlimit(resource.RLIMIT_AS, (1536 * 1024 * 1024,) * 2)
    resource.setrlimit(resource.RLIMIT_FSIZE, (16777216,) * 2)
    resource.setrlimit(resource.RLIMIT_CPU, (280, 300))
    signal.signal(signal.SIGXCPU, lambda *_: (_ for _ in ()).throw(ValueError("CPU_LIMIT")))
    signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(ValueError("TOTAL_TIMEOUT")))
    # Checkout and pin-check steps each have a one-minute ceiling. Reserve
    # >60s inside the eight-minute job, and 120s before the outer 420s kill.
    signal.alarm(300)
    now_before(CONTRACT["security_valid_until"])
    now_before(CONTRACT["saved_artifact"]["expires_at"])
    for path, blob in CONTRACT["source_blobs"].items():
        pinned(REPO / path, blob)
    token = os.environ.pop("P1R_GITHUB_TOKEN")
    main_sha = os.environ["GITHUB_SHA"]
    need(main_sha == os.environ["EXPECTED_MAIN"] and re.fullmatch(r"[a-f0-9]{40}", main_sha), "EXACT_MAIN")
    ref = document(get(CONTRACT["main_ref_url"], 4096, token))
    need(ref["object"]["sha"] == main_sha, "CURRENT_MAIN")
    claim = encoded({"ref": CONTRACT["once_ref"], "sha": main_sha})
    status, _, reply = request(CONTRACT["refs_url"], 4096, token=token, method="POST", data=claim)
    need(status == 201, "ONCE_CLAIM_UNCERTAIN_NO_RETRY")
    ref = document(reply)
    need(ref["ref"] == CONTRACT["once_ref"] and ref["object"]["sha"] == main_sha, "ONCE_CLAIM")
    REPORT.update({"main_sha": main_sha, "run_id": os.environ["GITHUB_RUN_ID"], "attempt": 1,
                   "once_ref": CONTRACT["once_ref"], "missing": list(CONTRACT["known_missing"])})
    with tempfile.TemporaryDirectory(prefix="p1r-preflight-") as tmp:
        artifacts(token, Path(tmp))
        packages()
        oci()
    now_before(CONTRACT["security_valid_until"])
    REPORT.update({"status": "INPUT_CONTRACT_INCOMPLETE_STOP" if REPORT["missing"] else "METADATA_LIST_COMPLETE",
                   "controlled_response_body_bytes": USED, "full_environment_total_bytes": None,
                   "payload_downloads": 0, "install_build_docker_fixture_runs": 0})


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        # Never echo network exceptions, bearer tokens, SAS URLs or remote content.
        reason = str(exc) if type(exc) is ValueError and re.fullmatch(r"[A-Z_]{1,64}", str(exc)) else "REJECTED"
        REPORT.update({"status": "STOP_HOLD", "stop_reason": reason,
                       "controlled_response_body_bytes": USED})
    raw = encoded(REPORT)
    need(len(raw) <= 262000, "RESULT_LIMIT")
    print(raw.decode())
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        Path(summary).write_text("## P1-R metadata preflight\n\n```json\n" + raw.decode() + "\n```\n")
    sys.exit(1 if REPORT["status"] == "STOP_HOLD" else 0)
