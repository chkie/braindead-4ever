# SPDX-License-Identifier: GPL-3.0-or-later
"""Upper bounds of the route data (Welle 6b): what no route can exceed, the measurement behind the
exceptions in data/plan/route-exceptions.toml.

  python3 -m tools.routekit bounds

1. Zone budget (guard P9, decision of 2026-11-02): the core may have as many zone sections as
   the smallest cap of the faction's combinations allows, up to the end level of the RestedXP
   Forever guides (max(RestedXP's sections, the start route's) minus the start zone) and above
   it (the start route's plus limit.p9_sections_extra). XP of every quest that lies inside one core zone
   (giver, objectives, ender; quest level 9 to 31, quest XP + objective kills at the quest's
   level, Forever kill rule) in the richest zones the budget allows, against the XP from the
   arrival window to level 30. Taking every one of these quests is an upper bound no route
   reaches (level windows, quest log, time).
2. Quest XP coverage per band (G3): every quest that can be handed in in the band at full XP
   (quest level from band start - 5 to band end + 2), of the whole faction and of the start zones
   and the zones of 1. only; the share of quest XP when the band's XP is gathered from the quests
   with the highest share of quest XP.
   Objective kills give the rest; with planned levels equal to the real ones a band cannot hold
   more quest XP than this.
"""

import json

from . import build, game, lint, sim, xp
from .io import repo_path


def quest_xp(r):
    return (r.get("xp") or {}).get("v") or 0


def kill_xp(r, ql, params):
    """XP of the objective kills at the quest's level, with the kills on the way (params.toml)."""
    kills = sum((o.get("count") or 1) * (params["item_kills"] if o.get("k") == "item" else 1)
                for o in r.get("obj", []) if o.get("k") in ("kill", "item"))
    return kills * (1 + params["extra_kills"]) * xp.kill_xp(ql, ql)


def zones_of(r):
    zs = {lint.zone_key(r["startPos"]["v"][0]), lint.zone_key(r["endPos"]["v"][0])}
    return zs | {lint.zone_key(o["pos"][0]) for o in r.get("obj", []) if o.get("pos")}


def zone_budget(baseline, races, params):
    """Core zone visits guard P9 allows a faction (speed): (total, end level, up to it, above it).
    The start module is one section (one start zone per race)."""
    from . import metrics

    secs = metrics.load_sections()
    extra = params.lim("p9_sections_extra")
    ends, ca, cb = [], [], []
    for race in races:
        for cls in game.COMBOS[race]:
            label = "%s/%s" % (game.RACES[race][0], game.CLASSES[cls])
            b = baseline["combos"].get("speed/" + label)
            if not b:
                continue
            sa, sb = b["p9_sections"]
            sec = secs.get(label, {})
            ends.append(sec.get("end", 30))
            ca.append(max(sec.get("sections", sa + extra), sa) - 1)
            cb.append(sb + extra)
    return min(ca) + min(cb), min(ends), min(ca), min(cb)


def collect(facts, baseline, plans, params):
    out = {}
    for plan in plans:
        fac = plan["faction"]
        races = game.races_of(fac)
        pool = build.Pool(facts, fac, races, "speed", set())
        starts = {lint.zone_key(z) for st in plan["start"] for z in st["zones"]}
        per_zone = {}
        rows = []
        for r in facts.q.values():
            if not pool.usable(r, True) or (r.get("classes") or {}).get("v") is not None:
                continue
            ql = (r.get("level") or {}).get("v") or (r.get("min") or {}).get("v") or 1
            qx, kx = quest_xp(r), kill_xp(r, ql, params)
            zs = zones_of(r)
            rows.append((ql, qx, kx, zs))
            if 9 <= ql <= 31 and len(zs) == 1:
                z = next(iter(zs))
                if z in starts or z in {1453, 1454, 1455, 1456, 1457, 1458}:
                    continue
                per_zone[z] = per_zone.get(z, 0.0) + qx + kx
        budget, end, cap_a, cap_b = zone_budget(baseline, races, params)
        richest = sorted(per_zone.items(), key=lambda kv: -kv[1])[:budget]
        need = xp.total_to(30) - xp.total_to(11)
        allowed = starts | {z for z, _ in richest}
        bands = {}
        for a, b in ((1, 10), (11, 20), (21, 30)):
            want = sum(xp.to_level(lv) for lv in range(a, min(b, 29) + 1))
            res = {}
            for name, where in (("faction", None), ("budget", allowed)):
                # a quest counts for a band when it can be handed in there at full XP (quest level
                # at least band start - 5) and accepted (quest level at most band end + 2)
                sel = sorted((x for x in rows if a - 5 <= x[0] <= b + 2 and (where is None or x[3] <= where)),
                             key=lambda x: -(x[1] / (x[1] + x[2] + 1e-9)))
                got_q = got = 0.0
                for ql, qx, kx, _ in sel:
                    if got >= want:
                        break
                    got_q += qx
                    got += qx + kx
                res[name] = (round(got_q / want, 3), got >= want)
            bands["%d-%d" % (a, b)] = {"need": want, "faction": res["faction"], "budget": res["budget"]}
        out[fac] = {
            "zone_budget": budget,
            "sections": [end, cap_a, cap_b],
            "richest_zones": [[game.ZONES.get(z, z), round(v)] for z, v in richest],
            "xp_richest": round(sum(v for _, v in richest)),
            "xp_11_to_30": need,
            "bands": bands,
        }
    return out


def main():
    facts = lint.Facts.load()
    with open(repo_path("data", "plan", "metrics-baseline.json"), encoding="utf-8") as fh:
        baseline = json.load(fh)
    res = collect(facts, baseline, build.load_plans(), sim.Params.load())
    for fac, r in res.items():
        end, ca, cb = r["sections"]
        print("%s: Wächter P9 erlaubt dem Kern %d Gebietsabschnitte bis Stufe %d und %d darüber, also höchstens %d Kerngebiete; reichste: %s" % (
            fac, ca, end, cb, r["zone_budget"], ", ".join("%s %d" % (n, v) for n, v in r["richest_zones"])))
        print("  alle Quests dieser Gebiete (Quest- + Ziel-Kill-XP): %d; nötig von Stufe 11 bis 30: %d (%.2f)" % (
            r["xp_richest"], r["xp_11_to_30"], r["xp_richest"] / r["xp_11_to_30"]))
        for band, b in r["bands"].items():
            print("  G3-Schranke %s: höchstens %.3f mit allen Quests der Fraktion, %.3f in Start- und P9-Gebieten%s" % (
                band, b["faction"][0], b["budget"][0], "" if b["budget"][1] else " (Band mit Quests allein nicht zu füllen)"))
    return 0
