#!/usr/bin/env python3
"""Pixel-level shade sprite conformance test.

Verifies that shade sprites are brightness-reduced copies of their base sprites,
not zoom crops or unrelated images. Checks dimensions, alpha preservation,
per-pixel RGB scaling, luminance ratio, and monotonic darkening.

Usage: python3 tests/shade-conformance.py <theme-dir> [<theme-dir> ...]
Exit code 0 = all pass, 1 = failures found.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

BRIGHTNESS_FACTORS = {1: 0.75, 2: 0.55}
LUMA_TOLERANCE = 0.015
MAX_RGB_ERROR = 1


def mean_luminance(pixels: list[tuple[int, ...]], alpha_threshold: int = 0) -> float:
    visible = [(r, g, b) for r, g, b, a in pixels if a > alpha_threshold]
    if not visible:
        return 0.0
    return sum(0.2126 * r + 0.7152 * g + 0.0722 * b for r, g, b in visible) / len(visible)


def check_shade(base_path: Path, shade_path: Path, factor: float) -> list[str]:
    base = Image.open(base_path).convert("RGBA")
    shade = Image.open(shade_path).convert("RGBA")
    failures = []

    if base.size != shade.size:
        failures.append(f"DIMENSIONS: base={base.size} shade={shade.size}")
        return failures

    bp = list(base.getdata())
    sp = list(shade.getdata())

    alpha_mismatches = sum(bp[i][3] != sp[i][3] for i in range(len(bp)))
    if alpha_mismatches > 0:
        failures.append(f"ALPHA: {alpha_mismatches} pixels differ (expected exact match)")

    visible = [i for i, p in enumerate(bp) if p[3] > 0]
    if not visible:
        failures.append("NO_VISIBLE_PIXELS: base sprite is fully transparent")
        return failures

    max_err = 0
    brightened = 0
    for i in visible:
        for c in range(3):
            expected = round(bp[i][c] * factor)
            actual = sp[i][c]
            err = abs(actual - expected)
            if err > max_err:
                max_err = err
            if actual > bp[i][c] + 1:
                brightened += 1

    if max_err > MAX_RGB_ERROR:
        failures.append(f"RGB_SCALING: max_error={max_err} (limit {MAX_RGB_ERROR})")

    if brightened > 0:
        failures.append(f"BRIGHTENED: {brightened} channels brighter than base+1")

    base_luma = mean_luminance(bp)
    shade_luma = mean_luminance(sp)
    if base_luma > 0:
        ratio = shade_luma / base_luma
        if abs(ratio - factor) > LUMA_TOLERANCE:
            failures.append(f"LUMINANCE: ratio={ratio:.4f} expected={factor}+-{LUMA_TOLERANCE}")

    return failures


def test_theme(theme_dir: Path) -> tuple[int, int, list[str]]:
    theme_file = theme_dir / "theme.json"
    sprites_dir = theme_dir / "sprites"
    theme = json.loads(theme_file.read_text(encoding="utf-8"))
    theme_name = theme.get("name", theme_dir.name)

    passed = 0
    failed = 0
    errors: list[str] = []

    stages = theme.get("stages", [])
    prev_shade_lumas: list[float] = []

    for stage in stages:
        sprite = stage.get("sprite", "")
        shade_sprites = stage.get("shade_sprites", [])
        if not sprite or len(shade_sprites) <= 1:
            continue

        base_path = sprites_dir / f"{sprite}.png"
        if not base_path.exists():
            errors.append(f"  FAIL: [{theme_name}] {sprite} base sprite missing")
            failed += 1
            continue

        base_img = Image.open(base_path).convert("RGBA")
        base_luma = mean_luminance(list(base_img.getdata()))
        shade_lumas = [base_luma]

        for idx in range(1, len(shade_sprites)):
            shade_name = shade_sprites[idx]
            shade_path = sprites_dir / f"{shade_name}.png"
            factor = BRIGHTNESS_FACTORS.get(idx)

            if not shade_path.exists():
                errors.append(f"  FAIL: [{theme_name}] {shade_name} shade sprite missing")
                failed += 1
                continue

            if factor is None:
                errors.append(f"  FAIL: [{theme_name}] {shade_name} no brightness factor for index {idx}")
                failed += 1
                continue

            failures = check_shade(base_path, shade_path, factor)

            shade_img = Image.open(shade_path).convert("RGBA")
            shade_luma = mean_luminance(list(shade_img.getdata()))
            shade_lumas.append(shade_luma)

            if failures:
                for f in failures:
                    errors.append(f"  FAIL: [{theme_name}] {shade_name} (factor={factor}): {f}")
                failed += 1
            else:
                print(f"  PASS: [{theme_name}] {shade_name} (factor={factor})")
                passed += 1

        for i in range(1, len(shade_lumas)):
            if shade_lumas[i] >= shade_lumas[i - 1]:
                label = shade_sprites[i] if i < len(shade_sprites) else f"shade-{i}"
                prev_label = shade_sprites[i - 1] if i - 1 < len(shade_sprites) else "base"
                errors.append(
                    f"  FAIL: [{theme_name}] monotonic darkening violated: "
                    f"{prev_label} luma={shade_lumas[i-1]:.1f} vs {label} luma={shade_lumas[i]:.1f}"
                )
                failed += 1

    return passed, failed, errors


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: shade-conformance.py <theme-dir> [<theme-dir> ...]", file=sys.stderr)
        sys.exit(2)

    total_passed = 0
    total_failed = 0
    all_errors: list[str] = []

    for theme_dir_arg in sys.argv[1:]:
        theme_dir = Path(theme_dir_arg)
        if not (theme_dir / "theme.json").exists():
            print(f"Skipping {theme_dir}: no theme.json", file=sys.stderr)
            continue

        print(f"\n--- {theme_dir.name} ---")
        passed, failed, errors = test_theme(theme_dir)
        total_passed += passed
        total_failed += failed
        all_errors.extend(errors)

    print(f"\n=== Shade conformance: {total_passed} passed, {total_failed} failed ===")
    for err in all_errors:
        print(err)

    sys.exit(1 if total_failed > 0 else 0)


if __name__ == "__main__":
    main()
