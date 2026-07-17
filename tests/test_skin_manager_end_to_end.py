#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import plistlib
import signal
import subprocess
import tempfile
import time
from pathlib import Path


APP = Path.home() / "Applications" / "Codex 皮肤管理器.app"
EXECUTABLE = APP / "Contents" / "MacOS" / "CodexSkinManager"
OFFICIAL_EXECUTABLE = Path("/Applications/ChatGPT.app/Contents/MacOS/ChatGPT")
REAL_STATE = Path.home() / "Library" / "Application Support" / "CodexSkinManager"
EXPECTED = {
    "meng-chuan-nightblade": ("1.0.1", "nightblade-v1"),
    "meng-chuan-red-lotus": ("1.0.1", "red-lotus-v1"),
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tree_fingerprint(root: Path) -> dict[str, tuple[int, str]]:
    if not root.exists():
        return {}
    return {
        str(path.relative_to(root)): (path.stat().st_size, sha256(path))
        for path in root.rglob("*")
        if path.is_file()
    }


def wait_until(predicate, *, timeout: float, label: str) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.1)
    raise AssertionError(f"timed out waiting for {label}")


def validate_installed_skin(directory: Path, expected_template: str) -> None:
    manifest = json.loads((directory / "manifest.json").read_text())
    rights = json.loads((directory / "rights.json").read_text())
    receipt = json.loads((directory / "installation.json").read_text())
    assert manifest["template"] == expected_template
    assert rights["redistributionAllowed"] is True
    assert rights["fanMade"] is True and rights["unofficial"] is True
    assert receipt["schemaVersion"] == 1
    assert receipt["trust"]["kind"] == "unsigned"
    for descriptor in receipt["files"]:
        path = directory / descriptor["path"]
        assert path.is_file()
        assert path.stat().st_size == descriptor["byteCount"]
        assert sha256(path) == descriptor["sha256"]
    preview = directory / manifest["preview"]
    assert preview.read_bytes().startswith(b"\x89PNG\r\n\x1a\n")
    assert b"caBX" not in preview.read_bytes()


def main() -> int:
    assert APP.is_dir() and EXECUTABLE.is_file() and os.access(EXECUTABLE, os.X_OK)
    with (APP / "Contents" / "Info.plist").open("rb") as handle:
        assert plistlib.load(handle)["CFBundleIdentifier"] == "com.opcspace.codex-skin-manager"
    official_before = sha256(OFFICIAL_EXECUTABLE)
    real_state_before = tree_fingerprint(REAL_STATE)

    with tempfile.TemporaryDirectory(prefix="codex-skin-manager-e2e-") as temporary:
        root = Path(temporary) / "state"
        env = os.environ.copy()
        env["CODEX_SKIN_MANAGER_STATE_ROOT"] = str(root)
        env["CODEX_SKIN_MANAGER_UI_TEST"] = "1"
        process = subprocess.Popen(
            [str(EXECUTABLE)],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        try:
            marker = root / "runtime" / "ui-ready.json"
            wait_until(marker.is_file, timeout=15, label="SwiftUI window marker")
            marker_data = json.loads(marker.read_text())
            assert marker_data == {"pid": process.pid, "visible": True}
            for skin_id, (version, _) in EXPECTED.items():
                wait_until(
                    (root / "skins" / skin_id / version / "installation.json").is_file,
                    timeout=20,
                    label=f"bundled skin {skin_id}",
                )
            assert process.poll() is None, "manager exited during bootstrap"
            for skin_id, (version, template) in EXPECTED.items():
                validate_installed_skin(root / "skins" / skin_id / version, template)
            assert not (root / "active.json").exists()
            assert not (root / "runtime" / "injector.pid").exists()
            time.sleep(1)
            assert process.poll() is None, "manager did not keep its main scene alive"
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)
        assert not (root / "runtime" / "injector.pid").exists()

    assert sha256(OFFICIAL_EXECUTABLE) == official_before
    assert tree_fingerprint(REAL_STATE) == real_state_before
    subprocess.run(
        ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(APP)],
        check=True,
        capture_output=True,
    )
    print("Codex Skin Manager end-to-end launch and isolated bootstrap passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
