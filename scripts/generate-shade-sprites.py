#!/usr/bin/env python3
"""Generate darkened shade sprite variants for VisualHUD themes.

Reads a theme.json, finds stages with multiple shades, and generates
brightness-reduced copies of the base sprite for each shade index > 0.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageEnhance


BRIGHTNESS_FACTORS = {1: 0.75, 2: 0.55}


def shade_sprite_name(sprite: str, color_family: str, shade_index: int) -> str:
    return f"{sprite}-{color_family}-{shade_index + 1}"


def generate_darkened_sprite(source: Path, dest: Path, factor: float) -> None:
    img = Image.open(source).convert("RGBA")
    alpha = img.getchannel("A")
    rgb = img.convert("RGB")
    darkened_rgb = ImageEnhance.Brightness(rgb).enhance(factor)
    result = darkened_rgb.convert("RGBA")
    result.putalpha(alpha)

    assert img.size == result.size
    assert list(result.getchannel("A").getdata()) == list(alpha.getdata())

    dest.parent.mkdir(parents=True, exist_ok=True)
    result.save(dest)


def process_theme(theme_path: Path, sprites_dir: Path, force: bool, dry_run: bool) -> dict:
    theme = json.loads(theme_path.read_text(encoding="utf-8"))
    manifest: list[dict] = []
    errors: list[str] = []

    for stage in theme.get("stages", []):
        sprite = stage.get("sprite", "")
        color_family = stage.get("color_family", "")
        shades = stage.get("shades", [])
        if not sprite or not color_family or len(shades) <= 1:
            continue

        source = sprites_dir / f"{sprite}.png"
        if not source.is_file():
            errors.append(f"Base sprite missing: {source}")
            continue

        shade_sprites = [sprite]
        for shade_index in range(1, len(shades)):
            if shade_index not in BRIGHTNESS_FACTORS:
                errors.append(
                    f"No brightness factor for shade index {shade_index} "
                    f"(stage {stage['name']}). Add to BRIGHTNESS_FACTORS."
                )
                continue

            name = shade_sprite_name(sprite, color_family, shade_index)
            dest = sprites_dir / f"{name}.png"
            shade_sprites.append(name)

            entry = {
                "stage": stage["name"],
                "base": sprite,
                "shade_sprite": name,
                "shade_index": shade_index,
                "brightness": BRIGHTNESS_FACTORS[shade_index],
                "file": str(dest),
            }

            if dest.exists() and not force:
                entry["skipped"] = "exists (use --force to overwrite)"
            elif dry_run:
                entry["skipped"] = "dry-run"
            else:
                generate_darkened_sprite(source, dest, BRIGHTNESS_FACTORS[shade_index])
                entry["generated"] = True

            manifest.append(entry)

    return {"manifest": manifest, "errors": errors}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--theme", required=True, type=Path, help="Path to theme.json")
    parser.add_argument("--sprites-dir", required=True, type=Path, help="Sprites directory")
    parser.add_argument("--force", action="store_true", help="Overwrite existing files")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be generated")
    args = parser.parse_args()

    result = process_theme(args.theme, args.sprites_dir, args.force, args.dry_run)

    for entry in result["manifest"]:
        status = "SKIP" if "skipped" in entry else "OK"
        detail = entry.get("skipped", "generated")
        print(f"  [{status}] {entry['shade_sprite']} ({entry['brightness']:.0%}) — {detail}")

    if result["errors"]:
        print("\nErrors:", file=sys.stderr)
        for err in result["errors"]:
            print(f"  {err}", file=sys.stderr)
        sys.exit(1)

    generated = sum(1 for e in result["manifest"] if e.get("generated"))
    skipped = sum(1 for e in result["manifest"] if "skipped" in e)
    print(f"\n{generated} generated, {skipped} skipped")


if __name__ == "__main__":
    main()
