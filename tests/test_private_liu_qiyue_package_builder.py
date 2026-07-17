#!/usr/bin/env python3
"""Verify the local-only Liu Qiyue launcher migration package."""

from __future__ import annotations

import base64
import hashlib
import json
import subprocess
import tempfile
import unittest
import zipfile
from io import BytesIO
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "scripts/build_private_liu_qiyue_skin.py"
TINY_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR42mNkYGD4z8DAwMDEAAUADgAB/2cZ1QAAAABJRU5ErkJggg=="
)


def png_bytes(size: tuple[int, int], color: tuple[int, int, int, int]) -> bytes:
    output = BytesIO()
    Image.new("RGBA", size, color).save(output, format="PNG")
    return output.getvalue()


class PrivateLiuQiyuePackageBuilderTests(unittest.TestCase):
    def test_builds_data_only_private_package(self) -> None:
        with tempfile.TemporaryDirectory(prefix="liu-qiyue-package-test-") as temporary:
            root = Path(temporary)
            runtime = root / "runtime"
            runtime.mkdir()
            (runtime / "hero-background.png").write_bytes(
                png_bytes((16, 10), (140, 12, 8, 255))
            )
            (runtime / "hero-character.png").write_bytes(
                png_bytes((6, 12), (8, 220, 40, 255))
            )
            (runtime / "ASSET-LICENSE.md").write_text(
                "Private preview only. Do not redistribute.\n", encoding="utf-8"
            )
            # Active content from the old launcher must never enter the package.
            (runtime / "injector.mjs").write_text("throw new Error('must not ship')", encoding="utf-8")
            (runtime / "renderer-inject.js").write_text("alert('must not ship')", encoding="utf-8")
            (runtime / "theme.css").write_text("@import 'https://example.com/evil.css';", encoding="utf-8")
            output = root / "Liu-Qiyue-Undying-Phoenix-1.0.1.codexskin"
            second_output = root / "Liu-Qiyue-Undying-Phoenix-1.0.1-second.codexskin"

            for destination in [output, second_output]:
                subprocess.run(
                    ["python3", str(BUILDER), "--runtime", str(runtime), "--output", str(destination)],
                    cwd=ROOT,
                    check=True,
                    text=True,
                    capture_output=True,
                )

            self.assertEqual(output.read_bytes(), second_output.read_bytes())

            with zipfile.ZipFile(output) as archive:
                names = archive.namelist()
                self.assertEqual(
                    names,
                    [
                        "manifest.json",
                        "LICENSES/assets.txt",
                        "assets/background.png",
                        "assets/hero.png",
                        "preview.png",
                        "rights.json",
                        "theme.json",
                    ],
                )
                self.assertTrue(all(item.compress_type == zipfile.ZIP_STORED for item in archive.infolist()))
                manifest = json.loads(archive.read("manifest.json"))
                rights = json.loads(archive.read("rights.json"))
                theme = json.loads(archive.read("theme.json"))
                self.assertEqual(manifest["id"], "liu-qiyue-undying-phoenix")
                self.assertEqual(manifest["template"], "undying-phoenix-v1")
                self.assertEqual(manifest["version"], "1.0.1")
                self.assertEqual(manifest["preview"], "preview.png")
                self.assertFalse(rights["redistributionAllowed"])
                self.assertFalse(rights["commercialUse"])
                self.assertEqual(theme["assets"], {
                    "background": "assets/background.png",
                    "hero": "assets/hero.png",
                })
                preview = Image.open(BytesIO(archive.read("preview.png"))).convert("RGB")
                self.assertEqual(preview.size, (1600, 1000))
                left = preview.getpixel((120, 500))
                right = preview.getpixel((1420, 500))
                self.assertGreater(left[0], left[1], "预览左侧应保留凰焰背景")
                self.assertGreater(right[1], right[0], "预览右侧应合成人物层")
                self.assertFalse(any(name.endswith((".command", ".css", ".js", ".mjs")) for name in names))
                declared = {item["path"]: item for item in manifest["files"]}
                self.assertEqual(set(declared), set(names) - {"manifest.json"})
                for name, descriptor in declared.items():
                    data = archive.read(name)
                    self.assertEqual(descriptor["byteCount"], len(data))
                    self.assertEqual(descriptor["sha256"], hashlib.sha256(data).hexdigest())

    def test_rejects_missing_private_license_boundary(self) -> None:
        with tempfile.TemporaryDirectory(prefix="liu-qiyue-package-test-") as temporary:
            root = Path(temporary)
            runtime = root / "runtime"
            runtime.mkdir()
            (runtime / "hero-background.png").write_bytes(TINY_PNG)
            (runtime / "hero-character.png").write_bytes(TINY_PNG)
            output = root / "skin.codexskin"

            result = subprocess.run(
                ["python3", str(BUILDER), "--runtime", str(runtime), "--output", str(output)],
                cwd=ROOT,
                text=True,
                capture_output=True,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
