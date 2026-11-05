# SPDX-License-Identifier: GPL-3.0-or-later
"""Merge the per-source facts into data/facts/quests.jsonl.

Rules (DR 20 §5, decided and revisable; documented in docs/ROUTE-FORMAT.md §Facts):
- Every value names its sources (`src`) and starts with status "unbestätigt".
- Roots: polestar, att and eglink count as separate roots, except that Polestar and EG Link
  agreeing on a new Forever quest (ID >= 70000) count as one root, because Polestar takes
  part of its new-quest data from EG Link (Polestar NOTICE.md).
- Positions agree when they are at most 10 yards apart. On the four maps with a changed
  frame (1412, 1423, 1433, 1453) map-percent coordinates (ATT) are not used.
- Prerequisites are "secured" when at least one root states them and no root states a
  different set, or for a Classic quest (ID < 70000) when no root states any (the Classic
  databases behind Polestar list chains completely). A new quest no root gives a
  prerequisite for has the state "unknown" and stays out of the Speed route.
- Cross-check (data/sources/check/prereq.jsonl, owner 2026-11-05: nothing unchecked): a
  prerequisite group a root states is dropped before the decision when the check refutes it
  (Classic quest, the reference lists no ID of the group); the record keeps it under
  `pre.refuted`. A quest whose stated groups are all refuted counts as having none.
- Game findings (data/sources/check/findings.jsonl): a prerequisite seen in the game is added
  (`src` "finding"); a quest the game did not offer for an unknown reason is held (`held`) and
  stays out of every route.
- Our own observations (data/sources/own/prereq.jsonl, written by `observe` from player
  exports) count as the root "own": confirmed prerequisites like a stated set, a confirmed
  "none" secures a quest that no other root states anything for.
- Dungeons (data/facts/dungeons.jsonl) come from the ATT instance files; their quests are
  the quests ATT lists under the instance plus Polestar dungeon quests (type 81) of the
  instance's area. The discovery catalog (data/facts/finds.jsonl) is ATT's treasures, books,
  rares and flight paths; map-percent coordinates on the four changed maps are left out.
- Service NPCs (class trainers, innkeepers, flight masters) and the flight network
  (data/facts/npcs.jsonl, flightnodes.jsonl, flightedges.jsonl) follow the rules in services.py.
"""

import collections
import os

from . import game, geo, services
from .io import read_json, read_jsonl, repo_path, write_json, write_jsonl

AGREE_YARDS = 10.0
MAX_MIN_LEVEL = 30
MAX_LEVEL = 34
EXCLUDED_TYPES = {1, 41, 62, 81, 82, 83, 84}  # group, PvP, raid, dungeon and other special types
SILENCE_COVERAGE = 0.5


def _band(level):
    return min(3, max(0, (int(level) - 1) // 10))


def _load(src):
    path = repo_path("data", "sources", src, "quests.jsonl")
    return {r["q"]: r for r in read_jsonl(path)} if os.path.exists(path) else {}


def _load_own():
    """Own observations: {quest: {"pre": [[id], ...], "basis": "observed" | "observed-none", "observers": n}}."""
    path = repo_path("data", "sources", "own", "prereq.jsonl")
    return {r["q"]: r for r in read_jsonl(path)} if os.path.exists(path) else {}


def _load_check():
    """Refuted prerequisite groups per quest and root: {quest: {root: [[id, ...], ...]}}."""
    path = repo_path("data", "sources", "check", "prereq.jsonl")
    if not os.path.exists(path):
        return {}
    return {r["q"]: r.get("refuted", {}) for r in read_jsonl(path)}


def _load_findings():
    """Game findings (data/sources/check/findings.jsonl): {quest: {"add": [[id]], "hold": text, "ref": text}}."""
    path = repo_path("data", "sources", "check", "findings.jsonl")
    if not os.path.exists(path):
        return {}
    return {r["q"]: r for r in read_jsonl(path)}


def apply_finding(pre, f):
    """A finding seen in the game outranks the sources: "add" puts prerequisite groups on top of the
    stated ones (secured); "hold" keeps the quest out of every route until a later finding clears it."""
    if not f:
        return pre, None
    if f.get("add"):
        have = {tuple(sorted(g)) for g in pre.get("v", [])}
        v = [list(g) for g in pre.get("v", [])] + [sorted(g) for g in f["add"] if tuple(sorted(g)) not in have]
        pre = dict(pre, v=v, state="secured", src=sorted(set(pre.get("src", [])) | {"finding"}), finding=f.get("ref", ""))
    held = {"why": f["hold"]} if f.get("hold") else None
    return pre, held


def _sources():
    out = {}
    for src in ("polestar", "att", "eglink", "own", "check"):
        p = repo_path("data", "sources", src, "SOURCE.json")
        if os.path.exists(p):
            out[src] = read_json(p)
    return out


def _roots(q, agreeing):
    s = set(agreeing)
    if game.is_new_quest(q) and {"polestar", "eglink"} <= s and "att" not in s:
        return len(s) - 1
    return len(s)


class ZoneResolver:
    """uiMap for a world point. Measured or explicit maps (EG Link, ATT) win; a bare world point
    (Polestar spawn) goes to the zone frame that contains it, preferring a hint (the quest's ATT
    zone, then the zone most quests of the same Polestar zone_area were measured in)."""

    def __init__(self, frames):
        self.frames = frames
        self.area_votes = collections.defaultdict(collections.Counter)

    def vote(self, area, ui_map):
        if area is not None and ui_map:
            self.area_votes[area][ui_map] += 1

    def resolve(self, inst, west, north, hints=()):
        cands = [
            m
            for m, r in self.frames.by_map.items()
            if r["map"] == inst and m not in game.NOT_ZONES and self.frames.contains(m, north, west)
        ]
        if not cands:
            return None
        for h in hints:
            if h in cands:
                return h
        return min(cands, key=lambda m: (self.frames.by_map[m]["top"] - self.frames.by_map[m]["bottom"]) * (self.frames.by_map[m]["left"] - self.frames.by_map[m]["right"]))

    def area_hint(self, area):
        votes = self.area_votes.get(area)
        return [m for m, _ in votes.most_common()] if votes else []


def _cands(frames, eg_pts, ps_pts, att_pts):
    """{src: [(inst, west, north, uiMap|None)]}"""
    out = {}
    if eg_pts:
        pts = [(frames.instance(m), w, n, m) for m, w, n in eg_pts if frames.instance(m) is not None and m not in game.NOT_ZONES]
        if pts:
            out["eglink"] = pts
    if ps_pts:
        out["polestar"] = [(i, w, n, None) for i, w, n in ps_pts]
    if att_pts:
        out["att"] = [(frames.instance(m), w, n, m) for m, w, n in att_pts]
    return out


def _pick_position(q, cands, resolver, hints):
    """Choose one position: EG Link (measured) before Polestar before ATT. Returns
    {v: [uiMap, west, north], src: agreeing sources, seen: all sources, roots} or None."""
    reps = {}
    for src, pts in cands.items():
        inst = collections.Counter(p[0] for p in pts).most_common(1)[0][0]
        on = [p for p in pts if p[0] == inst]
        m = geo.medoid([(p[2], p[1]) for p in on])
        rep = next(p for p in on if (p[2], p[1]) == m)
        reps[src] = rep
    if not reps:
        return None
    order = [s for s in ("eglink", "polestar", "att") if s in reps]
    chosen = reps[order[0]]
    agreeing = [
        s
        for s in order
        if reps[s][0] == chosen[0] and geo.dist((reps[s][2], reps[s][1]), (chosen[2], chosen[1])) <= AGREE_YARDS
    ]
    ui_map = chosen[3]
    if ui_map is None:
        near = [reps[s][3] for s in order if reps[s][3] and reps[s][0] == chosen[0] and geo.dist((reps[s][2], reps[s][1]), (chosen[2], chosen[1])) <= 50]
        ui_map = near[0] if near else resolver.resolve(chosen[0], chosen[1], chosen[2], hints)
    if ui_map is None:
        return None
    return {"v": [ui_map, chosen[1], chosen[2]], "src": agreeing, "seen": order, "roots": _roots(q, agreeing)}


def _att_world(att_rec, frames, field="startPct"):
    out = []
    for ui_map, x, y in att_rec.get(field, []) if att_rec else []:
        if ui_map in game.CHANGED_FRAMES:
            continue
        w = frames.to_world(ui_map, x, y)
        if w:
            out.append([ui_map, w[2], w[1]])
    return out


def _pre_groups(rec, src, breadcrumbs):
    """Normalised prerequisite groups: list of sorted tuples, one ID of a group is enough."""
    pre = rec.get("pre") if rec else None
    if not pre:
        return None
    groups = []
    for q in pre.get("all", []):
        if q not in breadcrumbs:
            groups.append((q,))
    anyq = tuple(sorted(q for q in pre.get("any", []) if q not in breadcrumbs))
    if anyq:
        groups.append(anyq)
    return sorted(set(groups))


def prereq_state(p, a, o, breadcrumbs, is_new, silent, refuted=None):
    """Prerequisite field of one quest from the Polestar record p, the ATT record a and our own
    observation o (data/sources/own/prereq.jsonl). silent: both Polestar and ATT are silent in a
    band where silence counts (see run)."""
    stated = []
    dropped = {}
    for s, r in (("polestar", p), ("att", a)):
        g = _pre_groups(r, s, breadcrumbs)
        bad = {tuple(sorted(x)) for x in (refuted or {}).get(s, [])}
        if g and bad:
            kept = [grp for grp in g if tuple(sorted(grp)) not in bad]
            if len(kept) < len(g):
                dropped[s] = [list(grp) for grp in g if tuple(sorted(grp)) in bad]
            g = kept
        if g is not None and g:
            stated.append((s, g))
    if o and o.get("pre"):
        stated.append(("own", sorted({tuple(sorted(g)) for g in o["pre"]})))
    if stated:
        # The root that states more IDs wins; a root that states a subset of them agrees
        # (ATT often names one of several race-specific variants Polestar lists).
        def ids(groups):
            return {x for grp in groups for x in grp}

        stated.sort(key=lambda sg: -len(ids(sg[1])))
        v = stated[0][1]
        agree = [s for s, g in stated if ids(g) <= ids(v)]
        state = "secured" if len(agree) == len(stated) else "conflict"
        pre = {"v": [list(g) for g in v], "src": agree, "state": state}
        if state == "conflict":
            pre["alt"] = {s: [list(g) for g in grp] for s, grp in stated if s not in agree}
        if dropped:
            pre["refuted"] = dropped
        return pre
    if dropped:
        return {"v": [], "src": sorted(dropped), "state": "secured", "basis": "check-refuted", "refuted": dropped}
    if o and o.get("basis") == "observed-none":
        return {"v": [], "src": ["own"], "state": "secured", "basis": "observed-none"}
    if not is_new and p is not None:
        return {"v": [], "src": ["polestar"], "state": "secured", "basis": "classic-none"}
    if silent:
        return {"v": [], "src": ["polestar", "att"], "state": "secured", "basis": "two-roots-silent"}
    return {"v": [], "src": [], "state": "unknown"}


def run():
    ps, att, eg = _load("polestar"), _load("att"), _load("eglink")
    own = _load_own()
    check = _load_check()
    findings = _load_findings()
    frames = geo.Frames(read_jsonl(repo_path("data", "sources", "polestar", "ui_map.jsonl")))
    sources = _sources()

    att_breadcrumbs = {q for q, r in att.items() if r.get("breadcrumb")}
    ps_breadcrumb_links = collections.defaultdict(set)
    for q, r in ps.items():
        for b in (r.get("pre") or {}).get("bc", []):
            ps_breadcrumb_links[q].add(b)

    resolver = ZoneResolver(frames)
    for q, r in ps.items():
        if r.get("area") is None:
            continue
        e = eg.get(q)
        for m, _, _ in (e or {}).get("startPos", []):
            resolver.vote(r["area"], m)
        a = att.get(q)
        if a and a.get("zone") and a.get("startPct"):
            resolver.vote(r["area"], a["zone"])

    # How systematically each root states prerequisites of new quests, per 10-level band.
    # Silence of a root only counts as "no prerequisite" in a band where that root states
    # prerequisites for at least SILENCE_COVERAGE of the new quests it lists.
    stated_cov = collections.defaultdict(lambda: [0, 0])
    for q in set(ps) | set(att):
        if not game.is_new_quest(q):
            continue
        lvl = (ps.get(q) or {}).get("level") or (eg.get(q) or {}).get("level") or (att.get(q) or {}).get("min")
        if lvl is None:
            continue
        for s_name, src in (("polestar", ps), ("att", att)):
            if q in src:
                cell = stated_cov[(s_name, _band(lvl))]
                cell[1] += 1
                cell[0] += 1 if src[q].get("pre") else 0

    def silence_counts(lvl):
        return all(
            stated_cov[(s_name, _band(lvl))][1] > 0
            and stated_cov[(s_name, _band(lvl))][0] / stated_cov[(s_name, _band(lvl))][1] >= SILENCE_COVERAGE
            for s_name in ("polestar", "att")
        )

    facts = []
    counts = collections.Counter()
    for q in sorted(set(ps) | set(att) | set(eg)):
        p, a, e = ps.get(q), att.get(q), eg.get(q)
        if a and a.get("removed"):
            counts["removed in ATT"] += 1
            continue
        if not p and not a:
            continue  # EG alone knows only that a quest exists, no route can be built from that
        rec = {"q": q, "new": game.is_new_quest(q), "status": "unbestätigt"}

        # levels
        lv = [(s, r["level"]) for s, r in (("polestar", p), ("eglink", e)) if r and r.get("level") is not None]
        if lv:
            v = lv[0][1]
            rec["level"] = {"v": v, "src": [s for s, x in lv if x == v]}
        mins = []
        if e and e.get("min") is not None:
            mins.append(("eglink", e["min"]))
        if a and a.get("min") is not None:
            mins.append(("att", a["min"]))
        if p and p.get("min") is not None:
            placeholder = p["min"] == 1 and (p.get("level") or 1) > 5
            if not placeholder:
                mins.append(("polestar", p["min"]))
        if mins:
            v = mins[0][1]
            rec["min"] = {"v": v, "src": [s for s, x in mins if x == v]}
        level = rec.get("level", {}).get("v")
        min_level = rec.get("min", {}).get("v")
        if (min_level is not None and min_level > MAX_MIN_LEVEL) or (level is not None and level > MAX_LEVEL):
            continue
        if level is None and min_level is None:
            counts["no level"] += 1
            continue

        # quest XP: only Polestar states it (full reward at the quest level, before the level reduction)
        if p and p.get("xp") is not None:
            rec["xp"] = {"v": p["xp"], "src": ["polestar"]}

        # type, repeatable
        if p and p.get("type") is not None:
            rec["type"] = p["type"]
        if (p and p.get("repeatable")) or (a and a.get("repeatable")):
            rec["repeatable"] = True
        if q in att_breadcrumbs:
            rec["breadcrumb"] = True
        if a and a.get("instance") is not None:
            rec["instance"] = a["instance"]

        # races, classes, side
        race_vals = []
        if p is not None:
            rs = game.races_from_mask(p.get("racesMask", 0))
            race_vals.append(("polestar", None if rs is None else sorted(rs)))
        if a and a.get("races"):
            race_vals.append(("att", a["races"]))
        if e and e.get("racesMask") is not None:
            rs = game.races_from_mask(e["racesMask"])
            race_vals.append(("eglink", None if rs is None else sorted(rs)))
        if race_vals:
            v = race_vals[0][1]
            agree = [s for s, x in race_vals if x == v or (x is None and v is None)]
            rec["races"] = {"v": v, "src": agree}
        class_vals = []
        if p is not None:
            cs = game.classes_from_mask(p.get("classesMask", 0))
            class_vals.append(("polestar", None if cs is None else sorted(cs)))
        if a and a.get("classes"):
            class_vals.append(("att", a["classes"]))
        if class_vals:
            v = class_vals[0][1]
            rec["classes"] = {"v": v, "src": [s for s, x in class_vals if x == v]}
        sides = []
        if p is not None:
            sides.append(("polestar", p["side"]))
        if a and a.get("races"):
            fs = {game.faction_of(r) for r in a["races"]}
            sides.append(("att", "B" if len(fs) == 2 else ("A" if game.ALLIANCE in fs else "H")))
        if e and e.get("factions"):
            fs = set(e["factions"])
            sides.append(("eglink", "B" if len(fs) == 2 else ("A" if game.ALLIANCE in fs else "H")))
        if sides:
            v = sides[0][1]
            agree = [s for s, x in sides if x == v]
            rec["side"] = {"v": v, "src": agree, "roots": _roots(q, agree)}

        # giver, ender
        for field in ("start", "end"):
            vals = [(s, r[field]) for s, r in (("polestar", p), ("att", a), ("eglink", e)) if r and r.get(field)]
            if vals:
                v = vals[0][1]
                key = lambda lst: sorted((x["k"], x["id"]) for x in lst)  # noqa: E731
                agree = [s for s, x in vals if set(key(x)) & set(key(v))]
                rec[field] = {"v": v, "src": agree}
        hints = []
        if a and a.get("zone"):
            hints.append(a["zone"])
        if p and p.get("area") is not None:
            hints.extend(resolver.area_hint(p["area"]))
        cands = _cands(frames, (e or {}).get("startPos"), (p or {}).get("startPos"), _att_world(a, frames))
        pos = _pick_position(q, cands, resolver, hints)
        if pos:
            rec["startPos"] = pos
        zone_hint = [pos["v"][0]] + hints if pos else hints
        cands = _cands(frames, (e or {}).get("endPos"), (p or {}).get("endPos"), None)
        pos = _pick_position(q, cands, resolver, zone_hint)
        if pos:
            rec["endPos"] = pos

        # objectives: items to bring, places to go
        items, objs = [], []
        for o in (p or {}).get("obj", []):
            entry = {"k": o["k"], "n": o["n"], "src": ["polestar"]}
            if "id" in o:
                entry["id"] = o["id"]
            if "count" in o:
                entry["count"] = o["count"]
            if "pos" in o:
                inst, west, north = o["pos"]
                ui_map = resolver.resolve(inst, west, north, zone_hint)
                if ui_map:
                    entry["pos"] = [ui_map, west, north]
            objs.append(entry)
            if o["k"] == "item" and "id" in o:
                items.append({"id": o["id"], "count": o.get("count", 1), "src": ["polestar"]})
        if a and a.get("obj"):
            for ao in a["obj"]:
                for it in ao.get("items", []):
                    hit = next((x for x in items if x["id"] == it), None)
                    if hit:
                        hit["src"].append("att")
                    elif not p:
                        items.append({"id": it, "count": 1, "src": ["att"]})
                if not p and ao.get("pct"):
                    w = _att_world({"startPct": ao["pct"]}, frames)
                    if w:
                        objs.append({"k": "item" if ao.get("items") else "kill", "n": ao.get("n", 1), "pos": w[0], "src": ["att"]})
        if items:
            rec["items"] = items
        if objs:
            rec["obj"] = objs
        starts_item = [s for s in rec.get("start", {}).get("v", []) if s["k"] == "item"]
        if starts_item:
            rec["startItem"] = starts_item[0]["id"]
            # evidence that the starting item drops (Polestar item_source: droppers with spawns)
            if p and p.get("startDrop"):
                rec["startDrop"] = {"v": p["startDrop"], "src": ["polestar"]}

        # prerequisites
        breadcrumbs = att_breadcrumbs | ps_breadcrumb_links.get(q, set())
        o = own.get(q)
        silent = p is not None and a is not None and level is not None and silence_counts(level)
        pre = prereq_state(p, a, o, breadcrumbs, rec["new"], silent, check.get(q))
        pre, held = apply_finding(pre, findings.get(q))
        if held:
            rec["held"] = held
        bc = sorted(breadcrumbs & ({x for r in (p, a) if r for x in (r.get("pre") or {}).get("all", []) + (r.get("pre") or {}).get("any", []) + (r.get("pre") or {}).get("bc", [])}))
        if bc:
            pre["breadcrumbs"] = bc
        if a and a.get("alt"):
            pre["exclusive"] = a["alt"]
        rec["pre"] = pre

        # zone of the quest: giver position, else ATT zone
        zone = rec.get("startPos", {}).get("v", [None])[0] or (a or {}).get("zone")
        if zone:
            rec["zone"] = zone
        facts.append(rec)
        counts["kept"] += 1
        counts["pre " + pre["state"]] += 1

    meta = {
        "license": "GPL-3.0-only",
        "note": "Merged from the sources below; contains Polestar forever-db data (GPL-3.0-only), "
        "EG Link data (CC BY 4.0) and All The Things data (MIT). Every value starts as unbestätigt.",
        "sources": {
            s: {k: v for k, v in m.items() if k in ("name", "repository", "commit", "version", "license")}
            for s, m in sources.items()
        },
        "rules": {
            "agreeYards": AGREE_YARDS,
            "maxMinLevel": MAX_MIN_LEVEL,
            "maxLevel": MAX_LEVEL,
            "silenceCoverage": SILENCE_COVERAGE,
        },
        "prereqCoverageNewQuests": {
            "%s %d-%d" % (s_name, b * 10 + 1, b * 10 + 10): "%d/%d" % tuple(v) for (s_name, b), v in sorted(stated_cov.items())
        },
        "counts": dict(counts),
    }
    dungeons = _dungeons(frames, ps, att, {r["q"] for r in facts})
    finds = _finds(frames)
    times = _times()
    npcs, nodes, edges, model = services.run(frames)
    meta["counts"]["dungeons"] = len(dungeons)
    meta["counts"]["finds"] = len(finds)
    meta["counts"]["timed modules"] = len(times)
    for role in services.ROLES:
        meta["counts"]["npcs " + role] = sum(1 for r in npcs if r["role"]["v"] == role)
    meta["counts"]["flight points"] = len(nodes)
    meta["counts"]["flight legs"] = len(edges)
    meta["counts"]["flight legs measured"] = sum(1 for e in edges if "src" in e.get("seconds", {}))
    meta["flightModel"] = {
        "basis": "model",
        "rule": "seconds = straight distance between the flight points (yards) x secondsPerYard, the median "
        "over the measured legs; replaced by a measured value as soon as one exists",
        "secondsPerYard": model["secondsPerYard"],
        "measuredLegs": model["legs"],
    }
    meta["rules"]["serviceZones"] = sorted(services.SERVICE_ZONES)
    write_json(repo_path("data", "facts", "FACTS.json"), meta)
    write_jsonl(repo_path("data", "facts", "npcs.jsonl"), npcs, key="id")
    write_jsonl(repo_path("data", "facts", "flightnodes.jsonl"), nodes, key="node")
    write_jsonl(repo_path("data", "facts", "flightedges.jsonl"), edges, key="key")
    write_jsonl(repo_path("data", "facts", "quests.jsonl"), facts)
    write_jsonl(repo_path("data", "facts", "dungeons.jsonl"), dungeons, key="id")
    write_jsonl(repo_path("data", "facts", "finds.jsonl"), finds, key="key")
    write_jsonl(repo_path("data", "facts", "times.jsonl"), times, key="module")
    counts["dungeons"], counts["finds"] = len(dungeons), len(finds)
    counts["npcs"], counts["flight points"], counts["flight legs"] = len(npcs), len(nodes), len(edges)
    return dict(counts)


# ATT puts placeholder entrances at the map centre when the entrance is not known yet
# (Hall of Thanes, Ruins of Lordaeron: 50.0, 50.0); those are left out.
PLACEHOLDER_PCT = (50.0, 50.0)
DUNGEON_TYPE = 81


def _dungeons(frames, ps, att, kept):
    """Instances with their quests (ATT instance files, Polestar dungeon quests of the area)."""
    path = repo_path("data", "sources", "att", "dungeons.jsonl")
    if not os.path.exists(path):
        return []
    out = []
    for d in read_jsonl(path):
        if d.get("timeline") and _att_removed(d["timeline"]):
            continue
        from_att = {q for q, r in att.items() if r.get("instance") == d["id"]} & kept
        from_ps = set()
        if d.get("area") is not None:
            from_ps = {q for q, r in ps.items() if r.get("area") == d["area"] and r.get("type") == DUNGEON_TYPE} & kept
        quests = from_att | from_ps
        if not quests:
            continue
        rec = {"id": d["id"], "quests": sorted(quests), "src": ["att"] + (["polestar"] if from_ps else [])}
        for k in ("area", "min"):
            if d.get(k) is not None:
                rec[k] = d[k]
        for ui_map, x, y in d.get("entrancePct", []):
            if (x, y) == PLACEHOLDER_PCT or ui_map in game.CHANGED_FRAMES or ui_map in game.NOT_ZONES:
                continue
            w = frames.to_world(ui_map, x, y)
            if w:
                rec["entrance"] = [ui_map, w[2], w[1]]
                rec["entrancePct"] = [ui_map, round(x * 100), round(y * 100)]
                break
        out.append(rec)
    return out


def _att_removed(timeline):
    return bool(timeline) and timeline[-1].split(" ")[0] in ("removed", "deleted")


def _finds(frames):
    """Discovery catalog from ATT: one record per entry, coordinates in hundredths of a percent
    (0-10000, the unit of the data collector and the in-game exchange)."""
    path = repo_path("data", "sources", "att", "finds.jsonl")
    if not os.path.exists(path):
        return []
    out = []
    for f in read_jsonl(path):
        if f.get("removed"):
            continue
        pts = [[m, round(x * 100), round(y * 100)] for m, x, y in f["pct"] if m not in game.CHANGED_FRAMES and m in frames.by_map]
        if not pts:
            continue
        rec = {"key": f["key"], "type": f["type"], "id": f["id"], "pos": pts, "src": ["att"], "status": "unbestätigt"}
        if f.get("races"):
            fs = {game.faction_of(r) for r in f["races"]}
            if len(fs) == 1:
                rec["side"] = "A" if game.ALLIANCE in fs else "H"
        out.append(rec)
    return out


def _times():
    """Module times from our own measured runs (data/sources/own/times.jsonl, written by observe)."""
    path = repo_path("data", "sources", "own", "times.jsonl")
    return read_jsonl(path) if os.path.exists(path) else []
