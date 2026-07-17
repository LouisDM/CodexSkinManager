#!/usr/bin/env python3
"""Build a deterministic, data-only Codex Skin Manager package."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import stat
import tempfile
import unicodedata
import zipfile
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


MAX_ENTRY_BYTES = 32 * 1024 * 1024
MAX_LICENSE_BYTES = 1024 * 1024
MAX_ARCHIVE_BYTES = 64 * 1024 * 1024
MAX_ENTRIES = 128
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
JPEG_SIGNATURE = b"\xff\xd8"
SEMVER_PATTERN = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
ID_PATTERN = re.compile(
    r"^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*$"
)

SUPPORTED_TEMPLATES = {
    "nightblade-v1",
    "red-lotus-v1",
    "undying-phoenix-v1",
}
COLOR_TOKENS = {
    "accent",
    "accentStrong",
    "canvas",
    "focus",
    "ink",
    "line",
    "mutedInk",
    "surface",
    "surfaceRaised",
}
NUMERIC_TOKENS = {"controlRadius", "motionDuration", "panelRadius"}
ASSET_SLOTS = {"avatar", "background", "hero"}
SKIN_KEYS = {
    "schemaVersion",
    "id",
    "name",
    "version",
    "template",
    "minManagerVersion",
    "preview",
    "author",
    "theme",
    "rights",
}
AUTHOR_KEYS = {"name", "website"}
THEME_KEYS = {"tokens", "assets", "focalPoints"}
RIGHTS_KEYS = {
    "redistributionAllowed",
    "commercialUse",
    "fanMade",
    "unofficial",
    "noEndorsement",
    "notice",
}


def json_bytes(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def zip_info(name: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    info.create_system = 3
    info.external_attr = 0o100644 << 16
    info.compress_type = zipfile.ZIP_STORED
    return info


def require_mapping(value: object, label: str, keys: set[str]) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{label} 必须是 JSON 对象")
    actual = set(value)
    missing = keys - actual
    unknown = actual - keys
    if missing:
        raise ValueError(f"{label} 缺少字段：{', '.join(sorted(missing))}")
    if unknown:
        raise ValueError(f"{label} 包含未知字段：{', '.join(sorted(unknown))}")
    return value


def no_duplicate_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"skin.json 包含重复字段：{key}")
        result[key] = value
    return result


def load_config(path: Path) -> dict[str, Any]:
    data = read_regular_file(path, maximum_bytes=1024 * 1024)
    try:
        decoded = json.loads(data.decode("utf-8"), object_pairs_hook=no_duplicate_object)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError(f"skin.json 不是有效的 UTF-8 JSON：{error}") from error
    return require_mapping(decoded, "skin.json", SKIN_KEYS)


def validate_relative_path(value: object, label: str) -> str:
    if not isinstance(value, str):
        raise ValueError(f"{label} 必须是相对路径字符串")
    if (
        not value
        or len(value.encode("utf-8")) > 240
        or value.startswith(("/", "~"))
        or "\\" in value
        or "\0" in value
        or "//" in value
    ):
        raise ValueError(f"{label} 路径不安全：{value!r}")
    parts = value.split("/")
    if len(parts) > 8 or any(part in {"", ".", ".."} for part in parts):
        raise ValueError(f"{label} 路径不安全：{value!r}")
    return value


def normalized_path(value: str) -> str:
    return unicodedata.normalize("NFC", value).casefold()


def require_string(value: object, label: str, maximum: int) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > maximum:
        raise ValueError(f"{label} 必须是 1–{maximum} 字符的非空字符串")
    return value


def validate_semver(value: object, label: str) -> str:
    if not isinstance(value, str) or SEMVER_PATTERN.fullmatch(value) is None:
        raise ValueError(f"{label} 必须使用 x.y.z 语义版本：{value!r}")
    return value


def validate_author(value: object) -> dict[str, Any]:
    author = require_mapping(value, "author", AUTHOR_KEYS)
    require_string(author["name"], "author.name", 128)
    website = author["website"]
    if website is not None:
        require_string(website, "author.website", 2048)
        parsed = urlparse(website)
        if parsed.scheme not in {"http", "https"} or not parsed.netloc:
            raise ValueError("author.website 仅支持完整的 http/https 地址或 null")
    return author


def validate_theme(value: object) -> dict[str, Any]:
    theme = require_mapping(value, "theme", THEME_KEYS)
    tokens = theme["tokens"]
    assets = theme["assets"]
    focal_points = theme["focalPoints"]
    if not isinstance(tokens, dict):
        raise ValueError("theme.tokens 必须是 JSON 对象")
    if not isinstance(assets, dict):
        raise ValueError("theme.assets 必须是 JSON 对象")
    if not isinstance(focal_points, dict):
        raise ValueError("theme.focalPoints 必须是 JSON 对象")

    for name, value in tokens.items():
        if not isinstance(name, str) or not isinstance(value, str):
            raise ValueError("theme.tokens 的名称和值必须是字符串")
        if name in COLOR_TOKENS:
            if re.fullmatch(r"#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?", value) is None:
                raise ValueError(f"颜色令牌 {name} 必须是 #RRGGBB 或 #RRGGBBAA")
        elif name in NUMERIC_TOKENS:
            try:
                number = float(value)
            except ValueError as error:
                raise ValueError(f"数值令牌 {name} 必须是 0–1000") from error
            if not math.isfinite(number) or not 0 <= number <= 1000:
                raise ValueError(f"数值令牌 {name} 必须是 0–1000")
        else:
            raise ValueError(f"不支持的主题令牌：{name}")

    for slot, path in assets.items():
        if slot not in ASSET_SLOTS:
            raise ValueError(f"不支持的素材槽：{slot}")
        validate_relative_path(path, f"theme.assets.{slot}")

    for slot, point in focal_points.items():
        if slot not in ASSET_SLOTS:
            raise ValueError(f"不支持的素材焦点槽：{slot}")
        if not isinstance(point, dict) or set(point) != {"x", "y"}:
            raise ValueError(f"theme.focalPoints.{slot} 必须只包含 x 和 y")
        for axis in ("x", "y"):
            coordinate = point[axis]
            if (
                not isinstance(coordinate, (int, float))
                or isinstance(coordinate, bool)
                or not math.isfinite(float(coordinate))
                or not 0 <= float(coordinate) <= 1
            ):
                raise ValueError(f"theme.focalPoints.{slot}.{axis} 必须在 0–1 之间")
    return theme


def validate_rights(value: object) -> dict[str, Any]:
    rights = require_mapping(value, "rights", RIGHTS_KEYS)
    for name in RIGHTS_KEYS - {"notice"}:
        if not isinstance(rights[name], bool):
            raise ValueError(f"rights.{name} 必须是布尔值")
    require_string(rights["notice"], "rights.notice", 4096)
    return rights


def read_regular_file(path: Path, *, maximum_bytes: int = MAX_ENTRY_BYTES) -> bytes:
    try:
        metadata = path.lstat()
    except FileNotFoundError as error:
        raise ValueError(f"缺少文件：{path}") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise ValueError(f"必须是普通文件且不能是符号链接：{path}")
    if metadata.st_size <= 0 or metadata.st_size > maximum_bytes:
        raise ValueError(f"文件大小不安全：{path}")
    data = path.read_bytes()
    if len(data) != metadata.st_size:
        raise ValueError(f"读取文件时大小发生变化：{path}")
    return data


def source_file(root: Path, relative: str) -> Path:
    cursor = root
    for component in relative.split("/"):
        cursor = cursor / component
        try:
            metadata = cursor.lstat()
        except FileNotFoundError as error:
            raise ValueError(f"缺少文件：{relative}") from error
        if stat.S_ISLNK(metadata.st_mode):
            raise ValueError(f"素材路径不能包含符号链接：{relative}")
    return cursor


def read_image(root: Path, relative: str) -> tuple[bytes, str]:
    suffix = Path(relative).suffix.lower()
    if suffix == ".png":
        mime = "image/png"
    elif suffix in {".jpg", ".jpeg"}:
        mime = "image/jpeg"
    else:
        raise ValueError(f"素材只支持 PNG/JPEG：{relative}")
    data = read_regular_file(source_file(root, relative))
    if mime == "image/png" and not data.startswith(PNG_SIGNATURE):
        raise ValueError(f"PNG 文件头无效：{relative}")
    if mime == "image/jpeg" and (not data.startswith(JPEG_SIGNATURE) or not data.endswith(b"\xff\xd9")):
        raise ValueError(f"JPEG 文件头无效：{relative}")
    return data, mime


def read_licenses(root: Path) -> dict[str, bytes]:
    license_root = root / "LICENSES"
    try:
        metadata = license_root.lstat()
    except FileNotFoundError as error:
        raise ValueError("缺少 LICENSES 目录") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise ValueError("LICENSES 必须是普通目录且不能是符号链接")

    result: dict[str, bytes] = {}
    for directory, directory_names, file_names in os.walk(license_root, followlinks=False):
        directory_path = Path(directory)
        for name in list(directory_names):
            child = directory_path / name
            if child.is_symlink():
                raise ValueError(f"LICENSES 不能包含符号链接：{child.relative_to(root)}")
        for name in sorted(file_names):
            path = directory_path / name
            if path.suffix.lower() != ".txt":
                continue
            relative = path.relative_to(root).as_posix()
            validate_relative_path(relative, "许可文件")
            data = read_regular_file(path, maximum_bytes=MAX_LICENSE_BYTES)
            try:
                text = data.decode("utf-8")
            except UnicodeDecodeError as error:
                raise ValueError(f"许可文件必须是 UTF-8 文本：{relative}") from error
            if "\0" in text:
                raise ValueError(f"许可文件不能包含 NUL 字符：{relative}")
            result[relative] = data
    if not result:
        raise ValueError("LICENSES 目录至少需要一个 .txt 素材许可文件")
    return result


def validate_config(config: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    schema_version = config["schemaVersion"]
    if not isinstance(schema_version, int) or isinstance(schema_version, bool) or schema_version != 1:
        raise ValueError("schemaVersion 当前只能是整数 1")
    identifier = config["id"]
    if (
        not isinstance(identifier, str)
        or not 3 <= len(identifier.encode("utf-8")) <= 64
        or ID_PATTERN.fullmatch(identifier) is None
    ):
        raise ValueError(f"皮肤 id 无效：{identifier!r}")
    require_string(config["name"], "name", 128)
    validate_semver(config["version"], "version")
    validate_semver(config["minManagerVersion"], "minManagerVersion")
    template = config["template"]
    if not isinstance(template, str) or template not in SUPPORTED_TEMPLATES:
        supported = "、".join(sorted(SUPPORTED_TEMPLATES))
        raise ValueError(f"当前管理器不支持模板 {template!r}；可用模板：{supported}")
    validate_relative_path(config["preview"], "preview")
    validate_author(config["author"])
    theme = validate_theme(config["theme"])
    rights = validate_rights(config["rights"])
    return theme, rights


def ensure_unique_paths(paths: list[str]) -> None:
    seen: dict[str, str] = {}
    for path in paths:
        key = normalized_path(path)
        if key in seen:
            raise ValueError(f"包内路径冲突：{seen[key]} 与 {path}")
        seen[key] = path


def build_package(source: Path, output: Path) -> Path:
    source = source.expanduser()
    if source.is_symlink():
        raise ValueError(f"源目录不能是符号链接：{source}")
    source = source.resolve(strict=True)
    if not source.is_dir():
        raise ValueError(f"源目录无效：{source}")
    if output.suffix.lower() != ".codexskin":
        raise ValueError("输出文件必须使用 .codexskin 扩展名")

    config = load_config(source / "skin.json")
    theme, rights = validate_config(config)
    image_paths = set(theme["assets"].values())
    image_paths.add(config["preview"])

    payloads = read_licenses(source)
    mime_by_path = {path: "text/plain" for path in payloads}
    for relative in sorted(image_paths):
        data, mime = read_image(source, relative)
        payloads[relative] = data
        mime_by_path[relative] = mime
    payloads["rights.json"] = json_bytes(rights)
    payloads["theme.json"] = json_bytes(theme)
    mime_by_path["rights.json"] = "application/json"
    mime_by_path["theme.json"] = "application/json"

    ensure_unique_paths(["manifest.json", *payloads])
    if len(payloads) + 1 > MAX_ENTRIES:
        raise ValueError(f"皮肤包文件数不能超过 {MAX_ENTRIES}")
    files = [
        {
            "byteCount": len(data),
            "mime": mime_by_path[path],
            "path": path,
            "sha256": sha256(data),
        }
        for path, data in sorted(payloads.items())
    ]
    manifest = json_bytes(
        {
            "author": config["author"],
            "files": files,
            "id": config["id"],
            "minManagerVersion": config["minManagerVersion"],
            "name": config["name"],
            "preview": config["preview"],
            "publisherPublicKey": None,
            "schemaVersion": config["schemaVersion"],
            "template": config["template"],
            "version": config["version"],
        }
    )

    output = output.expanduser().absolute()
    output.parent.mkdir(parents=True, exist_ok=True)
    output = output.parent.resolve() / output.name
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
        if temporary.stat().st_size > MAX_ARCHIVE_BYTES:
            raise ValueError("生成的皮肤包超过 64 MB")
        os.chmod(temporary, 0o644)
        os.replace(temporary, output)
    finally:
        if temporary.exists():
            temporary.unlink()
    return output


def main() -> int:
    parser = argparse.ArgumentParser(
        description="从 skin.json、图片和许可文本生成可直接导入的 data-only .codexskin"
    )
    parser.add_argument("--source", required=True, type=Path, help="包含 skin.json 的皮肤源目录")
    parser.add_argument("--output", required=True, type=Path, help="目标 .codexskin 文件")
    arguments = parser.parse_args()
    try:
        result = build_package(arguments.source, arguments.output)
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        parser.error(str(error))
    print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
