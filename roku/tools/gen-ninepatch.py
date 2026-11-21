#!/usr/bin/env python3
"""Writes the M12 step 10 9-patch images to roku/images/ (python3 -I roku/tools/gen-ninepatch.py).

Standard library only. Each image is a rounded rectangle drawn 4x supersampled, then the Roku/Android 9-patch
guide: a 1-px border, black (0,0,0,255) on the top row over the columns that stretch and on the left column over
the rows that stretch, transparent everywhere else. The stretch region is the middle (outside the corners and rim),
so the corners never scale; the rim's top-to-bottom gradient and the sheen sit in rows that Roku scales smoothly.

Colours and sizes come from roku/components/theme/Theme.bs (which maps them to MMTVL's DesignSystem/Theme.swift):
  panel             standard glass panel: fill, rim 3 px (top 0.70, middle 0.08, bottom 0.32), sheen 0.14 (Theme.swift glass*)
  panel_banner      banner role (D46): darker, more opaque fill, rim x0.4, no sheen (Theme.swift banner*)
  badge_banner      the behind-live badge (MMTVL's banner-role glass capsule): panel_banner's fill and rim, radius 24,
                    a capsule at timeshiftBadgeHeight 48
  panel_solid       menus over the busy guide (channel menu, group column): solidPanelFill (Theme.swift's Reduce
                    Transparency fill), the standard rim and sheen; at panel's 0.82 the guide's titles showed through
  settings_row      a one-line Settings row: settingsRowCapsuleFill plus the unfocused rim, radius 36 (a capsule at 72)
  settings_row_tall a two-line Settings row (title and detail): the same, radius 39 (Theme.swift settingsRowCornerRadius 40, on 3 px)
  settings_info_row a read-only Settings row: settingsInfoRowFill, no rim, radius 36; _tall: radius 39
  focus_row         white, radius 12: menu rows, the group column's focus (tint with focusBitmapBlendColor)
  focus_capsule     white, radius 36: one-line Settings rows (also the parent's opened row, tinted); _tall: radius 39
  guide_cell        TimeGrid programBackgroundBitmapUri: tileFill, radius 9, a 1/2-px transparent inset (3-px gaps)
  guide_focus       TimeGrid focusBitmapUri, variant A (chosen): white fill, radius 9, same inset
  guide_focus_ring  TimeGrid focusBitmapUri, variant B (not chosen): a 3-px white ring, radius 9, same inset
  bar               the banner's progress bar and track: white capsule, 9 high (tint with blendColor)

Plain gradients (not 9-patches; a Poster stretches them, loadDisplayMode scaleToFill):
  overlay_bottom    behind the player banner: clear at the top to liveOverlayBottom (black 0.85) at the bottom
  background        behind the guide, Settings and Import: background (0x1C1C1E) at the top to black at the bottom
  clear             fully transparent (step 12): TimeGrid's time bar and bottom overlay, which the frames don't draw
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


def make(name, size, radius, fill, inset=0, rim=None, rim_width=3, sheen=0.0, ring=None):
    """fill: (r, g, b, a) 0...255 or None; rim: (top, middle, bottom) white alphas; ring: width of a white ring.
    inset: a transparent margin, one number or (left, top, right, bottom)."""
    w, h = size
    il, it, ir, ib = inset if isinstance(inset, tuple) else (inset,) * 4
    x0, y0, x1, y1 = il, it, w - ir, h - ib
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

    # The corners stay fixed; the rim and ring are uniform along the straight edges, so they may stretch there. (Counting
    # the rim too would leave a 72-px capsule with no stretchable rows.)
    fixed = math.ceil(max(il, it, ir, ib) + radius)
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


def gradient(name, size, top, bottom):
    """A vertical gradient, (r, g, b, a) 0...255 at the top and bottom, with no 9-patch border."""
    w, h = size
    rows = []
    for y in range(h):
        t = y / (h - 1)
        px = [round(lerp(top[i], bottom[i], t)) for i in range(4)]
        rows.append(px * w)
    return name, w, h, rows


def main():
    images = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "images")
    specs = [
        # Theme.bs panelFill 0x262628D1, rim 0.70/0.08/0.32, sheen 0.14, radius 27 (glassCornerRadius), rim 3 (glassRimWidth).
        make("panel", (72, 72), 27, (0x26, 0x26, 0x28, 0xD1), rim=(0.70, 0.08, 0.32), sheen=0.14),
        # Theme.bs bannerPanelFill 0x0E0E10E0, rim x0.4 (bannerRimScale), no sheen (bannerSheenScale 0).
        make("panel_banner", (72, 72), 27, (0x0E, 0x0E, 0x10, 0xE0), rim=(0.28, 0.032, 0.128)),
        # The behind-live badge: panel_banner's fill and rim as a 48-px capsule (radius 24).
        make("badge_banner", (54, 54), 24, (0x0E, 0x0E, 0x10, 0xE0), rim=(0.28, 0.032, 0.128)),
        # Theme.bs solidPanelFill 0x1C1C1EEB with the standard rim and sheen.
        make("panel_solid", (72, 72), 27, (0x1C, 0x1C, 0x1E, 0xEB), rim=(0.70, 0.08, 0.32), sheen=0.14),
        # settingsRowCapsuleFill (white 0.075) with the unfocused rim, radius 36.
        # One-line rows are capsules at 72 (radius 36); two-line rows radius 39 (MMTVL 40, on the 3-px grid).
        make("settings_row", (76, 76), 36, (0xFF, 0xFF, 0xFF, 0x13), rim=(0.70, 0.08, 0.32)),
        make("settings_row_tall", (84, 84), 39, (0xFF, 0xFF, 0xFF, 0x13), rim=(0.70, 0.08, 0.32)),
        # settingsInfoRowFill (white 0.05), no rim.
        make("settings_info_row", (76, 76), 36, (0xFF, 0xFF, 0xFF, 0x0D)),
        make("settings_info_row_tall", (84, 84), 39, (0xFF, 0xFF, 0xFF, 0x0D)),
        make("focus_row", (30, 30), 12, (0xFF, 0xFF, 0xFF, 0xFF)),
        make("focus_capsule", (76, 76), 36, (0xFF, 0xFF, 0xFF, 0xFF)),
        make("focus_capsule_tall", (84, 84), 39, (0xFF, 0xFF, 0xFF, 0xFF)),
        # TimeGrid cells: radius 9 (guideCellCornerRadius) inside a transparent inset of 1 px left/top and 2 px
        # right/bottom, so neighbouring cells are 3 px apart (guideCellSpacing, on the 3-px grid).
        make("guide_cell", (28, 28), 9, (0xFF, 0xFF, 0xFF, 0x1F), inset=(1, 1, 2, 2)),
        make("guide_focus", (28, 28), 9, (0xFF, 0xFF, 0xFF, 0xFF), inset=(1, 1, 2, 2)),
        make("guide_focus_ring", (32, 32), 9, None, inset=(1, 1, 2, 2), ring=3),
        # liveBarHeight 9: radius 4 leaves one stretchable row (a capsule to the eye).
        make("bar", (12, 9), 4, (0xFF, 0xFF, 0xFF, 0xFF)),
    ]
    plain = [
        # Theme.bs liveOverlayBottom 0x000000D9.
        gradient("overlay_bottom", (4, 256), (0, 0, 0, 0), (0, 0, 0, 0xD9)),
        # Theme.bs background 0x1C1C1EFF to backgroundBottom 0x000000FF.
        gradient("background", (4, 256), (0x1C, 0x1C, 0x1E, 0xFF), (0, 0, 0, 0xFF)),
        gradient("clear", (4, 4), (0, 0, 0, 0), (0, 0, 0, 0)),
    ]
    for suffix, items in ((".9.png", specs), (".png", plain)):
        for name, w, h, rows in items:
            path = os.path.join(images, name + suffix)
            png(path, w, h, rows)
            print(f"{name}{suffix} {w}x{h} {os.path.getsize(path)} bytes")


if __name__ == "__main__":
    sys.exit(main())
