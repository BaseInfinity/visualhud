#!/usr/bin/env python3
"""Render a VisualHUD theme contact sheet for visual smoke review."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw


CARD_SIZE = (260, 430)
SPRITE_BOX = (220, 300)
PADDING = 18
COLUMNS = 4


def color_text(color: list[int]) -> str:
    return "-".join(str(value) for value in color)


def theme_entries(theme: dict[str, Any]) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    for stage in theme.get("stages", []):
        shade_sprites = stage.get("shade_sprites") or []
        shades = stage.get("shades") or []
        entries.append(
            {
                "kind": "stage",
                "name": stage["name"],
                "sprite": stage.get("sprite", ""),
                "badge": stage.get("badge", ""),
                "color": stage["color"],
            }
        )
        for index, sprite in enumerate(shade_sprites):
            if index == 0:
                continue
            entries.append(
                {
                    "kind": "stage-shade",
                    "name": f"{stage['name']} shade {index + 1}",
                    "sprite": sprite,
                    "badge": stage.get("badge", ""),
                    "color": shades[index] if index < len(shades) else stage["color"],
                    "base_sprite": stage.get("sprite", ""),
                }
            )

    for key in ("blocked", "done", "idle", "error"):
        state = theme.get(key)
        if state:
            entries.append(
                {
                    "kind": key,
                    "name": state["name"],
                    "sprite": state.get("sprite", ""),
                    "badge": state.get("badge", ""),
                    "color": state["color"],
                }
            )

    for key, state in sorted((theme.get("context_alerts") or {}).items()):
        entries.append(
            {
                "kind": "context",
                "name": state["name"],
                "sprite": state.get("sprite", ""),
                "badge": state.get("badge", ""),
                "color": state["color"],
                "level": key,
            }
        )
    return entries


def draw_label(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str) -> None:
    draw.text(xy, text, fill=(245, 245, 245, 255))


def render_card(entry: dict[str, Any], sprite_path: Path | None) -> Image.Image:
    color = entry["color"]
    card = Image.new("RGBA", CARD_SIZE, (18, 18, 18, 255))
    draw = ImageDraw.Draw(card)
    swatch = Image.new("RGBA", (CARD_SIZE[0], 54), tuple(color + [255]))
    card.alpha_composite(swatch, (0, 0))

    if sprite_path and sprite_path.is_file():
        sprite = Image.open(sprite_path).convert("RGBA")
        sprite.thumbnail(SPRITE_BOX, Image.Resampling.LANCZOS)
        x = (CARD_SIZE[0] - sprite.width) // 2
        y = 70 + (SPRITE_BOX[1] - sprite.height) // 2
        card.alpha_composite(sprite, (x, y))
    else:
        draw.rectangle((20, 88, CARD_SIZE[0] - 20, 88 + SPRITE_BOX[1]), outline=(220, 80, 80), width=4)
        draw_label(draw, (36, 218), "NO SPRITE")

    draw_label(draw, (16, 12), f"{entry['kind']}  {entry.get('badge', '')}")
    draw_label(draw, (16, CARD_SIZE[1] - 76), entry["name"])
    draw_label(draw, (16, CARD_SIZE[1] - 52), entry.get("sprite") or "color-only")
    draw_label(draw, (16, CARD_SIZE[1] - 28), color_text(color))
    return card


def render_contact_sheet(entries: list[dict[str, Any]], sprites_dir: Path, output: Path) -> list[str]:
    rows = (len(entries) + COLUMNS - 1) // COLUMNS
    sheet_size = (
        PADDING + COLUMNS * (CARD_SIZE[0] + PADDING),
        PADDING + rows * (CARD_SIZE[1] + PADDING),
    )
    sheet = Image.new("RGBA", sheet_size, (0, 0, 0, 255))
    missing_sprites: list[str] = []

    for index, entry in enumerate(entries):
        sprite = entry.get("sprite") or ""
        sprite_path = sprites_dir / f"{sprite}.png" if sprite else None
        if sprite and (not sprite_path or not sprite_path.is_file()):
            missing_sprites.append(sprite)

        card = render_card(entry, sprite_path)
        col = index % COLUMNS
        row = index // COLUMNS
        x = PADDING + col * (CARD_SIZE[0] + PADDING)
        y = PADDING + row * (CARD_SIZE[1] + PADDING)
        sheet.alpha_composite(card, (x, y))

    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output)
    return missing_sprites


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--theme", required=True, type=Path)
    parser.add_argument("--sprites-dir", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    theme = json.loads(args.theme.read_text(encoding="utf-8"))
    entries = theme_entries(theme)
    missing_sprites = render_contact_sheet(entries, args.sprites_dir, args.output)
    report = {
        "theme": str(args.theme),
        "sprites_dir": str(args.sprites_dir),
        "output": str(args.output),
        "entries": entries,
        "missing_sprites": sorted(missing_sprites),
    }
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
