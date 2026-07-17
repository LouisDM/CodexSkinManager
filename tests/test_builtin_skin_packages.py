#!/usr/bin/env python3
"""Validate manager-owned templates and public non-commercial built-in skins."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "skin-manager/Sources/CodexSkinManager/Resources"
TEMPLATES = RESOURCES / "Templates"
BUILTINS = RESOURCES / "BuiltinSkins"
ALLOWED_SUFFIXES = {".json", ".jpeg", ".jpg", ".png", ".txt"}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def png_chunks(path: Path) -> list[str]:
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"invalid PNG: {path}"
    chunks: list[str] = []
    offset = 8
    while offset + 12 <= len(data):
        length = int.from_bytes(data[offset : offset + 4], "big")
        kind = data[offset + 4 : offset + 8].decode("ascii")
        chunks.append(kind)
        offset += 12 + length
        if kind == "IEND":
            break
    return chunks


def validate_package(directory: Path, expected_id: str, expected_template: str) -> None:
    manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
    theme = json.loads((directory / "theme.json").read_text(encoding="utf-8"))
    rights = json.loads((directory / "rights.json").read_text(encoding="utf-8"))

    assert manifest["schemaVersion"] == 1
    assert manifest["id"] == expected_id
    assert manifest["version"] == "1.0.1"
    assert manifest["template"] == expected_template
    assert manifest["publisherPublicKey"] is None
    assert rights["redistributionAllowed"] is True
    assert rights["commercialUse"] is False
    assert rights["fanMade"] is True
    assert rights["unofficial"] is True
    assert rights["noEndorsement"] is True
    assert "non-commercial" in rights["notice"].lower()

    declared = {item["path"]: item for item in manifest["files"]}
    actual = {
        path.relative_to(directory).as_posix()
        for path in directory.rglob("*")
        if path.is_file() and path.name != "manifest.json"
    }
    assert set(declared) == actual
    assert "theme.json" in declared
    assert "rights.json" in declared
    assert manifest["preview"] in declared
    assert any(path.startswith("LICENSES/") for path in declared)
    assert set(theme["assets"]) >= {"hero", "background"}

    for relative, descriptor in declared.items():
        path = directory / relative
        assert path.suffix.lower() in ALLOWED_SUFFIXES, f"active content in package: {relative}"
        assert path.stat().st_size == descriptor["byteCount"]
        assert sha256(path) == descriptor["sha256"]
        assert "http://" not in path.read_bytes().lower().decode("latin1", errors="ignore")
        assert "https://" not in path.read_bytes().lower().decode("latin1", errors="ignore")
        if path.suffix.lower() == ".png":
            chunks = png_chunks(path)
            assert "caBX" not in chunks
            assert b"c2pa" not in path.read_bytes().lower()

    for asset_path in theme["assets"].values():
        assert asset_path in declared
        assert declared[asset_path]["mime"] in {"image/png", "image/jpeg"}


def main() -> int:
    nightblade_template = (TEMPLATES / "nightblade-v1.css").read_text(encoding="utf-8")
    red_lotus_template = (TEMPLATES / "red-lotus-v1.css").read_text(encoding="utf-8")
    assert "玄刃夜行" in nightblade_template
    assert ":root.codex-skin-template-nightblade-v1" in nightblade_template
    assert "--codex-skin-template-active: nightblade-v1" in nightblade_template
    assert "#codex-skin-manager-chrome::before" in nightblade_template
    assert "codex-meng-chuan-nightblade" not in nightblade_template
    assert "Red Lotus" in red_lotus_template
    assert ":root.codex-skin-template-red-lotus-v1" in red_lotus_template
    assert "--codex-skin-template-active: red-lotus-v1" in red_lotus_template
    assert "url(\"./hero-character.png\")" in nightblade_template
    assert "url(\"./meng-chuan-portrait.png\")" in red_lotus_template
    assert "@import" not in nightblade_template + red_lotus_template

    validate_package(BUILTINS / "nightblade", "meng-chuan-nightblade", "nightblade-v1")
    validate_package(BUILTINS / "red-lotus", "meng-chuan-red-lotus", "red-lotus-v1")
    print("Built-in skin packages are valid for public non-commercial distribution")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
