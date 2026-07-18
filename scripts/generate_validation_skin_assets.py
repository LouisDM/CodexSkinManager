#!/usr/bin/env python3
"""Generate deterministic raster assets for local validation skins."""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]


SKINS = {
    "hakimi-paw-atelier": {
        "background": ((8, 28, 33), (16, 58, 64), (241, 190, 102)),
        "hero": ((245, 214, 158, 255), (59, 43, 44, 255), (110, 203, 185, 255)),
        "preview": (0.64, 0.48),
    },
    "cai-xukun-stage-check": {
        "background": ((11, 8, 18), (54, 30, 79), (236, 195, 92)),
        "hero": ((232, 232, 236, 255), (43, 39, 54, 255), (210, 80, 160, 255)),
        "preview": (0.66, 0.42),
    },
    "tifa-seventh-heaven-flow": {
        "background": ((18, 10, 12), (84, 36, 44), (87, 174, 184)),
        "hero": ((236, 230, 215, 255), (42, 32, 34, 255), (172, 46, 58, 255)),
        "preview": (0.64, 0.5),
    },
}


def gradient(size: tuple[int, int], start: tuple[int, int, int], end: tuple[int, int, int]) -> Image.Image:
    width, height = size
    image = Image.new("RGB", size)
    pixels = image.load()
    for y in range(height):
        for x in range(width):
            mix = (x / width * 0.55) + (y / height * 0.45)
            pixels[x, y] = tuple(round(start[index] * (1 - mix) + end[index] * mix) for index in range(3))
    return image


def draw_background(skin_id: str, size: tuple[int, int]) -> Image.Image:
    dark, mid, accent = SKINS[skin_id]["background"]
    image = gradient(size, dark, mid).convert("RGBA")
    draw = ImageDraw.Draw(image, "RGBA")
    width, height = size
    for index in range(9):
        cx = int(width * (0.12 + index * 0.105))
        cy = int(height * (0.18 + 0.08 * math.sin(index * 1.7)))
        radius = int(width * (0.08 + (index % 3) * 0.025))
        draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=(*accent, 18))
    for index in range(18):
        y = int(height * (0.2 + index * 0.035))
        phase = index * 0.55
        points = []
        for step in range(80):
            x = int(width * step / 79)
            wave = math.sin(step * 0.2 + phase) * height * 0.018
            points.append((x, int(y + wave)))
        draw.line(points, fill=(*accent, 26), width=3)
    if skin_id == "hakimi-paw-atelier":
        for offset in range(8):
            x = int(width * (0.12 + offset * 0.1))
            y = int(height * (0.72 + 0.04 * math.sin(offset)))
            draw.ellipse((x, y, x + 72, y + 52), fill=(255, 226, 170, 34))
            for toe in range(4):
                draw.ellipse((x + 8 + toe * 15, y - 16, x + 24 + toe * 15, y + 2), fill=(255, 226, 170, 42))
    elif skin_id == "cai-xukun-stage-check":
        for x in (0.18, 0.5, 0.82):
            beam = [(int(width * x), 0), (int(width * (x - 0.18)), height), (int(width * (x + 0.18)), height)]
            draw.polygon(beam, fill=(*accent, 28))
        for index in range(7):
            x = int(width * (0.18 + index * 0.11))
            draw.rectangle((x, int(height * 0.78), x + 42, int(height * 0.86)), fill=(235, 203, 105, 50))
    else:
        for index in range(10):
            x = int(width * (0.04 + index * 0.11))
            draw.rounded_rectangle((x, int(height * 0.62), x + 160, int(height * 0.9)), radius=16, fill=(32, 20, 17, 88))
        draw.line((0, int(height * 0.7), width, int(height * 0.54)), fill=(*accent, 62), width=5)
    return image.filter(ImageFilter.GaussianBlur(radius=0.3))


def draw_hero(skin_id: str, size: tuple[int, int]) -> Image.Image:
    primary, dark, accent = SKINS[skin_id]["hero"]
    image = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(image, "RGBA")
    width, height = size
    if skin_id == "hakimi-paw-atelier":
        draw.ellipse((300, 320, 900, 980), fill=primary, outline=dark, width=18)
        draw.polygon([(420, 370), (520, 130), (610, 390)], fill=primary, outline=dark)
        draw.polygon([(710, 380), (870, 160), (840, 470)], fill=primary, outline=dark)
        draw.ellipse((470, 555, 540, 628), fill=dark)
        draw.ellipse((680, 555, 750, 628), fill=dark)
        draw.rounded_rectangle((560, 680, 650, 720), radius=28, fill=accent)
        draw.arc((725, 760, 1070, 1115), 270, 70, fill=accent, width=42)
        for center in [(520, 1000), (700, 1000)]:
            x, y = center
            draw.ellipse((x - 90, y - 65, x + 90, y + 65), fill=primary, outline=dark, width=12)
            for toe in range(4):
                draw.ellipse((x - 62 + toe * 40, y - 118, x - 24 + toe * 40, y - 76), fill=accent)
    elif skin_id == "cai-xukun-stage-check":
        draw.ellipse((430, 210, 750, 530), fill=primary, outline=dark, width=16)
        draw.rounded_rectangle((465, 505, 725, 1040), radius=110, fill=dark)
        draw.polygon([(465, 590), (230, 820), (305, 900), (555, 675)], fill=primary)
        draw.polygon([(720, 600), (995, 770), (925, 860), (650, 680)], fill=primary)
        draw.rectangle((580, 590, 620, 1110), fill=accent)
        draw.ellipse((515, 335, 570, 390), fill=dark)
        draw.ellipse((625, 335, 680, 390), fill=dark)
        for index in range(5):
            draw.arc((365 - index * 10, 155 - index * 10, 805 + index * 10, 590 + index * 10), 205, 332, fill=accent, width=4)
        draw.rounded_rectangle((780, 720, 830, 1100), radius=24, fill=primary)
        draw.ellipse((738, 660, 870, 792), fill=accent)
    else:
        draw.rounded_rectangle((410, 260, 760, 930), radius=170, fill=primary, outline=dark, width=16)
        draw.ellipse((445, 190, 725, 480), fill=primary, outline=dark, width=14)
        draw.polygon([(480, 430), (350, 740), (470, 780), (575, 510)], fill=dark)
        draw.polygon([(715, 435), (920, 690), (820, 760), (620, 525)], fill=dark)
        draw.rounded_rectangle((850, 650, 1030, 820), radius=76, fill=accent, outline=dark, width=12)
        draw.rounded_rectangle((285, 710, 460, 880), radius=76, fill=accent, outline=dark, width=12)
        draw.rectangle((492, 925, 555, 1240), fill=dark)
        draw.rectangle((625, 925, 688, 1240), fill=dark)
        draw.arc((340, 100, 840, 510), 198, 337, fill=dark, width=26)
        draw.polygon([(245, 910), (1020, 910), (900, 1028), (345, 1036)], fill=(92, 44, 40, 190))
    return image


def compose_preview(background: Image.Image, hero: Image.Image, skin_id: str) -> Image.Image:
    preview = background.resize((1600, 1000), Image.Resampling.LANCZOS).convert("RGBA")
    overlay = Image.new("RGBA", preview.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay, "RGBA")
    draw.rectangle((0, 0, 740, 1000), fill=(0, 0, 0, 104))
    draw.rounded_rectangle((90, 120, 620, 820), radius=34, fill=(255, 255, 255, 18), outline=(255, 255, 255, 58), width=2)
    for row in range(5):
        y = 210 + row * 92
        draw.rounded_rectangle((150, y, 520 - row * 28, y + 28), radius=14, fill=(255, 255, 255, 58))
    preview.alpha_composite(overlay)
    scale = 0.58
    resized = hero.resize((round(hero.width * scale), round(hero.height * scale)), Image.Resampling.LANCZOS)
    focus_x, focus_y = SKINS[skin_id]["preview"]
    x = int(preview.width * focus_x - resized.width * 0.5)
    y = int(preview.height * focus_y - resized.height * 0.5)
    preview.alpha_composite(resized, (x, y))
    return preview.convert("RGB")


def main() -> int:
    for skin_id in SKINS:
        root = ROOT / "skins" / skin_id
        expected = [root / "assets/background.png", root / "assets/hero.png", root / "preview.png"]
        if all(path.exists() for path in expected):
            continue
        assets = root / "assets"
        assets.mkdir(parents=True, exist_ok=True)
        background = draw_background(skin_id, (2400, 1600))
        hero = draw_hero(skin_id, (1200, 1400))
        preview = compose_preview(background, hero, skin_id)
        background.convert("RGB").save(assets / "background.png", optimize=True)
        hero.save(assets / "hero.png", optimize=True)
        preview.save(root / "preview.png", optimize=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
