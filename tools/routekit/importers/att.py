# SPDX-License-Identifier: GPL-3.0-or-later
"""Import from All The Things, Forever database (github.com/ATTWoWAddon/AllTheThings, MIT).

The Lua source files in .contrib/.db/forever/zones and .contrib/.db/forever/dungeons & raids
are evaluated in a Lua 5.1 sandbox (att_dump.lua). Kept: quest ID, giver IDs, coordinates in
map percent, prerequisites, races, classes, required level, breadcrumb and repeatable flags,
objective providers, the instance a dungeon quest belongs to; instances (area, entrance,
minimum level); the discovery catalog (treasures, books, rares, flight paths with coordinates).
Not kept: names, comments, descriptions.
"""

import json
import os
import subprocess

from .. import game
from ..io import git_head, write_json, write_jsonl

HERE = os.path.dirname(os.path.abspath(__file__))
REMOVED_PREFIXES = ("removed", "deleted")


def _removed(timeline):
    """ATT timeline strings: the last entry decides ('added …', 'removed …')."""
    if not timeline:
        return False
    return timeline[-1].split(" ")[0] in REMOVED_PREFIXES


def run(src_dir, out_dir, lua):
    db = os.path.join(src_dir, ".contrib", ".db")
    proc = subprocess.run([lua, os.path.join(HERE, "att_dump.lua"), db], capture_output=True, text=True)
    if proc.returncode != 0:
        raise SystemExit("att_dump failed (%d): %s" % (proc.returncode, proc.stderr.strip()))
    records, dungeons, finds = [], [], []
    for line in proc.stdout.splitlines():
        r = json.loads(line)
        if r.get("kind") == "dungeon":
            d = {"id": r["id"]}
            for src, dst in (("area", "area"), ("mapID", "mapID"), ("lvl", "min")):
                if r.get(src) is not None:
                    d[dst] = r[src]
            if r.get("coords"):
                d["entrancePct"] = [[c[2], round(c[0], 2), round(c[1], 2)] for c in r["coords"]]
            if r.get("timeline"):
                d["timeline"] = r["timeline"]
            dungeons.append(d)
            continue
        if r.get("kind") == "find":
            f = {"type": r["type"], "id": r["id"], "pct": [[c[2], round(c[0], 2), round(c[1], 2)] for c in r["coords"]]}
            if r.get("zoneMap"):
                f["zone"] = r["zoneMap"]
            if r.get("races"):
                f["races"] = sorted(x for x in r["races"] if x in game.RACES)
            if _removed(r.get("timeline")):
                f["removed"] = True
            first = f["pct"][0]
            f["key"] = "%s-%d-%d-%d-%d" % (f["type"], f["id"], first[0], round(first[1] * 100), round(first[2] * 100))
            if any(x["key"] == f["key"] for x in finds):
                continue  # the same entry listed twice
            finds.append(f)
            continue
        rec = {"q": r["q"]}
        if r.get("instance") is not None:
            rec["instance"] = r["instance"]
        if r.get("zoneMap"):
            rec["zone"] = r["zoneMap"]
        if r.get("side"):
            rec["side"] = r["side"][0]
        if r.get("races"):
            races = sorted(x for x in r["races"] if x in game.RACES)
            rec["races"] = races
        if r.get("classes"):
            rec["classes"] = sorted(x for x in r["classes"] if x in game.CLASSES)
        if r.get("lvl") is not None:
            rec["min"] = r["lvl"]
        if r.get("qg"):
            rec["start"] = [{"k": "npc", "id": i} for i in r["qg"]]
        if r.get("providers"):
            kinds = {"n": "npc", "o": "object", "i": "item"}
            rec.setdefault("start", []).extend(
                {"k": kinds.get(p[0], p[0]), "id": p[1]} for p in r["providers"] if p[0] in kinds
            )
        if r.get("coords"):
            rec["startPct"] = [[c[2], round(c[0], 2), round(c[1], 2)] for c in r["coords"]]
        if r.get("sourceQuests"):
            rec["pre"] = {"all": r["sourceQuests"]}
        if r.get("altQuests"):
            rec["alt"] = r["altQuests"]
        if r.get("breadcrumb"):
            rec["breadcrumb"] = True
        if r.get("repeatable"):
            rec["repeatable"] = True
        if _removed(r.get("timeline")):
            rec["removed"] = True
        if r.get("timeline"):
            rec["timeline"] = r["timeline"]
        objs = []
        for o in r.get("objectives") or []:
            oo = {}
            if o.get("n") is not None:
                oo["n"] = o["n"]
            items = [p[1] for p in (o.get("providers") or []) if p[0] == "i"]
            if items:
                oo["items"] = items
            if o.get("cr"):
                oo["npcs"] = o["cr"]
            if o.get("coords"):
                oo["pct"] = [[c[2], round(c[0], 2), round(c[1], 2)] for c in o["coords"]]
            if oo:
                objs.append(oo)
        if objs:
            rec["obj"] = objs
        records.append(rec)

    commit, date = git_head(src_dir)
    write_json(
        os.path.join(out_dir, "SOURCE.json"),
        {
            "source": "att",
            "name": "All The Things, Forever database",
            "repository": "https://github.com/ATTWoWAddon/AllTheThings/tree/master/.contrib/.db/forever",
            "commit": commit,
            "commitDate": date,
            "license": "MIT",
            "copyright": "Copyright (c) 2026 AllTheThings WoW Addon (MIT License, LICENSE in the source repository)",
            "files": ["quests.jsonl", "dungeons.jsonl", "finds.jsonl"],
            "selection": "every q() entry under .contrib/.db/forever/zones and .contrib/.db/forever/dungeons & raids, "
            "instanceroot() entries, o()/n()/fp() entries under the TREASURES, RARES and FLIGHT_PATHS headers of "
            "the zone files (book: an object holding an item of a library book quest), evaluated in a Lua 5.1 "
            "sandbox; coordinates in map percent (x, y on uiMap); no names or comments",
            "status": "unbestätigt",
        },
    )
    n = write_jsonl(os.path.join(out_dir, "quests.jsonl"), records)
    write_jsonl(os.path.join(out_dir, "dungeons.jsonl"), dungeons, key="id")
    write_jsonl(os.path.join(out_dir, "finds.jsonl"), finds, key="key")
    return {"quests": n, "dungeons": len(dungeons), "finds": len(finds), "commit": commit[:7], "stderr": proc.stderr.strip()}
