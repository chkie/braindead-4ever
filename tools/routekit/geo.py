# SPDX-License-Identifier: GPL-3.0-or-later
"""World coordinates, map frames and distances.

Convention (brain chapter 07 §2, chapter 08 §7): world positions are yards on an instance
(0 Eastern Kingdoms, 1 Kalimdor, 2991 Zephras). `north` is the first value of
UnitPosition("player"), `west` the second. Route files write `west,north` as `wx,wy`.
Map frames: `top`/`bottom` bound the north axis, `left`/`right` the west axis (left is the
larger west value). Map percent: x grows to the east, y to the south.
"""

import math

from . import game


class Frames:
    """uiMap frames, built from rows {ui_map, map, top, bottom, left, right}."""

    def __init__(self, rows):
        self.by_map = {}
        for r in rows:
            self.by_map[r["ui_map"]] = r

    def instance(self, ui_map):
        r = self.by_map.get(ui_map)
        return r["map"] if r else None

    def to_world(self, ui_map, x_pct, y_pct):
        """Map percent (0-100) -> (instance, north, west) or None."""
        r = self.by_map.get(ui_map)
        if not r:
            return None
        west = r["left"] - (x_pct / 100.0) * (r["left"] - r["right"])
        north = r["top"] - (y_pct / 100.0) * (r["top"] - r["bottom"])
        return r["map"], round(north, 1), round(west, 1)

    def to_percent(self, ui_map, north, west):
        r = self.by_map.get(ui_map)
        if not r:
            return None
        x = (r["left"] - west) / (r["left"] - r["right"]) * 100.0
        y = (r["top"] - north) / (r["top"] - r["bottom"]) * 100.0
        return x, y

    def contains(self, ui_map, north, west, margin=0.0):
        r = self.by_map.get(ui_map)
        if not r:
            return False
        return (
            r["bottom"] - margin <= north <= r["top"] + margin and r["right"] - margin <= west <= r["left"] + margin
        )

    def zone_of(self, instance, north, west):
        """Smallest zone frame on `instance` that contains the point, or None."""
        best, best_area = None, None
        for ui_map, r in self.by_map.items():
            if r["map"] != instance or ui_map in game.NOT_ZONES:
                continue
            if r["bottom"] <= north <= r["top"] and r["right"] <= west <= r["left"]:
                area = (r["top"] - r["bottom"]) * (r["left"] - r["right"])
                if best_area is None or area < best_area:
                    best, best_area = ui_map, area
        return best


def dist(a, b):
    """Distance in yards between (north, west) pairs."""
    return math.hypot(a[0] - b[0], a[1] - b[1])


def medoid(points):
    """The point with the smallest summed distance to all others (robust centre)."""
    if not points:
        return None
    if len(points) <= 2:
        return points[0]
    best, best_sum = None, None
    for p in points:
        s = sum(dist(p, q) for q in points)
        if best_sum is None or s < best_sum:
            best, best_sum = p, s
    return best
