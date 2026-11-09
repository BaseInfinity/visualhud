#!/usr/bin/env python3
"""Generate the original Railway Conductor theme art and whistle.

Every asset is drawn from primitives here: a blue 0-4-0 saddle-tank engine of
VisualHUD's own design (no face, no number), a three-aspect signal, and a
synthesized three-note steam whistle. Output is deterministic, so the shipped
files can be regenerated and compared.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import struct
import wave
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 512
GENERATOR = "scripts/generate-railway-assets.py"

BLUE = (38, 86, 168, 255)
BLUE_DARK = (24, 56, 116, 255)
BLACK = (28, 28, 34, 255)
STEEL = (120, 128, 140, 255)
BRASS = (214, 170, 72, 255)
COPPER = (184, 108, 62, 255)
RAIL = (150, 150, 160, 255)
SLEEPER = (92, 64, 44, 255)
SMOKE = (236, 236, 240, 210)

LAMP_RED = (226, 44, 40, 255)
LAMP_AMBER = (244, 164, 32, 255)
LAMP_GREEN = (40, 196, 92, 255)
LAMP_OFF = (52, 52, 58, 255)

# name -> (sky top, sky bottom, lit lamp or None, smoke puffs, engine x offset)
SCENES = {
    "railway-platform": ((70, 110, 170), (150, 180, 210), LAMP_GREEN, 0, -40),
    "railway-departing": ((60, 100, 165), (140, 175, 210), LAMP_GREEN, 2, -10),
    "railway-steam": ((55, 95, 160), (130, 165, 205), LAMP_GREEN, 4, 10),
    "railway-open-line": ((60, 120, 180), (170, 200, 220), LAMP_GREEN, 3, 30),
    "railway-viaduct": ((80, 120, 170), (200, 190, 170), LAMP_GREEN, 3, 40),
    "railway-tunnel": ((30, 40, 60), (70, 80, 100), LAMP_GREEN, 2, 50),
    "railway-grade": ((110, 90, 120), (210, 150, 110), LAMP_GREEN, 5, 30),
    "railway-express": ((20, 30, 70), (90, 70, 120), LAMP_GREEN, 6, 60),
    "railway-signal-green": ((50, 90, 70), (120, 170, 130), LAMP_GREEN, 1, -60),
    "railway-signal-amber": ((90, 70, 40), (190, 150, 90), LAMP_AMBER, 1, -60),
    "railway-signal-red": ((80, 30, 30), (170, 90, 80), LAMP_RED, 0, -60),
    "railway-arrival": ((40, 120, 80), (160, 210, 170), LAMP_GREEN, 1, -20),
    "railway-idle": ((40, 50, 70), (90, 100, 120), None, 0, -40),
}


def sky(draw: ImageDraw.ImageDraw, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> None:
    for y in range(SIZE):
        t = y / (SIZE - 1)
        color = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)
        draw.line([(0, y), (SIZE, y)], fill=color)


def track(draw: ImageDraw.ImageDraw) -> None:
    draw.rectangle([0, 400, SIZE, SIZE], fill=(70, 74, 64, 255))
    for x in range(-8, SIZE, 36):
        draw.rectangle([x, 404, x + 22, 416], fill=SLEEPER)
    draw.rectangle([0, 398, SIZE, 404], fill=RAIL)


def wheel(draw: ImageDraw.ImageDraw, cx: int, cy: int, r: int) -> None:
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=BLACK)
    draw.ellipse([cx - r + 6, cy - r + 6, cx + r - 6, cy + r - 6], fill=STEEL)
    for k in range(8):
        a = k * math.pi / 4
        draw.line([(cx, cy), (cx + (r - 7) * math.cos(a), cy + (r - 7) * math.sin(a))], fill=BLACK, width=3)
    draw.ellipse([cx - 7, cy - 7, cx + 7, cy + 7], fill=BLACK)


def engine(draw: ImageDraw.ImageDraw, dx: int) -> None:
    """A 0-4-0 saddle tank, facing right: cab at left, smokebox at right."""
    # Footplate and frame.
    draw.rectangle([90 + dx, 336, 400 + dx, 350], fill=BLACK)
    # Cab.
    draw.rectangle([96 + dx, 196, 196 + dx, 336], fill=BLUE)
    draw.rectangle([88 + dx, 184, 204 + dx, 198], fill=BLUE_DARK)
    draw.rounded_rectangle([118 + dx, 214, 176 + dx, 262], radius=10, fill=(200, 220, 235, 255))
    # Boiler under a saddle tank that wraps over its top.
    draw.rectangle([196 + dx, 262, 370 + dx, 336], fill=BLUE_DARK)
    draw.rounded_rectangle([196 + dx, 226, 352 + dx, 300], radius=34, fill=BLUE)
    draw.line([(204 + dx, 296), (344 + dx, 296)], fill=BRASS, width=3)
    # Smokebox and door.
    draw.rectangle([352 + dx, 252, 396 + dx, 336], fill=BLACK)
    draw.ellipse([380 + dx, 262, 408 + dx, 326], fill=(44, 44, 52, 255))
    # Chimney with a copper cap, and a brass dome on the tank.
    draw.rectangle([360 + dx, 196, 384 + dx, 252], fill=BLACK)
    draw.rectangle([354 + dx, 186, 390 + dx, 198], fill=COPPER)
    draw.rounded_rectangle([262 + dx, 204, 298 + dx, 232], radius=12, fill=BRASS)
    # Buffer beam and buffers (black, not a painted beam).
    draw.rectangle([396 + dx, 322, 412 + dx, 350], fill=BLACK)
    for by in (328, 342):
        draw.rectangle([412 + dx, by - 4, 426 + dx, by + 4], fill=STEEL)
    # Two driving axles, coupled.
    wheel(draw, 180 + dx, 366, 32)
    wheel(draw, 318 + dx, 366, 32)
    draw.line([(180 + dx, 378), (318 + dx, 378)], fill=STEEL, width=6)
    # Builder's plate, blank.
    draw.rounded_rectangle([126 + dx, 286, 168 + dx, 310], radius=6, fill=BRASS)


def smoke(draw: ImageDraw.ImageDraw, dx: int, puffs: int) -> None:
    for k in range(puffs):
        r = 16 + k * 7
        cx = 372 + dx - k * 34
        cy = 168 - k * 22
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=SMOKE)


def signal(draw: ImageDraw.ImageDraw, lit: tuple[int, int, int, int] | None) -> None:
    draw.rectangle([452, 150, 462, 400], fill=BLACK)
    draw.rounded_rectangle([432, 60, 482, 214], radius=14, fill=BLACK)
    for lamp, cy in ((LAMP_RED, 86), (LAMP_AMBER, 136), (LAMP_GREEN, 186)):
        fill = lamp if lamp == lit else LAMP_OFF
        if lamp == lit:
            draw.ellipse([457 - 26, cy - 26, 457 + 26, cy + 26], fill=lamp[:3] + (90,))
        draw.ellipse([457 - 17, cy - 17, 457 + 17, cy + 17], fill=fill)


def sprite(name: str) -> Image.Image:
    top, bottom, lit, puffs, dx = SCENES[name]
    image = Image.new("RGBA", (SIZE, SIZE))
    draw = ImageDraw.Draw(image, "RGBA")
    sky(draw, top, bottom)
    track(draw)
    engine(draw, dx)
    smoke(draw, dx, puffs)
    signal(draw, lit)
    return image


def whistle(path: Path) -> None:
    """Three-chime steam whistle: a breathy chord with a soft attack and tail."""
    rate = 22050
    seconds = 1.4
    notes = (466.16, 587.33, 698.46)
    rng = random.Random(1804)
    frames = bytearray()
    total = int(rate * seconds)
    for i in range(total):
        t = i / rate
        envelope = min(1.0, t / 0.08) * min(1.0, (seconds - t) / 0.35)
        vibrato = 1 + 0.004 * math.sin(2 * math.pi * 5.5 * t)
        tone = sum(math.sin(2 * math.pi * f * vibrato * t) for f in notes) / len(notes)
        breath = rng.uniform(-1, 1) * 0.12
        sample = int(max(-1.0, min(1.0, (tone * 0.7 + breath) * envelope)) * 26000)
        frames += struct.pack("<h", sample)
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(bytes(frames))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="theme directory to write into")
    args = parser.parse_args()

    sprites_dir = args.output / "sprites"
    sprites_dir.mkdir(parents=True, exist_ok=True)
    assets: dict[str, dict[str, str]] = {}
    for name in SCENES:
        path = sprites_dir / f"{name}.png"
        sprite(name).save(path, optimize=False)
        assets[f"sprites/{name}.png"] = {}

    whistle(args.output / "sounds" / "whistle.wav")
    assets["sounds/whistle.wav"] = {}

    for relative in assets:
        assets[relative] = {
            "sha256": sha256(args.output / relative),
            "generator": GENERATOR,
            "origin": "original",
            "license": "MIT",
        }

    manifest = {
        "schema": "visualhud-railway-assets-v1",
        "note": "Drawn and synthesized from primitives by the generator; no third-party art or audio.",
        "assets": dict(sorted(assets.items())),
    }
    (sprites_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
