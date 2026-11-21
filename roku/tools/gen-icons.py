#!/usr/bin/env python3
"""Writes the M12 icons to roku/images/ (python3 -I roku/tools/gen-icons.py). The sibling of gen-ninepatch.py.

Standard library only. Each icon is a white glyph on transparent, drawn 4x supersampled from stroked shapes on a
24-unit grid (the outline-icon convention the design file's icons use: stroke 2, round caps and joins) and scaled
to its size on the 1920 x 1080 canvas. A Poster tints it with blendColor (Theme.bs colours).

  icon_warning   72 x 72 (Theme.bs layout errorPanelSymbolSize): the error panel's warning sign, a rounded
                 triangle with an exclamation mark; tinted secondaryText (frame "Error panel", LsUbW)
"""
import math
import os
import struct
import sys
import zlib

SS = 4  # supersampling per axis


def png(path, width, height, rgba_rows):
    raw = b"".join(b"\x00" + bytes(row) for row in rgba_rows)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(data)


def segment_distance(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    length2 = dx * dx + dy * dy
    t = 0.0 if length2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / length2))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def triangle_signed_distance(px, py, vertices):
    """Distance to the triangle's outline, negative inside."""
    distance = min(segment_distance(px, py, *vertices[i], *vertices[(i + 1) % 3]) for i in range(3))
    sign = None
    inside = True
    for i in range(3):
        (ax, ay), (bx, by) = vertices[i], vertices[(i + 1) % 3]
        cross = (bx - ax) * (py - ay) - (by - ay) * (px - ax)
        side = cross >= 0
        if sign is None:
            sign = side
        elif side != sign:
            inside = False
    return -distance if inside else distance


def warning(units_x, units_y):
    """True where the 24-unit point is inked: a triangle outline with radius-1.6 corners (its centre line runs from
    y 3.4 at the apex to y 21 at the base), stroke 2; the mark's line from y 9 to 13 and its dot at y 17."""
    half = 1.0
    corner = 1.6
    inner = [(12.0, 5.0), (20.4, 19.4), (3.6, 19.4)]
    outline = triangle_signed_distance(units_x, units_y, inner) - corner
    if abs(outline) <= half:
        return True
    if segment_distance(units_x, units_y, 12.0, 9.0, 12.0, 13.0) <= half:
        return True
    return math.hypot(units_x - 12.0, units_y - 17.0) <= half


def icon(name, size, shape):
    rows = []
    scale = 24.0 / size
    for py in range(size):
        row = []
        for px in range(size):
            hits = 0
            for sy in range(SS):
                for sx in range(SS):
                    if shape((px + (sx + 0.5) / SS) * scale, (py + (sy + 0.5) / SS) * scale):
                        hits += 1
            row += [255, 255, 255, round(255 * hits / (SS * SS))]
        rows.append(row)
    return name, size, size, rows


def main():
    images = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "images")
    for name, w, h, rows in [icon("icon_warning", 72, warning)]:
        path = os.path.join(images, name + ".png")
        png(path, w, h, rows)
        print(f"{name}.png {w}x{h} {os.path.getsize(path)} bytes")


if __name__ == "__main__":
    sys.exit(main())
