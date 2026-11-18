#!/usr/bin/env python3
"""Writes the M12 step 10 9-patch images to roku/images/ (python3 -I roku/tools/gen-ninepatch.py).

Standard library only. Each image is a rounded rectangle drawn 4x supersampled, then the Roku/Android 9-patch
guide: a 1-px border, black (0,0,0,255) on the top row over the columns that stretch and on the left column over
the rows that stretch, transparent everywhere else. The stretch region is the middle (outside the corners and rim),
so the corners never scale; the rim's top-to-bottom gradient and the sheen sit in rows that Roku scales smoothly.

Colours and sizes come from roku/components/theme/Theme.bs (which maps them to MMTVL's DesignSystem/Theme.swift):
  panel             standard glass panel: fill, rim (top 0.70, middle 0.08, bottom 0.32), sheen 0.14 (Theme.swift glass*)
  panel_banner      banner role (D46): darker, more opaque fill, rim x0.4, no sheen (Theme.swift banner*)
  settings_row      a Settings row capsule: settingsRowCapsuleFill plus the unfocused rim
  focus_row         white, radius 12: menu rows, the group column's focus (tint with focusBitmapBlendColor)
  focus_capsule     white, radius 32: Settings rows and list focus
  guide_cell        TimeGrid programBackgroundBitmapUri: tileFill, radius 10, a 2-px transparent inset (4-px gaps)
  guide_focus       TimeGrid focusBitmapUri, variant A: white fill, radius 10, same inset
  guide_focus_ring  TimeGrid focusBitmapUri, variant B: a 4-px white ring, radius 10, same inset
  bar               the banner's progress bar and track: white capsule, radius 4 (tint with blendColor)
"""
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


def coverage(px, py, x0, y0, x1, y1, r):
    """Fraction of pixel (px, py) inside the rounded rect [x0, x1) x [y0, y1) with corner radius r."""
    inside = 0
    for sy in range(SS):
        for sx in range(SS):
            x = px + (sx + 0.5) / SS
            y = py + (sy + 0.5) / SS
            if x < x0 or x >= x1 or y < y0 or y >= y1:
                continue
            cx = min(max(x, x0 + r), x1 - r)
            cy = min(max(y, y0 + r), y1 - r)
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                inside += 1
    return inside / (SS * SS)


def over(dst, src):
    """Source-over compositing of straight-alpha (r, g, b, a) floats 0...1."""
    sr, sg, sb, sa = src
    dr, dg, db, da = dst
    a = sa + da * (1 - sa)
    if a == 0:
        return (0.0, 0.0, 0.0, 0.0)
    mix = lambda s, d: (s * sa + d * da * (1 - sa)) / a
    return (mix(sr, dr), mix(sg, dg), mix(sb, db), a)


def lerp(a, b, t):
    return a + (b - a) * t


def rim_alpha(t, top, middle, bottom):
    """Theme.swift's rim gradient: top at t=0, middle at t=0.5, bottom at t=1."""
    return lerp(top, middle, t * 2) if t < 0.5 else lerp(middle, bottom, (t - 0.5) * 2)


def make(name, size, radius, fill, inset=0, rim=None, rim_width=2, sheen=0.0, ring=None):
    """fill: (r, g, b, a) 0...255 or None; rim: (top, middle, bottom) white alphas; ring: width of a white ring."""
    w, h = size
    x0, y0, x1, y1 = inset, inset, w - inset, h - inset
    pixels = []
    for py in range(h):
        row = []
        t = (py + 0.5 - y0) / max(1, (y1 - y0))
        for px in range(w):
            outer = coverage(px, py, x0, y0, x1, y1, radius)
            colour = (0.0, 0.0, 0.0, 0.0)
            if outer > 0:
                if fill is not None:
                    colour = over(colour, (fill[0] / 255, fill[1] / 255, fill[2] / 255, fill[3] / 255 * outer))
                if sheen > 0 and t < 0.5:
                    colour = over(colour, (1.0, 1.0, 1.0, sheen * (1 - t * 2) * outer))
                band = ring if ring is not None else (rim_width if rim is not None else 0)
                if band:
                    inner = coverage(px, py, x0 + band, y0 + band, x1 - band, y1 - band, max(0, radius - band))
                    stroke = max(0.0, outer - inner)
                    alpha = 1.0 if ring is not None else rim_alpha(min(max(t, 0), 1), *rim)
                    colour = over(colour, (1.0, 1.0, 1.0, alpha * stroke))
            row.append(colour)
        pixels.append(row)

    fixed = inset + radius + max(rim_width if rim else 0, ring or 0)
    bw, bh = w + 2, h + 2
    rows = []
    for by in range(bh):
        out = []
        for bx in range(bw):
            if by == 0 or bx == 0:
                # Top guide: stretch columns; left guide: stretch rows. Corners of the border stay clear.
                if by == 0 and bx not in (0, bw - 1) and fixed <= bx - 1 < w - fixed:
                    out += [0, 0, 0, 255]
                elif bx == 0 and by not in (0, bh - 1) and fixed <= by - 1 < h - fixed:
                    out += [0, 0, 0, 255]
                else:
                    out += [0, 0, 0, 0]
            elif by == bh - 1 or bx == bw - 1:
                out += [0, 0, 0, 0]
            else:
                r, g, b, a = pixels[by - 1][bx - 1]
                out += [round(r * 255), round(g * 255), round(b * 255), round(a * 255)]
        rows.append(out)
    return name, bw, bh, rows


def main():
    images = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "images")
    specs = [
        # Theme.bs panelFill 0x262628D1, rim 0.70/0.08/0.32, sheen 0.14, radius 28 (glassCornerRadius).
        make("panel", (72, 72), 28, (0x26, 0x26, 0x28, 0xD1), rim=(0.70, 0.08, 0.32), sheen=0.14),
        # Theme.bs bannerPanelFill 0x0E0E10E0, rim x0.4 (bannerRimScale), no sheen (bannerSheenScale 0).
        make("panel_banner", (72, 72), 28, (0x0E, 0x0E, 0x10, 0xE0), rim=(0.28, 0.032, 0.128)),
        # settingsRowCapsuleFill (white 0.075) with the unfocused rim, radius 32.
        make("settings_row", (72, 72), 32, (0xFF, 0xFF, 0xFF, 0x13), rim=(0.70, 0.08, 0.32)),
        make("focus_row", (30, 30), 12, (0xFF, 0xFF, 0xFF, 0xFF)),
        make("focus_capsule", (72, 72), 32, (0xFF, 0xFF, 0xFF, 0xFF)),
        # TimeGrid cells: radius 10 (guideCellCornerRadius) inside a 2-px transparent inset.
        make("guide_cell", (28, 28), 10, (0xFF, 0xFF, 0xFF, 0x1F), inset=2),
        make("guide_focus", (28, 28), 10, (0xFF, 0xFF, 0xFF, 0xFF), inset=2),
        make("guide_focus_ring", (32, 32), 10, None, inset=2, ring=4),
        make("bar", (12, 10), 4, (0xFF, 0xFF, 0xFF, 0xFF)),
    ]
    for name, w, h, rows in specs:
        path = os.path.join(images, name + ".9.png")
        png(path, w, h, rows)
        print(f"{name}.9.png {w}x{h} {os.path.getsize(path)} bytes")


if __name__ == "__main__":
    sys.exit(main())
