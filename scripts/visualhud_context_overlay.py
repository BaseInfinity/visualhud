#!/usr/bin/env python3
"""Build a deterministic side-by-side RGBA PNG without runtime dependencies."""

import binascii
import os
from pathlib import Path
import struct
import sys
import tempfile
import zlib


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
ADAM7_PASSES = (
    (0, 0, 8, 8),
    (4, 0, 8, 8),
    (0, 4, 4, 8),
    (2, 0, 4, 4),
    (0, 2, 2, 4),
    (1, 0, 2, 2),
    (0, 1, 1, 2),
)
COLOR_CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}
VALID_BIT_DEPTHS = {
    0: {1, 2, 4, 8, 16},
    2: {8, 16},
    3: {1, 2, 4, 8},
    4: {8, 16},
    6: {8, 16},
}
MAX_PNG_DIMENSION = 4096
MAX_PNG_PIXELS = 4_194_304
MAX_COMPOSITE_PIXELS = 8_388_608
MAX_PNG_FILE_BYTES = 67_108_864


def _paeth(left: int, above: int, upper_left: int) -> int:
    estimate = left + above - upper_left
    left_distance = abs(estimate - left)
    above_distance = abs(estimate - above)
    upper_left_distance = abs(estimate - upper_left)
    if left_distance <= above_distance and left_distance <= upper_left_distance:
        return left
    if above_distance <= upper_left_distance:
        return above
    return upper_left


def _pass_size(total, start, step):
    if total <= start:
        return 0
    return (total - start + step - 1) // step


def _unfilter_scanline(scanline, previous, bytes_per_pixel, filter_type, path):
    decoded = bytearray(len(scanline))
    for index, value in enumerate(scanline):
        left = decoded[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
        above = previous[index] if previous else 0
        upper_left = previous[index - bytes_per_pixel] if previous and index >= bytes_per_pixel else 0
        if filter_type == 0:
            result = value
        elif filter_type == 1:
            result = value + left
        elif filter_type == 2:
            result = value + above
        elif filter_type == 3:
            result = value + ((left + above) // 2)
        elif filter_type == 4:
            result = value + _paeth(left, above, upper_left)
        else:
            raise ValueError(f"Unsupported PNG filter {filter_type}: {path}")
        decoded[index] = result & 0xFF
    return bytes(decoded)


def _samples_from_scanline(scanline, sample_count, bit_depth):
    if bit_depth == 8:
        return list(scanline[:sample_count])
    if bit_depth == 16:
        return [struct.unpack(">H", scanline[index:index + 2])[0]
                for index in range(0, sample_count * 2, 2)]

    mask = (1 << bit_depth) - 1
    samples = []
    for index in range(sample_count):
        bit_offset = index * bit_depth
        byte = scanline[bit_offset // 8]
        shift = 8 - bit_depth - (bit_offset % 8)
        samples.append((byte >> shift) & mask)
    return samples


def _scale_sample(sample, bit_depth):
    maximum = (1 << bit_depth) - 1
    return (sample * 255 + maximum // 2) // maximum


def _expected_raw_size(width, height, color_type, bit_depth, interlace):
    bits_per_pixel = COLOR_CHANNELS[color_type] * bit_depth
    passes = ADAM7_PASSES if interlace else ((0, 0, 1, 1),)
    total = 0
    for start_x, start_y, step_x, step_y in passes:
        pass_width = _pass_size(width, start_x, step_x)
        pass_height = _pass_size(height, start_y, step_y)
        if pass_width and pass_height:
            total += pass_height * (((pass_width * bits_per_pixel + 7) // 8) + 1)
    return total


def _bounded_decompress(compressed, expected_size, path):
    decoder = zlib.decompressobj()
    raw = decoder.decompress(bytes(compressed), expected_size + 1)
    if len(raw) > expected_size or decoder.unconsumed_tail:
        raise ValueError(f"PNG decompressed data exceeds context overlay limit: {path}")
    raw += decoder.flush(expected_size + 1 - len(raw))
    if len(raw) != expected_size or not decoder.eof or decoder.unused_data:
        raise ValueError(f"Unexpected PNG scanline size: {path}")
    return raw


def _rgba_pixel(samples, color_type, bit_depth, palette, transparency, path):
    if color_type == 0:
        gray = _scale_sample(samples[0], bit_depth)
        transparent_gray = struct.unpack(">H", transparency)[0] if len(transparency) == 2 else None
        return gray, gray, gray, 0 if samples[0] == transparent_gray else 255
    if color_type == 2:
        transparent_rgb = struct.unpack(">HHH", transparency) if len(transparency) == 6 else None
        rgb = tuple(_scale_sample(sample, bit_depth) for sample in samples[:3])
        return (*rgb, 0 if tuple(samples[:3]) == transparent_rgb else 255)
    if color_type == 3:
        index = samples[0]
        palette_offset = index * 3
        if palette_offset + 3 > len(palette):
            raise ValueError(f"PNG palette index is out of range: {path}")
        alpha = transparency[index] if index < len(transparency) else 255
        return (*palette[palette_offset:palette_offset + 3], alpha)
    if color_type == 4:
        gray = _scale_sample(samples[0], bit_depth)
        return gray, gray, gray, _scale_sample(samples[1], bit_depth)
    return tuple(_scale_sample(sample, bit_depth) for sample in samples[:4])


def _decode_pass(raw, raw_offset, width, height, start_x, start_y, step_x, step_y,
                 color_type, bit_depth, palette, transparency, pixels, image_width, path):
    channels = COLOR_CHANNELS[color_type]
    bits_per_pixel = channels * bit_depth
    row_bytes = (width * bits_per_pixel + 7) // 8
    bytes_per_pixel = max(1, (bits_per_pixel + 7) // 8)
    previous = b""

    for pass_y in range(height):
        if raw_offset + row_bytes + 1 > len(raw):
            raise ValueError(f"Unexpected PNG scanline size: {path}")
        filter_type = raw[raw_offset]
        raw_offset += 1
        scanline = _unfilter_scanline(
            raw[raw_offset:raw_offset + row_bytes], previous, bytes_per_pixel, filter_type, path
        )
        raw_offset += row_bytes
        previous = scanline
        samples = _samples_from_scanline(scanline, width * channels, bit_depth)
        for pass_x in range(width):
            source = pass_x * channels
            rgba = _rgba_pixel(
                samples[source:source + channels], color_type, bit_depth, palette, transparency, path
            )
            x = start_x + pass_x * step_x
            y = start_y + pass_y * step_y
            destination = (y * image_width + x) * 4
            pixels[destination:destination + 4] = bytes(rgba)
    return raw_offset


def read_png_rgba(path):
    """Decode a standards-compliant PNG into 8-bit row-major RGBA pixels."""

    source = Path(path)
    if source.stat().st_size > MAX_PNG_FILE_BYTES:
        raise ValueError(f"PNG file size exceeds context overlay limit: {path}")
    data = source.read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError(f"Not a PNG: {path}")

    offset = len(PNG_SIGNATURE)
    width = height = bit_depth = color_type = interlace = None
    palette = b""
    transparency = b""
    compressed = bytearray()
    while offset < len(data):
        if offset + 12 > len(data):
            raise ValueError(f"Truncated PNG chunk: {path}")
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        if offset + 12 + length > len(data):
            raise ValueError(f"Truncated PNG chunk data: {path}")
        chunk_type = data[offset + 4:offset + 8]
        chunk_data = data[offset + 8:offset + 8 + length]
        expected_crc = struct.unpack(">I", data[offset + 8 + length:offset + 12 + length])[0]
        actual_crc = binascii.crc32(chunk_type + chunk_data) & 0xFFFFFFFF
        if actual_crc != expected_crc:
            raise ValueError(f"PNG chunk CRC mismatch: {path}")
        offset += 12 + length

        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack(
                ">IIBBBBB", chunk_data
            )
            if width == 0 or height == 0:
                raise ValueError(f"PNG dimensions must be positive: {path}")
            if (width > MAX_PNG_DIMENSION or height > MAX_PNG_DIMENSION
                    or width * height > MAX_PNG_PIXELS):
                raise ValueError(f"PNG dimensions exceed context overlay limit: {path}")
            if color_type not in VALID_BIT_DEPTHS or bit_depth not in VALID_BIT_DEPTHS[color_type]:
                raise ValueError(f"Unsupported PNG color type or bit depth: {path}")
            if compression != 0 or filtering != 0 or interlace not in (0, 1):
                raise ValueError(f"Unsupported PNG encoding: {path}")
        elif chunk_type == b"PLTE":
            palette = bytes(chunk_data)
        elif chunk_type == b"tRNS":
            transparency = bytes(chunk_data)
        elif chunk_type == b"IDAT":
            compressed.extend(chunk_data)
        elif chunk_type == b"IEND":
            break

    if width is None or height is None or bit_depth is None or color_type is None:
        raise ValueError(f"PNG has no IHDR: {path}")
    if color_type == 3 and (not palette or len(palette) % 3 != 0 or len(palette) > 768):
        raise ValueError(f"Indexed PNG has an invalid palette: {path}")

    expected_raw_size = _expected_raw_size(width, height, color_type, bit_depth, interlace)
    raw = _bounded_decompress(compressed, expected_raw_size, path)
    pixels = bytearray(width * height * 4)
    raw_offset = 0
    passes = ADAM7_PASSES if interlace else ((0, 0, 1, 1),)
    for start_x, start_y, step_x, step_y in passes:
        pass_width = _pass_size(width, start_x, step_x)
        pass_height = _pass_size(height, start_y, step_y)
        if pass_width == 0 or pass_height == 0:
            continue
        raw_offset = _decode_pass(
            raw, raw_offset, pass_width, pass_height, start_x, start_y, step_x, step_y,
            color_type, bit_depth, palette, transparency, pixels, width, path
        )
    if raw_offset != len(raw):
        raise ValueError(f"Unexpected PNG scanline size: {path}")

    return width, height, bytes(pixels)


def _chunk(chunk_type: bytes, data: bytes) -> bytes:
    checksum = binascii.crc32(chunk_type + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + chunk_type + data + struct.pack(">I", checksum)


def write_png_rgba(path, width, height, pixels):
    """Atomically write deterministic non-interlaced 8-bit RGBA PNG bytes."""

    stride = width * 4
    if len(pixels) != height * stride:
        raise ValueError("RGBA pixel length does not match dimensions")
    scanlines = b"".join(b"\x00" + pixels[row * stride:(row + 1) * stride] for row in range(height))
    png = PNG_SIGNATURE
    png += _chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += _chunk(b"IDAT", zlib.compress(scanlines, level=9))
    png += _chunk(b"IEND", b"")

    destination = Path(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=destination.parent, prefix=f".{destination.name}.", delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(png)
    try:
        os.replace(temporary, destination)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def compose(primary_path, context_path, color_hex, output_path):
    primary_width, primary_height, primary = read_png_rgba(primary_path)
    context_width, context_height, context = read_png_rgba(context_path)
    color_text = color_hex[1:] if color_hex.startswith("#") else color_hex
    if len(color_text) != 6:
        raise ValueError("Context color must be #RRGGBB")
    panel_color = tuple(int(color_text[index:index + 2], 16) for index in (0, 2, 4))

    width = primary_width + context_width
    height = max(primary_height, context_height)
    if width * height > MAX_COMPOSITE_PIXELS:
        raise ValueError("Combined PNG dimensions exceed context overlay limit")
    pixels = bytearray(width * height * 4)
    for y in range(height):
        if y < primary_height:
            source_start = y * primary_width * 4
            destination_start = y * width * 4
            pixels[destination_start:destination_start + primary_width * 4] = primary[
                source_start:source_start + primary_width * 4
            ]
        for x in range(context_width):
            destination = (y * width + primary_width + x) * 4
            pixels[destination:destination + 4] = bytes((*panel_color, 255))
            if y >= context_height:
                continue
            source = (y * context_width + x) * 4
            alpha = context[source + 3]
            for channel in range(3):
                foreground = context[source + channel]
                background = panel_color[channel]
                pixels[destination + channel] = (foreground * alpha + background * (255 - alpha) + 127) // 255

    write_png_rgba(output_path, width, height, bytes(pixels))


def main(argv):
    if len(argv) != 5:
        print("usage: visualhud_context_overlay.py PRIMARY CONTEXT COLOR OUTPUT", file=sys.stderr)
        return 2
    compose(argv[1], argv[2], argv[3], argv[4])
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
