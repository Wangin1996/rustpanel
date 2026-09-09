import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import signal
import stat
import subprocess
import tarfile
import tempfile
import time
import urllib.parse
import urllib.request

DEFAULT_BASE = "https://raw.githubusercontent.com/Wangin1996/rustpanel/main"
VERSION = re.compile(r"^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
DIGEST = re.compile(r"^[0-9a-f]{64}$")
NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$")
MAX_FILE = 512 * 1024 * 1024


def release_version(value):
    match = VERSION.fullmatch(value or "")
    if not match:
        raise ValueError("invalid stable release version")
    return tuple(int(part) for part in match.groups())


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def manifest(directory, expected="", now=None):
    with (Path(directory) / "release.json").open("rb") as handle:
        raw = handle.read(65537)
    if len(raw) > 65536:
        raise ValueError("release manifest exceeds size limit")
    if expected and (not DIGEST.fullmatch(expected) or hashlib.sha256(raw).hexdigest() != expected):
        raise ValueError("release changed after update confirmation")
    data = json.loads(raw, object_pairs_hook=unique_object)
    clock = int(time.time()) if now is None else now
    if data.get("format") != 1:
        raise ValueError("unsupported release manifest")
    release_version(data.get("panel_version"))
    release_version(data.get("agent_version"))
    if type(data.get("published_at")) is not int or type(data.get("expires_at")) is not int or not data["published_at"] <= clock + 300 or not data["expires_at"] > max(clock, data["published_at"]):
        raise ValueError("expired or future release manifest")
    files = data.get("files", {})
    for name, item in files.items():
        if not NAME.fullmatch(name) or ".." in name or not DIGEST.fullmatch(item.get("sha256", "")) or type(item.get("size")) is not int or not 0 < item["size"] <= MAX_FILE:
            raise ValueError("invalid artifact metadata")
    for name in ("rust-panel", "web.tar.gz", "xboard-node", "xboard-node.sha256", "xboard-node.version", "install-panel.sh", "install-node.sh", "rust-panel.service", "xboard-node.service", "nginx-panel.conf", "release-verify.py", "panel-update-helper.sh", "rust-panel-update.service", "rust-panel-update.path"):
        if name not in files:
            raise ValueError("incomplete release manifest")
    return data


def artifact(directory, data, name):
    if not NAME.fullmatch(name) or ".." in name or name not in data["files"]:
        raise ValueError("unknown artifact")
    location = Path(directory) / name
    metadata = location.lstat()
    expected = data["files"][name]
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_size != expected["size"]:
        raise ValueError("artifact type or size mismatch: " + name)
    digest = hashlib.sha256()
    with location.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != expected["sha256"]:
        raise ValueError("artifact SHA-256 mismatch: " + name)
    return location


def extract_web(directory, data):
    archive = artifact(directory, data, "web.tar.gz")
    output = Path(directory) / "web"
    output.mkdir(mode=0o700)
    with tarfile.open(archive, "r:gz") as handle:
        members = []
        names = set()
        total = 0
        for item in handle:
            total += item.size
            if len(members) >= 5000 or total > 256 * 1024 * 1024:
                raise ValueError("Web archive exceeds extraction limits")
            path = PurePosixPath(item.name)
            if path.is_absolute() or ".." in path.parts or "\\" in item.name or not (item.isdir() or item.isfile()):
                raise ValueError("unsafe Web archive entry")
            if not (path.parts[:2] == ("xboard-admin", "dist") or path.parts[:1] == ("user-portal",) or (path.parts == ("xboard-admin",) and item.isdir())):
                raise ValueError("unexpected Web archive entry")
            if str(path) in names or item.size < 0 or item.issparse():
                raise ValueError("duplicate or sparse Web archive entry")
            names.add(str(path))
            item.mode = 0o755 if item.isdir() else 0o644
            item.uid = item.gid = 0
            item.uname = item.gname = ""
            members.append(item)
        for item in members:
            handle.extract(item, output)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        raise ValueError("release redirects are disabled")


def download(base, name, destination, limit):
    parsed = urllib.parse.urlparse(base)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment or not NAME.fullmatch(name):
        raise ValueError("invalid HTTPS release location")
    request = urllib.request.Request(base.rstrip("/") + "/" + name, headers={"Cache-Control": "no-cache"})
    opener = urllib.request.build_opener(NoRedirect())
    total = 0
    with opener.open(request, timeout=30) as response, open(destination, "xb") as output:
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > limit:
                raise ValueError("release download exceeds size limit")
            output.write(chunk)


def apply_request():
    import fcntl

    if os.geteuid() != 0:
        raise PermissionError("updater helper must be run by its systemd service")
    root = Path("/var/lib/rust-panel-updater")
    root.mkdir(mode=0o755, exist_ok=True)
    root_metadata = root.lstat()
    if not stat.S_ISDIR(root_metadata.st_mode) or root_metadata.st_uid != 0 or root_metadata.st_mode & 0o022:
        raise PermissionError("updater state directory must be root-owned and not group-writable")
    root.chmod(0o755)
    request_path = Path("/var/lib/rust-panel/panel-update.request")
    request = {}

    def status(phase, message):
        value = {"phase": phase, "message": message, "request_id": request.get("request_id"), "target_version": request.get("target_version"), "updated_at": int(time.time())}
        temporary = root / "status.tmp"
        temporary.write_text(json.dumps(value), encoding="utf-8")
        temporary.chmod(0o644)
        os.replace(temporary, root / "status.json")

    with (root / "lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            descriptor = os.open(request_path, os.O_RDONLY | os.O_NOFOLLOW)
            with os.fdopen(descriptor, "rb") as handle:
                metadata = os.fstat(handle.fileno())
                if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > 1024:
                    raise ValueError("invalid update request file")
                request = json.loads(handle.read(1025), object_pairs_hook=unique_object)
            request_path.unlink()
            if not re.fullmatch(r"panel-update-[0-9a-f]{48}", request.get("request_id", "")) or not DIGEST.fullmatch(request.get("manifest_sha256", "")):
                raise ValueError("invalid update request")
            current = Path("/opt/rust-panel/.release-version").read_text().strip()
            if release_version(request.get("target_version")) <= release_version(current):
                raise ValueError("same-version updates and downgrades are refused")
            base_file = Path("/etc/rust-panel/update-base")
            base = base_file.read_text().strip() if base_file.exists() else DEFAULT_BASE
            status("downloading", "Downloading and verifying release files")
            with tempfile.TemporaryDirectory(prefix="rust-panel-update-") as temporary:
                stage = Path(temporary)
                download(base, "release.json", stage / "release.json", 65536)
                data = manifest(stage, request["manifest_sha256"])
                if data["panel_version"] != request["target_version"]:
                    raise ValueError("release version changed after confirmation")
                download(base, "install-panel.sh", stage / "install-panel.sh", data["files"]["install-panel.sh"]["size"])
                installer = artifact(stage, data, "install-panel.sh")
                status("installing", "Installing verified files; panel will briefly restart")
                environment = {"PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", "HOME": "/root", "LANG": "C.UTF-8", "RP_BASE": base, "RP_EXPECTED_MANIFEST_SHA256": request["manifest_sha256"]}
                process = subprocess.Popen(["bash", str(installer)], env=environment, start_new_session=True)
                try:
                    result = process.wait(timeout=600)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=30)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                    raise RuntimeError("installer timed out; inspect service and rollback logs")
                if result:
                    raise RuntimeError("installer failed; previous files were restored where available")
            status("succeeded", "Panel update completed and health check passed")
        except Exception as error:
            if request_path.exists() or request_path.is_symlink():
                request_path.unlink()
            status("failed", str(error)[:240])
            raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["manifest", "file", "download", "extract-web", "apply-request"])
    parser.add_argument("directory", nargs="?", default=".")
    parser.add_argument("name", nargs="?")
    parser.add_argument("--expected-digest", default="")
    parser.add_argument("--base", default=DEFAULT_BASE)
    arguments = parser.parse_args()
    if arguments.command == "apply-request":
        apply_request()
    else:
        release = manifest(arguments.directory, arguments.expected_digest)
        if arguments.command == "download":
            if arguments.name not in release["files"] or not NAME.fullmatch(arguments.name) or ".." in arguments.name:
                raise ValueError("unknown artifact")
            download(arguments.base, arguments.name, Path(arguments.directory) / arguments.name, release["files"][arguments.name]["size"])
            artifact(arguments.directory, release, arguments.name)
        elif arguments.command == "file":
            artifact(arguments.directory, release, arguments.name)
        elif arguments.command == "extract-web":
            extract_web(arguments.directory, release)
        else:
            print(release["panel_version"])
