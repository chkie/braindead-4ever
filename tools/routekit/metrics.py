# SPDX-License-Identifier: GPL-3.0-or-later
"""Route metrics (Welle 6a): P1-P11 (DR 22c §F), G1-G12 (DR 22d) and the rules of the DR 22a
catalogue that can be checked on a route, for every combination in both modes.

  python3 -m tools.routekit metrics [--json PATH] [--md PATH] [--summary PATH] [--write-baseline]

Every figure comes from the simulator (tools/routekit/sim.py) and is a model figure: times are
Modellstunden (model hours), not a forecast of real play time. Limits and distances come from data/plan/params.toml
(`limit.*`), each with its source; most are chosen start values (DR 22c/22d) that Welle 6b
calibrates. In Welle 6a the report only reports: nothing here fails the build.

Level bands (G3-G6): 1-10, 11-20, 21-30 by the planned level of the step (`lv`). The XP of a band
is the XP to level through it: levels 1..10, 11..20 and 21..29 (the route ends on reaching 30).

Comparisons "not worse than the start" (P3, P4, P5, P9, P11) read data/plan/metrics-baseline.json,
written with --write-baseline. It stores counters, not hours, so a changed parameter prices the
start route and the new route alike.
"""

import json
import math
import random
import statistics

from . import build, game, geo, lint, routefmt, sim, xp
from .io import read_jsonl, repo_path

BANDS = ((1, 10), (11, 20), (21, 30))
CAPITALS = {1453, 1454, 1455, 1456, 1457, 1458}
SAME_NPC = build.SAME_SPOT  # yards: two actions this close are at the same NPC (as the builder)
BASELINE_PATH = repo_path("data", "plan", "metrics-baseline.json")
SECTIONS_PATH = repo_path("data", "plan", "zone-sections.toml")
DRAWN = ("detour_eastern_kingdoms", "detour_kalimdor", "detour_other", "flight_overhead_sec", "kill_sec_1",
         "kill_sec_60", "talk_sec", "interact_sec", "escort_sec", "level_overhead_sec", "grind_eff")

# Rules of DR 22a that cannot be checked on the route data today, with the reason.
NOT_CHECKABLE = {
    "R03": "Eigenschaft des Codes, nicht der Route: xp.py und XP.lua rechnen den Questwert aus dem Stufenabstand",
    "R08": "Wegverlängerung durch Kill-Abschnitte: die Daten haben keine Wege der Kills",
    "R14": "Flug gegen Fußweg: data/facts hat kein Flugnetz (TaxiPathNode)",
    "R15": "Klassenreisemittel: keine Teleport-Daten je Klasse",
    "R16": "Tod als Reise: das Routenformat hat keinen solchen Schritt",
    "R24": "Pflichtliste der Klassenquests je Klasse fehlt",
    "R25": "Lehrer im Stufenfenster: die Routen haben keine train-Schritte",
    "R29": "begründete Verzweigung: Strukturfrage des Baukastens (Welle 6b); alle Kombinationen werden simuliert",
    "R32": "Ende bei Stufe 60: die Routen enden bei 30",
    "R34": "Buff-Hinweise: die Routen haben keine",
    "R35": "Looten: Hinweistext, keine Routeneigenschaft",
}


def label_of(run):
    return "%s/%s/%s" % (run.mode, game.RACES[run.race][0], game.CLASSES[run.cls])


def combo_of(run):
    return "%s %s" % (game.RACES[run.race][0], game.CLASSES[run.cls])


def band_of(level):
    for a, b in BANDS:
        if a <= level <= b:
            return "%d-%d" % (a, b)
    return None


def band_need(a, b, target):
    return sum(xp.to_level(lv) or 0 for lv in range(a, min(b, target - 1) + 1))


class Grid:
    """Points per instance in square cells, for "what lies within r yards"."""

    def __init__(self, cell):
        self.cell = cell
        self.cells = {}

    def _key(self, inst, north, west):
        return inst, math.floor(north / self.cell), math.floor(west / self.cell)

    def add(self, pos, item):
        self.cells.setdefault(self._key(*pos), []).append((pos, item))

    def near(self, pos, r):
        inst, cn, cw = self._key(*pos)
        span = int(math.ceil(r / self.cell))
        out = []
        for dn in range(-span, span + 1):
            for dw in range(-span, span + 1):
                for p, item in self.cells.get((inst, cn + dn, cw + dw), ()):
                    if geo.dist(p[1:], pos[1:]) <= r:
                        out.append((p, item))
        return out


def samples(leg, step):
    """Points along a walked leg every `step` yards, both ends included."""
    frm, to = leg["frm"], leg["to"]
    n = max(1, int(leg["yd"] // step))
    return [(frm[0], frm[1] + (to[1] - frm[1]) * i / n, frm[2] + (to[2] - frm[2]) * i / n) for i in range(n + 1)]


class Context:
    def __init__(self, facts, mods, comps, params, detail=False):
        self.f, self.mods, self.comps, self.p = facts, mods, comps, params
        self.detail = detail  # the optimizer's repair rounds read what broke a rule (row["detail"])
        self.followups = {}  # q -> quests whose prerequisite groups name q
        for r in facts.q.values():
            for group in r.get("pre", {}).get("v", []) or []:
                for g in group:
                    self.followups.setdefault(g, []).append(r["q"])
        self.module_errs = {key: lint.lint_module(m, facts) for key, m in sorted(mods.items())}
        self.sections = load_sections()
        self.flight_masters = []
        for rec in read_jsonl(repo_path("data", "facts", "finds.jsonl")):
            if rec.get("type") != "flightpath":
                continue
            for m, x, y in rec.get("pos", []):
                if m in game.CHANGED_FRAMES:  # map percent is not valid there (docs/ROUTE-FORMAT.md, merge rule 2)
                    continue
                w = facts.frames.to_world(m, x / 100.0, y / 100.0)
                if w:
                    self.flight_masters.append((rec["id"], rec.get("side"), w))

    def eligible_pool(self, faction, mode, race, cls):
        pool = build.Pool(self.f, faction, [race], mode, set())
        out = []
        for q in sorted(self.f.q):
            r = self.f.q[q]
            if not pool.usable(r, True):
                continue
            qc = r.get("classes", {}).get("v")
            if qc is not None and cls not in qc:
                continue
            if not ((r.get("xp") or {}).get("v") or 0) > 0:
                continue
            out.append(r)
        return out

    def world(self, posv):
        inst = self.f.frames.instance(posv[0])
        return (inst if inst is not None else -1, posv[2], posv[1])


def load_sections(path=None):
    """data/plan/zone-sections.toml: zone sections of RestedXP Forever per combination (guard P9)."""
    import tomllib

    try:
        with open(path or SECTIONS_PATH, "rb") as fh:
            return tomllib.load(fh).get("combo", {})
    except FileNotFoundError:
        return {}


def _qlevel(r):
    return (r.get("level") or {}).get("v")


def _min(r):
    return (r.get("min") or {}).get("v") or 1


def _pre_ok(r, run, idx):
    pre = r.get("pre", {})
    if pre.get("state") not in ("secured", "conflict"):
        return True
    for group in pre.get("v", []):
        if not any(run.quest.get(g, {}).get("t", 1 << 30) < idx for g in group):
            return False
    return True


def _available(r, run, idx, level, log, log_limit):
    """Could the character take quest r at action idx (level, prerequisites, not taken, log)?"""
    q = r["q"]
    if run.quest.get(q, {}).get("a", 1 << 30) < idx:
        return False
    ql = _qlevel(r) or _min(r)
    if _min(r) > level or ql > level + lint.LEVEL_ABOVE or level > ql + 5:
        return False
    if log >= log_limit:
        return False
    return _pre_ok(r, run, idx)


def _left(run, i0, i1, pos, r):
    """Did the character go more than r yards from pos (or to another instance) between actions i0 and i1?"""
    for a in run.actions[i0:i1]:
        p = a["pos"]
        if p is None:
            continue
        if p[0] != pos[0] or geo.dist(p[1:], pos[1:]) > r:
            return True
    return False


def evaluate(ctx, run):
    """All per-combination figures of one simulated route."""
    p, f = ctx.p, ctx.f
    cf = p["class_factor"][game.CLASSES[run.cls]]
    faction = game.faction_of(run.race)
    row = {"label": label_of(run), "mode": run.mode, "faction": faction, "race": game.RACES[run.race][0],
           "class": game.CLASSES[run.cls], "combo": combo_of(run)}
    target = run.target
    h = {lv: run.reached[lv] / 3600.0 for lv in (10, 20, 30) if lv in run.reached}
    row["h10"], row["h20"], row["h30"] = h.get(10), h.get(20), h.get(30)
    # model hours per level band 1-10, 11-20, 21-30 (the band ends where the next one begins)
    ends = {"1-10": (1, 11), "11-20": (11, 21), "21-30": (21, 30)}
    row["band_h"] = {k: (run.reached[b] - run.reached[a]) / 3600.0 for k, (a, b) in ends.items()
                     if a in run.reached and b in run.reached}
    row["xph_1_20"] = xp.total_to(20) / h[20] if h.get(20) else None
    acts = run.actions
    det = {}
    step_of = [(a["module"], a["step"]) for a in acts]
    rf = {q: (f.q.get(q) or {}) for q in run.quest}

    # P2: coverage per start and core module, grind share per level
    mods = []
    for m in run.modules:
        if m["kind"] not in ("start", "core") or not m["levels"]:
            continue
        need = band_need(m["levels"][0], m["levels"][1] - 1, target + 1)
        if need > 0:
            mods.append((m["key"], (m["quest_xp"] + m["kill_xp"]) / need, m["quest_xp"] / need))
    worst = min(mods, key=lambda x: (x[1], x[0])) if mods else (None, None, None)
    row["p2_modules"] = [[k, round(c, 4), round(qc, 4)] for k, c, qc in mods]
    row["p2_min_cov"], row["p2_min_module"] = worst[1], worst[0]
    shares = [(run.level_grind.get(lv, 0.0) / t, lv) for lv, t in sorted(run.level_time.items()) if lv < target and t > 0]
    gmax = max(shares) if shares else (0.0, None)
    row["p2_grind_max"], row["p2_grind_level"] = gmax[0], gmax[1]
    row["p2_levels_over"] = sum(1 for s, _ in shares if s > p.lim("p2_grind_share"))
    row["grind_h"] = sum(g["sec"] for g in run.gates) / 3600.0

    # P3/P11: model hours 1-30 from the counters at level 30
    c30 = run.counters_at.get(30)
    row["counters30"] = {k: round(v, 6) for k, v in c30.items()} if c30 else None
    slow, fast = p["class_factor"]["WARRIOR"], p["class_factor"]["HUNTER"]
    # from the stored (rounded) counters, so a comparison with the baseline compares like with like
    row["p11_slow"] = sim.time_from(row["counters30"], p, slow) / 3600.0 if c30 else None
    row["p11_fast"] = sim.time_from(row["counters30"], p, fast) / 3600.0 if c30 else None

    # P4: legs; long legs for one quest at less than half the route's XP rate
    walks = [g for g in run.legs if g["kind"] == "walk"]
    row["p4_longest_yd"] = max((g["yd"] for g in walks), default=0.0)
    same_zone = [g for g in walks if None not in g["maps"] and lint.zone_key(g["maps"][0]) == lint.zone_key(g["maps"][1])]
    longest = max(same_zone, key=lambda g: g["yd"], default=None)
    row["p4_longest_zone_yd"] = longest["yd"] if longest else 0.0
    row["p4_longest_zone_at"] = acts[longest["action"]]["module"] if longest else None
    rate = xp.total_to(30) / run.reached[30] if 30 in run.reached else 0.0
    quests_of_step = {}
    for a in acts:
        if a["q"] is not None:
            quests_of_step.setdefault((a["module"], a["step"]), set()).add(a["q"])
    single = {}
    # a leg into another zone is the route's travel (with its own travel step), not a trip for the
    # quest of the step it ends at; P4 counts legs inside one zone (as P4yd)
    for g in same_zone:
        if g["action"] >= len(acts):
            continue
        qs = quests_of_step.get(step_of[g["action"]], set())
        if len(qs) == 1:
            single.setdefault(next(iter(qs)), []).append(g)
    long_legs = []
    for q, legs in sorted(single.items()):
        info = run.quest.get(q, {})
        value = (info.get("xp_t") or 0) + (info.get("kill_xp") or 0)
        sec = sum(g["sec"] for g in legs)
        for g in legs:
            if g["sec"] > p.lim("p4_leg_sec") and value / sec < 0.5 * rate:
                long_legs.append((q, round(g["yd"]), round(g["sec"])))
    row["p4_long"] = len(long_legs)
    row["p4_long_legs"] = long_legs[:10]

    # P5: avoidable returns (a visit ends 400 yd away; work on a later visit that was possible last time)
    visit_r = p.lim("p5_visit_yd")
    grid = Grid(visit_r)
    posacts = [i for i, a in enumerate(acts) if a["pos"] is not None]
    visits_back = {}  # rank where the current visit began -> [(action, last earlier action near it)]
    for n, i in enumerate(posacts):
        pos = acts[i]["pos"]
        near = sorted(rank for _, rank in grid.near(pos, visit_r))
        grid.add(pos, n)
        # walk back over the positioned actions before this one: the first one that is not near
        # (farther than 400 yd or on another instance) ends the current visit
        k, expected = len(near) - 1, n - 1
        while k >= 0 and near[k] == expected:
            k -= 1
            expected -= 1
        if k < 0:
            continue  # first visit to this place
        visits_back.setdefault(expected + 1, []).append((i, posacts[near[k]]))
    returns, wasted = 0, 0
    for start, items in sorted(visits_back.items()):
        verdicts, services, possible = [], False, []
        for i, j in items:
            a = acts[i]
            if a["verb"] in ("train", "fp", "sethome", "hs"):
                services = True
            if a["verb"] not in ("accept", "complete", "turnin"):
                continue
            q, info = a["q"], run.quest.get(a["q"], {})
            if a["verb"] == "accept":
                ok = _available(rf[q], run, j + 1, acts[j]["level"], acts[j]["log"], p["quest_log_work"])
            elif a["verb"] == "complete":
                ok = info.get("a", 1 << 30) <= j
            else:
                done = info.get("c") if rf[q].get("obj") else info.get("a")
                ok = done is not None and done <= j
            verdicts.append(ok)
            if ok:
                possible.append((i, j))
        if any(verdicts):
            returns += 1
            if ctx.detail:
                det.setdefault("p5_returns", []).append(possible)
            if all(verdicts) and not services:
                wasted += 1
                if ctx.detail:
                    det.setdefault("p5_wasted", []).append([(i, j) for i, j in items])
    row["p5_returns"], row["p5_wasted"] = returns, wasted

    # P6, R06, R13, R18: along the walked line
    pool = ctx.eligible_pool(faction, run.mode, run.race, run.cls)
    givers = Grid(p.lim("p6_passed_yd"))
    for r in pool:
        if r.get("startPos"):
            givers.add(ctx.world(r["startPos"]["v"]), r["q"])
    objectives = Grid(p.lim("r06_objective_yd"))
    for q in sorted(run.quest):
        for o in rf[q].get("obj", []):
            if o.get("pos"):
                objectives.add(ctx.world(o["pos"]), q)
    fms = Grid(100.0)
    for fid, side, w in ctx.flight_masters:
        if side in (None, faction[0]):
            fms.add(w, fid)
    learned = [pos for _, pos in run.fps if pos is not None]
    by_q = {r["q"]: r for r in pool}
    passed, obj_passed, fm_passed = {}, {}, set()
    step_len = p.lim("p6_sample_yd")
    line = Grid(250.0)  # every sampled point of the walked line, for the detour of a quest
    for g in walks:
        i = g["action"]
        if i >= len(acts):
            continue
        a = acts[i]
        for s in samples(g, step_len):
            line.add(s, i)
            for gp, q in givers.near(s, p.lim("p6_passed_yd")):
                if q in passed:
                    continue
                if _available(by_q[q], run, i, a["level"], a["log"], p["quest_log_work"]):
                    passed[q] = (i, gp)
            for op, q in objectives.near(s, p.lim("r06_objective_yd")):
                info = run.quest.get(q, {})
                if q in obj_passed or not (info.get("a", 1 << 30) < i < info.get("c", -1)):
                    continue
                obj_passed[q] = (i, op)
            for fp_pos, fid in fms.near(s, p.lim("r13_flight_master_yd")):
                if not any(lp[0] == fp_pos[0] and geo.dist(lp[1:], fp_pos[1:]) <= p.lim("r13_flight_master_yd") for lp in learned):
                    if fid not in fm_passed and ctx.detail:
                        det.setdefault("r13", []).append((fid, i))
                    fm_passed.add(fid)
    # P6 counts quests the route could take where it passes the giver (DR 22c §5, brain chapter 21
    # P6 "lohnende passierte Quest"): the giver stands in the zone the character is in, and every
    # zone of the quest (giver, objectives, ender) is still ahead on the route. A quest that needs
    # a zone the route does not visit again would cost an extra zone change (guard P9); it is
    # reported as P6z.
    ahead = [set() for _ in range(len(acts) + 1)]
    for k in range(len(acts) - 1, -1, -1):
        ahead[k] = ahead[k + 1] | ({lint.zone_key(acts[k]["zone"])} if acts[k]["zone"] is not None else set())

    def off_line(pos, i):
        """Distance from pos to the walked line from action i on (yards; 1e9 if not near)."""
        for radius in (250.0, 750.0, 2000.0):
            near = [geo.dist(lp[1:], pos[1:]) for lp, k in line.near(pos, radius) if k >= i and lp[0] == pos[0]]
            if near:
                return min(near)
        return 1e9

    cf_kill = cf
    rate_s = (xp.total_to(30) / run.reached[30]) if 30 in run.reached else 0.0

    def worth(r, i, level):
        """DR 22c §4.3 / brain chapter 21 §4.3 "lohnende Mitnahme": the quest's XP per second of
        extra time (detours from the walked line to giver, objectives and ender and back, two
        talks, the objectives' work) is at least the route's XP rate, or half of it when the
        detour takes less than 60 s. Returns (worth it, extra seconds)."""
        pts = [ctx.world(r["startPos"]["v"]), ctx.world(r["endPos"]["v"])]
        pts += [ctx.world(o["pos"]) for o in r.get("obj", []) if o.get("pos")]
        walk = 0.0
        for pt in pts:
            d = off_line(pt, i)
            if d >= 1e9:
                return False, 1e9
            walk += 2 * d
        walk_s = walk * sim.instance_detour(pts[0][0], p) / p["run_speed"]
        ql = _qlevel(r) or level
        work = 2 * p["talk_sec"]
        gain = xp.quest_xp((r.get("xp") or {}).get("v") or 0, ql, level)
        for o in r.get("obj", []):
            n = o.get("count") or 1
            if o.get("k") in ("kill", "item"):
                n = n * (p["item_kills"] if o.get("k") == "item" else 1) * (1 + p["extra_kills"])
                wa, wb = sim.kill_weights(level, ql, p)
                work += cf_kill * n * (p["kill_sec_1"] * wa + p["kill_sec_60"] * wb)
                gain += n * xp.kill_xp(level, ql)
            elif o.get("k") == "object":
                work += n * p["interact_sec"]
            elif o.get("k") == "talk":
                work += p["talk_sec"]
            elif o.get("k") == "event":
                work += p["escort_sec"]
        extra = walk_s + work
        if extra <= 0:
            return True, 0.0
        need = rate_s * (0.5 if walk_s < 60 else 1.0)
        return gain / extra >= need, extra

    def on_route(r, i):
        """The giver stands in the character's zone and every zone of the quest is still ahead."""
        if i >= len(acts) or acts[i]["zone"] is None:
            return False
        zones = {lint.zone_key(r["startPos"]["v"][0]), lint.zone_key(r["endPos"]["v"][0])}
        zones |= {lint.zone_key(o["pos"][0]) for o in r.get("obj", []) if o.get("pos")}
        return lint.zone_key(r["startPos"]["v"][0]) == lint.zone_key(acts[i]["zone"]) and zones <= ahead[i]

    never, later, off, slow = [], [], [], []
    for q, (i, gp) in sorted(passed.items()):
        a_idx = run.quest.get(q, {}).get("a")
        if not on_route(by_q[q], i):
            if a_idx is None:
                off.append(q)
            continue
        if a_idx is None and not worth(by_q[q], i, acts[i]["level"])[0]:
            slow.append(q)
            continue
        if a_idx is None:
            never.append(q)
        elif a_idx > i and _left(run, i, a_idx, gp, p.lim("p6_later_yd")):
            later.append(q)
    row["p6_never"], row["p6_later"] = len(never), len(later)
    row["p6_off"] = len(off)
    row["p6_slow"] = len(slow)
    row["p6_never_quests"] = never[:20]
    r06 = [q for q, (i, op) in sorted(obj_passed.items()) if _left(run, i, run.quest[q]["c"], op, visit_r)]
    if ctx.detail:
        det["p6_never"] = [(q, passed[q][0]) for q in never]
        det["p6_later"] = [(q, passed[q][0]) for q in later]
        det["r06"] = [(q, obj_passed[q][0]) for q in r06]
    row["r06_passed_objectives"] = len(r06)

    # P7: quest log
    row["p7_peak"], row["p7_over_work"] = run.log_peak, run.log_over_work
    row["p7_open_end"] = len(run.open_at_end)

    # P8: levels at accept and turn-in, outliers
    above = gray = 0
    accepts = []
    for a in acts:
        r = rf.get(a["q"]) if a["q"] is not None else None
        if not r:
            continue
        ql = _qlevel(r)
        if a["verb"] == "accept":
            accepts.append(ql or _min(r))
            if ql is not None and ql > a["level"] + lint.LEVEL_ABOVE:
                above += 1
        elif a["verb"] == "turnin" and ql is not None and xp.quest_factor(ql, a["level"]) < 0.8:
            gray += 1
    outliers = 0
    for i, ql in enumerate(accepts):
        nb = accepts[max(0, i - 5):i] + accepts[i + 1:i + 6]
        if nb and ql > statistics.median(nb) + p.lim("p8_outlier"):
            outliers += 1
    row["p8_above"], row["p8_gray"], row["p8_outliers"] = above, gray, outliers

    # P9: zone visits
    visits = []
    for a in acts:
        if a["zone"] is None:
            continue
        z = lint.zone_key(a["zone"])
        if not visits or visits[-1]["zone"] != z:
            visits.append({"zone": z, "quests": set(), "verbs": set(), "lv": []})
        if a["q"] is not None:
            visits[-1]["quests"].add(a["q"])
        visits[-1]["verbs"].add(a["verb"])
        if a["lv"] is not None:
            visits[-1]["lv"].append(a["lv"])
    row["p9_changes"] = max(0, len(visits) - 1)
    # zone sections per level band (decision of 2026-11-02 on guard P9): up to the end level of the
    # RestedXP Forever guides of the combination (data/plan/zone-sections.toml) and above it; a
    # visit counts in every band its planned levels touch
    sec = ctx.sections.get("%s/%s" % (row["race"], row["class"]), {})
    end = sec.get("end")
    spans = [(min(v["lv"]), max(v["lv"])) if v["lv"] else (None, None) for v in visits]
    row["p9_end"], row["p9_rxp"] = end, sec.get("sections")
    row["p9_sections"] = [sum(1 for lo, hi in spans if end is None or lo is None or lo <= end),
                          sum(1 for lo, hi in spans if end is not None and hi is not None and hi > end)]
    row["p9_visits"] = len(visits)
    row["p9_quests_per_visit"] = (sum(len(v["quests"]) for v in visits) / len(visits)) if visits else 0.0
    seen, r09, r26 = set(), 0, 0
    for v in visits:
        if v["zone"] in seen and len(v["quests"]) < p.lim("r09_min_quests"):
            r09 += 1
        seen.add(v["zone"])
        if v["zone"] in CAPITALS and not v["verbs"] & {"accept", "turnin", "train", "fp", "sethome", "hs"}:
            r26 += 1

    # G1: linter, G2: simulator
    keys = run.keys
    route_errs = lint.lint_route(ctx.mods, keys, run.race, run.cls, f, row["label"]) if keys else []
    mod_errs = [e for k in keys for e in ctx.module_errs.get(k, [])]
    row["g1_errors"] = len(route_errs) + len(mod_errs) + (0 if keys else 1)
    row["g2_stuck"] = len(run.stuck)
    row["g2_reached"] = 30 in run.reached

    # G3, G5, G6 per band (planned level of the step)
    cov, qcount, walk_yd = {}, {}, {}
    for a, b in BANDS:
        cov["%d-%d" % (a, b)] = 0.0
        qcount["%d-%d" % (a, b)] = 0
        walk_yd["%d-%d" % (a, b)] = 0.0
    for q, info in run.quest.items():
        if "t" in info and info.get("lv_plan"):
            band = band_of(info["lv_plan"])
            if band:
                cov[band] += info["xp_plan"]
    for a in acts:
        band = band_of(a["lv"] or 1)
        if a["verb"] == "accept" and band:
            qcount[band] += 1
    for g in walks:
        if g["action"] < len(acts):
            band = band_of(acts[g["action"]]["lv"] or 1)
            if band:
                walk_yd[band] += g["yd"]
    row["g3"] = {}
    row["g6_yd_per_xp"] = {}
    for a, b in BANDS:
        k = "%d-%d" % (a, b)
        need = band_need(a, b, target)
        row["g3"][k] = cov[k] / need if need else None
        row["g6_yd_per_xp"][k] = walk_yd[k] / cov[k] if cov[k] else None
    row["g3_min"] = min(v for v in row["g3"].values() if v is not None)
    row["g5"] = qcount
    row["g5"]["1-20"] = qcount["1-10"] + qcount["11-20"]

    # G7: level on arrival at the first core block
    core = next((m for m in run.modules if m["kind"] == "core"), None)
    row["g7_arrival"] = core["level0"] if core else None
    row["g7_dev"] = (core["levels"][0] - core["level0"]) if core else None

    # G8: class inserts
    inserts = [(m["key"], m["t1"] - m["t0"]) for m in run.modules if m["kind"] == "class"]
    row["g8_max_sec"] = max((s for _, s in inserts), default=0.0)
    row["g8_total_sec"] = sum(s for _, s in inserts)
    row["g8_inserts"] = [[k, round(s)] for k, s in inserts]

    # G9: trainers on the way; G11: own measurement of race and class conditions
    row["g9_trains"] = len(run.trains)
    taken = [q for q in sorted(run.quest) if "a" in run.quest[q]]
    own = [q for q in taken if "own" in (rf[q].get("races") or {}).get("src", []) + (rf[q].get("classes") or {}).get("src", [])]
    row["g11_own"] = len(own) / len(taken) if taken else 0.0
    # G11 holds "before label stabil" (DR 22d): it applies to a route with a module labelled stabil
    row["g11_stabil"] = any(ctx.mods.get(k) and ctx.mods[k].header.get("label") == "stabil" for k in keys)

    # Rules of DR 22a
    rules = {}
    r01 = [(q, info["full"] - info["xp_t"]) for q, info in sorted(run.quest.items())
           if "t" in info and info.get("ql") is not None and info["lv_t"] > info["ql"] + 5]
    rules["R01"] = len(r01)
    row["r01_lost_xp"] = sum(x for _, x in r01)
    rules["R02"] = sum(1 for q, info in run.quest.items()
                       if "t" in info and info.get("ql") is not None and info["lv_t"] >= info["ql"] + 10)
    r04 = 0
    for q, info in sorted(run.quest.items()):
        if "t" not in info:
            continue
        ends = {e.get("id") for e in (rf[q].get("end") or {}).get("v", []) if e.get("k") == "npc"}
        t_idx = info["t"]
        # level and quest log right after the turn-in (DR 22a R04: the follow-up "bereitsteht")
        lv_after = acts[t_idx + 1]["level"] if t_idx + 1 < len(acts) else run.end_level
        log_after = acts[t_idx + 1]["log"] if t_idx + 1 < len(acts) else 0
        for q2 in ctx.followups.get(q, []):
            i2 = run.quest.get(q2, {}).get("a")
            if i2 is None or i2 <= t_idx or step_of[i2] == step_of[t_idx]:
                continue
            if not _available(f.q.get(q2) or {"q": q2}, run, t_idx + 1, lv_after, log_after, p["quest_log_work"]):
                continue
            starts = {e.get("id") for e in ((f.q.get(q2) or {}).get("start") or {}).get("v", []) if e.get("k") == "npc"}
            if ends & starts:
                r04 += 1
                if ctx.detail:
                    det.setdefault("r04", []).append((q, q2))
    rules["R04"] = r04
    spot = Grid(SAME_NPC * 4)
    turnin_steps = {step_of[k] for k, a in enumerate(acts) if a["verb"] == "turnin"}
    r05 = 0
    for i, a in enumerate(acts):
        if a["pos"] is None:
            continue
        if a["verb"] == "accept" and step_of[i] not in turnin_steps:
            r = rf[a["q"]]
            for _, j in spot.near(a["pos"], SAME_NPC):
                # a later visit (DR 22a R05 "späterer Besuch"): the character went away from the
                # NPC in between (a visit ends 400 yd away, as P5); the next step at the same NPC is
                # the same visit
                if step_of[j] == step_of[i] or not _left(run, j, i, acts[j]["pos"], visit_r):
                    continue
                if _available(r, run, j + 1, acts[j]["level"], acts[j]["log"], p["quest_log_work"]):
                    r05 += 1
                    if ctx.detail:
                        det.setdefault("r05", []).append((a["q"], j))
                    break
        spot.add(a["pos"], i)
    rules["R05"] = r05
    rules["R06"] = len(r06)
    row["r06_parallel_share"] = 0.0  # the route format has no parallel objectives yet
    completes = [a for a in acts if a["verb"] == "complete" and a["pos"] is not None]
    r07 = 0
    for c1, c2 in zip(completes, completes[1:]):
        if c1["pos"][0] != c2["pos"][0] or geo.dist(c1["pos"][1:], c2["pos"][1:]) > visit_r:
            continue
        if run.quest.get(c2["q"], {}).get("a", 1 << 30) > c1["idx"]:
            continue
        between = acts[c1["idx"] + 1:c2["idx"]]
        if any(b["verb"] == "turnin" and b["pos"] is not None and (b["pos"][0] != c1["pos"][0] or geo.dist(b["pos"][1:], c1["pos"][1:]) > visit_r) for b in between):
            r07 += 1
            if ctx.detail:
                det.setdefault("r07", []).append((c1["idx"], c2["idx"]))
    rules["R07"] = r07
    rules["R09"] = r09
    rules["R10"] = sum(1 for _, rule, _ in run.hearth_errors if rule == "R10")
    rules["R11"] = sum(1 for i, pos in run.binds
                       if pos is None or not any(a["pos"] and a["pos"][0] == pos[0] and geo.dist(a["pos"][1:], pos[1:]) <= visit_r
                                                 and a["verb"] in ("accept", "turnin") for a in acts[i + 1:]))
    rules["R12"] = sum(1 for _, rule, _ in run.hearth_errors if rule == "R12")
    rules["R13"] = len(fm_passed)
    r18 = r18_off = 0
    for gte in run.gates:
        if gte["pos"] is None or gte["idx"] >= len(acts):
            continue
        a = acts[gte["idx"]]
        # quests the character could take before it grinds (level before the grind, DR 22a R18)
        lv0 = int(math.floor(gte["from"] + 1e-9))
        near_q = [q for _, q in givers.near(gte["pos"], p.lim("p6_passed_yd"))
                  if _available(by_q[q], run, gte["idx"], lv0, a["log"], p["quest_log_work"])]
        # as P6: only quests the route can take there (zone of the character, all zones ahead)
        off_q = [q for q in near_q if not on_route(by_q[q], gte["idx"]) or not worth(by_q[q], gte["idx"], lv0)[0]]
        near_q = [q for q in near_q if q not in off_q]
        if off_q:
            r18_off += 1
        if near_q:
            r18 += 1
            if ctx.detail:
                det.setdefault("r18", []).append((gte["idx"], sorted(near_q)))
    rules["R17"] = sum(1 for _, has_place in run.xp_marks if not has_place)
    rules["R18"] = r18
    row["r18_off"] = r18_off
    rules["R19"] = sum(1 for g in run.gates if not g["announced"])
    rules["R20"] = sum(1 for q in taken if any(o.get("k") == "event" for o in rf[q].get("obj", [])))
    rules["R21"] = sum(1 for q in taken if any(o.get("k") == "item" for o in rf[q].get("obj", [])))
    rules["R22"] = sum(1 for q in taken if rf[q].get("type") in build.EXCLUDED_TYPES)
    rules["R23"] = sum(1 for e in route_errs if e.code in ("filter", "vorquest", "fraktion", "stufe")) + sum(
        1 for _, text in run.stuck if "Vorquest" in text)
    rules["R26"] = r26
    rules["R27"] = sum(1 for a in acts if a["verb"] == "complete" and a["q"] is not None and (_qlevel(rf[a["q"]]) or 0) > a["level"] + p.lim("r27_above"))
    rules["R28"] = sum(1 for q in taken if rf[q].get("instance") is not None) if run.mode == "speed" else 0
    rules["R30"] = sum(1 for _, text in run.stuck if "R30" in text)
    rules["R31"] = len(run.open_at_end)
    rules["R33"] = sum(1 for k in keys if ctx.mods.get(k) and ctx.mods[k].header.get("label") == "stabil")
    row["rules"] = rules
    if ctx.detail:
        det["gates"] = [(g["idx"], g["to"], g["announced"]) for g in run.gates]
        det["long_legs"] = long_legs
        row["detail"] = det
    return row


# --- summary over all combinations ------------------------------------------------------------------

def _draws(params):
    """The held-out parameter draws (DR 22c §D): normal around the mean, cut at +/- clip sd, > 0."""
    rng = random.Random(params.lim("p3_seed"))
    clip = params.lim("p3_clip_sd")
    out = []
    for _ in range(params.lim("p3_draws")):
        values = {}
        for k in DRAWN:
            e = params.param[k]
            mean, sd = e["value"], e.get("sd", 0.0)
            v = rng.gauss(mean, sd) if sd else mean
            v = min(max(v, mean - clip * sd), mean + clip * sd)
            values[k] = max(v, 1e-6)
        out.append(params.with_values(values))
    return out


def _cross(rows, params, baseline):
    """Figures that compare combinations: G4, G5, G6, G10, P10, and the comparison with the baseline."""
    by_mode = {}
    for r in rows:
        by_mode.setdefault(r["mode"], []).append(r)
    draws = _draws(params)
    for mode, rs in by_mode.items():
        for a, b in BANDS:
            k = "%d-%d" % (a, b)
            best = max(r["g3"][k] for r in rs)
            yds = [r["g6_yd_per_xp"][k] for r in rs if r["g6_yd_per_xp"][k] is not None]
            ymed = statistics.median(yds) if yds else None
            qmax = max(r["g5"][k] for r in rs)
            for r in rs:
                r.setdefault("g4_gap", {})[k] = best - r["g3"][k]
                d = r["g6_yd_per_xp"][k]
                r.setdefault("g6_ratio", {})[k] = d / ymed if d is not None and ymed else None
                r.setdefault("g5_ratio", {})[k] = qmax / r["g5"][k] if r["g5"][k] else None
        qmax = max(r["g5"]["1-20"] for r in rs)
        for r in rs:
            r["g5_ratio"]["1-20"] = qmax / r["g5"]["1-20"] if r["g5"]["1-20"] else None
            r["g4_max_gap"] = max(r["g4_gap"].values())
            r["g5_max_ratio"] = max(v for v in r["g5_ratio"].values() if v is not None)
            r["g6_max_ratio"] = max(v for v in r["g6_ratio"].values() if v is not None)
        best_class = {}
        for r in rs:
            best_class[r["class"]] = min(best_class.get(r["class"], 1e18), r["h30"])
        for r in rs:
            r["g10_regret"] = (r["h30"] - best_class[r["class"]]) / best_class[r["class"]]
    for r in rows:
        cf = params["class_factor"][r["class"]]
        r["p3_draws_h30"] = [sim.time_from(r["counters30"], d, cf) / 3600.0 for d in draws]
        combos = (baseline or {}).get("combos", {})
        base = combos.get(r["label"])
        r["baseline"] = bool(base)
        # P3 of the explorer compares with the speed start route (decision of 2026-11-02): the
        # explorer is the speed route plus finds; the old explorer route took breadcrumbs and
        # quests with unconfirmed prerequisites and is no reference for "not slower"
        p3base = combos.get("speed/" + r["label"].split("/", 1)[1]) if r["mode"] == "explorer" else base
        if base and p3base:
            bh = [sim.time_from(p3base["counters30"], d, cf) / 3600.0 for d in draws]
            r["p3_worse_draws"] = sum(1 for now, old in zip(r["p3_draws_h30"], bh) if now > old + 1e-6)
            r["p3_max_delta_h"] = round(max(now - old for now, old in zip(r["p3_draws_h30"], bh)), 6)
            r["p4_vs_base"] = r["p4_long"] - base["p4_long"]
            r["p5_vs_base"] = r["p5_returns"] - base["p5_returns"]
            # guard P9 (decision of 2026-11-02): zone sections up to the end level of RestedXP
            # Forever at most as many as RestedXP has there (or the start route, if it had more),
            # above it at most the start route's plus p9_sections_extra
            sa, sb = base.get("p9_sections", [base["p9_changes"] + 1, 0])
            cap = [max(r["p9_rxp"] if r["p9_rxp"] is not None else sa + params.lim("p9_sections_extra"), sa),
                   sb + params.lim("p9_sections_extra")]
            r["p9_cap"] = cap
            r["p9_vs_base"] = max(r["p9_sections"][0] - cap[0], r["p9_sections"][1] - cap[1])
            r["p11_vs_base"] = round(max(r["p11_slow"] - sim.time_from(base["counters30"], params, params["class_factor"]["WARRIOR"]) / 3600.0,
                                   r["p11_fast"] - sim.time_from(base["counters30"], params, params["class_factor"]["HUNTER"]) / 3600.0), 6)


def p10(rows):
    """Spread of model hours per band over the combinations of a faction (DR 22c P10). Report only:
    DR 22d compares times only within a class (G10)."""
    out = []
    for mode in routefmt.MODES:
        for faction in (game.ALLIANCE, game.HORDE):
            rs = [r for r in rows if r["mode"] == mode and r["faction"] == faction]
            for a, b in BANDS:
                k = "%d-%d" % (a, b)
                vals = sorted((r["band_h"][k], r["combo"]) for r in rs if k in r["band_h"])
                out.append({"mode": mode, "faction": faction, "band": k, "min": vals[0][0], "min_combo": vals[0][1],
                            "max": vals[-1][0], "max_combo": vals[-1][1], "ratio": vals[-1][0] / vals[0][0]})
    return out


# Kennzahl: id, title, value(row), bad ("high" or "low"), limit(params) or None, kind
# kind: "limit" (must hold from Welle 6b), "base" (not worse than the start route), "H"/"W" (DR 22a
# hard/soft rule), "report" (no limit).
def _metric_table(params):
    L = params.lim
    rule = lambda key: (lambda r: r["rules"][key])  # noqa: E731
    return [
        ("h30", "Modellstunden 1–30", lambda r: r["h30"], "high", None, "report"),
        ("xph", "XP je Modellstunde 1–20 (Prüfband 22b)", lambda r: r["xph_1_20"], "band", params.check["xph_1_20"]["value"], "check"),
        ("P2", "P2 kleinste Deckung eines Moduls (Quest- + Ziel-Kill-XP)", lambda r: r["p2_min_cov"], "low", L("p2_coverage"), "limit"),
        ("P2g", "P2 größter Grind-Anteil einer Stufe", lambda r: r["p2_grind_max"], "high", L("p2_grind_share"), "limit"),
        ("P3", "P3 Ziehungen schlechter als Startlösung (von 16)", lambda r: r.get("p3_worse_draws"), "high", 0, "base"),
        ("P3h", "P3 Modellstunden 1–30, längste der 16 Ziehungen", lambda r: max(r["p3_draws_h30"]), "high", None, "report"),
        ("P4", "P4 lange Einzelquest-Wege im Gebiet (über 0,05 Modellstunden, unter ½ Routenrate)", lambda r: r["p4_long"], "high", 0, "limit"),
        ("P4b", "P4 lange Einzelquest-Wege mehr als Startlösung", lambda r: r.get("p4_vs_base"), "high", 0, "base"),
        ("P4yd", "P4 längster Fußweg im selben Gebiet (yd)", lambda r: r["p4_longest_zone_yd"], "high", None, "report"),
        ("P5", "P5 vermeidbare Rückkehren", lambda r: r["p5_returns"], "high", None, "report"),
        ("P5b", "P5 vermeidbare Rückkehren mehr als Startlösung", lambda r: r.get("p5_vs_base"), "high", 0, "base"),
        ("P5w", "P5 verschwendete Wege", lambda r: r["p5_wasted"], "high", 0, "limit"),
        ("P6", "P6 vorbeigelaufen, nie genommen", lambda r: r["p6_never"], "high", 0, "limit"),
        ("P6l", "P6 vorbeigelaufen, erst später genommen", lambda r: r["p6_later"], "high", 0, "limit"),
        ("P6z", "P6 vorbeigelaufen, braucht ein Gebiet, das die Route nicht mehr besucht (Wächter P9)", lambda r: r["p6_off"], "high", None, "report"),
        ("P6n", "P6 vorbeigelaufen, lohnt nicht (XP je Zusatzsekunde unter der Routenrate)", lambda r: r["p6_slow"], "high", None, "report"),
        ("P7", "P7 Questlog-Spitze", lambda r: r["p7_peak"], "high", params["quest_log_work"], "limit"),
        ("P7o", "P7 angenommen und nie abgegeben", lambda r: r["p7_open_end"], "high", 0, "limit"),
        ("P8", "P8 Annahme über Stufe + 2, graue Abgabe, Ausreißer", lambda r: r["p8_above"] + r["p8_gray"] + r["p8_outliers"], "high", 0, "limit"),
        ("P9", "P9 Gebietswechsel", lambda r: r["p9_changes"], "high", None, "report"),
        ("P9b", "P9 Gebietsabschnitte über der Obergrenze (RestedXP bzw. Startlösung + 2)", lambda r: r.get("p9_vs_base"), "high", 0, "base"),
        ("P9a", "P9 Gebietsabschnitte bis zum Ende von RestedXP (Stufe 21/22)", lambda r: r["p9_sections"][0], "high", None, "report"),
        ("P9c", "P9 Gebietsabschnitte darüber bis Stufe 30", lambda r: r["p9_sections"][1], "high", None, "report"),
        ("P9q", "P9 Quests je Gebietsbesuch", lambda r: r["p9_quests_per_visit"], "low", None, "report"),
        ("P11", "P11 Modellstunden 1–30 Profil langsam (Krieger-Faktor)", lambda r: r["p11_slow"], "high", None, "report"),
        ("P11f", "P11 Modellstunden 1–30 Profil schnell (Jäger-Faktor)", lambda r: r["p11_fast"], "high", None, "report"),
        ("P11b", "P11 Mehrstunden gegen Startlösung, Profil langsam oder schnell", lambda r: r.get("p11_vs_base"), "high", 0, "base"),
        ("G1", "G1 Linter-Fehler", lambda r: r["g1_errors"], "high", 0, "limit"),
        ("G2", "G2 Hänger im Simulator", lambda r: r["g2_stuck"] + (0 if r["g2_reached"] else 1), "high", 0, "limit"),
        ("G3", "G3 kleinste Quest-XP-Deckung eines Bands", lambda r: r["g3_min"], "low", L("g3_coverage"), "limit"),
        ("G4", "G4 Abstand zur besten Deckung im Band", lambda r: r["g4_max_gap"], "high", L("g4_coverage_spread"), "limit"),
        ("G5", "G5 Questzahl: meiste / eigene je Band", lambda r: r["g5_max_ratio"], "high", L("g5_quest_ratio"), "limit"),
        ("G6", "G6 Laufweg je Quest-XP / Median je Band", lambda r: r["g6_max_ratio"], "high", L("g6_walk_ratio"), "limit"),
        ("G7", "G7 Abweichung der Ankunftsstufe vom Beginn des ersten Kernblocks", lambda r: abs(r["g7_dev"]) if r["g7_dev"] is not None else None, "high", L("g7_arrival"), "limit"),
        ("G8", "G8 längster Klasseneinschub (Modellstunden)", lambda r: r["g8_max_sec"] / 3600.0, "high", L("g8_insert_sec") / 3600.0, "limit"),
        ("G8s", "G8 Klasseneinschübe gesamt (Modellstunden)", lambda r: r["g8_total_sec"] / 3600.0, "high", L("g8_insert_total_sec") / 3600.0, "limit"),
        ("G9", "G9 train-Schritte auf der Route (Lehrerwege prüfbar ab einem)", lambda r: r["g9_trains"], "low", None, "open0"),
        ("G10", "G10 Rückstand zur besten Route der Klasse", lambda r: r["g10_regret"], "high", L("g10_regret"), "limit"),
        ("G11", "G11 Anteil Routenquests mit eigener Volk-/Klassen-Messung (gilt ab Etikett stabil)",
         lambda r: r["g11_own"] if r.get("g11_stabil") else None, "low", L("g11_own"), "limit"),
        ("R01", "R01 Abgabe über Questlevel + 5 (H)", rule("R01"), "high", 0, "H"),
        ("R02", "R02 Abgabe ab Questlevel + 10 (H)", rule("R02"), "high", 0, "H"),
        ("R04", "R04 Folgequest am selben NPC nicht im selben Schritt (H)", rule("R04"), "high", 0, "H"),
        ("R05", "R05 späterer Besuch nur zur Annahme (H)", rule("R05"), "high", 0, "H"),
        ("R06", "R06 aktives Ziel passiert, später eigener Besuch (H)", rule("R06"), "high", 0, "H"),
        ("R07", "R07 Zwischenabgabe zwischen zwei nahen Zielen (H)", rule("R07"), "high", 0, "H"),
        ("R09", "R09 Rückkehr ins Gebiet mit weniger als 3 Quests (H)", rule("R09"), "high", 0, "H"),
        ("R10", "R10 Ruhestein ohne Bedingungen (H)", rule("R10"), "high", 0, "H"),
        ("R11", "R11 Bindung ohne späteren Besuch (H)", rule("R11"), "high", 0, "H"),
        ("R12", "R12 Ruhestein vor Ablauf der Abklingzeit (H)", rule("R12"), "high", 0, "H"),
        ("R13", "R13 unbekannter Flugmeister passiert (H)", rule("R13"), "high", 0, "H"),
        ("R17", "R17 Grind-Schritt ohne Ort (H)", rule("R17"), "high", 0, "H"),
        ("R18", "R18 Grind trotz annehmbarer Quest in 500 yd (H)", rule("R18"), "high", 0, "H"),
        ("R18z", "R18 Grind neben Quests, die ein Gebiet außerhalb der Route brauchen oder nicht lohnen", lambda r: r["r18_off"], "high", None, "report"),
        ("R19", "R19 Grind ohne vorherige Ankündigung (H)", rule("R19"), "high", 0, "H"),
        ("R20", "R20 Eskorten-/Ereignisquests im Speed-Pfad (W)", rule("R20"), "high", None, "W"),
        ("R21", "R21 Sammelquests ohne Abbruchregel (W)", rule("R21"), "high", None, "W"),
        ("R22", "R22 Gruppen-/Elitequests im Solo-Pfad (H)", rule("R22"), "high", 0, "H"),
        ("R23", "R23 nicht verfügbare Quest (H)", rule("R23"), "high", 0, "H"),
        ("R26", "R26 Hauptstadtbesuch ohne Grund (H)", rule("R26"), "high", 0, "H"),
        ("R27", "R27 Questziel mehr als 2 Stufen über dem Spieler (W)", rule("R27"), "high", None, "W"),
        ("R28", "R28 Dungeonquest im Speed-Pfad (H)", rule("R28"), "high", 0, "H"),
        ("R30", "R30 Questlog über 40 (H)", rule("R30"), "high", 0, "H"),
        ("R31", "R31 Quest am Ende noch im Log (W)", rule("R31"), "high", None, "W"),
        ("R33", "R33 Etikett stabil ohne Messung (H)", rule("R33"), "high", 0, "H"),
    ]


def _ok(value, bad, limit):
    if value is None or limit is None:
        return None
    if bad == "band":
        return limit[0] <= value <= limit[1]
    return value >= limit if bad == "low" else value <= limit


def summarize(rows, params):
    out = []
    for mid, title, get, bad, limit, kind in _metric_table(params):
        for mode in routefmt.MODES:
            rs = [r for r in rows if r["mode"] == mode]
            vals = [(get(r), r["label"]) for r in rs if get(r) is not None]
            if not vals:
                out.append({"id": mid, "title": title, "mode": mode, "kind": kind, "bad": bad, "limit": limit,
                            "status": "offen", "worst": [], "fails": None})
                continue
            if bad == "band":
                lo, hi = limit
                key = lambda v: min(v[0] - lo, hi - v[0])  # noqa: E731  closest to an edge first
            elif bad == "low":
                key = lambda v: v[0]  # noqa: E731
            else:
                key = lambda v: -v[0]  # noqa: E731
            ordered = sorted(vals, key=lambda v: (key(v), v[1]))
            fails = sum(1 for v, _ in vals if _ok(v, bad, limit) is False)
            if kind == "open0" and all(v == 0 for v, _ in vals):
                status = "offen (keine train-Schritte in den Routen)"
            elif kind in ("report", "W", "open0") or limit is None:
                status = "Bericht"
            elif kind == "base" and not any(r["baseline"] for r in rs):
                status = "offen (keine Startlösung)"
            else:
                status = "erfüllt" if fails == 0 else "verletzt"
            out.append({"id": mid, "title": title, "mode": mode, "kind": kind, "bad": bad, "limit": limit, "status": status,
                        "fails": fails, "worst": [[round(v, 4) if isinstance(v, float) else v, lab] for v, lab in ordered[:5]]})
    return out


def collect(facts, mods, comps, params, baseline=None, modes=routefmt.MODES, combo_list=None):
    ctx = Context(facts, mods, comps, params)
    runs = sim.simulate_all(facts, mods, comps, params, modes, combo_list)
    again = sim.simulate_all(facts, mods, comps, params, modes, combo_list)
    h1, h2 = sim.digest(runs), sim.digest(again)
    rows = [evaluate(ctx, run) for run in runs]
    _cross(rows, params, baseline)
    report = {
        "format": 1,
        "p1": {"digest": h1, "second_run": h2, "equal": h1 == h2},
        "params_errors": params.errors(),
        "rows": rows,
        "summary": summarize(rows, params),
        "p10": p10(rows),
        "g12": g12(rows, params),
        "not_checkable": NOT_CHECKABLE,
        "hours_by_faction": hours_by_faction(rows),
    }
    return report


def g12(rows, params):
    """G1-G10 for the two Skyborne races separately (DR 22d G12): failed checks per race and mode."""
    table = {m[0]: m for m in _metric_table(params)}
    ids = ("G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8", "G8s", "G10")
    out = []
    for race in ("SKYBORNE_A", "SKYBORNE_H"):
        for mode in routefmt.MODES:
            rs = [r for r in rows if r["race"] == race and r["mode"] == mode]
            failed = []
            for mid in ids:
                _, _, get, bad, limit, _ = table[mid]
                n = sum(1 for r in rs if _ok(get(r), bad, limit) is False)
                if n:
                    failed.append("%s (%d)" % (mid, n))
            out.append({"race": race, "mode": mode, "combos": len(rs), "failed": failed})
    return out


def hours_by_faction(rows):
    out = []
    for mode in routefmt.MODES:
        for faction in (game.ALLIANCE, game.HORDE):
            hs = sorted((r["h30"], r["combo"]) for r in rows if r["mode"] == mode and r["faction"] == faction)
            vals = [h for h, _ in hs]
            out.append({"mode": mode, "faction": faction, "min": hs[0], "median": statistics.median(vals), "max": hs[-1],
                        "h20_median": statistics.median(r["h20"] for r in rows if r["mode"] == mode and r["faction"] == faction)})
    return out


# --- gate (Welle 6b: the CI job "Route quality" fails on a breach) ------------------------------------

EXCEPTIONS_PATH = repo_path("data", "plan", "route-exceptions.toml")
GATED = ("limit", "base", "H", "check")


def load_exceptions(path=None):
    import tomllib

    try:
        with open(path or EXCEPTIONS_PATH, "rb") as fh:
            return tomllib.load(fh).get("exception", [])
    except FileNotFoundError:
        return []


def _covered(exc, mid, mode, label, value, bad):
    for e in exc:
        if e["id"] != mid or mode not in e.get("modes", routefmt.MODES):
            continue
        combos = e.get("combos", "*")
        if combos != "*" and label.split("/", 1)[1] not in combos:
            continue
        if bad == "low" and value >= e["min"] - 1e-9:
            return e
        if bad != "low" and value <= e["max"] + 1e-9:
            return e
    return None


def gate(report, params, exceptions):
    """Every breach of a limit, a guard against the start route, a hard rule of DR 22a or the
    model check by a combination, and whether a measured exception (data/plan/route-exceptions.toml)
    covers it. An exception covers a metric only up to its measured value."""
    out = []
    table = {m[0]: m for m in _metric_table(params)}
    for mid, title, get, bad, limit, kind in table.values():
        if kind not in GATED or limit is None:
            continue
        for r in report["rows"]:
            v = get(r)
            if kind == "base" and not r.get("baseline"):
                continue
            if _ok(v, bad, limit) is not False:
                continue
            e = _covered(exceptions, mid, r["mode"], r["label"], v, bad)
            out.append({"id": mid, "mode": r["mode"], "label": r["label"], "value": v, "limit": limit,
                        "covered": bool(e), "exception": e.get("reason", "")[:60] if e else None})
    if not report["p1"]["equal"]:
        out.append({"id": "P1", "mode": "-", "label": "-", "value": 0, "limit": 1, "covered": False, "exception": None})
    return out


def gate_text(breaches):
    open_ = [b for b in breaches if not b["covered"]]
    lines = ["Gate: %d Überschreitungen, %d durch gemessene Ausnahmen gedeckt, %d offen" % (
        len(breaches), len(breaches) - len(open_), len(open_))]
    by = {}
    for b in open_:
        by.setdefault((b["id"], b["mode"]), []).append(b)
    for (mid, mode), bs in sorted(by.items()):
        worst = ", ".join("%s %s" % (b["label"].split("/", 1)[1], _fmt(b["value"])) for b in bs[:5])
        lines.append("OFFEN %s %s: %d Kombinationen (%s)" % (mid, mode, len(bs), worst))
    return "\n".join(lines)


# --- output ------------------------------------------------------------------------------------------

def _fmt(v):
    if v is None:
        return "–"
    if isinstance(v, float):
        if abs(v) >= 100:
            return "%.0f" % v
        return "%.2f" % v
    if isinstance(v, (list, tuple)):
        return "–".join(_fmt(x) for x in v)
    return str(v)


def _limit_text(item):
    lim, kind = item["limit"], item["kind"]
    if kind == "base":
        return "≤ Startlösung"
    if lim is None:
        return "–"
    if isinstance(lim, list):
        return "%s–%s" % (_fmt(lim[0]), _fmt(lim[1]))
    return ("≥ " if item["bad"] == "low" else "≤ ") + _fmt(lim)


def text_table(report):
    lines = ["P1 Determinismus: Prüfsumme %s, zweiter Lauf %s" % (report["p1"]["digest"][:16],
             "gleich" if report["p1"]["equal"] else "VERSCHIEDEN")]
    if report["params_errors"]:
        lines.append("Parameterfehler: " + "; ".join(report["params_errors"]))
    lines.append("%-5s %-8s %-62s %-12s %-26s %s" % ("Id", "Modus", "Kennzahl", "Grenzwert", "Status", "schlechteste 5"))
    for s in report["summary"]:
        worst = ", ".join("%s %s" % (lab.split("/", 1)[1], _fmt(v)) for v, lab in s["worst"])
        status = s["status"] + ("" if s["fails"] in (None, 0) or s["status"] == "Bericht" else " (%d)" % s["fails"])
        lines.append("%-5s %-8s %-62s %-12s %-26s %s" % (s["id"], s["mode"], s["title"][:62], _limit_text(s), status, worst))
    for h in report["hours_by_faction"]:
        lines.append("Modellstunden 1–30 %s %s: %s (%s) / Median %s / %s (%s); 1–20 Median %s" % (
            h["mode"], h["faction"], _fmt(h["min"][0]), h["min"][1], _fmt(h["median"]), _fmt(h["max"][0]), h["max"][1],
            _fmt(h["h20_median"])))
    return "\n".join(lines)


def markdown(report, title="Routenkennzahlen"):
    out = ["## %s" % title, ""]
    out.append("Modellstunden aus `tools/routekit/sim.py` mit den Parametern aus `data/plan/params.toml`, keine Vorhersage "
               "echter Spielzeit. Status: erfüllt oder verletzt (Zahl der Kombinationen) gegen den Grenzwert aus "
               "`data/plan/params.toml`; Bericht ohne Grenzwert; offen, wenn nicht prüfbar. Bänder 1–10, 11–20, 21–30 nach der "
               "geplanten Stufe des Schritts. Seit Welle 6b bricht jede Überschreitung, die keine gemessene Ausnahme in "
               "`data/plan/route-exceptions.toml` deckt, den CI-Job „Route quality“ ab.")
    out.append("")
    p1 = report["p1"]
    out.append("P1 Determinismus: Prüfsumme `%s`, zweiter Lauf %s." % (p1["digest"], "gleich" if p1["equal"] else "**verschieden**"))
    out.append("")
    out.append("### Modellstunden 1–30 je Fraktion")
    out.append("")
    out.append("| Modus | Fraktion | schnellste | Median | langsamste | Median 1–20 |")
    out.append("| --- | --- | --- | --- | --- | --- |")
    for h in report["hours_by_faction"]:
        out.append("| %s | %s | %s (%s) | %s | %s (%s) | %s |" % (h["mode"], h["faction"], _fmt(h["min"][0]), h["min"][1],
                                                              _fmt(h["median"]), _fmt(h["max"][0]), h["max"][1], _fmt(h["h20_median"])))
    out.append("")
    out.append("### Kennzahlen mit den fünf schlechtesten Kombinationen")
    out.append("")
    out.append("| Id | Modus | Kennzahl | Grenzwert | Status | schlechteste 5 |")
    out.append("| --- | --- | --- | --- | --- | --- |")
    for s in report["summary"]:
        worst = "; ".join("%s %s" % (lab.split("/", 1)[1].replace("/", " "), _fmt(v)) for v, lab in s["worst"])
        status = s["status"] + ("" if s["fails"] in (None, 0) or s["status"] == "Bericht" else " (%d)" % s["fails"])
        out.append("| %s | %s | %s | %s | %s | %s |" % (s["id"], s["mode"], s["title"], _limit_text(s), status, worst))
    out.append("")
    out.append("### P10 Spannweite der Modellstunden je Band und Fraktion")
    out.append("")
    out.append("| Modus | Fraktion | Band | kürzeste | längste | Verhältnis |")
    out.append("| --- | --- | --- | --- | --- | --- |")
    for x in report["p10"]:
        out.append("| %s | %s | %s | %s (%s) | %s (%s) | %s |" % (x["mode"], x["faction"], x["band"], _fmt(x["min"]), x["min_combo"],
                                                             _fmt(x["max"]), x["max_combo"], _fmt(x["ratio"])))
    out.append("")
    out.append("### G12 Himmelsgeborene je Fraktion")
    out.append("")
    out.append("| Volk | Modus | Kombinationen | verletzte Prüfungen (Anzahl Kombinationen) |")
    out.append("| --- | --- | --- | --- |")
    for x in report["g12"]:
        out.append("| %s | %s | %d | %s |" % (x["race"], x["mode"], x["combos"], ", ".join(x["failed"]) or "keine"))
    out.append("")
    out.append("### Nicht an der Route prüfbar")
    out.append("")
    for k, v in sorted(report["not_checkable"].items()):
        out.append("- %s: %s" % (k, v))
    out.append("")
    for mode in routefmt.MODES:
        out.append("### Alle Kombinationen, %s" % mode)
        out.append("")
        out.append("| Kombination | Modellstunden 1–20 | Modellstunden 1–30 | P2 Deckung min | P2 Grind max | P4 längster Weg yd | P5 | P6 nie/später | P7 | P9 | G3 1–10/11–20/21–30 | Quests 1–10/11–20/21–30 | G7 | G8 h | G10 |")
        out.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
        for r in report["rows"]:
            if r["mode"] != mode:
                continue
            g3 = "/".join(_fmt(r["g3"][k]) for k in ("1-10", "11-20", "21-30"))
            g5 = "/".join(str(r["g5"][k]) for k in ("1-10", "11-20", "21-30"))
            out.append("| %s | %s | %s | %s | %s | %s | %d | %d/%d | %d | %d | %s | %s | %s | %s | %s |" % (
                r["combo"], _fmt(r["h20"]), _fmt(r["h30"]), _fmt(r["p2_min_cov"]), _fmt(r["p2_grind_max"]),
                _fmt(r["p4_longest_zone_yd"]), r["p5_returns"], r["p6_never"], r["p6_later"], r["p7_peak"], r["p9_changes"],
                g3, g5, _fmt(r["g7_dev"]), _fmt(r["g8_total_sec"] / 3600.0), _fmt(r["g10_regret"])))
        out.append("")
    return "\n".join(out)


def baseline_of(report):
    combos = {}
    for r in report["rows"]:
        combos[r["label"]] = {"counters30": r["counters30"], "p4_long": r["p4_long"], "p5_returns": r["p5_returns"],
                              "p9_changes": r["p9_changes"], "p9_sections": r["p9_sections"], "h30": round(r["h30"], 4)}
    return {"format": 1, "note": "Start route of Welle 6 for the comparisons P3, P4, P5, P9 and P11 (tools/routekit/metrics.py). "
            "Counters at level 30 per combination; written with python3 -m tools.routekit metrics --write-baseline.",
            "digest": report["p1"]["digest"], "combos": combos}


def _json_safe(obj):
    if isinstance(obj, float):
        return round(obj, 6)
    if isinstance(obj, dict):
        return {str(k): _json_safe(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [_json_safe(v) for v in obj]
    return obj


def write_json(path, obj):
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(_json_safe(obj), fh, sort_keys=True, indent=1, ensure_ascii=False)
        fh.write("\n")


def main(json_path=None, md_path=None, summary_path=None, write_baseline=False, check=False, routes=None):
    facts, mods, comps, params = sim.load(routes=routes)
    baseline = None
    try:
        with open(BASELINE_PATH, encoding="utf-8") as fh:
            baseline = json.load(fh)
    except FileNotFoundError:
        pass
    report = collect(facts, mods, comps, params, baseline)
    breaches = gate(report, params, load_exceptions())
    report["gate"] = breaches
    print(text_table(report))
    print(gate_text(breaches))
    if json_path:
        write_json(json_path, report)
    if md_path:
        with open(md_path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(markdown(report) + "\n")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8", newline="\n") as fh:
            fh.write("## Gate\n\n```\n" + gate_text(breaches) + "\n```\n\n")
            fh.write(markdown(report, "Route quality") + "\n")
    if write_baseline:
        write_json(BASELINE_PATH, baseline_of(report))
        print("Startlösung geschrieben: %s" % BASELINE_PATH)
    if not report["p1"]["equal"] or report["params_errors"]:
        return 1
    if check and any(not b["covered"] for b in breaches):
        return 1
    return 0
