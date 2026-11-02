# SPDX-License-Identifier: GPL-3.0-or-later
"""Run times from the in-game exchange (docs/RUN-TIMES.md). Reads the CSV tables that
`node decoder/cli.mjs --runs` writes from PM1 exports and gives the median time of every section
per class and mode, players who follow the route and players who play freely kept apart:

  python3 -m tools.routekit runs CSV_FILES... [--json OUT]

Columns: token, race, class, mode, kind, section, version, seconds, xp, in_order, level, day, source.
kind l = a level (section = the level), m = a route module (section = Proto.ModuleNumber of its key).
Groups: "follows" = route mode s or e and at least FOLLOW_MIN % of the section's steps done in route
order; "free" = mode f (no route, window closed or guidance paused); "partial" = the rest.
"""

import csv
import json
import os

FOLLOW_MIN = 80  # chosen value: share of steps in route order that counts as following the route
PRIME = 9999991
COLUMNS = ["token", "race", "class", "mode", "kind", "section", "version", "seconds", "xp", "in_order", "level", "day", "source"]
NUMBERS = ("race", "class", "section", "version", "seconds", "xp", "in_order", "level", "day")


def module_number(key):
    """Number of a module key in run messages, like Proto.ModuleNumber (djb2 modulo 9999991, plus 1)."""
    h = 5381
    for b in key.encode("utf-8"):
        h = (h * 33 + b) % PRIME
    return h + 1


def module_names(keys=None):
    """{number: module key} for the route modules in data/routes (or the given keys)."""
    if keys is None:
        from . import lint

        mods, _ = lint.load_routes()
        keys = mods.keys()
    return {module_number(k): k for k in keys}


def group(row):
    if row["mode"] == "f":
        return "free"
    return "follows" if row["in_order"] >= FOLLOW_MIN else "partial"


def read(paths):
    """Rows of all tables; one per (token, kind, section), conflicting values for a key drop both."""
    rows = {}
    for p in paths:
        with open(p, encoding="utf-8", newline="") as fh:
            for r in csv.DictReader(fh):
                if set(COLUMNS) - set(r):
                    raise ValueError("%s: not a run table (columns %s)" % (p, ", ".join(COLUMNS)))
                try:
                    row = {k: (int(r[k]) if k in NUMBERS else r[k]) for k in COLUMNS}
                except ValueError:
                    continue
                key = (row["token"], row["kind"], row["section"])
                values = tuple(row[k] for k in COLUMNS if k != "source")
                if key not in rows:
                    rows[key] = (values, row)
                elif rows[key] and rows[key][0] != values:
                    rows[key] = None
    return [v[1] for v in rows.values() if v]


def median(values):
    s = sorted(values)
    n = len(s)
    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2


def summary(rows, names=None):
    """Median seconds and XP per hour per section, class, mode and group, sorted."""
    names = names or {}
    groups = {}
    for r in rows:
        key = (r["kind"], r["section"], r["class"], r["mode"], group(r))
        groups.setdefault(key, []).append(r)
    out = []
    for (kind, section, cls, mode, grp), rs in sorted(groups.items()):
        out.append(
            {
                "kind": kind,
                "section": section,
                "module": names.get(section) if kind == "m" else None,
                "class": cls,
                "mode": mode,
                "group": grp,
                "runs": len(rs),
                "seconds": median([r["seconds"] for r in rs]),
                "xpPerHour": round(median([r["xp"] * 3600 / r["seconds"] for r in rs])),
            }
        )
    return out


def run(paths, json_out=None):
    files = []
    for p in paths:
        files += sorted(os.path.join(p, f) for f in os.listdir(p)) if os.path.isdir(p) else [p]
    rows = read(files)
    names = module_names()
    out = summary(rows, names)
    if json_out:
        with open(json_out, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(out, fh, ensure_ascii=False, indent=1)
            fh.write("\n")
    return {"rows": len(rows), "tokens": len({r["token"] for r in rows}), "groups": len(out)}, out
