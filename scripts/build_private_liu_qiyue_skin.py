#!/usr/bin/env python3
"""Convert the local Liu Qiyue legacy runtime into a data-only private skin package."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
import zipfile
from io import BytesIO
from pathlib import Path

try:
    from PIL import Image, ImageFilter, ImageOps
except ImportError:
    Image = ImageFilter = ImageOps = None


SKIN_ID = "liu-qiyue-undying-phoenix"
SKIN_NAME = "柳七月 · 不死凰焰"
SKIN_VERSION = "1.0.1"
TEMPLATE = "undying-phoenix-v1"
MAX_SOURCE_BYTES = 32 * 1024 * 1024
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
PREVIEW_SIZE = (1_600, 1_000)


def json_bytes(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_plain_file(path: Path, *, png: bool = False) -> bytes:
    if not path.is_file() or path.is_symlink():
        raise ValueError(f"缺少普通文件：{path}")
    size = path.stat().st_size
    if size <= 0 or size > MAX_SOURCE_BYTES:
        raise ValueError(f"文件大小不安全：{path}")
    data = path.read_bytes()
    if png and not data.startswith(PNG_SIGNATURE):
        raise ValueError(f"不是有效的 PNG 文件：{path}")
    return data


def zip_info(name: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    info.create_system = 3
    info.external_attr = 0o100644 << 16
    info.compress_type = zipfile.ZIP_STORED
    return info


def build_preview(background: bytes, hero: bytes) -> bytes:
    if Image is None or ImageFilter is None or ImageOps is None:
        raise ValueError("生成柳七月预览图需要 Pillow：python3 -m pip install Pillow")
    try:
        with Image.open(BytesIO(background)) as source_background:
            canvas = ImageOps.fit(
                source_background.convert("RGBA"),
                PREVIEW_SIZE,
                method=Image.Resampling.LANCZOS,
                centering=(0.68, 0.5),
            )
        with Image.open(BytesIO(hero)) as source_hero:
            hero_layer = source_hero.convert("RGBA")
    except (OSError, ValueError) as error:
        raise ValueError(f"无法生成柳七月预览图：{error}") from error

    scale = min(610 / hero_layer.width, 980 / hero_layer.height)
    hero_size = (
        max(1, round(hero_layer.width * scale)),
        max(1, round(hero_layer.height * scale)),
    )
    hero_layer = hero_layer.resize(hero_size, Image.Resampling.LANCZOS)
    hero_alpha = hero_layer.getchannel("A")
    x = PREVIEW_SIZE[0] - hero_layer.width
    y = (PREVIEW_SIZE[1] - hero_layer.height) // 2

    shadow = Image.new("RGBA", hero_layer.size, (0, 0, 0, 0))
    shadow.putalpha(hero_alpha.filter(ImageFilter.GaussianBlur(22)).point(lambda value: round(value * 0.62)))
    canvas.alpha_composite(shadow, (x - 20, y + 18))

    hero_layer.putalpha(hero_alpha.point(lambda value: round(value * 0.94)))
    canvas.alpha_composite(hero_layer, (x, y))

    output = BytesIO()
    canvas.convert("RGB").save(output, format="PNG", compress_level=9)
    return output.getvalue()


def build_package(runtime: Path, output: Path) -> Path:
    runtime = runtime.expanduser()
    if runtime.is_symlink():
        raise ValueError(f"运行时目录不能是符号链接：{runtime}")
    runtime = runtime.resolve(strict=True)
    if not runtime.is_dir():
        raise ValueError(f"运行时目录无效：{runtime}")
    if output.suffix.lower() != ".codexskin":
        raise ValueError("输出文件必须使用 .codexskin 扩展名")

    background = read_plain_file(runtime / "hero-background.png", png=True)
    hero = read_plain_file(runtime / "hero-character.png", png=True)
    preview = build_preview(background, hero)
    license_bytes = read_plain_file(runtime / "ASSET-LICENSE.md")
    license_text = license_bytes.decode("utf-8")
    if "private" not in license_text.lower():
        raise ValueError("素材许可未声明 private 使用边界")

    theme = json_bytes({
        "assets": {
            "background": "assets/background.png",
            "hero": "assets/hero.png",
        },
        "focalPoints": {
            "background": {"x": 0.68, "y": 0.45},
            "hero": {"x": 0.5, "y": 0.2},
        },
        "tokens": {
            "accent": "#F26B2F",
            "accentStrong": "#FFD47A",
            "canvas": "#090404",
            "controlRadius": "12",
            "focus": "#FFD47A",
            "ink": "#FFF4DF",
            "line": "#5B251B",
            "motionDuration": "180",
            "mutedInk": "#9AAABC",
            "panelRadius": "7",
            "surface": "#140707",
            "surfaceRaised": "#23100D",
        },
    })
    rights = json_bytes({
        "commercialUse": False,
        "fanMade": True,
        "noEndorsement": True,
        "notice": (
            "Private local preview and evaluation only. Redistribution, publication, sale, "
            "official endorsement claims, and commercial use are not permitted."
        ),
        "redistributionAllowed": False,
        "unofficial": True,
    })
    payloads = {
        "LICENSES/assets.txt": license_bytes,
        "assets/background.png": background,
        "assets/hero.png": hero,
        "preview.png": preview,
        "rights.json": rights,
        "theme.json": theme,
    }
    mime_by_suffix = {
        ".json": "application/json",
        ".png": "image/png",
        ".txt": "text/plain",
    }
    files = [
        {
            "byteCount": len(data),
            "mime": mime_by_suffix[Path(name).suffix.lower()],
            "path": name,
            "sha256": sha256(data),
        }
        for name, data in sorted(payloads.items())
    ]
    manifest = json_bytes({
        "author": {"name": "OPCspace", "website": None},
        "files": files,
        "id": SKIN_ID,
        "minManagerVersion": "1.1.0",
        "name": SKIN_NAME,
        "preview": "preview.png",
        "publisherPublicKey": None,
        "schemaVersion": 1,
        "template": TEMPLATE,
        "version": SKIN_VERSION,
    })

    output = output.expanduser().absolute()
    output.parent.mkdir(parents=True, exist_ok=True)
    file_descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{output.name}.", suffix=".tmp", dir=output.parent
    )
    os.close(file_descriptor)
    temporary = Path(temporary_name)
    try:
        with zipfile.ZipFile(temporary, mode="w", compression=zipfile.ZIP_STORED) as archive:
            archive.writestr(zip_info("manifest.json"), manifest)
            for name, data in sorted(payloads.items()):
                archive.writestr(zip_info(name), data)
        os.chmod(temporary, 0o644)
        os.replace(temporary, output)
    finally:
        if temporary.exists():
            temporary.unlink()
    return output


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build a private data-only .codexskin from the Liu Qiyue legacy runtime"
    )
    parser.add_argument("--runtime", required=True, type=Path, help="legacy runtime directory")
    parser.add_argument("--output", required=True, type=Path, help="destination .codexskin")
    arguments = parser.parse_args()
    try:
        output = build_package(arguments.runtime, arguments.output)
    except (OSError, UnicodeError, ValueError, zipfile.BadZipFile) as error:
        parser.error(str(error))
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
