#!/usr/bin/env python3
"""Build versioned GitHub Release assets from the repository source."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "skin-manager"
BUILTINS = PACKAGE / "Sources" / "CodexSkinManager" / "Resources" / "BuiltinSkins"
SKINS = ROOT / "skins"
APP_BUILDER = ROOT / "scripts" / "build_codex_skin_manager_app.py"
AUTHORING_PACKAGER = ROOT / "scripts" / "build_codexskin.py"
APP_NAME = "Codex 皮肤管理器.app"
BUILTIN_RELEASE_SKINS = (
    ("nightblade", "Meng-Chuan-Nightblade"),
    ("red-lotus", "Meng-Chuan-Red-Lotus"),
)

def run(command: list[str], *, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=cwd, check=True, text=True, capture_output=True)


def project_version() -> str:
    return json.loads((ROOT / "package.json").read_text(encoding="utf-8"))["version"]


def manifest_version(directory: Path) -> str:
    return json.loads((directory / "manifest.json").read_text(encoding="utf-8"))["version"]


def source_skin_metadata(directory: Path) -> dict:
    return json.loads((directory / "skin.json").read_text(encoding="utf-8"))


def source_release_name(directory: Path) -> str:
    return "-".join(part.capitalize() for part in directory.name.split("-"))


def redistributable_source_skins() -> list[Path]:
    if not SKINS.is_dir():
        return []
    sources: list[Path] = []
    for skin_json in sorted(SKINS.glob("*/skin.json")):
        source = skin_json.parent
        metadata = source_skin_metadata(source)
        if metadata.get("rights", {}).get("redistributionAllowed") is True:
            sources.append(source)
    return sources


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


def build_builtin_skin(source: Path, destination: Path) -> None:
    run(
        [
            "/usr/bin/swift",
            "run",
            "-c",
            "release",
            "SkinReleasePackager",
            "--source",
            str(source),
            "--output",
            str(destination),
        ],
        cwd=PACKAGE,
    )


def build_source_skin(source: Path, destination: Path) -> None:
    metadata = source_skin_metadata(source)
    if metadata.get("rights", {}).get("redistributionAllowed") is not True:
        raise ValueError(f"{source} is not marked as redistributable and cannot be published")
    run(
        [
            sys.executable,
            str(AUTHORING_PACKAGER),
            "--source",
            str(source),
            "--output",
            str(destination),
        ],
        cwd=ROOT,
    )


def build_app_archive(destination: Path, version: str) -> None:
    run([sys.executable, str(APP_BUILDER)])
    app = ROOT / "build" / APP_NAME
    if not app.is_dir():
        raise FileNotFoundError(app)
    run(
        [
            "/usr/bin/ditto",
            "-c",
            "-k",
            "--sequesterRsrc",
            "--keepParent",
            str(app),
            str(destination / f"Codex-Skin-Manager-v{version}-macOS.zip"),
        ]
    )


def write_checksums(directory: Path) -> None:
    assets = sorted(path for path in directory.iterdir() if path.is_file() and path.name != "SHA256SUMS.txt")
    lines = [f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}" for path in assets]
    (directory / "SHA256SUMS.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build Codex Skin Manager GitHub Release assets")
    parser.add_argument("--output", type=Path, default=ROOT / "dist" / f"v{project_version()}")
    parser.add_argument("--skins-only", action="store_true", help="skip the macOS app archive")
    args = parser.parse_args()
    output = args.output.expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="codex-skin-release-stage-", dir=output.parent) as temporary:
        stage = Path(temporary) / output.name
        stage.mkdir()
        for directory_name, release_name in BUILTIN_RELEASE_SKINS:
            source = BUILTINS / directory_name
            build_builtin_skin(source, stage / f"{release_name}-{manifest_version(source)}.codexskin")
        for source in redistributable_source_skins():
            release_name = source_release_name(source)
            version = source_skin_metadata(source)["version"]
            build_source_skin(source, stage / f"{release_name}-{version}.codexskin")
        if not args.skins_only:
            build_app_archive(stage, project_version())
        write_checksums(stage)
        replace_directory(stage, output)

    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
