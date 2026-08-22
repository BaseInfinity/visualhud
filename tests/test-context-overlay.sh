#!/bin/bash
# Regression contract for source-backed context alert character overlays.

set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/visualhud-context-overlay.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    [ "$expected" = "$actual" ] || fail "$label (expected '$expected', got '$actual')"
    printf 'PASS: %s\n' "$label"
}

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    [[ "$haystack" == *"$needle"* ]] || fail "$label (expected '$needle')"
    printf 'PASS: %s\n' "$label"
}

wait_for_lines() {
    local file="$1" expected="$2" attempt=0 count=0
    while :; do
        count=$(wc -l < "$file" 2>/dev/null | tr -d ' ' || printf 0)
        [ "$count" -ge "$expected" ] && return 0
        attempt=$((attempt + 1))
        [ "$attempt" -lt 300 ] || fail "timed out waiting for $expected background calls"
        sleep 0.01
    done
}

echo "=== Test Suite: context character overlay ==="

COMPOSITOR="$ROOT_DIR/scripts/visualhud_context_overlay.py"
COMPOSITE="$TMP_ROOT/composite.png"

python3 - "$COMPOSITOR" "$TMP_ROOT" <<'PY'
import binascii
import importlib.util
from pathlib import Path
import struct
import sys
import zlib

module_path, fixture_root = sys.argv[1:]
spec = importlib.util.spec_from_file_location("visualhud_context_overlay", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
fixture_root = Path(fixture_root)


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", binascii.crc32(kind + data) & 0xFFFFFFFF)


def write_png(name, color_type, rows, bit_depth=8, palette=b"", transparency=b"", interlace=0):
    height = len(rows)
    width = len(rows[0])
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color_type]

    def scanline(points):
        samples = [component for point in points for component in point[:channels]]
        if bit_depth == 16:
            encoded = b"".join(struct.pack(">H", sample) for sample in samples)
        elif bit_depth == 8:
            encoded = bytes(samples)
        else:
            encoded = bytearray((len(samples) * bit_depth + 7) // 8)
            for index, sample in enumerate(samples):
                shift = 8 - bit_depth - ((index * bit_depth) % 8)
                encoded[(index * bit_depth) // 8] |= sample << shift
            encoded = bytes(encoded)
        return b"\x00" + encoded

    if interlace:
        passes = ((0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4),
                  (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2))
        raw = bytearray()
        for start_x, start_y, step_x, step_y in passes:
            for y in range(start_y, height, step_y):
                points = [rows[y][x] for x in range(start_x, width, step_x)]
                if points:
                    raw.extend(scanline(points))
    else:
        raw = b"".join(scanline(row) for row in rows)

    data = b"\x89PNG\r\n\x1a\n"
    data += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, bit_depth, color_type, 0, 0, interlace))
    if palette:
        data += chunk(b"PLTE", palette)
    if transparency:
        data += chunk(b"tRNS", transparency)
    data += chunk(b"IDAT", zlib.compress(bytes(raw)))
    data += chunk(b"IEND", b"")
    path = fixture_root / name
    path.write_bytes(data)
    return path


oversized = fixture_root / "oversized.png"
oversized.write_bytes(
    b"\x89PNG\r\n\x1a\n"
    + chunk(b"IHDR", struct.pack(">IIBBBBB", 4097, 1, 8, 6, 0, 0, 0))
    + chunk(b"IDAT", zlib.compress(b"\x00"))
    + chunk(b"IEND", b"")
)
try:
    module.read_png_rgba(oversized)
except ValueError as error:
    assert "context overlay limit" in str(error), error
else:
    raise AssertionError("oversized PNG was not rejected before decoding")

compressed_bomb = fixture_root / "compressed-bomb.png"
compressed_bomb.write_bytes(
    b"\x89PNG\r\n\x1a\n"
    + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
    + chunk(b"IDAT", zlib.compress(b"\x00" * 1_000_000))
    + chunk(b"IEND", b"")
)
try:
    module.read_png_rgba(compressed_bomb)
except ValueError as error:
    assert "decompressed data exceeds context overlay limit" in str(error), error
else:
    raise AssertionError("overlong decompressed stream was not bounded")


fixtures = [
    (write_png("gray-1.png", 0, [[(0,), (1,), (0,), (1,)]], bit_depth=1),
     bytes((0, 0, 0, 255, 255, 255, 255, 255) * 2)),
    (write_png("gray-4.png", 0, [[(0,), (5,), (10,), (15,)]], bit_depth=4),
     bytes(component for gray in (0, 85, 170, 255) for component in (gray, gray, gray, 255))),
    (write_png("gray-16.png", 0, [[(0,), (65535,)]], bit_depth=16),
     bytes((0, 0, 0, 255, 255, 255, 255, 255))),
    (write_png("rgb.png", 2, [[(9, 19, 29), (39, 49, 59)]]), bytes((9, 19, 29, 255, 39, 49, 59, 255))),
    (write_png("rgb-16.png", 2, [[(65535, 32896, 0)]], bit_depth=16), bytes((255, 128, 0, 255))),
    (write_png("palette.png", 3, [[(0,), (1,)]], bit_depth=1,
               palette=bytes((10, 20, 30, 40, 50, 60)), transparency=bytes((0, 200))),
     bytes((10, 20, 30, 0, 40, 50, 60, 200))),
    (write_png("gray-alpha.png", 4, [[(70, 80), (90, 100)]]), bytes((70, 70, 70, 80, 90, 90, 90, 100))),
    (write_png("gray-alpha-16.png", 4, [[(65535, 32896)]], bit_depth=16), bytes((255, 255, 255, 128))),
    (write_png("rgba-16.png", 6, [[(65535, 0, 32896, 16448)]], bit_depth=16), bytes((255, 0, 128, 64))),
    (write_png("adam7-rgba.png", 6,
               [[(x * 20, y * 30, x + y, 255) for x in range(5)] for y in range(5)], interlace=1),
     bytes(component for y in range(5) for x in range(5) for component in (x * 20, y * 30, x + y, 255))),
]

for path, expected in fixtures:
    width, height, actual = module.read_png_rgba(path)
    assert width * height * 4 == len(expected), path.name
    assert actual == expected, f"decoded pixels differ for {path.name}"

original_read_png = module.read_png_rgba
module.read_png_rgba = lambda path: ((4096, 1024, b"") if str(path) == "wide" else (1024, 4096, b""))
try:
    module.compose("wide", "tall", "#ffe1eb", fixture_root / "oversized-composite.png")
except ValueError as error:
    assert "Combined PNG dimensions exceed context overlay limit" in str(error), error
else:
    raise AssertionError("oversized combined canvas was allocated")
finally:
    module.read_png_rgba = original_read_png
PY
printf 'PASS: compositor bounds memory and decodes grayscale, RGB, palette, alpha, and Adam7 PNG assets\n'

python3 "$COMPOSITOR" \
    "$ROOT_DIR/themes/pokemon/sprites/raichu.png" \
    "$ROOT_DIR/themes/pokemon/sprites/blissey.png" \
    '#ffe1eb' \
    "$COMPOSITE"

python3 - "$COMPOSITOR" "$ROOT_DIR/themes/pokemon/sprites/raichu.png" \
    "$ROOT_DIR/themes/pokemon/sprites/blissey.png" "$COMPOSITE" <<'PY'
import importlib.util
import sys

module_path, primary_path, context_path, composite_path = sys.argv[1:]
spec = importlib.util.spec_from_file_location("visualhud_context_overlay", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

primary_width, primary_height, primary = module.read_png_rgba(primary_path)
context_width, context_height, context = module.read_png_rgba(context_path)
width, height, composite = module.read_png_rgba(composite_path)

assert (width, height) == (primary_width + context_width, max(primary_height, context_height))
for y in range(primary_height):
    source = primary[y * primary_width * 4:(y + 1) * primary_width * 4]
    rendered = composite[y * width * 4:y * width * 4 + primary_width * 4]
    assert rendered == source, f"primary pixels changed on row {y}"

right = bytearray()
for y in range(height):
    start = (y * width + primary_width) * 4
    right.extend(composite[start:start + context_width * 4])
assert any(context[index + 3] and tuple(right[index:index + 3]) != (255, 225, 235)
           for index in range(0, len(context), 4)), "context character pixels are absent"
PY
printf 'PASS: deterministic composite preserves the journey pixels and renders Blissey\n'

first_hash=$(shasum -a 256 "$COMPOSITE" | awk '{print $1}')
python3 "$COMPOSITOR" \
    "$ROOT_DIR/themes/pokemon/sprites/raichu.png" \
    "$ROOT_DIR/themes/pokemon/sprites/blissey.png" \
    '#ffe1eb' \
    "$COMPOSITE"
assert_eq "Repeated composition is byte deterministic" \
    "$first_hash" \
    "$(shasum -a 256 "$COMPOSITE" | awk '{print $1}')"

state_b64=$(node "$ROOT_DIR/scripts/visualhud-json.js" wezterm-state \
    title context-title primary.png '#2d184c' '#0d0716' 3 journey 50 D Donatello project \
    blissey.png '#ffe1eb')
state_json=$(printf '%s' "$state_b64" | base64 --decode 2>/dev/null || printf '%s' "$state_b64" | base64 -D)
assert_eq "WezTerm payload preserves the primary sprite" "primary.png" "$(printf '%s' "$state_json" | jq -r '.sprite_path')"
assert_eq "WezTerm payload carries a distinct context sprite" "blissey.png" "$(printf '%s' "$state_json" | jq -r '.context_sprite_path')"
assert_eq "WezTerm payload carries the scoped context color" "#ffe1eb" "$(printf '%s' "$state_json" | jq -r '.context_color')"

lua_source=$(cat "$ROOT_DIR/wezterm/visualhud.lua")
assert_contains "WezTerm renderer reads the context sprite independently" "state.context_sprite_path" "$lua_source"
assert_contains "WezTerm renderer reads the context panel color independently" "state.context_color" "$lua_source"

MOCK_SET_BG="$TMP_ROOT/set_bg.py"
SET_BG_LOG="$TMP_ROOT/set-bg.jsonl"
cat > "$MOCK_SET_BG" <<'PY'
import json
import os
import sys

with open(os.environ["VISUALHUD_SET_BG_LOG"], "a", encoding="utf-8") as handle:
    handle.write(json.dumps(sys.argv[1:]) + "\n")
PY

STATE_DIR="$TMP_ROOT/state"
TTY_LOG="$TMP_ROOT/tty.log"
mkdir -p "$STATE_DIR"
: > "$SET_BG_LOG"
: > "$TTY_LOG"
SESSION_ID="w0t0p0:CONTEXT_OVERLAY"

run_hook() {
    printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Read","session_id":"context-overlay"}' \
        | ITERM_SESSION_ID="$SESSION_ID" VISUALHUD_RENDERER=iterm2 VISUALHUD_ACTIVITY_MODE=legacy \
            VISUALHUD_THEME=pokemon VISUALHUD_THEMES_DIR="$ROOT_DIR/themes" \
            VISUALHUD_STATE_DIR="$STATE_DIR" VISUALHUD_TTY=/dev/null VISUALHUD_BG=on \
            VISUALHUD_SET_BG="$MOCK_SET_BG" VISUALHUD_SET_BG_LOG="$SET_BG_LOG" \
            VISUALHUD_CONTEXT_USED_PERCENT="$1" VISUALHUD_REAPPLY_DELAY=0 \
            bash "$ROOT_DIR/engine.sh"
}

run_hook 85
wait_for_lines "$SET_BG_LOG" 1
critical_call=$(sed -n '1p' "$SET_BG_LOG")
assert_eq "Critical iTerm frame keeps the active journey image as the primary input" \
    "charmander.png" "$(printf '%s' "$critical_call" | jq -r '.[0] | split("/") | last')"
assert_eq "Critical iTerm frame supplies the Blissey sidecar" \
    "blissey.png" "$(printf '%s' "$critical_call" | jq -r '.[2] | split("/") | last')"
assert_eq "Critical iTerm frame supplies Pokemon Center pink-white" \
    "#ffe1eb" "$(printf '%s' "$critical_call" | jq -r '.[3]')"

run_hook 20
wait_for_lines "$SET_BG_LOG" 2
normal_call=$(sed -n '2p' "$SET_BG_LOG")
assert_eq "De-escalation restores the same primary image" \
    "charmander.png" "$(printf '%s' "$normal_call" | jq -r '.[0] | split("/") | last')"
assert_eq "De-escalation removes the context image" "" "$(printf '%s' "$normal_call" | jq -r '.[2]')"
assert_eq "De-escalation removes the context color" "" "$(printf '%s' "$normal_call" | jq -r '.[3]')"

printf 'All context character overlay tests passed.\n'
