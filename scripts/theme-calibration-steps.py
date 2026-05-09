#!/usr/bin/env python3
"""Generate ordered VisualHUD theme calibration steps."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any


if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def color_text(color: list[int]) -> str:
    return "-".join(str(value) for value in color)


def progress_bar(theme: dict[str, Any], stage_index: int | None) -> str:
    if not stage_index:
        return ""
    tokens = theme.get("progress_bar") or []
    if not tokens:
        return "#" * stage_index
    return "".join(str(token) for token in tokens[:stage_index])


def stage_start(stages: list[dict[str, Any]], index: int) -> int:
    if index == 0:
        return 1
    return int(stages[index - 1].get("max", 0)) + 1


def overflow_shade_span(stages: list[dict[str, Any]], index: int, shade_count: int) -> int:
    if index == 0:
        return shade_count * 20
    previous_start = stage_start(stages, index - 1)
    previous_max = int(stages[index - 1].get("max", previous_start))
    return max(1, previous_max - previous_start + 1) * shade_count


def shade_trigger_count(stages: list[dict[str, Any]], index: int, shade_index: int, shade_count: int) -> int:
    stage = stages[index]
    start = stage_start(stages, index)
    stage_max = int(stage.get("max", 999999))
    if stage_max >= 999999:
        span = overflow_shade_span(stages, index, shade_count)
    else:
        span = max(1, stage_max - start + 1)
    return start + math.ceil(shade_index * span / shade_count)


def stage_entries(theme: dict[str, Any]) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    stages = theme.get("stages") or []
    for index, stage in enumerate(stages):
        shades = stage.get("shades") or [stage["color"]]
        shade_sprites = stage.get("shade_sprites") or []
        shade_count = max(1, len(shades))
        for shade_index in range(shade_count):
            color = shades[shade_index] if shade_index < len(shades) else stage["color"]
            sprite = (
                shade_sprites[shade_index]
                if shade_index < len(shade_sprites)
                else stage.get("sprite", "")
            )
            name = stage["name"] if shade_index == 0 else f"{stage['name']} shade {shade_index + 1}"
            entries.append(
                {
                    "kind": "stage" if shade_index == 0 else "stage-shade",
                    "name": name,
                    "badge": stage.get("badge", ""),
                    "sprite": sprite,
                    "base_sprite": stage.get("sprite", ""),
                    "color": color,
                    "color_family": stage.get("color_family", ""),
                    "stage_index": index + 1,
                    "progress_bar": progress_bar(theme, index + 1),
                    "trigger_count": shade_trigger_count(stages, index, shade_index, shade_count),
                }
            )
    return entries


def lifecycle_entries(theme: dict[str, Any]) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    for key in ("blocked", "review", "done", "idle", "error"):
        state = theme.get(key)
        if not state:
            continue
        stage_index = state.get("stage")
        entries.append(
            {
                "kind": key,
                "name": state["name"],
                "badge": state.get("badge", ""),
                "sprite": state.get("sprite", ""),
                "color": state["color"],
                "stage_index": stage_index,
                "progress_bar": progress_bar(theme, stage_index),
            }
        )
    return entries


def context_entries(theme: dict[str, Any]) -> list[dict[str, Any]]:
    alerts = theme.get("context_alerts") or {}
    ordered = sorted(alerts.items(), key=lambda item: item[1].get("min_percent", 0))
    entries: list[dict[str, Any]] = []
    for key, state in ordered:
        entries.append(
            {
                "kind": "context",
                "level": key,
                "name": state["name"],
                "badge": state.get("badge", ""),
                "sprite": state.get("sprite", ""),
                "color": state["color"],
                "context_percent": state.get("min_percent", 0),
                "stage_index": 1,
                "progress_bar": progress_bar(theme, 1),
                "trigger_count": 1,
                "note": "context overlay; live rendering preserves the active stage sprite/color",
            }
        )
    return entries


def calibration_entries(theme: dict[str, Any]) -> list[dict[str, Any]]:
    entries = stage_entries(theme) + lifecycle_entries(theme) + context_entries(theme)
    total = len(entries)
    for index, entry in enumerate(entries, start=1):
        entry["step"] = index
        entry["total"] = total
    return entries


def text_line(entry: dict[str, Any]) -> str:
    prefix = f"[{entry['step']:02d}/{entry['total']:02d}]"
    badge = entry.get("badge") or "-"
    parts = [
        prefix,
        f"{badge} {entry['name']}",
        f"kind={entry['kind']}",
        f"progress={entry.get('progress_bar', '')}",
        f"sprite={entry.get('sprite', '')}",
        f"color={color_text(entry['color'])}",
    ]
    if entry.get("trigger_count"):
        parts.append(f"count={entry['trigger_count']}")
    if entry.get("kind") == "context":
        parts.append(f"context overlay {entry.get('context_percent', 0)}%")
    return " | ".join(parts)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--theme", required=True, type=Path)
    parser.add_argument("--theme-name", required=True)
    parser.add_argument("--format", choices=("json", "json-lines", "text"), default="text")
    parser.add_argument("--limit", type=int, default=0)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    theme = json.loads(args.theme.read_text(encoding="utf-8"))
    entries = calibration_entries(theme)
    limited_entries = entries[: args.limit] if args.limit else entries
    if args.format == "json":
        print(
            json.dumps(
                {
                    "theme": args.theme_name,
                    "theme_file": str(args.theme),
                    "total": len(entries),
                    "entries": limited_entries,
                },
                indent=2,
            )
        )
    elif args.format == "json-lines":
        for entry in limited_entries:
            print(json.dumps(entry, separators=(",", ":")))
    else:
        for entry in limited_entries:
            print(text_line(entry))


if __name__ == "__main__":
    main()
