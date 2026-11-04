# SPDX-License-Identifier: GPL-3.0-or-later
"""Compiler: data/routes/<faction> -> Braindead4Ever/Routes/Data_<Faction>.lua (docs/ROUTE-FORMAT.md
§Compiled form), and the flight network of data/facts -> Braindead4Ever/Routes/Data_Flights.lua
for the flight legs in the exchange (§Flights in the exchange). The output is deterministic, so CI
can rebuild it and compare."""

import filecmp
import json
import os
import tempfile

from . import game, routefmt
from .io import read_jsonl, repo_path

FORMAT = 1
VERB_CODE = {
    "accept": 1,
    "complete": 2,
    "turnin": 3,
    "collect": 4,
    "goto": 5,
    "travel": 6,
    "hs": 7,
    "sethome": 8,
    "fp": 9,
    "train": 10,
    "xp": 11,
    "note": 12,
}
HOW_CODE = {"walk": 1, "fly": 2, "boat": 3, "zeppelin": 4, "airship": 5, "tram": 6, "portal": 7, "hearth": 8}
SRC_BIT = {"polestar": 1, "att": 2, "eglink": 4, "own": 8, "plan": 16}
STATUS_CODE = {"unbestätigt": 0, "bestätigt": 1}


def _lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _num(x):
    if isinstance(x, float):
        return ("%.1f" % x).rstrip("0").rstrip(".") if x != int(x) else str(int(x))
    return str(x)


def _ids(filt_races, filt_classes):
    parts = []
    if filt_races is not None:
        parts.append("r = { %s }" % ", ".join(str(r) for r in sorted(filt_races)))
    if filt_classes is not None:
        parts.append("c = { %s }" % ", ".join(str(c) for c in sorted(filt_classes)))
    return parts


def _src_mask(src):
    m = 0
    for s in src:
        m |= SRC_BIT[s]
    return m


def _element(el):
    v = el.verb
    a = el.args
    vals = [VERB_CODE[v]]
    if v in ("accept", "complete", "turnin"):
        vals.append(a["q"])
    elif v == "collect":
        vals += [a["item"], a["n"]]
    elif v == "goto":
        vals += [a["map"], a["wx"], a["wy"], a.get("r", 10.0)]
    elif v == "travel":
        vals += [HOW_CODE[a["how"]], a["map"]]
    elif v == "xp":
        vals.append(a["level"])
    elif v == "note":
        vals.append(_lua_str(a["text"]))
    vals += [_src_mask(el.src), STATUS_CODE[el.status]]
    if v == "goto":
        vals.append(int(el.prov.get("roots", 1)))
    out = [_num(x) if not isinstance(x, str) else x for x in vals]
    if el.filter is not None:
        out += _ids(el.filter.races, el.filter.classes)
    return "{ " + ", ".join(out) + " }"


def _module(m):
    lv = m.levels()
    lines = ["\t\t[%s] = {" % _lua_str(m.key)]
    lines.append(
        "\t\t\tkind = %s, mode = %s, levels = { %d, %d }, label = %s, version = %s,"
        % (_lua_str(m.kind), _lua_str(m.mode), lv[0], lv[1], _lua_str(m.header["label"]), m.header["version"])
    )
    if m.filter is not None:
        lines.append("\t\t\t" + ", ".join(_ids(m.filter.races, m.filter.classes)) + ",")
    lines.append("\t\t\tsteps = {")
    for st in m.steps:
        head = ["id = %s" % _lua_str(st.id)]
        if st.lv is not None:
            head.append("lv = %d" % st.lv)
        if st.filter is not None:
            head += _ids(st.filter.races, st.filter.classes)
        if st.ret:
            head.append("ret = %s" % _lua_str(st.ret))
        els = [_element(el) for el in st.elements]
        lines.append("\t\t\t\t{ %s, %s }," % (", ".join(head), ", ".join(els)))
    lines.append("\t\t\t},")
    lines.append("\t\t},")
    return lines


def _compose(comp):
    lines = ["\tcompose = {"]
    for mode in routefmt.MODES:
        c = comp.modes.get(mode)
        if not c:
            continue
        lines.append("\t\t%s = {" % mode)
        lines.append("\t\t\tstarts = {")
        for f, key in c["starts"]:
            lines.append("\t\t\t\t{ key = %s, %s }," % (_lua_str(key), ", ".join(_ids(f.races, f.classes)) or "r = nil"))
        lines.append("\t\t\t},")
        lines.append("\t\t\tcore = { %s }," % ", ".join(_lua_str(k) for k in c["core"]))
        lines.append("\t\t\tinserts = {")
        for f, after, key in c["inserts"]:
            ids = _ids(f.races, f.classes)
            lines.append("\t\t\t\t{ after = %s, key = %s%s }," % (_lua_str(after), _lua_str(key), ", " + ", ".join(ids) if ids else ""))
        lines.append("\t\t\t},")
        lines.append("\t\t},")
    lines.append("\t},")
    return lines


def _quest_ids(fmods):
    ids = set()
    for m in fmods:
        for st in m.steps:
            for el in st.elements:
                if el.verb in ("accept", "complete", "turnin"):
                    ids.add(el.args["q"])
    return ids


def _quests(fmods, facts):
    """Quest facts the addon needs at runtime (docs/ROUTE-FORMAT.md §Compiled form, quests):
    level, XP and prerequisite groups of every quest the faction's modules name."""
    lines = ["\tquests = {"]
    for q in sorted(_quest_ids(fmods)):
        rec = facts.get(q, {})
        level = (rec.get("level") or {}).get("v") or 0
        xp = (rec.get("xp") or {}).get("v") or 0
        groups = [sorted(g) for g in (rec.get("pre") or {}).get("v") or [] if g]
        vals = [str(level), str(xp)]
        if groups:
            vals.append("{ %s }" % ", ".join("{ %s }" % ", ".join(str(x) for x in g) for g in groups))
        lines.append("\t\t[%d] = { %s }," % (q, ", ".join(vals)))
    lines.append("\t},")
    return lines


def _unsure(fmods, facts, extra_ids=()):
    """Quest IDs whose prerequisites are not secured (unknown or conflicting): the runtime marks
    their chain as incomplete until our own observations confirm it."""
    ids = sorted(q for q in _quest_ids(fmods) | set(extra_ids) if (facts.get(q, {}).get("pre") or {}).get("state", "unknown") != "secured")
    lines = ["\tunsure = {"]
    for i in range(0, len(ids), 12):
        lines.append("\t\t%s," % ", ".join(str(q) for q in ids[i : i + 12]))
    lines.append("\t},")
    return lines


# Dungeon hint (docs/ROUTE-RUNTIME.md §Dungeon hint). Chosen values, not measured: the level band of
# an instance starts DUNGEON_BELOW levels under the median quest level (at least at the instance's
# minimum level) and ends DUNGEON_ABOVE levels over the highest quest level.
DUNGEON_BELOW = 3
DUNGEON_ABOVE = 2
# Forever: "Dungeon quests now reward 50% less extra experience beyond normal quest values"
# (Beta Development Notes #4, brain chapter 14 §4.3). The normal value of a quest level is the
# median full XP of the ordinary quests (Polestar type 0) of that level.
DUNGEON_EXTRA_FACTOR = 0.5


def _normal_xp(facts):
    by_level = {}
    for r in facts.values():
        lv, xp = (r.get("level") or {}).get("v"), (r.get("xp") or {}).get("v")
        if r.get("type") == 0 and lv and xp:
            by_level.setdefault(lv, []).append(xp)
    out = {}
    for lv, xs in by_level.items():
        xs = sorted(xs)
        out[lv] = xs[len(xs) // 2]
    return out


def forever_dungeon_xp(full, level, normal):
    """Full XP of a dungeon quest after the Forever rule: the part above a normal quest of the same
    level is halved. Without a normal value the full XP stays (no invented reduction)."""
    base = normal.get(level)
    if not full or base is None or full <= base:
        return full or 0
    return int(round((base + DUNGEON_EXTRA_FACTOR * (full - base)) / 5.0)) * 5


def _side_ok(r, faction):
    side = (r.get("side") or {}).get("v")
    return side in ("B", faction[0])


def _dungeon_tables(faction, facts, dungeons):
    """dungeons = { [instance] = { area, min, lo, hi, entrance, quests } } and dquests = { [quest] =
    { level, min, xp, uiMap, wx, wy [, pre] [, r] [, c] } } for the faction. Quests without a known
    giver position or started by an item are left out: the hint names givers on the way."""
    normal = _normal_xp(facts)
    dl, ql, used = ["\tdungeons = {"], ["\tdquests = {"], set()
    for d in sorted(dungeons, key=lambda d: d["id"]):
        qs = []
        for q in d["quests"]:
            r = facts.get(q)
            if not r or not _side_ok(r, faction) or r.get("startItem") or not r.get("startPos"):
                continue
            races = (r.get("races") or {}).get("v")
            if races is not None and not set(races) & set(game.races_of(faction)):
                continue
            qs.append(r)
        if not qs:
            continue
        levels = sorted((r.get("level") or {}).get("v") or (r.get("min") or {}).get("v") or 1 for r in qs)
        median = levels[len(levels) // 2]
        lo = max(d.get("min") or 1, median - DUNGEON_BELOW)
        hi = levels[-1] + DUNGEON_ABOVE
        parts = ["area = %d" % d["area"]] if d.get("area") is not None else []
        parts += ["min = %d" % (d.get("min") or 1), "lo = %d" % lo, "hi = %d" % hi]
        if d.get("entrance"):
            e = d["entrance"]
            parts.append("entrance = { %d, %s, %s }" % (e[0], _num(e[1]), _num(e[2])))
        parts.append("quests = { %s }" % ", ".join(str(r["q"]) for r in qs))
        dl.append("\t\t[%d] = { %s }," % (d["id"], ", ".join(parts)))
        for r in qs:
            if r["q"] in used:
                continue
            used.add(r["q"])
            lv = (r.get("level") or {}).get("v") or 0
            mn = (r.get("min") or {}).get("v") or lv or 1
            xp = forever_dungeon_xp((r.get("xp") or {}).get("v") or 0, lv, normal)
            m, w, n = r["startPos"]["v"]
            vals = [str(lv), str(mn), str(xp), str(m), _num(w), _num(n)]
            groups = [sorted(g) for g in (r.get("pre") or {}).get("v") or [] if g]
            if groups:
                vals.append("pre = { %s }" % ", ".join("{ %s }" % ", ".join(str(x) for x in g) for g in groups))
            races = (r.get("races") or {}).get("v")
            if races is not None and not set(game.races_of(faction)) <= set(races):
                vals.append("r = { %s }" % ", ".join(str(x) for x in sorted(set(races) & set(game.races_of(faction)))))
            classes = (r.get("classes") or {}).get("v")
            if classes is not None:
                vals.append("c = { %s }" % ", ".join(str(x) for x in sorted(classes)))
            ql.append("\t\t[%d] = { %s }," % (r["q"], ", ".join(vals)))
    dl.append("\t},")
    ql.append("\t},")
    return dl, ql, used


FIND_CODE = {"quest": 1, "treasure": 2, "book": 3, "rare": 4, "flightpath": 5, "place": 6}


def _finds(faction, finds):
    """Discovery catalog: { type, id, uiMap, x1, y1, x2, y2, ... } with x, y in hundredths of a percent;
    only the points on the first point's map."""
    lines = ["\tfinds = {"]
    for f in sorted(finds, key=lambda f: f["key"]):
        if f.get("side") not in (None, faction[0]):
            continue
        m = f["pos"][0][0]
        pts = [p for p in f["pos"] if p[0] == m]
        vals = [str(FIND_CODE[f["type"]]), str(f["id"]), str(m)] + ["%d, %d" % (p[1], p[2]) for p in pts]
        lines.append("\t\t{ %s }," % ", ".join(vals))
    lines.append("\t},")
    return lines


def _times(times):
    """Measured module times: { [module] = { runs, median seconds } } (own data, docs/ROUTE-RUNTIME.md)."""
    lines = ["\ttimes = {"]
    for t in sorted(times, key=lambda t: t["module"]):
        lines.append("\t\t[%s] = { %d, %d }," % (_lua_str(t["module"]), t["runs"], t["seconds"]))
    lines.append("\t},")
    return lines


def _classic(facts):
    """Quest IDs the facts know as Classic quests (not new in Forever). The explorer logic counts an
    accepted quest as a discovery only when it is neither one of these nor a route or dungeon quest."""
    ids = sorted(q for q, r in facts.items() if not r.get("new"))
    lines = ["\tclassic = {"]
    for i in range(0, len(ids), 16):
        lines.append("\t\t%s," % ", ".join(str(q) for q in ids[i : i + 16]))
    lines.append("\t},")
    return lines


def _maps(fmods, dquest_maps, frames):
    """Continent (instance) of every uiMap the faction's goto points and dungeon quest givers use:
    { [uiMap] = instance }. The dungeon hint measures distances in world yards, which only compare on
    the same continent (brain chapter 07 §2)."""
    ui = set(dquest_maps)
    for m in fmods:
        for st in m.steps:
            for el in st.elements:
                if el.verb == "goto":
                    ui.add(el.args["map"])
    lines = ["\tmaps = {"]
    pairs = ["[%d] = %d" % (u, frames[u]) for u in sorted(ui) if frames.get(u) is not None]
    for i in range(0, len(pairs), 8):
        lines.append("\t\t%s," % ", ".join(pairs[i : i + 8]))
    lines.append("\t},")
    return lines


def compile_faction(faction, mods, comp, facts=None, extra=None):
    fmods = sorted((m for m in mods.values() if m.faction == faction), key=lambda m: m.key)
    sources = sorted({m.header.get("sources", "") for m in fmods})
    out = [
        "-- SPDX-License-Identifier: GPL-3.0-only",
        "-- Generated by tools/routekit (compile) from data/routes/%s. Do not edit; change the route" % faction.lower(),
        "-- files and run: python3 -m tools.routekit compile. Layout: docs/ROUTE-FORMAT.md.",
        "-- Data from Polestar forever-db (GPL-3.0-only), from Efficient Games' EG Link output (CC BY 4.0,",
        "-- changed: reduced to quest facts) and from All The Things (MIT). Credits and licences: NOTICE.",
        "-- Every value has the status \"unbestätigt\" until our own measurements confirm it.",
        "local _, ns = ...",
        "ns.RouteData = ns.RouteData or {}",
        "-- A function, so the tables are only built for the faction that is played.",
        "ns.RouteData.%s = function()" % faction,
        "\treturn {",
        "\tformat = %d," % FORMAT,
        "\tfaction = %s," % _lua_str(faction),
        "\tsources = %s," % _lua_str(" | ".join(sources)),
        "\tmodules = {",
    ]
    for m in fmods:
        out += _module(m)
    out.append("\t},")
    out += _compose(comp)
    out += _quests(fmods, facts or {})
    extra = extra or {}
    dl, ql, dq = _dungeon_tables(faction, facts or {}, extra.get("dungeons", []))
    out += _unsure(fmods, facts or {}, dq)
    out += dl + ql
    out += _finds(faction, extra.get("finds", []))
    out += _times([t for t in extra.get("times", []) if t["module"].startswith(faction[0].lower() + "-")])
    out += _classic(facts or {})
    dmaps = [(facts or {})[q]["startPos"]["v"][0] for q in dq]
    out += _maps(fmods, dmaps, extra.get("frames", {}))
    out += ["\t}", "end", ""]
    return "\n".join(out)


def compile_flights(nodes, edges, model, frames):
    """Flight facts for Collector/Flights.lua: { secondsPerYard, nodes = { [node] = { instance, west,
    north } (yards, {} without a position) }, legs = { ["from>to"] = flights measured, 0 for a model
    value } }. Both factions: the checks only need to know that a point or a leg exists."""
    out = [
        "-- SPDX-License-Identifier: GPL-3.0-only",
        "-- Generated by tools/routekit (compile) from data/facts/flightnodes.jsonl, flightedges.jsonl and",
        "-- FACTS.json. Do not edit; run: python3 -m tools.routekit merge, then compile. Layout and use:",
        "-- docs/ROUTE-FORMAT.md §Flights in the exchange. Data from Polestar forever-db (GPL-3.0-only), from",
        "-- Efficient Games' EG Link output (CC BY 4.0, changed: reduced to flight points and flown legs) and",
        "-- from All The Things (MIT). Credits and licences: NOTICE.",
        "local _, ns = ...",
        "ns.FlightFacts = {",
    ]
    per_yard = (model or {}).get("secondsPerYard")
    out.append("\tsecondsPerYard = %s," % (repr(float(per_yard)) if per_yard else "nil"))
    out.append("\tnodes = {")
    for r in sorted(nodes, key=lambda r: r["node"]):
        pos = (r.get("pos") or {}).get("v")
        inst = frames.get(pos[0]) if pos else None
        if pos and inst is not None:
            out.append("\t\t[%d] = { %d, %d, %d }," % (r["node"], inst, round(pos[1]), round(pos[2])))
        else:
            out.append("\t\t[%d] = {}," % r["node"])
    out.append("\t},")
    out.append("\tlegs = {")
    for e in sorted(edges, key=lambda e: (e["from"], e["to"])):
        secs = e.get("seconds") or {}
        flights = 0 if secs.get("basis") == "model" else int(secs.get("flights") or 0)
        out.append('\t\t["%d>%d"] = %d,' % (e["from"], e["to"], flights))
    out.append("\t},")
    out += ["}", ""]
    return "\n".join(out)


def _write(target_dir):
    from . import lint

    mods, comps = lint.load_routes()
    facts = {r["q"]: r for r in read_jsonl(repo_path("data", "facts", "quests.jsonl"))}
    extra = {}
    for name in ("dungeons", "finds", "times"):
        path = repo_path("data", "facts", name + ".jsonl")
        extra[name] = read_jsonl(path) if os.path.exists(path) else []
    frames = repo_path("data", "sources", "polestar", "ui_map.jsonl")
    extra["frames"] = {r["ui_map"]: r["map"] for r in read_jsonl(frames)} if os.path.exists(frames) else {}
    written = []
    for faction in (game.ALLIANCE, game.HORDE):
        comp = next(c for c in comps if c.faction == faction)
        path = os.path.join(target_dir, "Data_%s.lua" % faction)
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(compile_faction(faction, mods, comp, facts, extra))
        written.append(path)
    nodes = read_jsonl(repo_path("data", "facts", "flightnodes.jsonl"))
    edges = read_jsonl(repo_path("data", "facts", "flightedges.jsonl"))
    with open(repo_path("data", "facts", "FACTS.json"), encoding="utf-8") as fh:
        model = json.load(fh).get("flightModel")
    path = os.path.join(target_dir, "Data_Flights.lua")
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(compile_flights(nodes, edges, model, extra["frames"]))
    written.append(path)
    return written


def run():
    out = repo_path("Braindead4Ever", "Routes")
    os.makedirs(out, exist_ok=True)
    files = _write(out)
    return {os.path.basename(f): os.path.getsize(f) for f in files}


def check():
    """Compile into a temp dir and compare with the committed files: exit 1 on drift."""
    with tempfile.TemporaryDirectory() as tmp:
        files = _write(tmp)
        bad = []
        for f in files:
            committed = repo_path("Braindead4Ever", "Routes", os.path.basename(f))
            if not os.path.exists(committed) or not filecmp.cmp(f, committed, shallow=False):
                bad.append(os.path.basename(f))
        if bad:
            print("compiled route data out of date: %s (run python3 -m tools.routekit compile)" % ", ".join(bad))
            return 1
    print("compiled route data up to date")
    return 0
