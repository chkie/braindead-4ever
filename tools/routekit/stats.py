# SPDX-License-Identifier: GPL-3.0-or-later
"""Counts per combination and level band: steps, quests, steps with a coordinate, accepts with
a secured prerequisite. Bands follow the planned level of a step (lv)."""

import collections

from . import game, lint, routefmt

BANDS = ((1, 20), (21, 30))


def collect(mods, comps, facts):
    rows = []
    for mode in routefmt.MODES:
        for race, cls in game.all_combos():
            faction = game.faction_of(race)
            comp = next(c for c in comps if c.faction == faction)
            keys = comp.route(mode, race, cls) or []
            c = collections.Counter()
            for key in keys:
                m = mods[key]
                if m.filter and not m.filter.applies(race, cls):
                    continue
                for st in m.steps:
                    if st.filter and not st.filter.applies(race, cls):
                        continue
                    lv = st.lv or 1
                    band = next(("%d-%d" % b for b in BANDS if b[0] <= lv <= b[1]), "31+")
                    c[band, "steps"] += 1
                    if any(el.verb == "goto" for el in st.elements):
                        c[band, "coord"] += 1
                    for el in st.elements:
                        if el.verb == "accept":
                            c[band, "accepts"] += 1
                            if facts.pre(el.args["q"]).get("state") == "secured":
                                c[band, "secured"] += 1
            rows.append((mode, faction, game.RACES[race][0], game.CLASSES[cls], len(keys), c))
    return rows


def main():
    facts = lint.Facts.load()
    mods, comps = lint.load_routes()
    rows = collect(mods, comps, facts)
    total = collections.Counter()
    print("mode     faction  race        class    modules  steps1-20 steps21-30 quests1-20 quests21-30")
    for mode, faction, race, cls, nmods, c in rows:
        print(
            "%-8s %-8s %-11s %-8s %7d %10d %10d %10d %11d"
            % (mode, faction, race, cls, nmods, c["1-20", "steps"], c["21-30", "steps"], c["1-20", "accepts"], c["21-30", "accepts"])
        )
        for k, v in c.items():
            total[(mode,) + k] += v
    for mode in routefmt.MODES:
        steps = sum(total[mode, b, "steps"] for b in ("1-20", "21-30", "31+"))
        coord = sum(total[mode, b, "coord"] for b in ("1-20", "21-30", "31+"))
        acc = sum(total[mode, b, "accepts"] for b in ("1-20", "21-30", "31+"))
        sec = sum(total[mode, b, "secured"] for b in ("1-20", "21-30", "31+"))
        print(
            "%s: %d steps over 56 combinations, %.1f %% with coordinate; %d accepts, %.1f %% with secured prerequisite"
            % (mode, steps, 100.0 * coord / max(1, steps), acc, 100.0 * sec / max(1, acc))
        )
    return 0
