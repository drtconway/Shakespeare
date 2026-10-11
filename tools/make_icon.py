#!/usr/bin/env python3
"""Draw the harp icon used by the minimap button.

Usage:
    python3 tools/make_icon.py [preview.png]

Writes media/harp.tga (64x64, 32-bit with alpha, which WoW loads directly)
and optionally a PNG preview.
"""

import math
import struct
import sys
import zlib
from pathlib import Path

SIZE = 64
SS = 4  # supersampling factor for anti-aliasing
MIRROR = False  # True puts the pillar on the right

ROOT = Path(__file__).resolve().parent.parent

GOLD = (226, 172, 48)
DARK = (58, 34, 12)
STRING = (245, 236, 210)


def bezier(p0, p1, p2, p3, n=24):
    pts = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        x = u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1]
        pts.append((x, y))
    return pts


def segments(points):
    return list(zip(points, points[1:]))


def dist_to_segment(px, py, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def near(px, py, segs, width):
    return any(dist_to_segment(px, py, a, b) <= width / 2 for a, b in segs)


# The harp: a pillar on the left, a curved neck across the top, and a
# soundbox running diagonally back down to the foot, with strings between.
neck = bezier((15, 12), (26, 1), (38, 24), (52, 15))
soundbox = [(52, 15), (19, 56)]
pillar = bezier((16, 57), (11, 42), (12, 24), (15, 12), 12)
foot = [(13, 58), (24, 58)]


def neck_y(x):
    return min((p for p in neck), key=lambda p: abs(p[0] - x))[1]


def soundbox_y(x):
    (x0, y0), (x1, y1) = soundbox
    return y0 + (x - x0) * (y1 - y0) / (x1 - x0)


strings = [[(x, neck_y(x) + 1), (x, soundbox_y(x) - 1)] for x in range(20, 50, 4)]

frame = segments(neck) + segments(soundbox) + segments(pillar) + segments(foot)
string_segs = [s for st in strings for s in segments(st)]

LAYERS = [  # (segments, width, colour), drawn in order
    (frame, 7.5, DARK),
    (frame, 4.5, GOLD),
    (string_segs, 1.4, STRING),
]


def render(dx=0.0, dy=0.0):
    """Render the harp, optionally mirrored, shifted by (dx, dy)."""
    pixels = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            r = g = b = a = 0.0
            for sy in range(SS):
                for sx in range(SS):
                    px = x + (sx + 0.5) / SS
                    px = (SIZE - px + dx) if MIRROR else (px - dx)
                    py = y + (sy + 0.5) / SS - dy
                    colour = None
                    for segs, width, col in LAYERS:
                        if near(px, py, segs, width):
                            colour = col
                    if colour:
                        r += colour[0]
                        g += colour[1]
                        b += colour[2]
                        a += 1
            n = SS * SS
            if a:
                row.append((round(r / a), round(g / a), round(b / a), round(255 * a / n)))
            else:
                row.append((0, 0, 0, 0))
        pixels.append(row)
    return pixels


def write_tga(path, pixels):
    # Uncompressed true-colour, 32 bpp, origin top-left (descriptor 0x28).
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    body = bytes(c for row in pixels for (r, g, b, a) in row for c in (b, g, r, a))
    path.write_bytes(header + body)


def write_png(path, pixels):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    raw = b"".join(b"\0" + bytes(c for px in row for c in px) for row in pixels)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


def centring_offset(pixels):
    """Shift that puts the centre of the drawn pixels at the centre of the image."""
    xs = [x for row in pixels for x, px in enumerate(row) if px[3] > 40]
    ys = [y for y, row in enumerate(pixels) for px in row if px[3] > 40]
    cx = (min(xs) + max(xs) + 1) / 2
    cy = (min(ys) + max(ys) + 1) / 2
    return SIZE / 2 - cx, SIZE / 2 - cy


def main():
    dx, dy = centring_offset(render())
    pixels = render(dx, dy)
    dest = ROOT / "media" / "harp.tga"
    dest.parent.mkdir(exist_ok=True)
    write_tga(dest, pixels)
    print(f"wrote {dest.relative_to(ROOT)}")
    if len(sys.argv) > 1:
        write_png(Path(sys.argv[1]), pixels)


if __name__ == "__main__":
    main()
