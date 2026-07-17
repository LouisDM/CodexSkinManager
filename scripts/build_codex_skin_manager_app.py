#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "skin-manager"
INFO_PLIST = PACKAGE / "Resources" / "Info.plist"
APP_ICON_SOURCE = PACKAGE / "Resources" / "AppIcon-1024.png"
RESOURCE_SOURCE = PACKAGE / "Sources" / "CodexSkinManager" / "Resources"
BUILD_ROOT = ROOT / "build"
APP_NAME = "Codex 皮肤管理器.app"
BUILD_APP = BUILD_ROOT / APP_NAME
DEFAULT_INSTALL_APP = Path.home() / "Applications" / APP_NAME


def run(command: list[str], *, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=cwd, check=True, text=True, capture_output=True)


def replace_directory(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    incoming = destination.parent / f".{destination.name}.incoming-{uuid.uuid4().hex}"
    backup = destination.parent / f".{destination.name}.backup-{uuid.uuid4().hex}"
    shutil.copytree(source, incoming, symlinks=False, copy_function=shutil.copy2)
    moved_existing = False
    try:
        if destination.exists():
            os.replace(destination, backup)
            moved_existing = True
        os.replace(incoming, destination)
    except Exception:
        if incoming.exists():
            shutil.rmtree(incoming)
        if moved_existing and backup.exists() and not destination.exists():
            os.replace(backup, destination)
        raise
    if backup.exists():
        shutil.rmtree(backup)


def build_app_icon(iconset: Path, destination: Path) -> None:
    if not APP_ICON_SOURCE.is_file():
        raise FileNotFoundError(APP_ICON_SOURCE)
    iconset.mkdir(parents=True)
    representations = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for filename, size in representations.items():
        run([
            "/usr/bin/sips",
            "-z", str(size), str(size),
            str(APP_ICON_SOURCE),
            "--out", str(iconset / filename),
        ])
    run(["/usr/bin/iconutil", "-c", "icns", str(iconset), "-o", str(destination)])
    os.chmod(destination, 0o644)


def build_app() -> Path:
    if not INFO_PLIST.is_file():
        raise FileNotFoundError(INFO_PLIST)
    run(["/usr/bin/swift", "build", "-c", "release"], cwd=PACKAGE)
    bin_path = Path(run(["/usr/bin/swift", "build", "-c", "release", "--show-bin-path"], cwd=PACKAGE).stdout.strip())
    executable = bin_path / "CodexSkinManager"
    if not executable.is_file():
        raise FileNotFoundError(executable)

    BUILD_ROOT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="codex-skin-manager-app-", dir=BUILD_ROOT) as temporary:
        stage = Path(temporary) / APP_NAME
        contents = stage / "Contents"
        macos = contents / "MacOS"
        resources = contents / "Resources"
        macos.mkdir(parents=True)
        shutil.copy2(INFO_PLIST, contents / "Info.plist")
        shutil.copy2(executable, macos / "CodexSkinManager")
        os.chmod(macos / "CodexSkinManager", 0o755)
        run(["/usr/bin/strip", "-S", str(macos / "CodexSkinManager")])
        shutil.copytree(RESOURCE_SOURCE, resources, symlinks=False, copy_function=shutil.copy2)
        build_app_icon(Path(temporary) / "AppIcon.iconset", resources / "AppIcon.icns")
        for path in resources.rglob("*"):
            if path.is_file():
                os.chmod(path, 0o644)

        run(["/usr/bin/xattr", "-cr", str(stage)])
        run([
            "/usr/bin/codesign",
            "--force",
            "--deep",
            "--sign", "-",
            "--timestamp=none",
            str(stage),
        ])
        run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(stage)])
        replace_directory(stage, BUILD_APP)
    return BUILD_APP


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the native Codex Skin Manager app bundle")
    parser.add_argument("--install", action="store_true", help="atomically install under ~/Applications")
    parser.add_argument("--destination", type=Path, help="override the install destination (requires --install)")
    args = parser.parse_args()
    if args.destination and not args.install:
        parser.error("--destination requires --install")

    app = build_app()
    if args.install:
        destination = (args.destination or DEFAULT_INSTALL_APP).expanduser().resolve()
        allowed_parent = (Path.home() / "Applications").resolve()
        if destination.parent != allowed_parent and args.destination is None:
            raise RuntimeError("default installation escaped ~/Applications")
        replace_directory(app, destination)
        run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(destination)])
        app = destination
    print(app)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
