# SPDX-License-Identifier: GPL-3.0-or-later
"""Draws the arrow textures of the addon: Braindead4Ever/Media/arrow.tga and arrow-outline.tga.

Blizzard's atlas Navigation-Tracked-Arrow is 22x18 and the arrow showed it at 44x36, twice its size:
the edges stepped (owner, screenshot round 3). These textures have the same arrowhead with a notch at
128x128, white, so SetVertexColor gives the palette color directly. The notch keeps the tip readable
at every angle (finding M11). The outline is the same shape grown by OUTLINE pixels.

Pure Python, no imaging library: every pixel is sampled SS x SS times. Run from the repository root:

  python3 -m tools.media.arrow
"""

import os
import struct

SIZE = 128
SS = 4  # samples per pixel and axis
# arrowhead pointing up, in pixels: tip, right wing, notch, left wing. Shape and outline stay inside
# the circle of radius 64 around the centre, the point SetRotation turns about, so no angle cuts a wing.
SHAPE = [(64.0, 12.0), (108.0, 100.0), (64.0, 82.0), (20.0, 100.0)]
OUTLINE = 7.0

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
MEDIA = os.path.join(ROOT, "Braindead4Ever", "Media")


def inside(x, y, poly):
    hit = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            hit = not hit
    return hit


def edge_dist2(x, y, poly):
    best = None
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        dx, dy = x2 - x1, y2 - y1
        t = max(0.0, min(1.0, ((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy)))
        px, py = x1 + t * dx - x, y1 + t * dy - y
        d = px * px + py * py
        if best is None or d < best:
            best = d
    return best


def coverage(grow):
    """Alpha 0..255 per pixel, rows top to bottom."""
    r2 = grow * grow
    rows = []
    for py in range(SIZE):
        row = []
        for px in range(SIZE):
            hits = 0
            for sy in range(SS):
                for sx in range(SS):
                    x, y = px + (sx + 0.5) / SS, py + (sy + 0.5) / SS
                    if inside(x, y, SHAPE) or (grow > 0 and edge_dist2(x, y, SHAPE) <= r2):
                        hits += 1
            row.append(round(255 * hits / (SS * SS)))
        rows.append(row)
    return rows


def tga(rows):
    """Uncompressed 32-bit TGA, origin bottom left (descriptor 0x08), white with alpha, like Media/icon.tga."""
    head = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
    body = bytearray()
    for row in reversed(rows):
        for a in row:
            body += bytes((255, 255, 255, a))  # B, G, R, A
    return head + bytes(body)


def build():
    return {"arrow.tga": tga(coverage(0.0)), "arrow-outline.tga": tga(coverage(OUTLINE))}


def main():
    for name, data in build().items():
        with open(os.path.join(MEDIA, name), "wb") as fh:
            fh.write(data)
        print("wrote", name, len(data), "bytes")


if __name__ == "__main__":
    main()
