# SPDX-License-Identifier: GPL-3.0-or-later
"""Baukasten builder: data/plan/*.toml + data/facts -> data/routes/<faction>/*.route + COMPOSE.

A computed route ("Rechenroute"), not a played one: zone order and level bands come from the
plan (our route logic), quests, coordinates and prerequisites from data/facts. Within a zone
the order is greedy: the nearest possible action next (accept, objective, turn-in), with
prerequisites, a quest log of 20 and the planned level respected. Every element carries its
sources and the status "unbestätigt"; every module carries the label "vorläufig".

After building, the linter checks all 56 combinations; quests that cause errors are left out
and the modules are built again, until the linter is clean.
"""

import collections
import os
import shutil
import tomllib

from . import game, geo, lint, routefmt
from .io import read_json, repo_path

LOG_LIMIT = 20
LEVEL_ABOVE = lint.LEVEL_ABOVE
TRIVIAL_BELOW = 4  # skip quests more than 4 levels below the block start (grey, little XP)
LEVEL_PENALTY = 600.0  # yards of detour worth one planned level
SAME_SPOT = 15.0  # yards: actions this close share one step
EXCLUDED_TYPES = {1, 41, 62, 81, 82, 83, 84}
MAX_ROUNDS = 12


def _src(field):
    return ",".join(field.get("src") or field.get("seen") or [])


class Pool:
    """Quests of one module with what is needed to schedule them."""

    def __init__(self, facts, faction, races, mode, exclude):
        self.facts = facts
        self.faction = faction
        self.races = set(races)
        self.mode = mode
        self.exclude = exclude

    def usable(self, r, allow_class):
        if r["q"] in self.exclude:
            return False
        if r.get("type") in EXCLUDED_TYPES or r.get("repeatable") or r.get("startItem"):
            return False
        # Quests ATT lists under an instance belong to the dungeon hint, not to the route, unless
        # Polestar types them as an ordinary quest (type 0, e.g. Red Silk Bandanas in Westfall).
        if r.get("instance") is not None and r.get("type") != 0:
            return False
        if self.mode == "speed" and (r.get("breadcrumb") or r["pre"]["state"] != "secured"):
            return False
        side = r.get("side", {}).get("v")
        if side not in ("B", self.faction[0]):
            return False
        qr = r.get("races", {}).get("v")
        if qr is not None and not (set(qr) & self.races):
            return False
        qc = r.get("classes", {}).get("v")
        if qc is not None and not allow_class:
            return False
        if not r.get("startPos") or not r.get("endPos"):
            return False
        return True


def _filter_text(r, races_universe):
    parts = []
    qr = r.get("races", {}).get("v")
    if qr is not None and not set(races_universe) <= set(qr):
        toks = [game.RACES[x][0] for x in sorted(set(qr) & set(races_universe))]
        parts.append("race=" + ",".join(toks))
    qc = r.get("classes", {}).get("v")
    if qc is not None:
        parts.append("class=" + ",".join(game.CLASSES[x] for x in sorted(qc) if x in game.CLASSES))
    return " ".join(parts)


class Scheduler:
    """Greedy ordering of accept / complete / turn-in actions inside a set of zones."""

    def __init__(self, facts, quests, zones, levels, done_before, carry, start_pos, multi_zone=False):
        self.f = facts
        self.quests = {r["q"]: r for r in quests}
        self.zones = {lint.zone_key(z) for z in zones}
        self.levels = levels
        self.done = set(done_before)
        self.carry = dict(carry)  # quest -> record, accepted earlier, turn-in still open
        self.pos = start_pos
        self.multi = multi_zone

    def _pre_ok(self, r):
        pre = r["pre"]
        if pre["state"] not in ("secured", "conflict"):
            return True
        return all(any(g in self.done for g in group) for group in pre["v"])

    def _cost(self, target):
        if self.pos is None:
            return 0.0
        m1, w1, n1 = self.pos
        m2, w2, n2 = target
        inst1, inst2 = self.f.frames.instance(m1), self.f.frames.instance(m2)
        if inst1 != inst2:
            return 1e7
        d = geo.dist((n1, w1), (n2, w2))
        if lint.zone_key(m1) != lint.zone_key(m2):
            d += 5000.0
        return d

    def run(self):
        """Greedy: the cheapest next action. Cost = distance in yards plus LEVEL_PENALTY yards for
        every level an accept would raise the planned level. The planned level never goes down
        and is the lowest level that meets the rules (min level, quest level at most 2 above)."""
        accepted, completed, turned = {}, set(), []
        actions = []
        planned = self.levels[0]
        for q, r in self.carry.items():
            accepted[q] = r
            completed.add(q)
        while True:
            cands = []
            for q, r in accepted.items():
                if q in turned:
                    continue
                if q not in completed and r.get("obj"):
                    pos = next((o["pos"] for o in r["obj"] if o.get("pos")), None)
                    cands.append((self._cost(pos) if pos else 0.0, 2, "complete", q, pos, planned))
                elif lint.zone_key(r["endPos"]["v"][0]) in self.zones:
                    cands.append((self._cost(r["endPos"]["v"]), 0, "turnin", q, r["endPos"]["v"], planned))
            open_log = len([q for q in accepted if q not in turned])
            if open_log < LOG_LIMIT:
                for q, r in self.quests.items():
                    if q in accepted or q in self.done:
                        continue
                    mn = r.get("min", {}).get("v") or 1
                    lvl = r.get("level", {}).get("v") or mn
                    need = max(mn, lvl - LEVEL_ABOVE, planned)
                    if need > self.levels[1] or lvl < self.levels[0] - TRIVIAL_BELOW:
                        continue
                    if not self._pre_ok(r):
                        continue
                    cost = self._cost(r["startPos"]["v"]) + LEVEL_PENALTY * (need - planned)
                    cands.append((cost, 1, "accept", q, r["startPos"]["v"], need))
            if not cands:
                break
            cands.sort(key=lambda c: (c[0], c[1], c[3]))
            cost, _, verb, q, pos, need = cands[0]
            planned = need
            if verb == "accept":
                accepted[q] = self.quests[q]
            elif verb == "complete":
                completed.add(q)
            else:
                turned.append(q)
                self.done.add(q)
            actions.append((verb, q, pos, planned))
            if pos:
                self.pos = pos
        open_quests = {q: r for q, r in accepted.items() if q not in turned}
        return actions, open_quests


def _goto_line(verb, q, pos, facts):
    r = facts.q[q]
    if verb == "accept":
        field = r["startPos"]
        psrc, roots = ",".join(field["src"]), field.get("roots", 1)
    elif verb == "turnin":
        field = r["endPos"]
        psrc, roots = ",".join(field["src"]), field.get("roots", 1)
    else:
        o = next(o for o in r["obj"] if o.get("pos"))
        psrc, roots = ",".join(o["src"]), 1
    return "  goto %d %.1f,%.1f r=10 | src=%s status=unbestätigt roots=%d" % (pos[0], pos[1], pos[2], psrc, roots)


def _el_line(verb, q, facts):
    r = facts.q[q]
    if verb == "accept":
        src = _src(r.get("start", {})) or _src(r.get("startPos", {}))
    elif verb == "turnin":
        src = _src(r.get("end", {})) or _src(r.get("endPos", {}))
    else:
        src = ",".join(sorted({x for o in r.get("obj", []) for x in o.get("src", [])}))
    return "  %s %d | src=%s status=unbestätigt" % (verb, q, src)


def _emit_steps(actions, facts, races_universe, first_travel=None, ret_reason=None, start_zone=None):
    """Group actions into steps and write them as text lines. A zone change gets its own
    travel step without filter, so every combination sees it."""
    steps = []
    for verb, q, pos, lv in actions:
        r = facts.q[q]
        filt = _filter_text(r, races_universe)
        if steps:
            last = steps[-1]
            same = (
                last["pos"] is not None
                and pos is not None
                and lint.zone_key(last["pos"][0]) == lint.zone_key(pos[0])
                and geo.dist((last["pos"][2], last["pos"][1]), (pos[2], pos[1])) <= SAME_SPOT
                and last["filter"] == filt
                and verb in ("accept", "turnin")
                and last["verbs"] <= {"accept", "turnin"}
            )
            if same:
                last["actions"].append((verb, q, pos))
                last["verbs"].add(verb)
                last["lv"] = max(last["lv"], lv)
                continue
        steps.append({"actions": [(verb, q, pos)], "pos": pos, "filter": filt, "verbs": {verb}, "lv": lv})

    lines = []
    zone = start_zone
    visited = {lint.zone_key(start_zone)} if start_zone else set()
    used_ids = set()

    def new_id(base):
        sid = base
        while sid in used_ids:
            sid += "x"
        used_ids.add(sid)
        return sid

    def travel(how, to, lv):
        nonlocal zone
        head = "@%s lv=%d" % (new_id("r%d" % to), lv)
        if ret_reason:
            head += ' !return "%s"' % ret_reason
        lines.append(head)
        lines.append("  travel %s %d | src=plan status=unbestätigt" % (how, to))
        zone = to
        visited.add(lint.zone_key(to))

    for i, s in enumerate(steps):
        verb, q, pos = s["actions"][0]
        if i == 0 and first_travel:
            travel(first_travel[0], first_travel[1], s["lv"])
        if pos is not None and (zone is None or lint.zone_key(pos[0]) != lint.zone_key(zone)):
            if zone is None:
                zone = pos[0]
                visited.add(lint.zone_key(zone))
            else:
                same_inst = facts.frames.instance(pos[0]) == facts.frames.instance(zone)
                travel("walk" if same_inst else "boat", pos[0], s["lv"])
        sid = new_id({"accept": "a", "complete": "c", "turnin": "t"}[verb] + str(q))
        head = "@%s lv=%d" % (sid, s["lv"])
        if s["filter"]:
            head += " << " + s["filter"]
        lines.append(head)
        for v, qq, _ in s["actions"]:
            lines.append(_el_line(v, qq, facts))
        if pos is not None:
            lines.append(_goto_line(verb, q, pos, facts))
    return lines, zone


def _header(key, kind, faction, mode, levels, sources, for_filter=None, text=None):
    out = [
        "-- SPDX-License-Identifier: GPL-3.0-only",
        "-- Generated by tools/routekit (build) from data/plan and data/facts. Computed route, not played.",
        "-- Contains data from Polestar forever-db (GPL-3.0-only), EG Link (CC BY 4.0, Efficient Games)",
        "-- and All The Things (MIT); see NOTICE.",
        "#module %s" % key,
        "#kind %s" % kind,
        "#faction %s" % faction,
        "#mode %s" % mode,
        "#levels %d-%d" % tuple(levels),
    ]
    if for_filter:
        out.append("#for %s" % for_filter)
    if text:
        out.append("#text %s" % text)
    out += ["#label vorläufig", "#version 1", "#sources %s" % sources, ""]
    return out


def _sources_header():
    meta = read_json(repo_path("data", "facts", "FACTS.json"))
    parts = []
    for s in ("polestar", "att", "eglink"):
        m = meta["sources"].get(s)
        if m:
            v = m.get("version")
            parts.append("%s=%s%s" % (s, (v + "@") if v else "", m["commit"][:7]))
    return " ".join(parts)


def _quest_zone_ok(r, zones, allow_end_zones):
    zs = {lint.zone_key(z) for z in zones}
    if lint.zone_key(r["startPos"]["v"][0]) not in zs:
        return False
    for o in r.get("obj", []):
        if o.get("pos") and lint.zone_key(o["pos"][0]) not in zs:
            return False
    return lint.zone_key(r["endPos"]["v"][0]) in {lint.zone_key(z) for z in allow_end_zones}


def _zones_of(r):
    zs = {lint.zone_key(r["startPos"]["v"][0]), lint.zone_key(r["endPos"]["v"][0])}
    zs |= {lint.zone_key(o["pos"][0]) for o in r.get("obj", []) if o.get("pos")}
    return zs


def build_faction(plan, facts, mode, exclude, sources):
    faction = plan["faction"]
    px = plan["prefix"]
    fr = game.races_of(faction)
    files = {}
    compose = ["#mode %s" % mode]
    pool = Pool(facts, faction, fr, mode, exclude)
    start_zones = {lint.zone_key(z) for st in plan["start"] for z in st["zones"]}
    core_zones = {lint.zone_key(b["zone"]) for b in plan["core"]}
    placed = collections.defaultdict(set)  # raceID -> quests placed in start or core modules

    # start modules
    for st in plan["start"]:
        races = [game.RACE_BY_TOKEN[t] for t in st["races"]]
        p = Pool(facts, faction, races, mode, exclude)
        quests = [r for r in facts.q.values() if p.usable(r, True) and _quest_zone_ok(r, st["zones"], st["zones"])]
        quests = [
            r
            for r in quests
            if r.get("classes", {}).get("v") is None
            or any(c in r["classes"]["v"] for race in races for c in game.COMBOS[race])
        ]
        key = "%s-%s-start-%s" % (px, mode, st["module"])
        sch = Scheduler(facts, quests, st["zones"], st["levels"], set(), {}, None)
        actions, _ = sch.run()
        lines, _ = _emit_steps(actions, facts, races, start_zone=st["zones"][0])
        text = _header(key, "start", faction, mode, st["levels"], sources, "race=" + ",".join(st["races"]))
        files[key] = text + lines
        compose.append("start %s << race=%s" % (key, ",".join(st["races"])))
        for race in races:
            placed[race] |= {a[1] for a in actions}

    # core blocks; class quests that stay inside the block zone go in with a class filter
    core_keys = []
    done, carry = set(), {}
    zones_later = [b["zone"] for b in plan["core"]]
    prev_pos = None
    for i, b in enumerate(plan["core"]):
        later = zones_later[i:]
        quests = [r for r in facts.q.values() if pool.usable(r, True) and _quest_zone_ok(r, [b["zone"]], later)]
        sch = Scheduler(facts, quests, [b["zone"]], b["levels"], done, carry, prev_pos)
        actions, open_q = sch.run()
        key = "%s-%s-core-%02d-%d" % (px, mode, i + 1, b["zone"])
        lines, _ = _emit_steps(actions, facts, fr, first_travel=(b["how"], b["zone"]))
        files[key] = _header(key, "core", faction, mode, b["levels"], sources) + lines
        core_keys.append(key)
        done = sch.done
        carry = open_q
        prev_pos = sch.pos
        for race in fr:
            placed[race] |= {a[1] for a in actions}
    compose.append("core " + " ".join(core_keys))

    # class inserts per race and class: class quests in zones the route does not visit
    # (capitals, Moonglade ...), anchored where the planned level fits
    anchors = [("start", 0, plan["start"][0]["levels"][1])] + [
        (k, i + 1, b["levels"][1]) for i, (k, b) in enumerate(zip(core_keys, plan["core"]))
    ]
    for race in fr:
        for cls in game.COMBOS[race]:
            p = Pool(facts, faction, [race], mode, exclude)
            cq = []
            for r in facts.q.values():
                qc = r.get("classes", {}).get("v")
                if qc is None or cls not in qc or r["q"] in placed[race] or not p.usable(r, True):
                    continue
                if _zones_of(r) & (start_zones | core_zones):
                    continue
                cq.append(r)
            by_anchor = collections.defaultdict(list)
            for r in cq:
                mn = r.get("min", {}).get("v") or r.get("level", {}).get("v") or 1
                anchor = next((a for a in anchors if a[2] >= mn), anchors[-1])
                by_anchor[anchor[0]].append(r)
            done_cls = set()
            for anchor, idx, lvl_end in anchors:
                qs = by_anchor.get(anchor)
                if not qs:
                    continue
                zones = sorted(set().union(*(_zones_of(r) for r in qs)))
                levels = [lvl_end, lvl_end]
                sch = Scheduler(facts, qs, zones, levels, done_cls, {}, None, multi_zone=True)
                actions, _ = sch.run()
                if not actions:
                    continue
                done_cls |= sch.done
                rt, ct = game.RACES[race][0], game.CLASSES[cls]
                key = "%s-%s-class-%s-%s-%02d" % (px, mode, rt.lower().replace("_", ""), ct.lower(), idx)
                first = actions[0][2]
                lines, _ = _emit_steps(actions, facts, [race], first_travel=("walk", first[0]), ret_reason="Klassenquest")
                text = _header(key, "class", faction, mode, levels, sources, "race=%s class=%s" % (rt, ct))
                files[key] = text + lines
                compose.append("insert after %s %s << race=%s class=%s" % (anchor, key, rt, ct))
    return files, compose


def write_all(plans, facts, exclude):
    sources = _sources_header()
    root = repo_path("data", "routes")
    if os.path.isdir(root):
        shutil.rmtree(root)
    counts = collections.Counter()
    for plan in plans:
        fdir = os.path.join(root, plan["faction"].lower())
        os.makedirs(fdir, exist_ok=True)
        comp_lines = [
            "-- SPDX-License-Identifier: GPL-3.0-only",
            "-- Generated by tools/routekit (build). Which modules make the route for a race and class.",
            "#faction %s" % plan["faction"],
        ]
        for mode in routefmt.MODES:
            files, compose = build_faction(plan, facts, mode, exclude, sources)
            for key, lines in files.items():
                with open(os.path.join(fdir, key + ".route"), "w", encoding="utf-8", newline="\n") as fh:
                    fh.write("\n".join(lines) + "\n")
                counts["modules"] += 1
            comp_lines += compose
        with open(os.path.join(fdir, "COMPOSE"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write("\n".join(comp_lines) + "\n")
    return counts


def load_plans():
    plans = []
    for name in ("alliance", "horde"):
        with open(repo_path("data", "plan", name + ".toml"), "rb") as fh:
            plans.append(tomllib.load(fh))
    return plans


def run():
    facts = lint.Facts.load()
    plans = load_plans()
    exclude = set()
    for rnd in range(1, MAX_ROUNDS + 1):
        counts = write_all(plans, facts, exclude)
        mods, comps = lint.load_routes()
        errs = lint.lint_all(mods, comps, facts)
        bad = {e.quest for e in errs if e.quest is not None}
        if not errs:
            return {"rounds": rnd, "modules": counts["modules"], "excluded": len(exclude)}
        if not bad:
            for e in errs[:20]:
                print(e)
            raise SystemExit("build: %d linter errors without a quest to leave out" % len(errs))
        exclude |= bad
    for e in errs[:20]:
        print(e)
    raise SystemExit("build: linter still finds %d errors after %d rounds" % (len(errs), MAX_ROUNDS))
