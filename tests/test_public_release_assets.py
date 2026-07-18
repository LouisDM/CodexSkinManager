#!/usr/bin/env python3
"""Build and validate deterministic, publicly redistributable skin packages."""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "scripts" / "build_release_assets.py"
EXPECTED = {
    "Cai-Xukun-Stage-Check-1.0.1.codexskin": ("cai-xukun-stage-check", "1.0.1"),
    "Hakimi-Paw-Atelier-1.0.2.codexskin": ("hakimi-paw-atelier", "1.0.2"),
    "Liu-Qiyue-Undying-Phoenix-1.0.2.codexskin": ("liu-qiyue-undying-phoenix", "1.0.2"),
    "Meng-Chuan-Nightblade-1.0.1.codexskin": ("meng-chuan-nightblade", "1.0.1"),
    "Meng-Chuan-Red-Lotus-1.0.1.codexskin": ("meng-chuan-red-lotus", "1.0.1"),
    "Tifa-Seventh-Heaven-Flow-1.0.1.codexskin": ("tifa-seventh-heaven-flow", "1.0.1"),
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def build(output: Path) -> None:
    assert BUILDER.is_file(), f"missing public release builder: {BUILDER}"
    subprocess.run(
        [sys.executable, str(BUILDER), "--skins-only", "--output", str(output)],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )


def validate_package(path: Path, expected_id: str, expected_version: str) -> None:
    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        assert infos and all(info.compress_type == zipfile.ZIP_STORED for info in infos)
        assert not any(info.is_dir() for info in infos)
        names = [info.filename for info in infos]
        assert len(names) == len(set(names))
        manifest = json.loads(archive.read("manifest.json"))
        rights = json.loads(archive.read("rights.json"))
        license_text = archive.read("LICENSES/assets.txt").decode("utf-8")

        assert manifest["id"] == expected_id
        assert manifest["version"] == expected_version
        assert rights["redistributionAllowed"] is True
        assert rights["commercialUse"] is False
        assert isinstance(rights["fanMade"], bool)
        assert rights["unofficial"] is True
        assert rights["noEndorsement"] is True
        assert "non-commercial" in rights["notice"].lower()
        assert "public non-commercial" in license_text.lower()

        descriptors = {item["path"]: item for item in manifest["files"]}
        assert set(names) == {"manifest.json", *descriptors}
        for relative, descriptor in descriptors.items():
            data = archive.read(relative)
            assert len(data) == descriptor["byteCount"]
            assert sha256(data) == descriptor["sha256"]


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="codex-skin-release-test-") as temporary:
        first = Path(temporary) / "first"
        second = Path(temporary) / "second"
        build(first)
        build(second)

        assert {path.name for path in first.glob("*.codexskin")} == set(EXPECTED)
        for filename, (skin_id, version) in EXPECTED.items():
            first_package = first / filename
            second_package = second / filename
            validate_package(first_package, skin_id, version)
            assert first_package.read_bytes() == second_package.read_bytes(), filename

        checksum_lines = (first / "SHA256SUMS.txt").read_text(encoding="utf-8").splitlines()
        expected_lines = [
            f"{sha256((first / filename).read_bytes())}  {filename}"
            for filename in sorted(EXPECTED)
        ]
        assert checksum_lines == expected_lines

    print("Public release skin packages are deterministic and import-contract compatible")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
