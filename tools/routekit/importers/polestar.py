# SPDX-License-Identifier: GPL-3.0-or-later
"""Import from Polestar forever-db (github.com/fitzforge/polestar, folder forever-db).

The tables used here are GPL-3.0-only (datapackage.json). Output goes to
data/sources/polestar/ and keeps that licence. Titles and names are not copied (brain
chapter 16: only IDs and coordinates in the repository, names at runtime from the client).

Service NPCs (npcs.jsonl): class trainers, innkeepers and flight masters, chosen by their title
(`subname`); only the role, the class of a trainer, the faction template, a side derived from it
and the spawn points are kept, never the title or the name.
"""

import collections
import json
import os
import re

from .. import game, geo
from ..io import git_head, write_json, write_jsonl

# Quest band kept for routes 1-30, with a margin for quests just above the band.
MAX_MIN_LEVEL = 30
MAX_LEVEL = 34
MAX_POSITIONS = 6

# Service NPCs by title. The titles are read, never written.
INNKEEPER_TITLES = {"Innkeeper"}
FLIGHT_MASTER_TITLES = {"Gryphon Master", "Wind Rider Master", "Hippogryph Master", "Flight Master", "Bat Handler"}
TRAINER_TITLE = re.compile(r"(Warrior|Paladin|Hunter|Rogue|Priest|Shaman|Mage|Warlock|Druid) Trainer")
CLASS_OF_TITLE = {name.capitalize(): cid for cid, name in game.CLASSES.items()}

# Side of a faction template, derived from the quests the NPCs with that template give and take
# (quest side 1 Alliance, 2 Horde, 0 both). Chosen thresholds, documented in docs/ROUTE-FORMAT.md
# §Service NPCs: one side when at least SIDE_SHARE of the one-faction quests are of that side and
# at least SIDE_MIN of them exist; both sides when both factions have such quests and quests for
# both are at least BOTH_SHARE of all; otherwise no side.
SIDE_SHARE = 0.95
SIDE_MIN = 3
BOTH_SHARE = 0.5


def npc_role(subname):
    """(role, classID) for a title, or (None, None)."""
    s = subname or ""
    if s in INNKEEPER_TITLES:
        return "innkeeper", None
    if s in FLIGHT_MASTER_TITLES:
        return "flightmaster", None
    m = TRAINER_TITLE.fullmatch(s)
    if m:
        return "trainer", CLASS_OF_TITLE[m.group(1)]
    return None, None


def template_sides(votes):
    """{faction_template: Counter(A=, H=, B=)} -> {faction_template: "A" | "H" | "B"}."""
    out = {}
    for ft, c in votes.items():
        a, h, b = c["A"], c["H"], c["B"]
        one = a + h
        if one >= SIDE_MIN and a >= SIDE_SHARE * one:
            out[ft] = "A"
        elif one >= SIDE_MIN and h >= SIDE_SHARE * one:
            out[ft] = "H"
        elif a > 0 and h > 0 and b >= BOTH_SHARE * (one + b):
            out[ft] = "B"
    return out


def _rows(path):
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            if line.strip():
                yield json.loads(line)


def run(src_dir, out_dir):
    db = os.path.join(src_dir, "forever-db")
    data = os.path.join(db, "data")
    with open(os.path.join(db, "index.json"), encoding="utf-8") as fh:
        index = json.load(fh)
    with open(os.path.join(db, "datapackage.json"), encoding="utf-8") as fh:
        package = json.load(fh)
    licences = {r["name"]: r["licenses"][0]["name"] for r in package["resources"]}
    for table in ("quest", "quest_start", "quest_end", "quest_prereq", "quest_objective", "spawn", "ui_map"):
        if licences.get(table) != "GPL-3.0-only":
            raise SystemExit("polestar: unexpected licence for %s: %s" % (table, licences.get(table)))

    ui_rows = [
        {k: r[k] for k in ("ui_map", "map", "top", "bottom", "left", "right")} for r in _rows(os.path.join(data, "ui_map.jsonl"))
    ]

    quests = {}
    for r in _rows(os.path.join(data, "quest.jsonl")):
        level, min_level = r.get("level"), r.get("min_level")
        if min_level is not None and min_level > MAX_MIN_LEVEL:
            continue
        if level is not None and level > MAX_LEVEL:
            continue
        rec = {"q": r["id"], "side": {0: "B", 1: "A", 2: "H"}[r["side"]]}
        for src, dst in (
            ("level", "level"),
            ("min_level", "min"),
            ("races", "racesMask"),
            ("classes", "classesMask"),
            ("type", "type"),
            ("zone_area", "area"),
            ("xp", "xp"),
        ):
            if r.get(src) is not None:
                rec[dst] = r[src]
        if r.get("repeatable"):
            rec["repeatable"] = True
        quests[r["id"]] = rec

    for name, field in (("quest_start", "start"), ("quest_end", "end")):
        for r in _rows(os.path.join(data, name + ".jsonl")):
            q = quests.get(r["quest"])
            if q is not None:
                q.setdefault(field, []).append({"k": r["kind"], "id": r["id"]})

    for r in _rows(os.path.join(data, "quest_prereq.jsonl")):
        q = quests.get(r["quest"])
        if q is None:
            continue
        pre = q.setdefault("pre", {})
        key = "bc" if r.get("breadcrumb") else r["mode"]
        pre.setdefault(key, []).append(r["pre"])

    for r in _rows(os.path.join(data, "quest_objective.jsonl")):
        q = quests.get(r["quest"])
        if q is None:
            continue
        o = {"k": r["kind"], "n": r["n"]}
        if r.get("target") is not None:
            o["id"] = r["target"]
        if r.get("count") is not None:
            o["count"] = r["count"]
        q.setdefault("obj", []).append(o)

    # Which spawns are needed: givers, enders, kill/object targets, droppers of item targets.
    want = collections.defaultdict(set)
    item_targets = set()
    for q in quests.values():
        for s in q.get("start", []) + q.get("end", []):
            if s["k"] in ("npc", "object"):
                want[s["k"]].add(s["id"])
        for o in q.get("obj", []):
            if o["k"] == "kill" and "id" in o:
                want["npc"].add(o["id"])
            elif o["k"] == "object" and "id" in o:
                want["object"].add(o["id"])
            elif o["k"] == "item" and "id" in o:
                item_targets.add(o["id"])
        for s in q.get("start", []):
            if s["k"] == "item":
                item_targets.add(s["id"])
    droppers = collections.defaultdict(list)
    for r in _rows(os.path.join(data, "item_source.jsonl")):
        if r["item"] in item_targets and r["kind"] in ("npc", "object"):
            droppers[r["item"]].append((r.get("chance", 0) or 0, r["kind"], r["id"]))
            want[r["kind"]].add(r["id"])

    spawns = collections.defaultdict(list)
    for r in _rows(os.path.join(data, "spawn.jsonl")):
        if r["id"] in want.get(r["kind"], ()):
            spawns[(r["kind"], r["id"])].append((r["map"], r["x"], r["y"]))

    def positions(kind, ident, limit=MAX_POSITIONS):
        """[[instance, west, north]] in world yards; the zone is resolved in the merge step."""
        return [[inst, round(west, 1), round(north, 1)] for inst, north, west in spawns.get((kind, ident), [])[:limit]]

    def cluster(points):
        """Medoid of the points on the most common instance: one position for an objective area."""
        if not points:
            return None
        inst = collections.Counter(p[0] for p in points).most_common(1)[0][0]
        pts = [(p[2], p[1]) for p in points if p[0] == inst][:200]
        north, west = geo.medoid(pts)
        return [inst, west, north]

    for q in quests.values():
        for field, pfield in (("start", "startPos"), ("end", "endPos")):
            pos = []
            for s in q.get(field, []):
                if s["k"] in ("npc", "object"):
                    pos.extend(positions(s["k"], s["id"]))
            if pos:
                q[pfield] = pos[:MAX_POSITIONS]
        # A quest started by an item: where the item drops (table item_source, the five droppers
        # with the highest chance, their spawns), one position for the area as for an item
        # objective. `startDrop` records that a dropper with spawns exists (the evidence the
        # route builder needs); without one the quest keeps no start position.
        items = [s["id"] for s in q.get("start", []) if s["k"] == "item"]
        if items and "startPos" not in q:
            pts, n = [], 0
            for _, kind, ident in sorted(droppers.get(items[0], []), reverse=True)[:5]:
                found = positions(kind, ident, limit=200)
                if found:
                    n += 1
                    pts.extend(found)
            c = cluster(pts)
            if c:
                q["startPos"] = [c]
                q["startDrop"] = n
        for o in q.get("obj", []):
            pts = []
            if o["k"] in ("kill", "object") and "id" in o:
                pts = positions("npc" if o["k"] == "kill" else "object", o["id"], limit=200)
            elif o["k"] == "item" and "id" in o:
                for _, kind, ident in sorted(droppers.get(o["id"], []), reverse=True)[:5]:
                    pts.extend(positions(kind, ident, limit=200))
            c = cluster(pts)
            if c:
                o["pos"] = c

    npcs = _npcs(data)

    commit, date = git_head(src_dir)
    write_json(
        os.path.join(out_dir, "SOURCE.json"),
        {
            "source": "polestar",
            "name": "Polestar forever-db",
            "repository": "https://github.com/fitzforge/polestar/tree/next/forever-db",
            "commit": commit,
            "commitDate": date,
            "version": index["version"],
            "clientBuild": index["clientBuild"],
            "license": "GPL-3.0-only",
            "files": ["quests.jsonl", "ui_map.jsonl", "npcs.jsonl"],
            "selection": "quests with min_level <= %d and level <= %d; tables quest, quest_start, quest_end, "
            "quest_prereq, quest_objective, spawn, item_source, ui_map; no titles or names. Service NPCs from "
            "tables npc and spawn: class trainers, innkeepers and flight masters chosen by title, with role, "
            "class, faction template, a side derived from the sides of the quests NPCs with the same template "
            "give and take, and spawn points; no titles or names" % (MAX_MIN_LEVEL, MAX_LEVEL),
            "status": "unbestätigt",
        },
    )
    write_jsonl(os.path.join(out_dir, "ui_map.jsonl"), ui_rows, key="ui_map")
    n = write_jsonl(os.path.join(out_dir, "quests.jsonl"), quests.values())
    write_jsonl(os.path.join(out_dir, "npcs.jsonl"), npcs, key="id")
    return {
        "quests": n,
        "ui_maps": len(ui_rows),
        "npcs": dict(collections.Counter(r["role"] for r in npcs)),
        "commit": commit[:7],
        "version": index["version"],
    }


def _npcs(data):
    """Class trainers, innkeepers and flight masters: [{id, role, class?, ft?, side?, pos}] with
    pos [[instance, west, north], ...] in world yards (the zone is resolved in the merge step)."""
    npc_rows = {r["id"]: r for r in _rows(os.path.join(data, "npc.jsonl"))}
    side_of_quest = {r["id"]: {0: "B", 1: "A", 2: "H"}[r["side"]] for r in _rows(os.path.join(data, "quest.jsonl"))}
    votes = collections.defaultdict(collections.Counter)
    for name in ("quest_start", "quest_end"):
        for r in _rows(os.path.join(data, name + ".jsonl")):
            n = npc_rows.get(r["id"]) if r["kind"] == "npc" else None
            if n and n.get("faction_template") is not None and r["quest"] in side_of_quest:
                votes[n["faction_template"]][side_of_quest[r["quest"]]] += 1
    sides = template_sides(votes)

    out = {}
    for ident, r in npc_rows.items():
        role, cls = npc_role(r.get("subname"))
        if role is None:
            continue
        rec = {"id": ident, "role": role, "pos": []}
        if cls is not None:
            rec["class"] = cls
        ft = r.get("faction_template")
        if ft is not None:
            rec["ft"] = ft
            if ft in sides:
                rec["side"] = sides[ft]
        out[ident] = rec
    for r in _rows(os.path.join(data, "spawn.jsonl")):
        rec = out.get(r["id"]) if r["kind"] == "npc" else None
        if rec is not None and len(rec["pos"]) < MAX_POSITIONS:
            rec["pos"].append([r["map"], round(r["y"], 1), round(r["x"], 1)])
    return [r for r in out.values() if r["pos"]]
