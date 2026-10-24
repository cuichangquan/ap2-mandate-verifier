"""SOURCE ONLY / NOT_RUN. Future explicit Approval B is required."""
import argparse
import ast
import base64
import copy
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import re
import signal
import stat
import subprocess
import sys
import tempfile
import time
import types

BASE = "b858d2b37b529527307957335b722b88481d7fe7"
AP2 = "b4587ac1d055888a73b4b21750973cffba961793"
REFERENCES = {
 "research/phase2a_e06i/e03_e04_signed_oracle.py": "884900e2c3420ebfc2393413ae0e6010db71b28f8a6ef02eec997defa57b8caf",
 "test/o2o5_compare.py": "97faec0c3a36bcf60b6c7a340a38ab9e0512ab3bc04716af04ce7c8f47bc4ba4",
 "research/stage11/archive/O4_VERIFIED_REPORT.json": "f45e3b94c8434ab117acba8b94ca8bfb1e37dae42a2936fb2f5205c103dcdef8",
 "research/stage15/compare.py": "b4d83be75dd9083fcfee7733e160b37e47cf4eb28b72497b51f45e1c9e2fbc8e",
 "test/stage11_identity.py": "604c03c9b8405421f8611c8f2ed7f56891c7103cdfc54e2f261968916bc16dc4",
 "research/stage11/inputs/O4_HTTP_ACQUISITION.json": "06ee7ad9d219af1619c5a5aec59000ff87f6be49cff91e4a60f68968b57b20c3",
 "research/stage11/dependencies/o1o3-requirements.lock": "8e6d9f8898e607fc95b41e3ed8cf24b8cb88afd95aadd86bf9797349341092ba",
 "research/stage11/dependencies/o4-requirements.lock": "7a468daf8e42b283c0172f3cd6a61f480a04b1f10fa5be1a547e917ff8b96432"
}
SCHEMAS = {
 "ap2/open_checkout_mandate.json": [
  "bd6eb1c95a5ccb967259fae49100287755251c9d1bdb48342d96dd99fcb30b41",
  "e3d9cafa7311d90612c7f908ae9b8821ddc8735a"
 ],
 "ap2/checkout_mandate.json": [
  "10c0341edfeaa9084d3704ef8e94869de20499c8e357068d65f8d622bf79483a",
  "8755db60a1c6e15f49cfe6c9a5dee6838d2f379d"
 ],
 "ap2/types/item.json": [
  "48c24532f105fda096ab89a27e04e896a597fda7e308e96cc88e11ce6a6632f9",
  "0b31d4b0a0ee5d96d2d08d0b9d7b6081aaa41c2e"
 ],
 "ap2/types/merchant.json": [
  "13457334d8577230a1cce5265971cfc02f68f5d4e97f74bd2e78128105d3ab31",
  "2e44a4dc943c009af106e7103e9e30f4e556b98c"
 ],
 "ucp/types/checkout.json": [
  "275f6589d4f49313f6d8cf3a0e3aedfca1d7209c3a8b8be404097c3d86d964f9",
  "bb9697ecea36b81f283165ad85a19753f00cfa59"
 ],
 "ucp/types/line_item.json": [
  "d71c13b023631f118b1a9df51433abc25883332f7ac2c097396ab956e0c494e6",
  "a8482fc594d6792c43eb65c3cdeae86a2996cdc4"
 ],
 "ucp/types/total.json": [
  "a49d2d2feb6567a3ba20b2770ee707e0f3de481bcece9ab8577a65dec9709531",
  "491c47c787a968fb64e72329d97898cfb17353e6"
 ],
 "ucp/types/link.json": [
  "7685745f445a7ac9a6044de3f9a4cdd62a3422c200f39696f5e6b0292e08b478",
  "e05cc0048c35cd2f89d6b480189739cf3f688da6"
 ],
 "ucp/types/buyer.json": [
  "93df45c6d425486742527e7ed6d9d91feca558f4802141ba994e609011a14df9",
  "0c408c6d1499dc9f249b6260ca5ce8848cd0b1c2"
 ],
 "ucp/types/message.json": [
  "b2b2774f2ab2b08ff79bb1cd8165905e624235ab19a10e687629baab094fc003",
  "694a4edd619d5dae95843af0ac71ef676d969bbd"
 ],
 "ucp/types/message_error.json": [
  "435b63a09d9b3ffede0a576d9ef2230f85d87e59b2006f55dc64079d380a1c75",
  "2c26c91ad2c11fd39ce2d0ebbf631a036c3d6f1a"
 ],
 "ucp/types/message_warning.json": [
  "836fd348a2085d95d332d1449bbb52a4ba6544faab32fab3827670b9d8e0ae4b",
  "35e9cd4b5160e84c2b4a802b54ef9ed7278ef3e8"
 ],
 "ucp/types/message_info.json": [
  "0c64b5d186f51f591c73e33bb4ff381bf648b301cc22827003185c78bfcf0c79",
  "bb92a0a0566a0496082499c15b772a5bc5e65cdb"
 ]
}
SOURCES = {
 "lib/ap2_mandate_verifier.rb":"4824eeef1ce6c7833bcc24bc0bf9abc265df0b35ba135e54b4341b54c2f65ef2",
 "lib/ap2_mandate_verifier/host_binding.rb":"917a4c139accd77d5bbe9125c64ea258349b6854ac04e0fefe33536b9b88ec0a",
 "lib/ap2_mandate_verifier/input_validator.rb":"395f8e6f2012ab400d7b17f1fdcf4ee63a3c1c9622da4f2b32d35b522542bf00",
 "lib/ap2_mandate_verifier/purchase_binding.rb":"6f2108ac3298e4558fc053139d045d399687ccc3bf39c01945ed52d529dc26df",
 "lib/ap2_mandate_verifier/research_result.rb":"02159d2f451461ef818d7b6c9d55349cdfb6e23d9ced7d688730d22c8e96827d",
 "lib/ap2_mandate_verifier/result.rb":"fade8a1e922f7b4cf2439c120580160f85e0f22f6cfac9ff1ab1364d7b34d310",
 "lib/ap2_mandate_verifier/root_disclosures.rb":"55e97aa3b606eee64afbf929941fabb24286755297e1ed5bf48a5066e1352df6",
 "lib/ap2_mandate_verifier/root_signature.rb":"d9b68d989700a0c103f80004e14fb2d3aa992f823434e07bf2971f63052519dd",
 "lib/ap2_mandate_verifier/scoped_constraints.rb":"b2b5fa4cd1b4ce83cfc5ffc1be0a09ce57ad4a1b9be6778e581dd38f5ce5fd84",
 "lib/ap2_mandate_verifier/trust_context.rb":"430eb9f9f3be4c0d7e799e95b68009c08582b6961aa954cc866ff012a3b2be36"
}
DEPS = {"jwcrypto":"1.6.1","cryptography":"50.0.2","cffi":"2.0.0",
 "typing-extensions":"4.15.0","pycparser":"2.23","jsonschema":"4.26.0",
 "jsonschema-specifications":"2025.9.1","referencing":"0.37.0",
 "rpds-py":"0.30.0","attrs":"26.1.0"}
EXPECTED = {"FULL":"scoped_research_verified","QUANTITY_FLOAT":"invalid_scoped_schema",
 "TOTALS_ONLY":"amount_mismatch","BAD_MERCHANT_BEFORE_TOTALS":"invalid_root_signature"}
FIXTURE = "research/stage11/inputs/O2O5_PUBLIC_CASES.json"
FIXTURE_SHA = "be17fc33612ec561147100fbb901f5c2ef288d4535ed1aa69b56a61447fc8942"
HISTORICAL_SCHEMA = "research/stage11/archive/O4_VERIFIED_REPORT.json"
CASE_ORIGIN = {"FULL":"FULL","QUANTITY_FLOAT":"QUANTITY_TYPE",
               "TOTALS_ONLY":"TOTALS","BAD_MERCHANT_BEFORE_TOTALS":"TOTALS"}


class Stop(Exception):
    pass


def need(ok, reason):
    if not ok:
        raise Stop(reason)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


def b64(raw):
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def digest(wire):
    return b64(hashlib.sha256(wire.encode("ascii")).digest())


def read(path, cap):
    before = os.lstat(path)
    need(stat.S_ISREG(before.st_mode) and 0 < before.st_size <= cap, "file_type_size")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        opened = os.fstat(fd)
        raw = os.read(fd, cap + 1)
        after = os.fstat(fd)
        keys = ("st_dev","st_ino","st_mode","st_nlink","st_uid","st_gid",
                "st_size","st_mtime_ns","st_ctime_ns")
        need(len(raw) == opened.st_size and all(
            getattr(before,k) == getattr(opened,k) == getattr(after,k) ==
            getattr(os.lstat(path),k) for k in keys), "file_changed")
        return raw
    finally:
        os.close(fd)


def selected(raw, names, assignments=(), **env):
    """Only fixed named definitions/assignments; never run a generator/module main."""
    tree = ast.parse(raw)
    nodes = []
    found = set()
    for node in tree.body:
        name = node.name if isinstance(node, (ast.FunctionDef, ast.ClassDef)) else (
            node.targets[0].id if isinstance(node, ast.Assign) and len(node.targets)==1
            and isinstance(node.targets[0], ast.Name) else None)
        if name in (*names, *assignments):
            need(name not in found, "duplicate_reference_definition")
            if hasattr(node, "decorator_list"):
                need(not node.decorator_list, "decorated_reference")
            nodes.append(node)
            found.add(name)
    need(found == set(names) | set(assignments), "missing_reference_definition")
    namespace = dict(__name__="fixed_e06_reference", **env)
    exec(compile(ast.Module(body=nodes, type_ignores=[]), "<fixed-reference>", "exec"), namespace)
    return types.SimpleNamespace(**namespace)


def references(root):
    raw = {p:read(root/p,65536) for p in REFERENCES}
    need(all(sha(raw[p])==h for p,h in REFERENCES.items()), "reference_source_pin")
    common = dict(json=json, base64=base64, hashlib=hashlib, os=os, stat=stat, re=re)
    o = selected(raw["research/phase2a_e06i/e03_e04_signed_oracle.py"],
        ("Stop","demand","strict_json","sha","b64url","decode64","bounded_tree",
         "original_signature","inspect_graph"), ("ALLOWED","B64"), **common)
    from jwcrypto import jws
    from jwcrypto.jwk import JWK
    b = selected(raw["test/o2o5_compare.py"],
        ("Reject","need","public","signed","lifetime","binding","resolve","subset"),
        json=json, hashlib=hashlib, jws=jws, JWK=JWK)
    s = selected(raw["research/stage15/compare.py"], ("model","args","evaluate"),
        ("PROFILE","P","PH","ROLES","SCOPE"),
        json=json, copy=copy, hashlib=hashlib, SHA=sha, J=encode)
    history=o.strict_json(raw[HISTORICAL_SCHEMA])
    need(history["fixture_sha256"]==FIXTURE_SHA,"historical_fixture_identity")
    return o,b,s,history


def schemas(directory, o):
    from jsonschema import Draft202012Validator
    from referencing import Registry, Resource
    from urllib.parse import urljoin
    registry = Registry(retrieve=lambda uri: (_ for _ in ()).throw(Stop("unregistered_schema_ref")))
    records = {}
    for path,(h,blob) in SCHEMAS.items():
        raw=read(directory/path,16384)
        need(sha(raw)==h and hashlib.sha1(
            b"blob "+str(len(raw)).encode()+b"\0"+raw).hexdigest()==blob, "schema_pin")
        value=o.strict_json(raw)
        need(value["$schema"]=="https://json-schema.org/draft/2020-12/schema", "schema_dialect")
        uri=value["$id"]
        need(uri not in records and uri.startswith("https://ap2-protocol.org/schemas/"), "schema_id")
        records[uri]=value
        registry=registry.with_resource(uri,Resource.from_contents(value))
    def closure(v,base):
        if isinstance(v,dict):
            base=urljoin(base,v.get("$id",""))
            if "$ref" in v:
                need(urljoin(base,v["$ref"]).split("#")[0] in records,"schema_closure")
                registry.resolver(base_uri=base).lookup(v["$ref"])
            for item in v.values(): closure(item,base)
        elif isinstance(v,list):
            for item in v: closure(item,base)
    for uri,value in records.items():
        Draft202012Validator.check_schema(value)
        closure(value,uri)
    ids={"open":"open_checkout_mandate","closed":"checkout_mandate.json",
         "merchant":"types/merchant.json","checkout":"types/checkout.json","item":"types/item.json"}
    return {name:Draft202012Validator(records["https://ap2-protocol.org/schemas/"+suffix],
            registry=registry) for name,suffix in ids.items()}


def saved_models(bundle, o, stage):
    """No signing/key generation; preserve saved signed wire bytes exactly."""
    cases=bundle["cases"]
    models={}
    for name, origin in CASE_ORIGIN.items():
        inputs=copy.deepcopy(cases[origin])
        if name=="BAD_MERCHANT_BEFORE_TOTALS":
            # Previously saved public negative key; no credential/private-key input.
            inputs["trusted_merchant_public_key_pem"]=cases["WRONG_MERCHANT_KEY"]["trusted_merchant_public_key_pem"]
            need(inputs["trusted_merchant_public_key_pem"]!=cases["TOTALS"]["trusted_merchant_public_key_pem"],
                 "merchant_key_control")
        model=stage.model(inputs)
        models[name]=model
        need(all(model["i"][k]==cases[origin][k] for k in
                 ("root_presentation","terminal_jws","host_checkout_jws")),
             "saved_signed_wire_changed")
    base=o.strict_json(o.decode64(cases["FULL"]["host_checkout_jws"].split(".")[1]))
    quantity=o.strict_json(o.decode64(cases["QUANTITY_TYPE"]["host_checkout_jws"].split(".")[1]))
    need(type(quantity["line_items"][0]["quantity"]) is float and
         quantity["line_items"][0]["quantity"]==2.0 and
         type(base["line_items"][0]["quantity"]) is int,"quantity_lexical_control")
    quantity["line_items"][0]["quantity"]=base["line_items"][0]["quantity"]
    need(quantity==base,"quantity_other_content_changed")
    totals=o.strict_json(o.decode64(cases["TOTALS"]["host_checkout_jws"].split(".")[1]))
    changed=copy.deepcopy(base)
    need(changed["totals"]==[{"type":"subtotal","amount":200},{"type":"total","amount":200}],
         "full_totals_control")
    changed["totals"][1]["amount"]=201
    need(totals==changed and cases["TOTALS"]["expected_total_minor"]==200,
         "totals_other_content_changed")
    for name in models:
        need(models[name]["i"]["root_presentation"]==cases["FULL"]["root_presentation"],
             "same_issuer_root_control")
    return models


def independent(name,m,o,b,stage,validators,history):
    i=m["i"];events=[]
    _,payload,parts=o.original_signature(i["root_presentation"],b.public(i["trusted_issuer_public_key_pem"]))
    need(o.inspect_graph(payload,parts)=="FULL","independent_graph")
    opening=b.resolve(payload,parts,o)["delegate_payload"][0]
    signatures={"Issuer":"VALID"}
    for role,wire,pem,typ in (
        ("Agent",i["terminal_jws"],i["expected_agent_public_key_pem"],"kb+sd-jwt"),
        ("Merchant",i["host_checkout_jws"],i["trusted_merchant_public_key_pem"],"JWT")):
        try: b.signed(wire,pem,typ,o,events,role);signatures[role]="VALID"
        except b.Reject: signatures[role]="INVALID"
    need(signatures=={"Issuer":"VALID","Agent":"VALID",
                      "Merchant":"INVALID" if name=="BAD_MERCHANT_BEFORE_TOTALS" else "VALID"},
         "signature_control")
    terminal=o.strict_json(o.decode64(i["terminal_jws"].split(".")[1]))
    cart=o.strict_json(o.decode64(i["host_checkout_jws"].split(".")[1]))
    objects=dict(open=opening,closed=terminal["delegate_payload"][0],
                 merchant=cart["merchant"],checkout=cart,item=cart["line_items"][0]["item"])
    verdict={}
    for kind,value in objects.items():
        errors=list(validators[kind].iter_errors(value))
        def leaves(e):
            return sum((leaves(x) for x in e.context),[]) if e.context else [e]
        flat=sum((leaves(e) for e in errors),[])
        verdict[kind]={"valid":not errors,"errors":[
            {"path":list(e.absolute_path),"keyword":e.validator} for e in flat]}
    need(all(v["valid"] for v in verdict.values()),"official_schema_control")
    previous=history["cases"][CASE_ORIGIN[name]]
    need(all(previous["presented"][kind]["verdict"]=="VALID"
             for kind in ("open","closed","merchant","checkout")),
         "historical_schema_control")
    code,python_events,facts=stage.evaluate(m,o,b)
    need(code==EXPECTED[name],"independent_expected_code")
    if name!="BAD_MERCHANT_BEFORE_TOTALS":
        b.binding(i,opening,o,[])
    return dict(signatures=signatures,signature_wire_sha256={
                "Issuer":sha(i["root_presentation"].split("~")[0].encode()),
                "Agent":sha(i["terminal_jws"].encode()),"Merchant":sha(i["host_checkout_jws"].encode())},
                official_schema=verdict,historical_schema_case=CASE_ORIGIN[name],code=code,
                python_events=python_events,evidence=facts)


def observe(ruby, script, data, env, remaining):
    limit=min(10,remaining-4)
    need(limit>0,"batch_cleanup_reserve")
    process=subprocess.Popen([ruby,str(script)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,env=env) # Inherit this batch worker's owned process group.
    out=err=b"";failed=False;reaped=False
    try:
        out,err=process.communicate(data,timeout=limit)
    except BaseException:
        failed=True
    finally:
        try:
            if process.poll() is None: process.kill()
            process.wait(timeout=3)
            reaped=True
        except BaseException:
            pass
    need(reaped,"UNKNOWN_ruby_child_recovery")
    need(not failed,"ruby_timeout_or_failure")
    need(process.returncode==0 and not err and len(out)<=131072,"observer_process")
    return json.loads(out)


def compare_observation(name,actual,expected):
    good=name=="FULL"
    need((actual["code"],actual["status"],actual["success"],actual["evidence"])==
         (expected["code"],"verified_research" if good else "rejected",good,expected["evidence"]),
         "public_result_mismatch")
    events=actual["events"]
    signatures=[(e["role"],e["state"]) for e in events if e["kind"]=="signature"]
    need(all(e["wire_sha256"]==expected["signature_wire_sha256"][e["role"]]
             for e in events if e["kind"]=="signature"),"signature_wire_identity")
    want=[(r,s) for r in ("Issuer","Agent","Merchant") for s in
          ("call","raise" if r=="Merchant" and name=="BAD_MERCHANT_BEFORE_TOTALS" else "return")]
    need(signatures==want,"signature_call_return_causality")
    need([e["state"] for e in events if e["kind"]=="graph"]==["call","return"],
         "graph_call_return_causality")
    issuer_return=next(i for i,e in enumerate(events) if e["kind"]=="signature" and
                       e["role"]=="Issuer" and e["state"]=="return")
    graph_return=next(i for i,e in enumerate(events) if e["kind"]=="graph" and e["state"]=="return")
    agent_call=next(i for i,e in enumerate(events) if e["kind"]=="signature" and e["role"]=="Agent")
    need(issuer_return<graph_return<agent_call,"root_graph_agent_order")
    first=[i for i,e in enumerate(events) if e["kind"]=="content_first_check"]
    if name=="BAD_MERCHANT_BEFORE_TOTALS":
        need(not first and not any(e["kind"]=="content_raise" for e in events),"content_reached_after_bad_signature")
        need(not any(e["kind"]=="binding" and e["state"]=="return" for e in events),
             "binding_returned_after_bad_signature")
    else:
        need(len(first)==1,"content_observation_unproven")
        prior=events[:first[0]]
        need(any(e["kind"]=="binding" and e["state"]=="return" for e in prior),
             "binding_not_complete_before_content")
        need([(e["role"],e["state"]) for e in prior if e["kind"]=="signature"]==want,
             "content_before_all_signature_returns")
        if not good:
            target,line,code=("quantity!",93,"invalid_scoped_schema") if name=="QUANTITY_FLOAT" else (
                "totals!",109,"amount_mismatch")
            need(any(e["kind"]=="content_raise" and e["method"]==target and e["line"]==line and
                     e["code"]==code for e in events),"wrong_content_rejection_site")
        else:
            need(not any(e["kind"]=="content_raise" for e in events) and
                 any(e["kind"]=="constraints" and e["state"]=="return" for e in events),
                 "full_content_not_returned")


def run_batch(a,out,marker,started):
    need((platform.python_implementation(),platform.python_version(),platform.system(),platform.machine())==
         ("CPython","3.11.15","Darwin","arm64"),"python_identity")
    need({k:importlib.metadata.version(k) for k in DEPS}==DEPS,"dependency_identity")
    root=Path(a.source_root)
    sources={path:read(root/path,65536) for path in SOURCES}
    need({p:sha(v) for p,v in sources.items()}==SOURCES,"product_source_pin")
    o,b,stage,history=references(root)
    raw=read(root/FIXTURE,1048576);need(sha(raw)==FIXTURE_SHA,"fixture_pin")
    validators=schemas(Path(a.schema_dir),o)
    models=saved_models(o.strict_json(raw),o,stage)
    observer=read(Path(__file__).with_name("observe.rb"),32768)
    rows={};public_inputs={}
    env={k:v for k,v in os.environ.items() if k not in ("RUBYOPT","RUBYLIB","GEM_HOME","GEM_PATH")
         and not k.startswith("BUNDLE_")}
    env.update(GEM_HOME=a.gem_home,GEM_PATH=a.gem_path,BUNDLE_IGNORE_CONFIG="1")
    try:
        with tempfile.TemporaryDirectory(prefix="e06-semantic-fixed-source-") as tmp:
            tree=Path(tmp).resolve()
            for path,value in {**sources,"research/e06_semantic_subset/observe.rb":observer}.items():
                target=tree/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(value)
            for name,m in models.items():
                expected=independent(name,m,o,b,stage,validators,history)
                inputs=stage.args(m);encoded=encode(inputs).encode()
                need(b"PRIVATE KEY" not in encoded and len(encoded)<=262144,"public_only_inputs")
                remaining=300-(time.monotonic()-started);need(remaining>0,"batch_deadline")
                actual=observe(a.ruby,tree/"research/e06_semantic_subset/observe.rb",
                               encode(dict(args=inputs)).encode(),env,remaining)
                compare_observation(name,actual,expected)
                need(actual["source_sha256"]==SOURCES,"loaded_source_identity")
                public_inputs[name]=inputs
                rows[name]=dict(expected=expected,actual=actual,
                    input_sha256=sha(encoded),wire_sha256={k:sha(inputs[k].encode()) for k in
                    ("root_presentation","terminal_jws","host_checkout_jws")},comparison="MATCH")
        need(time.monotonic()-started<=300 and len(rows)==4,"batch_completion")
        report=dict(evidence_id="E06-SEMANTIC-MBA-20261024-R1",
            scope="LIMITED_OBSERVED_E06_SEMANTIC_SUBSET_NOT_GATE_PASS",baseline=BASE,
            ap2=AP2,product_sha256=SOURCES,references_sha256=REFERENCES,schemas_sha256=SCHEMAS,
            observer_sha256=sha(observer),compare_sha256=sha(read(Path(__file__),65536)),
            dependency_versions=DEPS,cases=rows,elapsed_seconds=time.monotonic()-started,
            private_keys="NONE_USED_OR_GENERATED",signatures="EXACT_SAVED_SYNTHETIC_WIRE_REPLAY",
            fixture_sha256=FIXTURE_SHA,case_origins=CASE_ORIGIN,
            merchant_key_control_origin="WRONG_MERCHANT_KEY saved public PEM; TOTALS signed wires unchanged",
            terminal_boundary="OUT_OF_SCOPE",gate="E06_PARTIAL_OPEN",owner_core_go="NOT_GRANTED")
        (out/"PUBLIC_INPUTS.json").write_text(encode(public_inputs)+"\n")
        (out/"REPORT.json").write_text(encode(report)+"\n")
        marker.write_text(encode(dict(status="WORKER_COMPLETE_NOT_FINAL",cases=4,
                                     scope="CONTROLLER_RECOVERY_CHECK_REQUIRED")))
    except BaseException:
        marker.write_text(encode(dict(status="STOP_UNPROVEN",completed_cases=len(rows),rerun_allowed=False)))
        raise


def main():
    p=argparse.ArgumentParser(description="SOURCE_ONLY; separate Approval B required before running")
    for name in ("source-root","schema-dir","ruby","gem-home","gem-path","out"):
        p.add_argument("--"+name,required=True)
    p.add_argument("--execute-approved",action="store_true")
    p.add_argument("--_worker",action="store_true",help=argparse.SUPPRESS)
    a=p.parse_args()
    need(a.execute_approved and sys.flags.optimize==0,"execution_hold_or_optimized_python")
    sys.dont_write_bytecode=True
    out=Path(a.out)
    marker=out/"BATCH.json"
    if a._worker:
        state=json.loads(read(marker,16384))
        need(state["status"]=="STARTED" and state["controller_pid"]==os.getppid() and
             os.environ.get("E06_CONTROLLER_PID")==str(os.getppid()),"worker_without_controller")
        run_batch(a,out,marker,state["started_monotonic"])
        return
    out.mkdir(mode=0o700,exist_ok=False)
    started=time.monotonic()
    marker.write_text(encode(dict(status="STARTED",scope="E06_SEMANTIC_SUBSET",cases=4,
                                 controller_pid=os.getpid(),started_monotonic=started)))
    worker=None;failed=False;recovered=False;survivor=False
    try:
        env={**os.environ,"E06_CONTROLLER_PID":str(os.getpid()),"PYTHONDONTWRITEBYTECODE":"1"}
        worker=subprocess.Popen([sys.executable,str(Path(__file__).resolve()),*sys.argv[1:],"--_worker"],
            env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
        worker.wait(timeout=max(1,296-(time.monotonic()-started)))
        failed=worker.returncode!=0
    except BaseException:
        failed=True
    finally:
        if worker is not None:
            try:
                try:
                    os.killpg(worker.pid,0)
                    survivor=True
                    os.killpg(worker.pid,signal.SIGKILL)
                except ProcessLookupError:
                    pass
                worker.wait(timeout=1)
                end=time.monotonic()+2
                while True:
                    try: os.killpg(worker.pid,0)
                    except ProcessLookupError:
                        recovered=True
                        break
                    if time.monotonic()>=end: break
                    time.sleep(.05)
            except BaseException:
                pass
    try:
        state=json.loads(read(marker,16384))
        need(isinstance(state,dict),"marker_shape")
    except BaseException:
        state={"status":"UNREADABLE_OR_PARTIAL_WORKER_MARKER"}
    complete=(not failed and not survivor and recovered and
              state.get("status")=="WORKER_COMPLETE_NOT_FINAL" and time.monotonic()-started<=300)
    if not complete:
        marker.write_text(encode(dict(status="UNKNOWN" if not recovered else "STOP_UNPROVEN",
            worker_pid=worker.pid if worker else None,owned_group_recovered=recovered,
            worker_state=state,rerun_allowed=False)))
        raise Stop("batch_failure_or_recovery_unknown")
    try:
        report=json.loads(read(out/"REPORT.json",524288))
        report["supervision"]={"owned_group_recovered":True,"worker_pid":worker.pid,
            "total_seconds":time.monotonic()-started,"deadline_seconds":300}
        (out/"REPORT.json").write_text(encode(report)+"\n")
        marker.write_text(encode(dict(status="COMPLETE",cases=4,owned_group_recovered=True,
                                     scope="LIMITED_OBSERVED_NOT_GATE_PASS")))
    except BaseException:
        marker.write_text(encode(dict(status="STOP_UNPROVEN",phase="report_finalization",
                                     owned_group_recovered=True,rerun_allowed=False)))
        raise Stop("finalization_failed")


if __name__=="__main__":
    try: main()
    except BaseException:
        print("E06 SEMANTIC STOP/UNPROVEN; no rerun; no Host ALLOW",file=sys.stderr)
        sys.exit(1)


