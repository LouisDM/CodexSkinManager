#!/usr/bin/env python3
"""Contract tests for the generic declarative skin authoring packager."""

from __future__ import annotations

import base64
import hashlib
import json
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "scripts/build_codexskin.py"
TINY_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR42mNkYGD4z8DAwMDEAAUADgAB/2cZ1QAAAABJRU5ErkJggg=="
)


def authoring_config() -> dict:
    return {
        "schemaVersion": 1,
        "id": "sample-night-skin",
        "name": "示例 · 夜行皮肤",
        "version": "1.0.0",
        "template": "nightblade-v1",
        "minManagerVersion": "1.1.0",
        "preview": "preview.png",
        "author": {"name": "Skin Author", "website": None},
        "theme": {
            "tokens": {
                "accent": "#8FD8FF",
                "canvas": "#080D15",
                "panelRadius": "12",
            },
            "assets": {
                "background": "assets/background.png",
                "hero": "assets/hero.png",
            },
            "focalPoints": {
                "background": {"x": 0.62, "y": 0.5},
                "hero": {"x": 0.5, "y": 0.2},
            },
        },
        "rights": {
            "redistributionAllowed": False,
            "commercialUse": False,
            "fanMade": True,
            "unofficial": True,
            "noEndorsement": True,
            "notice": "Private local preview only.",
        },
    }


class SkinAuthoringPackagerTests(unittest.TestCase):
    def make_source(self, root: Path, config: dict | None = None) -> Path:
        source = root / "sample-skin"
        (source / "assets").mkdir(parents=True)
        (source / "LICENSES").mkdir()
        (source / "skin.json").write_text(
            json.dumps(config or authoring_config(), ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        (source / "preview.png").write_bytes(TINY_PNG)
        (source / "assets/background.png").write_bytes(TINY_PNG)
        (source / "assets/hero.png").write_bytes(TINY_PNG)
        (source / "LICENSES/assets.txt").write_text(
            "Private preview asset boundary.\n", encoding="utf-8"
        )
        # Undeclared active content must never enter the package.
        (source / "legacy.command").write_text("#!/bin/zsh\n", encoding="utf-8")
        (source / "template.css").write_text("@import 'https://example.com/evil.css';\n", encoding="utf-8")
        (source / "injector.js").write_text("alert('must not ship')\n", encoding="utf-8")
        return source

    def run_builder(self, source: Path, output: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", str(BUILDER), "--source", str(source), "--output", str(output)],
            cwd=ROOT,
            text=True,
            capture_output=True,
        )

    def test_builds_deterministic_manager_compatible_data_only_package(self) -> None:
        with tempfile.TemporaryDirectory(prefix="skin-authoring-test-") as temporary:
            root = Path(temporary)
            source = self.make_source(root)
            first = root / "first.codexskin"
            second = root / "second.codexskin"

            for output in [first, second]:
                result = self.run_builder(source, output)
                self.assertEqual(result.returncode, 0, result.stderr)

            self.assertEqual(first.read_bytes(), second.read_bytes())
            with zipfile.ZipFile(first) as archive:
                names = archive.namelist()
                self.assertEqual(names, [
                    "manifest.json",
                    "LICENSES/assets.txt",
                    "assets/background.png",
                    "assets/hero.png",
                    "preview.png",
                    "rights.json",
                    "theme.json",
                ])
                self.assertTrue(all(item.compress_type == zipfile.ZIP_STORED for item in archive.infolist()))
                self.assertFalse(any(name.endswith((".command", ".css", ".js", ".mjs")) for name in names))
                manifest = json.loads(archive.read("manifest.json"))
                theme = json.loads(archive.read("theme.json"))
                rights = json.loads(archive.read("rights.json"))
                self.assertEqual(manifest["id"], "sample-night-skin")
                self.assertEqual(manifest["template"], "nightblade-v1")
                self.assertIsNone(manifest["publisherPublicKey"])
                self.assertEqual(theme, authoring_config()["theme"])
                self.assertEqual(rights, authoring_config()["rights"])
                descriptors = {item["path"]: item for item in manifest["files"]}
                self.assertEqual(set(descriptors), set(names) - {"manifest.json"})
                for name, descriptor in descriptors.items():
                    data = archive.read(name)
                    self.assertEqual(descriptor["byteCount"], len(data))
                    self.assertEqual(descriptor["sha256"], hashlib.sha256(data).hexdigest())

    def test_rejects_unsafe_paths_unknown_tokens_and_missing_license(self) -> None:
        with tempfile.TemporaryDirectory(prefix="skin-authoring-test-") as temporary:
            root = Path(temporary)

            unsafe = authoring_config()
            unsafe["theme"]["assets"]["hero"] = "../hero.png"
            unsafe_source = self.make_source(root / "unsafe", unsafe)
            self.assertNotEqual(self.run_builder(unsafe_source, root / "unsafe.codexskin").returncode, 0)

            unknown = authoring_config()
            unknown["theme"]["tokens"]["arbitraryCSS"] = "url(https://example.com)"
            unknown_source = self.make_source(root / "unknown", unknown)
            self.assertNotEqual(self.run_builder(unknown_source, root / "unknown.codexskin").returncode, 0)

            missing_license_source = self.make_source(root / "missing-license")
            (missing_license_source / "LICENSES/assets.txt").unlink()
            self.assertNotEqual(
                self.run_builder(missing_license_source, root / "missing-license.codexskin").returncode,
                0,
            )


if __name__ == "__main__":
    unittest.main()
