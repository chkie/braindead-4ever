# SPDX-License-Identifier: GPL-3.0-or-later
"""Import from EG Link output for WoW: Forever (github.com/JIVESCORP/eg-link-output-wowf).

Data from Efficient Games (https://efficient.games), licensed under CC BY 4.0. Changes made
here: reduced to quest facts (who gives and takes a quest, where players stood, which faction
the server describes a quest for, levels and race mask from the server cache), merged over all
builds of the products wow_classic_beta and wowf. No game text is copied (no titles, no names,
no quest text): the README grants no rights in Blizzard's content.
"""

import collections
import glob
import json
import os

from ..io import git_head, write_json, write_jsonl

MAX_POSITIONS = 6


def _load(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def _pos(p):
    """EG position -> [uiMap, west, north] (worldX is the north axis, worldY the west axis)."""
    if not p.get("uiMap") or p.get("worldX") is None or p.get("worldY") is None:
        return None
    return [p["uiMap"], round(p["worldY"], 1), round(p["worldX"], 1)]


def run(src_dir, out_dir):
    files = sorted(glob.glob(os.path.join(src_dir, "data", "*", "*", "*.json")))
    quests = collections.defaultdict(dict)
    builds = set()
    starts = {}

    def add_pos(q, field, positions, sources):
        rec = quests[q]
        lst = rec.setdefault(field, [])
        for p in positions:
            pp = _pos(p)
            if pp and pp not in lst and len(lst) < MAX_POSITIONS:
                lst.append(pp)
        key = field.replace("Pos", "Sources")
        rec[key] = max(rec.get(key, 0), sources or 0)

    for path in files:
        product = os.path.basename(os.path.dirname(os.path.dirname(path)))
        build = os.path.basename(os.path.dirname(path))
        name = os.path.basename(path)
        if product not in ("wow_classic_beta", "wowf"):
            continue
        if name not in ("npcs.json", "quest_scan.json", "quests.enUS.json", "game_rules.json"):
            continue
        builds.add(product + "/" + build)
        d = _load(path)
        if d.get("meta", {}).get("license") != "CC BY 4.0":
            raise SystemExit("eglink: unexpected licence in " + path)
        if name == "npcs.json":
            for kind, coll in (("npc", d.get("npcs", {})), ("object", d.get("objects", {}))):
                for ident, n in coll.items():
                    for qid in n.get("offers", {}):
                        q = int(qid)
                        g = quests[q].setdefault("start", [])
                        if {"k": kind, "id": int(ident)} not in g:
                            g.append({"k": kind, "id": int(ident)})
                        add_pos(q, "startPos", n.get("positions", []), n.get("sources"))
                    for qid in n.get("takes", {}):
                        q = int(qid)
                        g = quests[q].setdefault("end", [])
                        if {"k": kind, "id": int(ident)} not in g:
                            g.append({"k": kind, "id": int(ident)})
                        add_pos(q, "endPos", n.get("positions", []), n.get("sources"))
        elif name == "quest_scan.json":
            for qid, r in d.get("described", {}).items():
                f = quests[int(qid)].setdefault("factions", {})
                for side, cnt in r.get("factions", {}).items():
                    f[side] = f.get(side, 0) + cnt
        elif name == "quests.enUS.json":
            for qid, r in d.get("quests", {}).items():
                rec = quests[int(qid)]
                for src, dst in (("level", "level"), ("minLevel", "min")):
                    if r.get(src) is not None:
                        rec[dst] = r[src]
                if r.get("raceMask"):
                    mask = int(r["raceMask"], 16)
                    rec["racesMask"] = 0 if mask == 0xFFFFFFFFFFFFFFFF else mask
        elif name == "game_rules.json":
            for key, r in d.get("starts", {}).items():
                s = starts.setdefault(key, {"positions": [], "count": 0})
                s["count"] += r.get("count", 0)
                for p in r.get("positions", []):
                    pp = _pos(p)
                    if pp and pp not in s["positions"]:
                        s["positions"].append(pp)

    records = []
    for q, rec in quests.items():
        rec["q"] = q
        records.append(rec)
    start_rows = []
    for key, s in starts.items():
        race_token, faction, class_token = key.split("|")
        start_rows.append(
            {"key": key, "race": race_token, "faction": faction, "class": class_token, "count": s["count"], "positions": s["positions"][:MAX_POSITIONS]}
        )

    commit, date = git_head(src_dir)
    write_json(
        os.path.join(out_dir, "SOURCE.json"),
        {
            "source": "eglink",
            "name": "EG Link output: World of Warcraft: Forever",
            "repository": "https://github.com/JIVESCORP/eg-link-output-wowf",
            "commit": commit,
            "commitDate": date,
            "builds": sorted(builds),
            "license": "CC-BY-4.0",
            "attribution": "Data from Efficient Games (https://efficient.games), licensed under CC BY 4.0 "
            "(https://creativecommons.org/licenses/by/4.0/). Changed: reduced to quest facts and start positions, "
            "merged over builds, coordinates reordered.",
            "files": ["quests.jsonl", "starts.jsonl"],
            "status": "unbestätigt",
        },
    )
    n = write_jsonl(os.path.join(out_dir, "quests.jsonl"), records)
    write_jsonl(os.path.join(out_dir, "starts.jsonl"), start_rows, key="key")
    return {"quests": n, "starts": len(start_rows), "builds": len(builds), "commit": commit[:7]}

