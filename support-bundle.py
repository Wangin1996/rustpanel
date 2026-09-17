#!/usr/bin/env python3
"""Collect an allowlisted local diagnostic snapshot. Never read panel.env or logs."""
import json
import re
import subprocess
import time
from pathlib import Path


def collect(run=subprocess.run, read=lambda path: Path(path).read_text()):
    result = {"format": "rust-panel-support-v1", "collected_at": int(time.time())}
    for name in ("rust-panel", "xboard-node"):
        command = [f"/opt/{name}/{name}", "--version" if name == "rust-panel" else "-v"]
        try:
            output = run(command, capture_output=True, text=True, timeout=5)
            # Export version only, not arbitrary process output or build paths.
            found = re.search(r"\bv[0-9]+\.[0-9]+\.[0-9]+\b", output.stdout)
            result[name] = {"version": found.group() if found else "unknown"}
        except (OSError, subprocess.TimeoutExpired):
            result[name] = {"version": "unavailable"}
    for name in ("rust-panel", "xboard-node", "rust-panel-update", "rust-panel-update.path"):
        try:
            output = run(["systemctl", "show", name, "--property=ActiveState,SubState,Result,ExecMainStatus"], capture_output=True, text=True, timeout=5)
            allowed = {"ActiveState", "SubState", "Result", "ExecMainStatus"}
            result.setdefault("services", {})[name] = {key: value for line in output.stdout.splitlines() if "=" in line for key, value in [line.split("=", 1)] if key in allowed and re.fullmatch(r"[a-z0-9-]{1,32}", value)}
        except (OSError, subprocess.TimeoutExpired):
            pass
    try:
        status = json.loads(read("/var/lib/rust-panel-updater/status.json"))
        result["update"] = {}
        if status.get('phase') in ('queued', 'downloading', 'installing', 'succeeded', 'failed'):
            result['update']['phase'] = status['phase']
        if re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+', str(status.get('target_version', ''))):
            result['update']['target_version'] = status['target_version']
        if type(status.get('updated_at')) is int:
            result['update']['updated_at'] = status['updated_at']
    except (OSError, ValueError):
        pass
    return result


if __name__ == "__main__":
    print(json.dumps(collect(), ensure_ascii=False, indent=2))
