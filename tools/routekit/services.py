# SPDX-License-Identifier: GPL-3.0-or-later
"""Service NPCs and the flight network: data/sources -> data/facts/npcs.jsonl, flightnodes.jsonl
and flightedges.jsonl (docs/ROUTE-FORMAT.md §Service NPCs and flights). Called by `merge`.

Rules (decided 2026-11-03, revisable):
- Service NPCs are class trainers, innkeepers and flight masters. Roles come from Polestar (the
  NPC's title), EG Link (the window a player opened) and ATT (the flight master of a flight point).
  A trainer is kept only with a class from Polestar's title: EG Link's class trainer type also
  covers pet trainers, weapon masters and riding instructors (measured 2026-11-03).
  Only NPCs standing in a route zone (tools/routekit/game.py ZONES: the zones of levels 1 to 34 and
  the capitals) are kept.
- Every value names its sources and starts with status "unbestätigt". Positions: EG Link (where a
  player stood at the open window) before Polestar (spawn point) before ATT (map percent; not on the
  four maps with a changed frame); positions agree within 10 yards. Polestar takes part of its
  Forever data from EG Link, so for service NPCs the two count as one root. The zone of a bare
  world point: the map of another source within 50 yards, else the zone most EG Link positions
  within 150 yards name (ZoneOf), else the smallest zone frame.
- Sides: EG Link (as the game showed it) before ATT (races of a flight point) before Polestar
  (derived from the faction template, importers/polestar.py). Sources that state another side are
  listed under `alt`.
- Flight points come from ATT and EG Link; a point's position is that of its flight master or ATT's
  coordinate. A flight leg (edge) exists only when a source flew it: two consecutive flight points of
  a trip in EG Link or in our own records. No edge is derived from anything else.
- Flight seconds of a leg: measured (own before EG Link: the median of the flights of a trip that
  was flown without a stop), else a model value: straight distance between the two flight points
  times the median seconds per yard of all measured legs, marked "basis": "model".
"""

import collections
import os

from . import game, geo
from .io import read_jsonl, repo_path

AGREE_YARDS = 10.0
NEAR_YARDS = 50.0  # as merge.py: a source's explicit map counts for a bare point this close
SERVICE_ZONES = set(game.ZONES)
ROLES = ("trainer", "innkeeper", "flightmaster")
# Polestar and EG Link count as one root for service NPCs (see the module doc).
SAME_ROOT = {"polestar": "eglink"}


def _read(*parts):
    path = repo_path("data", "sources", *parts)
    return read_jsonl(path) if os.path.exists(path) else []


def _faction_of_races(races):
    fs = {game.faction_of(r) for r in races if r in game.RACES}
    if len(fs) != 1:
        return None
    return "A" if game.ALLIANCE in fs else "H"


def _roots(srcs):
    return len({SAME_ROOT.get(s, s) for s in srcs})


def _choose(cands, order):
    """cands {src: value}: the first source in `order` wins; returns {v, src, alt?} or None."""
    present = [s for s in order if s in cands and cands[s] is not None]
    if not present:
        return None
    v = cands[present[0]]
    out = {"v": v, "src": [s for s in present if cands[s] == v]}
    alt = {s: cands[s] for s in present if cands[s] != v}
    if alt:
        out["alt"] = alt
    return out


class ZoneOf:
    """Zone of a bare world point. Zone frames are rectangles and overlap at the borders (Darkshire
    lies inside the frame of Deadwind Pass), so the smallest frame alone is not enough: among the
    zone frames that contain the point, the zone most measured points (EG Link: a player's map at an
    open window) within VOTE_YARDS name wins; without such points the smallest frame."""

    VOTE_YARDS = 150.0

    def __init__(self, frames):
        self.frames = frames
        self.points = collections.defaultdict(list)  # instance -> [(north, west, uiMap)]
        for r in _read("eglink", "quests.jsonl"):
            for field in ("startPos", "endPos"):
                for m, w, n in r.get(field, []):
                    self._add(m, w, n)
        for r in _read("eglink", "npcs.jsonl"):
            for m, w, n in r.get("pos", []):
                self._add(m, w, n)

    def _add(self, ui_map, west, north):
        inst = self.frames.instance(ui_map)
        if inst is not None and ui_map not in game.NOT_ZONES:
            self.points[inst].append((north, west, ui_map))

    def __call__(self, inst, west, north):
        cands = [m for m, r in self.frames.by_map.items() if r["map"] == inst and m not in game.NOT_ZONES and self.frames.contains(m, north, west)]
        if len(cands) <= 1:
            return cands[0] if cands else None
        votes = collections.Counter(
            m for n, w, m in self.points.get(inst, ()) if m in cands and geo.dist((n, w), (north, west)) <= self.VOTE_YARDS
        )
        if votes:
            return votes.most_common(1)[0][0]
        return self.frames.zone_of(inst, north, west)


def _position(frames, cands, zone_of):
    """cands {src: [(instance, west, north, uiMap|None)]} -> {v: [uiMap, west, north], src, seen,
    roots} with the medoid of each source on its most common instance, or None. A bare point takes
    the map of another source within NEAR_YARDS, else zone_of."""
    reps = {}
    for src, pts in cands.items():
        if not pts:
            continue
        inst = collections.Counter(p[0] for p in pts).most_common(1)[0][0]
        on = [p for p in pts if p[0] == inst]
        m = geo.medoid([(p[2], p[1]) for p in on])
        reps[src] = next(p for p in on if (p[2], p[1]) == m)
    order = [s for s in ("own", "eglink", "polestar", "att") if s in reps]
    if not order:
        return None
    chosen = reps[order[0]]
    agreeing = [
        s for s in order if reps[s][0] == chosen[0] and geo.dist((reps[s][2], reps[s][1]), (chosen[2], chosen[1])) <= AGREE_YARDS
    ]
    ui_map = chosen[3]
    if ui_map is None:
        near = [
            reps[s][3]
            for s in order
            if reps[s][3] and reps[s][0] == chosen[0] and geo.dist((reps[s][2], reps[s][1]), (chosen[2], chosen[1])) <= NEAR_YARDS
        ]
        ui_map = near[0] if near else zone_of(chosen[0], chosen[1], chosen[2])
    if ui_map is None:
        return None
    return {"v": [ui_map, chosen[1], chosen[2]], "src": agreeing, "seen": order, "roots": _roots(agreeing)}


def _att_points(frames, pct):
    out = []
    for ui_map, x, y in pct:
        if ui_map in game.CHANGED_FRAMES:
            continue
        w = frames.to_world(ui_map, x, y)
        if w:
            out.append((w[0], w[2], w[1], ui_map))
    return out


def _sources_npcs(frames):
    """{(role, npcID): {src: {...}}} from Polestar, EG Link and ATT flight points."""
    out = collections.defaultdict(dict)
    for r in _read("polestar", "npcs.jsonl"):
        pts = [(i, w, n, None) for i, w, n in r["pos"]]
        out[(r["role"], r["id"])]["polestar"] = {"side": r.get("side"), "class": r.get("class"), "pos": pts}
    for r in _read("eglink", "npcs.jsonl"):
        pts = [(frames.instance(m), w, n, m) for m, w, n in r.get("pos", []) if frames.instance(m) is not None and m not in game.NOT_ZONES]
        for role in r["roles"]:
            out[(role, r["id"])]["eglink"] = {"side": r.get("side"), "node": r.get("node"), "pos": pts}
    for f in _att_flightpaths():
        for npc in f.get("masters", []):
            e = out[("flightmaster", npc)].setdefault("att", {"side": _faction_of_races(f.get("races") or []), "node": f["id"], "pos": []})
            e["pos"] += _att_points(frames, f["pct"])
    return out


def _att_flightpaths():
    return [f for f in _read("att", "finds.jsonl") if f["type"] == "flightpath" and not f.get("removed")]


def npc_facts(frames, zone_of):
    """All service NPCs (world-wide, used for the flight points) and the facts kept (route zones)."""
    every, kept = [], []
    for (role, ident), by_src in sorted(_sources_npcs(frames).items(), key=lambda kv: (kv[0][1], kv[0][0])):
        rec = {"id": ident, "role": {"v": role, "src": sorted(by_src, key=_src_order)}, "status": "unbestätigt"}
        cls = by_src.get("polestar", {}).get("class")
        if role == "trainer" and cls is None:
            # EG Link's trainer type 0 also covers pet trainers, weapon masters and riding
            # instructors; only Polestar's title names the class.
            continue
        if cls is not None:
            rec["class"] = {"v": cls, "src": ["polestar"]}
        side = _choose({s: d.get("side") for s, d in by_src.items()}, ("eglink", "att", "polestar"))
        if side:
            rec["side"] = side
        if role == "flightmaster":
            node = _choose({s: d.get("node") for s, d in by_src.items()}, ("eglink", "att"))
            if node:
                rec["node"] = node
        pos = _position(frames, {s: d["pos"] for s, d in by_src.items()}, zone_of)
        if pos:
            rec["pos"] = pos
            rec["zone"] = pos["v"][0]
        every.append(rec)
        if rec.get("zone") in SERVICE_ZONES:
            kept.append(rec)
    return every, kept


def _src_order(s):
    return ("own", "eglink", "polestar", "att").index(s)


def _legs(trips, src, legs, timed):
    """Collect legs (consecutive flight points) and the flight seconds of trips flown without a stop."""
    for t in trips:
        for path in t["paths"]:
            for a, b in zip(path, path[1:]):
                e = legs.setdefault((a, b), {"src": set(), "trips": set()})
                e["src"].add(src)
                e["trips"].add(t["key"])
        direct = len(t["paths"]) == 1 and len(t["paths"][0]) == 2
        if direct and t.get("seconds") and not t.get("talent"):
            a, b = t["paths"][0]
            c = timed.setdefault((src, a, b), collections.Counter())
            for secs, n in t["seconds"].items():
                c[int(secs)] += n


def _median(counter):
    values = sorted(counter.elements())
    return values[len(values) // 2]


def measured_seconds(timed):
    """{(src, a, b): Counter(seconds)} -> {(a, b): {v: median, src, flights}}; own before EG Link."""
    measured = {}
    for (src, a, b), c in sorted(timed.items(), key=lambda kv: kv[0][0] == "own"):
        measured[(a, b)] = {"v": _median(c), "src": [src], "flights": sum(c.values())}
    return measured


def flight_facts(frames, npcs, zone_of):
    """Flight points and legs: (nodes, edges, model) for data/facts."""
    masters_of = collections.defaultdict(dict)  # node -> {npcID: flight master fact}
    for r in npcs:
        if r["role"]["v"] == "flightmaster" and r.get("node"):
            masters_of[r["node"]["v"]][r["id"]] = r
    att = {f["id"]: f for f in _att_flightpaths()}

    legs, timed = {}, {}
    _legs(_read("eglink", "flights.jsonl"), "eglink", legs, timed)
    _legs(_read("own", "flights.jsonl"), "own", legs, timed)

    ids = set(att) | set(masters_of) | {x for leg in legs for x in leg}
    nodes = {}
    for node in sorted(ids):
        rec = {"node": node, "status": "unbestätigt"}
        srcs = set()
        cands = collections.defaultdict(list)
        sides = {}
        if node in att:
            srcs.add("att")
            cands["att"] += _att_points(frames, att[node]["pct"])
            sides["att"] = _faction_of_races(att[node].get("races") or [])
        ms = masters_of.get(node, {})
        if ms:
            rec["masters"] = {"v": sorted(ms), "src": sorted({s for r in ms.values() for s in r["node"]["src"]}, key=_src_order)}
            srcs.update(rec["masters"]["src"])
            for r in ms.values():
                p = r.get("pos")
                if p:
                    for s in p["src"]:
                        if s != "att":
                            ui_map, w, n = p["v"]
                            cands[s].append((frames.instance(ui_map), w, n, ui_map))
                for s in (r.get("side") or {}).get("src", []):
                    sides.setdefault(s, r["side"]["v"])
        if any(node in leg for leg in legs):
            srcs.update(s for leg, e in legs.items() if node in leg for s in e["src"])
        rec["src"] = sorted(srcs, key=_src_order)
        side = _choose(sides, ("eglink", "att", "polestar"))
        if side:
            rec["side"] = side
        pos = _position(frames, cands, zone_of)
        if pos:
            rec["pos"] = pos
            rec["zone"] = pos["v"][0]
        nodes[node] = rec

    def dist(a, b):
        pa, pb = nodes[a].get("pos"), nodes[b].get("pos")
        if not (pa and pb) or frames.instance(pa["v"][0]) != frames.instance(pb["v"][0]):
            return None
        return geo.dist((pa["v"][2], pa["v"][1]), (pb["v"][2], pb["v"][1]))

    measured = measured_seconds(timed)
    ratios = sorted(m["v"] / d for (a, b), m in measured.items() if (d := dist(a, b)))
    factor = round(ratios[len(ratios) // 2], 4) if ratios else None
    model = {"secondsPerYard": factor, "legs": len(ratios)}

    edges = []
    for (a, b), e in sorted(legs.items()):
        rec = {"key": "%d>%d" % (a, b), "from": a, "to": b, "src": sorted(e["src"], key=_src_order), "trips": len(e["trips"]), "status": "unbestätigt"}
        if (a, b) in measured:
            rec["seconds"] = measured[(a, b)]
        elif factor and dist(a, b):
            rec["seconds"] = {"v": round(dist(a, b) * factor), "basis": "model"}
        edges.append(rec)
    return list(nodes.values()), edges, model


def run(frames):
    zone_of = ZoneOf(frames)
    every, kept = npc_facts(frames, zone_of)
    nodes, edges, model = flight_facts(frames, every, zone_of)
    return kept, nodes, edges, model
