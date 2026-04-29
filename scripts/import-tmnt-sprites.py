#!/usr/bin/env python3
"""Import TMNT character-select panels as source-backed VisualHUD sprites."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageFilter


SPRITES = (
    "tmnt-leonardo",
    "tmnt-michelangelo",
    "tmnt-donatello",
    "tmnt-raphael",
)
HUD_BACKGROUND_SIZE = (900, 1400)


@dataclass(frozen=True)
class Box:
    left: int
    top: int
    right: int
    bottom: int

    def as_list(self) -> list[int]:
        return [self.left, self.top, self.right, self.bottom]


def is_content_pixel(pixel: tuple[int, ...]) -> bool:
    red, green, blue = pixel[:3]
    alpha = pixel[3] if len(pixel) > 3 else 255
    return alpha > 16 and max(red, green, blue) > 24


def grouped_ranges(values: list[int], min_gap: int = 8) -> list[tuple[int, int]]:
    if not values:
        return []

    ranges: list[tuple[int, int]] = []
    start = prev = values[0]
    for value in values[1:]:
        if value - prev > min_gap:
            ranges.append((start, prev + 1))
            start = value
        prev = value
    ranges.append((start, prev + 1))
    return ranges


def fallback_panel_boxes(width: int, height: int) -> list[Box]:
    panel_width = width // len(SPRITES)
    boxes: list[Box] = []
    for index in range(len(SPRITES)):
        left = index * panel_width
        right = width if index == len(SPRITES) - 1 else (index + 1) * panel_width
        boxes.append(Box(left, 0, right, height))
    return boxes


def select_main_content_range(rows: list[int]) -> tuple[int, int] | None:
    ranges = grouped_ranges(rows)
    if not ranges:
        return None

    return max(ranges, key=lambda item: (item[1] - item[0], -item[0]))


def detect_panel_boxes(image: Image.Image) -> list[Box]:
    rgba = image.convert("RGBA")
    width, height = rgba.size
    pixels = rgba.load()
    min_column_pixels = max(3, height // 25)

    content_columns: list[int] = []
    for x in range(width):
        count = 0
        for y in range(height):
            if is_content_pixel(pixels[x, y]):
                count += 1
        if count >= min_column_pixels:
            content_columns.append(x)

    x_ranges = [
        item
        for item in grouped_ranges(content_columns)
        if item[1] - item[0] >= max(20, width // 30)
    ]
    if len(x_ranges) != len(SPRITES):
        return fallback_panel_boxes(width, height)

    boxes: list[Box] = []
    for left, right in x_ranges:
        rows: list[int] = []
        for y in range(height):
            if any(is_content_pixel(pixels[x, y]) for x in range(left, right)):
                rows.append(y)

        content_range = select_main_content_range(rows)
        if content_range:
            top = max(0, content_range[0])
            bottom = min(height, content_range[1])
        else:
            top = 0
            bottom = height
        boxes.append(Box(left, top, right, bottom))

    return boxes


def write_manifest(
    manifest_path: Path,
    source: Path,
    source_label: str,
    boxes: list[Box],
) -> None:
    entries = {
        sprite: {
            "source": manifest_source_path(source),
            "source_label": source_label,
            "crop": boxes[index].as_list(),
        }
        for index, sprite in enumerate(SPRITES)
    }
    write_manifest_entries(manifest_path, entries)


def manifest_source_path(source: Path) -> str:
    try:
        return str(source.resolve().relative_to(Path.cwd().resolve()))
    except ValueError:
        return str(source)


def write_manifest_entries(manifest_path: Path, entries: dict[str, dict[str, object]]) -> None:
    manifest = {
        "schema": "visualhud-tmnt-sprites-v1",
        "sprites": {},
    }
    if manifest_path.is_file():
        existing = json.loads(manifest_path.read_text(encoding="utf-8"))
        if existing.get("schema") == manifest["schema"] and isinstance(existing.get("sprites"), dict):
            manifest["sprites"] = existing["sprites"]

    manifest["sprites"].update(entries)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def resize_cover(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    target_width, target_height = size
    source_width, source_height = image.size
    scale = max(target_width / source_width, target_height / source_height)
    resized = image.resize(
        (round(source_width * scale), round(source_height * scale)),
        Image.Resampling.LANCZOS,
    )
    left = (resized.width - target_width) // 2
    top = (resized.height - target_height) // 2
    return resized.crop((left, top, left + target_width, top + target_height))


def resize_contain(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    target_width, target_height = size
    source_width, source_height = image.size
    scale = min(target_width / source_width, target_height / source_height)
    return image.resize(
        (round(source_width * scale), round(source_height * scale)),
        Image.Resampling.LANCZOS,
    )


def sample_corner_matte(image: Image.Image) -> tuple[int, int, int] | None:
    rgba = image.convert("RGBA")
    width, height = rgba.size
    sample_size = max(2, min(width, height) // 24)
    pixels = rgba.load()
    samples: list[tuple[int, int, int]] = []
    corners = (
        (0, 0),
        (width - sample_size, 0),
        (0, height - sample_size),
        (width - sample_size, height - sample_size),
    )

    for left, top in corners:
        for y in range(top, top + sample_size):
            for x in range(left, left + sample_size):
                red, green, blue, alpha = pixels[x, y]
                if alpha > 200:
                    samples.append((red, green, blue))

    if len(samples) < sample_size * sample_size:
        return None

    matte = tuple(round(sum(pixel[index] for pixel in samples) / len(samples)) for index in range(3))
    if max(matte) - min(matte) > 35:
        return None
    if not 55 <= sum(matte) / 3 <= 230:
        return None

    max_deviation = max(max(abs(pixel[index] - matte[index]) for index in range(3)) for pixel in samples)
    if max_deviation > 28:
        return None
    return matte


def strip_neutral_corner_matte(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    matte = sample_corner_matte(rgba)
    if matte is None:
        return rgba

    hard_distance = 42
    soft_distance = 82
    pixels = rgba.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha == 0:
                continue
            distance = max(
                abs(red - matte[0]),
                abs(green - matte[1]),
                abs(blue - matte[2]),
            )
            if distance <= hard_distance:
                pixels[x, y] = (red, green, blue, 0)
            elif distance <= soft_distance:
                keep_ratio = (distance - hard_distance) / (soft_distance - hard_distance)
                pixels[x, y] = (red, green, blue, round(alpha * keep_ratio))

    return rgba


def rgb_color(value: object) -> tuple[int, int, int] | None:
    if not isinstance(value, list) or len(value) != 3:
        return None
    if not all(isinstance(channel, int) and 0 <= channel <= 255 for channel in value):
        return None
    return (value[0], value[1], value[2])


def sprite_backdrop_colors(theme_path: Path) -> dict[str, tuple[int, int, int]]:
    if not theme_path.is_file():
        return {}

    theme = json.loads(theme_path.read_text(encoding="utf-8"))
    colors: dict[str, tuple[int, int, int]] = {}

    for stage in theme.get("stages", []):
        if not isinstance(stage, dict):
            continue
        stage_color = rgb_color(stage.get("color"))
        sprite = stage.get("sprite")
        if isinstance(sprite, str) and stage_color is not None:
            colors[sprite] = stage_color
        shades = stage.get("shades")
        shade_sprites = stage.get("shade_sprites")
        if isinstance(shades, list) and isinstance(shade_sprites, list):
            for index, shade_sprite in enumerate(shade_sprites):
                shade_color = rgb_color(shades[index]) if index < len(shades) else stage_color
                if isinstance(shade_sprite, str) and shade_color is not None:
                    colors[shade_sprite] = shade_color

    for state_name in ("blocked", "done", "idle", "error"):
        state = theme.get(state_name)
        if not isinstance(state, dict):
            continue
        state_color = rgb_color(state.get("color"))
        sprite = state.get("sprite")
        if isinstance(sprite, str) and state_color is not None:
            colors[sprite] = state_color

    context_alerts = theme.get("context_alerts")
    if isinstance(context_alerts, dict):
        for alert in context_alerts.values():
            if not isinstance(alert, dict):
                continue
            alert_color = rgb_color(alert.get("color"))
            sprite = alert.get("sprite")
            if isinstance(sprite, str) and alert_color is not None:
                colors[sprite] = alert_color

    return colors


def backdrop_color_for_sprite(sprite: str, output_dir: Path) -> tuple[int, int, int] | None:
    return sprite_backdrop_colors(output_dir.parent / "theme.json").get(sprite)


def render_hud_background(
    panel: Image.Image,
    backdrop_color: tuple[int, int, int] | None = None,
) -> Image.Image:
    cover = resize_cover(panel, HUD_BACKGROUND_SIZE)
    cover = cover.filter(ImageFilter.GaussianBlur(radius=26))
    if backdrop_color is None:
        background = cover
    else:
        background = Image.new("RGBA", HUD_BACKGROUND_SIZE, (*backdrop_color, 255))
        background.alpha_composite(cover)
    shade = Image.new("RGBA", HUD_BACKGROUND_SIZE, (0, 0, 0, 92))
    background.alpha_composite(shade)

    foreground = resize_contain(
        panel,
        (HUD_BACKGROUND_SIZE[0] - 90, HUD_BACKGROUND_SIZE[1] - 120),
    )
    x = (HUD_BACKGROUND_SIZE[0] - foreground.width) // 2
    y = (HUD_BACKGROUND_SIZE[1] - foreground.height) // 2
    background.alpha_composite(foreground, (x, y))
    return background


def import_sprites(source: Path, output_dir: Path, source_label: str) -> None:
    if not source.is_file():
        raise SystemExit(f"source image does not exist: {source}")

    output_dir.mkdir(parents=True, exist_ok=True)
    image = Image.open(source).convert("RGBA")
    boxes = detect_panel_boxes(image)
    if len(boxes) != len(SPRITES):
        raise SystemExit(f"expected {len(SPRITES)} crop boxes, got {len(boxes)}")

    for sprite, box in zip(SPRITES, boxes):
        crop = image.crop(tuple(box.as_list()))
        render_hud_background(
            crop,
            backdrop_color_for_sprite(sprite, output_dir),
        ).save(output_dir / f"{sprite}.png")

    write_manifest(output_dir / "manifest.json", source, source_label, boxes)


def import_asset(
    sprite: str,
    source: Path,
    output_dir: Path,
    source_label: str,
    crop_box: Box | None = None,
) -> None:
    if not source.is_file():
        raise SystemExit(f"source image does not exist: {source}")
    if not sprite:
        raise SystemExit("asset sprite name must not be empty")

    output_dir.mkdir(parents=True, exist_ok=True)
    image = Image.open(source).convert("RGBA")
    crop = crop_box or Box(0, 0, image.size[0], image.size[1])
    if crop.left < 0 or crop.top < 0 or crop.right > image.size[0] or crop.bottom > image.size[1]:
        raise SystemExit(f"crop is outside source bounds for {sprite}: {crop.as_list()}")
    if crop.left >= crop.right or crop.top >= crop.bottom:
        raise SystemExit(f"crop has invalid dimensions for {sprite}: {crop.as_list()}")

    panel = image.crop(tuple(crop.as_list()))
    backdrop_color = backdrop_color_for_sprite(sprite, output_dir)
    if crop_box is not None:
        panel = strip_neutral_corner_matte(panel)
    render_hud_background(panel, backdrop_color).save(output_dir / f"{sprite}.png")
    entry: dict[str, object] = {
        "source": manifest_source_path(source),
        "source_label": source_label,
        "crop": crop.as_list(),
    }
    if backdrop_color is not None:
        entry["backdrop_color"] = list(backdrop_color)
    if crop_box is not None:
        entry["composition"] = "character-focused"

    write_manifest_entries(
        output_dir / "manifest.json",
        {sprite: entry},
    )


def parse_asset(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise SystemExit(f"asset must be SPRITE=SOURCE: {value}")
    sprite, source_value = value.split("=", 1)
    return sprite, Path(source_value)


def parse_asset_crop(value: str) -> tuple[str, Path, Box]:
    parts = value.split("=", 2)
    if len(parts) != 3:
        raise SystemExit(f"asset crop must be SPRITE=SOURCE=LEFT,TOP,RIGHT,BOTTOM: {value}")

    sprite, source_value, crop_value = parts
    crop_parts = crop_value.split(",")
    if len(crop_parts) != 4:
        raise SystemExit(f"asset crop must include four coordinates: {value}")

    try:
        left, top, right, bottom = (int(part) for part in crop_parts)
    except ValueError as error:
        raise SystemExit(f"asset crop coordinates must be integers: {value}") from error

    return sprite, Path(source_value), Box(left, top, right, bottom)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Crop a four-panel TMNT character-select reference into VisualHUD sprites."
    )
    parser.add_argument("--source", type=Path, help="Source character-select image")
    parser.add_argument(
        "--asset",
        action="append",
        default=[],
        metavar="SPRITE=SOURCE",
        help="Import a single source image as one sprite backdrop; may be repeated",
    )
    parser.add_argument(
        "--asset-crop",
        action="append",
        default=[],
        metavar="SPRITE=SOURCE=LEFT,TOP,RIGHT,BOTTOM",
        help="Import a cropped source region as a character-focused sprite; may be repeated",
    )
    parser.add_argument(
        "--output-dir",
        default=Path("themes/tmnt/sprites"),
        type=Path,
        help="Directory for generated sprite PNGs and manifest.json",
    )
    parser.add_argument(
        "--source-label",
        default=None,
        help="Human-readable provenance label stored in manifest.json",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if not args.source and not args.asset and not args.asset_crop:
        raise SystemExit("one of --source, --asset, or --asset-crop is required")

    if args.source:
        source = args.source
        source_label = args.source_label or source.name
        import_sprites(source, args.output_dir, source_label)

    for asset in args.asset:
        sprite, source = parse_asset(asset)
        source_label = args.source_label or source.name
        import_asset(sprite, source, args.output_dir, source_label)

    for asset_crop in args.asset_crop:
        sprite, source, crop_box = parse_asset_crop(asset_crop)
        source_label = args.source_label or source.name
        import_asset(sprite, source, args.output_dir, source_label, crop_box)


if __name__ == "__main__":
    main()
