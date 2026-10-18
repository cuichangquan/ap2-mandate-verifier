"""One read-only systemctl query; no U6 mechanism imports or experiment setup."""
import datetime
import json
import os
from pathlib import Path
import platform
import selectors
import signal
import subprocess
import sys
import time

ARGV = ("/usr/bin/systemctl", "is-system-running")
STREAM_CAP = 4096
RESULT_CAP = 65536
QUERY_SECONDS = 4
STATES = {"initializing", "starting", "running", "degraded", "maintenance",
          "stopping", "offline", "unknown"}


def kill_query(proc):
    # This group contains only our fixed read-only query, never a system service.
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def capture(proc, *, clock=time.monotonic, selector_factory=selectors.DefaultSelector,
            read=os.read, terminate=kill_query, deadline_seconds=QUERY_SECONDS):
    kept = {"stdout": bytearray(), "stderr": bytearray()}
    seen = {"stdout": 0, "stderr": 0}
    reason = None
    cleanup = False
    start = clock()
    try:
        with selector_factory() as sel:
            for name in kept:
                sel.register(getattr(proc, name), selectors.EVENT_READ, name)
            while sel.get_map() or proc.poll() is None:
                if clock()-start >= deadline_seconds:
                    reason = "COMMAND_TIMEOUT"
                    break
                for key, _ in sel.select(0.05):
                    name = key.data
                    chunk = read(key.fd, min(1024, STREAM_CAP+1-seen[name]))
                    if not chunk:
                        sel.unregister(key.fileobj)
                        continue
                    seen[name] += len(chunk)
                    kept[name].extend(chunk[:STREAM_CAP-len(kept[name])])
                    if seen[name] > STREAM_CAP:
                        reason = "COMMAND_OUTPUT_LIMIT"
                        break
                if reason:
                    break
        if reason:
            terminate(proc)
        proc.wait(timeout=1)
        cleanup = True
    except Exception as exc:
        reason = reason or "CAPTURE_ERROR_"+type(exc).__name__
    finally:
        try:
            if not cleanup:
                terminate(proc)
                proc.wait(timeout=1)
                cleanup = True
        except Exception:
            cleanup = False
        for name in kept:
            getattr(proc, name).close()
    return {"returncode": proc.returncode, "failure": reason,
            "query_reaped": cleanup, "seconds": round(clock()-start, 6),
            **{name: bytes(data).decode("utf-8", "backslashreplace") for name, data in kept.items()},
            "bytes_read": seen, "stream_cap": STREAM_CAP,
            "truncated": {name: seen[name] > STREAM_CAP for name in kept}}


def classify(row):
    if not row["query_reaped"]:
        return "COMMAND_CLEANUP_UNCONFIRMED"
    if row["failure"]:
        return row["failure"]
    if row["returncode"] is None:
        return "COMMAND_EXIT_UNKNOWN"
    if row["returncode"] < 0:
        return "COMMAND_SIGNAL"
    if row["returncode"] != 0:
        return "COMMAND_NONZERO"
    if row["stdout"] != "running\n" or row["stderr"]:
        return "COMMAND_UNEXPECTED_OUTPUT"
    return "QUERY_RUNNING_OBSERVED"


def main():
    result = {"scope": "DIAGNOSTIC_ONLY_NINE_MECHANISMS_NOT_RUN",
              "argv": ARGV, "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "sha": os.environ.get("GITHUB_SHA"), "run": os.environ.get("GITHUB_RUN_ID"),
              "attempt": os.environ.get("GITHUB_RUN_ATTEMPT"), "queries_attempted": 0,
              "experiment_units_created": 0, "experiment_directories_created": 0,
              "status": "STOP_NO_RETRY"}
    try:
        if platform.system() != "Linux" or os.geteuid() != 0:
            raise RuntimeError("LINUX_ROOT_REQUIRED")
        if 'VERSION_ID="24.04"' not in Path('/etc/os-release').read_text():
            raise RuntimeError("UBUNTU_24_04_REQUIRED")
        result["queries_attempted"] = 1
        try:
            proc = subprocess.Popen(ARGV, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, start_new_session=True,
                                    env={"PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C",
                                         "SYSTEMD_COLORS": "0"})
        except OSError as exc:
            result["classification"] = "COMMAND_SPAWN_ERROR"
            result["spawn_error"] = {"type": type(exc).__name__, "errno": exc.errno}
        else:
            row = capture(proc)
            result["query"] = row
            state = row["stdout"].strip()
            result["reported_system_state"] = state if state in STATES else "UNRECOGNIZED"
            result["classification"] = classify(row)
            if result["classification"] == "QUERY_RUNNING_OBSERVED":
                result["status"] = "DIAGNOSTIC_OBSERVED_ONLY"
    except Exception as exc:
        result["classification"] = "DIAGNOSTIC_PRECONDITION_OR_INTERNAL_ERROR"
        result["error_type"] = type(exc).__name__
    result["ended_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    payload = json.dumps(result, sort_keys=True, ensure_ascii=True).encode()+b"\n"
    if len(payload) > RESULT_CAP:
        payload = b'{"status":"STOP_NO_RETRY","classification":"RESULT_LIMIT"}\n'
        result["status"] = "STOP_NO_RETRY"
    Path("u6-diagnostic-result.json").write_bytes(payload)
    return 0 if result["status"] == "DIAGNOSTIC_OBSERVED_ONLY" else 78


if __name__ == "__main__":
    sys.exit(main())
