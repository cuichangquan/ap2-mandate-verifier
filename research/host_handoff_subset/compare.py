"""NOT_RUN: bounded future controller, no third-party imports or signing."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import time

BASE = 'feb3c426365b5bb9d2fe2752a30f0e08f7eee48c'
INPUT_SHA = 'cc26cf7115c59c5e44c34a5a051f7dd17577958c32df7113ecbe022bb390a4f5'
# Independent transition oracle: never derived from verifier output.
EXPECTED = {
 'NORMAL': (['MODEL_COMMIT'], 'consumed', 'accepted', 1),
 'REPLAY': (['MODEL_COMMIT', 'REPLAY_REJECT'], 'consumed', 'accepted', 1),
 'KEY_REVOKED_AFTER_EVIDENCE': (['KEY_REJECT'], 'issued', 'open', 0),
 'ORDER_CHANGED_AFTER_EVIDENCE': (['ORDER_REJECT'], 'issued', 'open', 0),
 'ROTATED_OLD_KEY': (['KEY_REJECT'], 'issued', 'open', 0),
 'PROFILE_SNAPSHOT_ROLLBACK': (['ROLLBACK_REJECT'], 'issued', 'open', 0),
 'TRUST_UNAVAILABLE': (['HOLD'], 'issued', 'open', 0),
 'CONSUMPTION_UNKNOWN': (['PENDING', 'PENDING'], 'pending', 'unknown', 1),
}
PINS = {
 'lib/ap2_mandate_verifier.rb':'4824eeef1ce6c7833bcc24bc0bf9abc265df0b35ba135e54b4341b54c2f65ef2',
 'host_binding':'917a4c139accd77d5bbe9125c64ea258349b6854ac04e0fefe33536b9b88ec0a',
 'input_validator':'395f8e6f2012ab400d7b17f1fdcf4ee63a3c1c9622da4f2b32d35b522542bf00',
 'purchase_binding':'6f2108ac3298e4558fc053139d045d399687ccc3bf39c01945ed52d529dc26df',
 'research_result':'02159d2f451461ef818d7b6c9d55349cdfb6e23d9ced7d688730d22c8e96827d',
 'result':'fade8a1e922f7b4cf2439c120580160f85e0f22f6cfac9ff1ab1364d7b34d310',
 'root_disclosures':'55e97aa3b606eee64afbf929941fabb24286755297e1ed5bf48a5066e1352df6',
 'root_signature':'d9b68d989700a0c103f80004e14fb2d3aa992f823434e07bf2971f63052519dd',
 'scoped_constraints':'b2b5fa4cd1b4ce83cfc5ffc1be0a09ce57ad4a1b9be6778e581dd38f5ce5fd84',
 'trust_context':'430eb9f9f3be4c0d7e799e95b68009c08582b6961aa954cc866ff012a3b2be36',
}

def need(ok, reason):
    if not ok:
        raise RuntimeError(reason)

def digest(raw):
    return hashlib.sha256(raw).hexdigest()

def read(path, cap):
    before = os.lstat(path)
    need(stat.S_ISREG(before.st_mode) and 0 < before.st_size <= cap, 'regular read')
    fields = lambda s: (s.st_dev, s.st_ino, s.st_mode, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, 'rb') as stream:
        opened = os.fstat(stream.fileno())
        need(fields(before) == fields(opened), 'read identity')
        raw = stream.read(cap + 1)
        need(fields(opened) == fields(os.fstat(stream.fileno())) == fields(os.lstat(path)), 'read changed')
    need(0 < len(raw) <= cap, 'read size')
    return raw

def save(path, value):
    with path.open('x', encoding='utf-8') as stream:
        json.dump(value, stream, ensure_ascii=True, allow_nan=False, indent=2)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--execute-approved', action='store_true')
    parser.add_argument('--_worker', action='store_true', help=argparse.SUPPRESS)
    for name in ['source-root', 'inputs', 'ruby', 'gem-home', 'gem-path', 'out']:
        parser.add_argument('--' + name, required=True)
    opt = parser.parse_args()
    need(opt.execute_approved and sys.flags.optimize == 0, 'execution approval / optimization')
    started = time.monotonic()
    deadline = started + 300
    out = Path(opt.out)
    if not opt._worker:
        supervise(opt, out, started)
        return
    need(os.environ.get('HANDOFF_CONTROLLER') == str(os.getppid()), 'owned worker only')
    # Exclusive directory is the once guard. An existing failed directory is never reused.
    rows, process, recovered = [], None, True
    try:
        need(sys.platform == 'darwin', 'MBA only')
        sources = {}
        frozen_root = out / 'source'
        (frozen_root / 'lib/ap2_mandate_verifier').mkdir(parents=True)
        for key, pin in PINS.items():
            name = key if key.endswith('.rb') else 'lib/ap2_mandate_verifier/' + key + '.rb'
            source = read(Path(opt.source_root) / name, 65536)
            need(digest(source) == pin, 'product pin')
            target = frozen_root / name
            with target.open('xb') as stream:
                stream.write(source)
            target.chmod(0o400)
            sources[name] = pin
        raw = read(Path(opt.inputs), 262144)
        need(digest(raw) == INPUT_SHA, 'saved input pin')
        args = json.loads(raw)['FULL']
        observer_source = read(Path(__file__).with_name('observe.rb'), 65536)
        observer_sha = digest(observer_source)
        observer = out / 'observe.rb'
        with observer.open('xb') as stream:
            stream.write(observer_source)
        observer.chmod(0o400)
        env = {'PATH':'/usr/bin:/bin', 'HOME':str(out.resolve()), 'GEM_HOME':opt.gem_home,
               'GEM_PATH':opt.gem_path, 'LANG':'C.UTF-8'}
        for case, expected in EXPECTED.items():
            need(time.monotonic() + 11 < deadline, 'batch deadline')
            request = json.dumps({'scenario':case, 'args':args}, separators=(',', ':')).encode()
            need(len(request) <= 262144, 'request cap')
            # No child is allowed to spawn helpers. Each owns a process group for cleanup.
            process = subprocess.Popen([opt.ruby, str(observer), str(frozen_root.resolve())],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                env=env)
            recovered = False
            try:
                stdout, stderr = process.communicate(request, timeout=10)
            finally:
                # Ruby has no helper-spawning code. Outer controller owns the whole group.
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=1)
                recovered = True
            need(process.returncode == 0 and not stderr and len(stdout) <= 65536, 'child failed')
            row = json.loads(stdout)
            need(row['scenario'] == case and row['evidence_created'] is True and
                 row['gem_code'] == 'scoped_research_verified', 'real Evidence prerequisite')
            actual = (row['verdicts'], row['nonce_state'], row['order_state'], row['attempts'])
            need(actual == expected, 'Host transition mismatch')
            rows.append(row)
        need(time.monotonic() <= deadline and recovered, 'final budget / recovery')
        save(out / 'WORKER.json', {'status':'WORKER_COMPLETE_NOT_FINAL', 'baseline':BASE,
             'source_sha256':sources, 'inputs_sha256':INPUT_SHA,
             'compare_sha256':digest(read(Path(__file__), 65536)), 'observe_sha256':observer_sha,
             'seconds':time.monotonic()-started, 'completed':len(rows), 'results':rows,
             'network':0, 'db_atomicity_proved':False, 'production_go':False})
    except BaseException as error:
        save(out / 'STOP.json', {'status':'STOP_UNPROVEN' if recovered else 'UNKNOWN',
             'completed':len(rows), 'seconds':time.monotonic()-started,
             'exception_class':type(error).__name__, 'rerun_allowed':False})
        raise SystemExit('STOP: see sanitized local record') from None

def supervise(opt, out, started):
    out.mkdir(mode=0o700, parents=False, exist_ok=False)
    # Exclusive receipt/directory is never removed or reused after failure.
    save(out / 'BATCH.json', {'state':'STARTED', 'rerun_allowed':False})
    env = dict(os.environ, HANDOFF_CONTROLLER=str(os.getpid()), PYTHONDONTWRITEBYTECODE='1')
    worker, recovered, code, failed = None, False, None, False
    cleanup_errors = []
    try:
        worker = subprocess.Popen([sys.executable, '-B', str(Path(__file__).resolve()),
            *sys.argv[1:], '--_worker'], env=env, start_new_session=True,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        code = worker.wait(timeout=max(0.1, 296-(time.monotonic()-started)))
    except BaseException:
        failed = True
    finally:
        if worker is not None:
            try:
                os.killpg(worker.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            except BaseException as error:
                cleanup_errors.append(type(error).__name__)
            try:
                worker.wait(timeout=1)
            except BaseException as error:
                cleanup_errors.append(type(error).__name__)
            until = min(started+299, time.monotonic()+2)
            while time.monotonic() < until:
                try:
                    os.killpg(worker.pid, 0)
                except ProcessLookupError:
                    recovered = True
                    break
                except BaseException as error:
                    cleanup_errors.append(type(error).__name__)
                    break
                time.sleep(0.01)
        save(out / 'SUPERVISION.json', {'worker_exit':code, 'group_recovered':recovered,
             'cleanup_errors':cleanup_errors, 'seconds':time.monotonic()-started, 'rerun_allowed':False})
    if failed or code != 0 or cleanup_errors or not recovered or time.monotonic()-started >= 300:
        save(out / 'CONTROLLER_STOP.json', {'status':'STOP_UNPROVEN' if recovered and not cleanup_errors else 'UNKNOWN',
             'worker_exit':code, 'group_recovered':recovered, 'cleanup_errors':cleanup_errors, 'rerun_allowed':False})
        raise SystemExit('STOP: see supervision record')
    report = json.loads(read(out / 'WORKER.json', 65536))
    need(report['completed'] == 8, 'incomplete batch')
    report.update(status='LIMITED_OBSERVED', seconds=time.monotonic()-started,
                  owned_group_recovered=True)
    save(out / 'REPORT.json', report)

if __name__ == '__main__':
    main()
