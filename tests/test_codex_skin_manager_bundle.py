#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import plistlib
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "scripts" / "build_codex_skin_manager_app.py"
BUILD_APP = ROOT / "build" / "Codex 皮肤管理器.app"
INSTALLED_APP = Path.home() / "Applications" / "Codex 皮肤管理器.app"
ICON_SOURCE = ROOT / "skin-manager" / "Resources" / "AppIcon-1024.png"


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, check=True, text=True, capture_output=True)


def inspect_bundle(app: Path) -> None:
    assert app.is_dir(), f"missing app bundle: {app}"
    plist_path = app / "Contents" / "Info.plist"
    executable = app / "Contents" / "MacOS" / "CodexSkinManager"
    resources = app / "Contents" / "Resources"
    app_icon = resources / "AppIcon.icns"
    assert plist_path.is_file()
    assert executable.is_file() and os.access(executable, os.X_OK)
    assert ICON_SOURCE.is_file(), f"missing icon master: {ICON_SOURCE}"
    source_properties = run([
        "/usr/bin/sips",
        "-g", "pixelWidth",
        "-g", "pixelHeight",
        str(ICON_SOURCE),
    ]).stdout
    assert "pixelWidth: 1024" in source_properties
    assert "pixelHeight: 1024" in source_properties
    assert app_icon.is_file() and app_icon.stat().st_size > 10_000
    assert (resources / "Engine" / "injector.mjs").is_file()
    assert (resources / "Engine" / "renderer-inject.js").is_file()
    assert (resources / "Templates" / "nightblade-v1.css").is_file()
    assert (resources / "Templates" / "red-lotus-v1.css").is_file()
    assert (resources / "Templates" / "undying-phoenix-v1.css").is_file()
    assert (resources / "BuiltinSkins" / "nightblade" / "manifest.json").is_file()
    assert (resources / "BuiltinSkins" / "red-lotus" / "manifest.json").is_file()

    with plist_path.open("rb") as handle:
        plist = plistlib.load(handle)
    assert plist["CFBundleIdentifier"] == "com.opcspace.codex-skin-manager"
    assert plist["CFBundleExecutable"] == "CodexSkinManager"
    assert plist["CFBundleShortVersionString"] == "1.1.3"
    assert plist["CFBundleVersion"] == "3"
    assert plist["CFBundleIconFile"] == "AppIcon"
    assert plist["LSMinimumSystemVersion"] == "13.0"
    assert plist["NSHighResolutionCapable"] is True
    exported = plist["UTExportedTypeDeclarations"]
    assert any(item["UTTypeIdentifier"] == "com.opcspace.codexskin" for item in exported)
    document_types = plist["CFBundleDocumentTypes"]
    assert any("com.opcspace.codexskin" in item["LSItemContentTypes"] for item in document_types)
    codexskin_type = next(item for item in exported if item["UTTypeIdentifier"] == "com.opcspace.codexskin")
    assert codexskin_type["UTTypeTagSpecification"]["public.filename-extension"] == ["codexskin"]

    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)])
    signature = run(["/usr/bin/codesign", "-dv", "--verbose=4", str(app)]).stderr
    assert "Signature=adhoc" in signature

    forbidden = [
        b"/.worktrees/skin-manager",
        str(ROOT).encode(),
    ]
    for path in [executable, plist_path, resources / "Engine" / "injector.mjs"]:
        payload = path.read_bytes()
        assert not any(marker in payload for marker in forbidden), f"embedded workspace path in {path}"

    assert not (app / "Contents" / "Resources" / "active.json").exists()
    assert not any(path.suffix in {".sh", ".command"} for path in resources.rglob("*"))


def main() -> int:
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--install", action="store_true", help="build, install, and inspect the requested destination")
    group.add_argument("--installed", action="store_true", help="inspect the already-installed app without rebuilding")
    args = parser.parse_args()

    if args.installed:
        app = INSTALLED_APP
    else:
        assert BUILDER.is_file(), f"missing bundle builder: {BUILDER}"
        command = [sys.executable, str(BUILDER)]
        if args.install:
            command.append("--install")
        run(command)
        app = INSTALLED_APP if args.install else BUILD_APP
    inspect_bundle(app)
    print(f"Codex Skin Manager bundle is valid: {app}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
