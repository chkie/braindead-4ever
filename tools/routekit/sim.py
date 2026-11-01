# SPDX-License-Identifier: GPL-3.0-or-later
"""Route simulator (Welle 6a, DR 22c §A): plays the composed route of one race, class and mode
step by step and prices it in model time, reported as Modellstunden (model hours: what the
model charges for the route, not a forecast of real play time; DR 22b §6).

State while playing: position, model time, level and XP, quest log, accepted, completed and
handed-in quests, hearthstone binding and cooldown, flight paths learnt, and counters (yards
walked, kills, talks, flights, grind). Time comes from the parameters in data/plan/params.toml
(DR 22b); XP from tools/routekit/xp.py, the same rules as the addon (Pathmark/Routes/XP.lua).

Rules of the model (each one a parameter or a stated choice in params.toml):

- Walking: straight line between positions x detour factor of the continent / run speed.
- Changing continent, or a step that travels by boat, zeppelin, airship or tram: one transport
  (half a cycle waiting, then the ride); a portal costs one object use; `travel fly` flies the
  straight line; `hs` hearths to the bound place when the stone is ready.
- Objectives: kills at the quest's level with the class factor; one kill per item to collect;
  objects and talks one use each; event objectives as escorts. Kills on the way add
  `extra_kills` per objective kill.
- Kill XP with the Forever rule; quest XP at the level of the turn-in with the reduction by
  level difference.
- Grind fill: an accept needs the planned level of its step (and the quest's minimum level); a
  character below it grinds creatures of its own level at kill XP / kill time x grind_eff.
  The route ends when the character reaches the highest level of its modules (30 today); the
  rest is ground as well.
- Quest log: more than 40 open quests is an error (R30), more than 35 is above the working
  limit (decision of the plan).

The simulator is deterministic: no random numbers, no set iteration over strings, no clock.
Time is also kept as counters (DR 22c §D, Polestar pattern): model time = counters x
parameters, so other class profiles and parameter draws need no new play (`time_from`).
"""

import tomllib

from . import game, geo, lint, routefmt, xp
from .io import repo_path

PARAMS_PATH = repo_path("data", "plan", "params.toml")
FOREVER = ("ja", "unbestätigt", "gewählt")
TRANSPORT = ("boat", "zeppelin", "airship", "tram")


class Params:
    """data/plan/params.toml: model parameters (`param`), model checks (`check`), limits (`limit`)."""

    def __init__(self, raw):
        self.raw = raw
        self.param = raw.get("param", {})
        self.check = raw.get("check", {})
        self.limit = raw.get("limit", {})

    @classmethod
    def load(cls, path=None):
        with open(path or PARAMS_PATH, "rb") as fh:
            return cls(tomllib.load(fh))

    def __getitem__(self, key):
        return self.param[key]["value"]

    def lim(self, key):
        return self.limit[key]["value"]

    def errors(self):
        """Entries without a value, a source or a Forever status; parameters also need a date."""
        out = []
        for table in ("param", "check", "limit"):
            for key, e in sorted(self.raw.get(table, {}).items()):
                if "value" not in e:
                    out.append("%s.%s: no value" % (table, key))
                if not str(e.get("source", "")).strip():
                    out.append("%s.%s: no source" % (table, key))
                if e.get("forever") not in FOREVER:
                    out.append("%s.%s: forever must be one of %s" % (table, key, ", ".join(FOREVER)))
                if table != "limit" and not e.get("date"):
                    out.append("%s.%s: no date" % (table, key))
                if e.get("forever") == "gewählt" and not (e.get("note") or "gewählt" in str(e.get("source"))):
                    if table == "param":
                        out.append("%s.%s: a chosen value needs a note why" % (table, key))
        return out

    def with_values(self, values):
        """A copy with other parameter values ({key: value}), for the parameter draws."""
        raw = {k: dict(v) for k, v in self.raw.items()}
        raw["param"] = {k: dict(v) for k, v in self.param.items()}
        for k, v in values.items():
            raw["param"][k]["value"] = v
        return Params(raw)


def kill_weights(level, mob_level, params):
    """(a, b) with kill seconds = (kill_sec_1 x a + kill_sec_60 x b) x class factor: the linear
    prior from level 1 to 60, then more time for creatures above and less below."""
    t = (min(max(level, 1), 60) - 1) / 59.0
    diff = mob_level - level
    if diff > 0:
        f = 1 + params["kill_above"] * diff
    else:
        f = max(params["kill_below_min"], 1 - params["kill_below"] * (-diff))
    return (1 - t) * f, t * f


def instance_detour(inst, params):
    if inst == 0:
        return params["detour_eastern_kingdoms"]
    if inst == 1:
        return params["detour_kalimdor"]
    return params["detour_other"]


COUNTERS = (
    "walk_yd_0",  # yards walked on foot, Eastern Kingdoms
    "walk_yd_1",  # Kalimdor
    "walk_yd_x",  # other instances (Zephras Isle)
    "mount_yd_0",  # yards ridden (level >= mount_level)
    "mount_yd_1",
    "mount_yd_x",
    "fly_yd",
    "flights",
    "transports",
    "portals",
    "hearths",
    "talks",
    "interacts",
    "escorts",
    "levelups",
    "kill_a",  # objective kills incl. kills on the way, weights for kill_sec_1
    "kill_b",  # ... for kill_sec_60
    "grind_a",  # grind kills, weights for kill_sec_1 (divided by grind_eff)
    "grind_b",
)


def time_from(counters, params, class_factor):
    """Model seconds from counters: the same sum the simulator adds up step by step."""
    c = counters
    v = params["run_speed"]
    m = v * params["mount_speed"]
    det = (params["detour_eastern_kingdoms"], params["detour_kalimdor"], params["detour_other"])
    t = 0.0
    for i, suffix in enumerate(("0", "1", "x")):
        t += c["walk_yd_" + suffix] * det[i] / v + c["mount_yd_" + suffix] * det[i] / m
    t += c["fly_yd"] / params["flight_speed"] + c["flights"] * (params["flight_hop_sec"] + params["flight_overhead_sec"])
    cycle = params["transport_cycle_sec"]
    t += c["transports"] * (cycle / 2 + (cycle / 2 - params["transport_dock_sec"]))
    t += c["portals"] * params["portal_sec"] + c["hearths"] * params["hearth_cast_sec"]
    t += c["talks"] * params["talk_sec"] + c["interacts"] * params["interact_sec"] + c["escorts"] * params["escort_sec"]
    t += c["levelups"] * params["level_overhead_sec"]
    k1, k60 = params["kill_sec_1"], params["kill_sec_60"]
    t += class_factor * (k1 * c["kill_a"] + k60 * c["kill_b"])
    t += class_factor * (k1 * c["grind_a"] + k60 * c["grind_b"]) / params["grind_eff"]
    return t


class Run:
    """Result of one simulated route: actions, legs, per-level and per-module records, counters."""

    def __init__(self, mode, race, cls, keys):
        self.mode, self.race, self.cls, self.keys = mode, race, cls, keys
        self.actions = []  # dicts, in the order played
        self.legs = []  # dicts: frm, to, inst, yd, kind, sec, action (index of the action it leads to)
        self.modules = []  # dicts per module: key, kind, levels, t0, t1, quest_xp, kill_xp, grind_xp, ...
        self.counters = {k: 0.0 for k in COUNTERS}
        self.level_time = {}  # level -> model seconds spent in that level
        self.level_grind = {}  # level -> model seconds of grind in that level
        self.reached = {1: 0.0}  # level -> model time it was reached
        self.counters_at = {1: {k: 0.0 for k in COUNTERS}}  # level -> counters when it was reached
        self.gates = []  # grind fills: dicts with idx, level from/to, xp, sec, announced, reason
        self.stuck = []  # (action index or -1, text)
        self.log_peak = 0
        self.log_over_work = 0  # accepts that pushed the log above the working limit
        self.hearth_errors = []  # (index, rule, text)
        self.binds = []  # (action index, position)
        self.fps = []  # (action index, position)
        self.trains = []  # action indices
        self.xp_marks = []  # (action index, step has a place): `xp` elements, the announced grinds
        self.quest = {}  # q -> {"a": idx, "c": idx, "t": idx, "lv_t": level at turn-in, ...}
        self.end_level = 1
        self.target = 0
        self.time = 0.0

    @property
    def hours(self):
        return self.time / 3600.0


class Simulator:
    def __init__(self, facts, mods, params):
        self.f = facts
        self.mods = mods
        self.p = params

    # --- state helpers -------------------------------------------------------------------------

    def _class_factor(self, cls):
        return self.p["class_factor"][game.CLASSES[cls]]

    def _add_time(self, run, sec, grind=False):
        run.time += sec
        run.level_time[self.level] = run.level_time.get(self.level, 0.0) + sec
        if grind:
            run.level_grind[self.level] = run.level_grind.get(self.level, 0.0) + sec

    def _add_xp(self, run, amount):
        """Adds XP; every level-up costs level_overhead_sec (trainer, vendor)."""
        self.xp += amount
        while self.level < xp.MAX_LEVEL:
            need = xp.to_level(self.level)
            if need is None or self.xp < need:
                break
            self.xp -= need
            self.level += 1
            run.reached[self.level] = run.time
            run.counters_at[self.level] = dict(run.counters)
            run.counters["levelups"] += 1
            self._add_time(run, self.p["level_overhead_sec"])

    def _kill(self, run, n, mob_level):
        """n objective kills (fractional allowed), each with kills on the way."""
        extra = self.p["extra_kills"]
        food = self.p["food_kill_xp"]
        gained = 0.0
        left = n
        while left > 1e-9:
            k = min(1.0, left)
            left -= k
            a, b = kill_weights(self.level, mob_level, self.p)
            w = k * (1 + extra)
            run.counters["kill_a"] += w * a
            run.counters["kill_b"] += w * b
            self._add_time(run, self.cf * w * (self.p["kill_sec_1"] * a + self.p["kill_sec_60"] * b))
            g = w * xp.kill_xp(self.level, mob_level) * (1 + food)
            gained += g
            self._add_xp(run, g)
        return gained

    def _grind_to(self, run, level, idx, reason, announced):
        """Grinds creatures of the character's own level until `level` is reached."""
        if self.level >= level:
            return
        g = {"idx": idx, "from": self.level + self.xp / (xp.to_level(self.level) or 1), "to": level, "xp": 0.0,
             "sec": 0.0, "announced": announced, "reason": reason, "pos": self.pos}
        eff = self.p["grind_eff"]
        while self.level < level:
            need = xp.to_level(self.level) - self.xp
            per = xp.kill_xp(self.level, self.level) * (1 + self.p["food_kill_xp"])
            kills = need / per
            a, b = kill_weights(self.level, self.level, self.p)
            run.counters["grind_a"] += kills * a
            run.counters["grind_b"] += kills * b
            sec = self.cf * kills * (self.p["kill_sec_1"] * a + self.p["kill_sec_60"] * b) / eff
            self._add_time(run, sec, grind=True)
            g["xp"] += need
            g["sec"] += sec
            self.cur_module["grind_xp"] += need
            self.cur_module["grind_sec"] += sec
            self._add_xp(run, need)
        run.gates.append(g)

    def _speed(self):
        return self.p["run_speed"] * (self.p["mount_speed"] if self.level >= self.p["mount_level"] else 1.0)

    def _move(self, run, target, how, idx, ui_map=None):
        """Moves to target (instance, north, west) on uiMap ui_map. Returns the leg or None."""
        if target is None:
            return None
        if self.pos is None:
            self.pos, self.pos_map = target, ui_map
            return None
        frm = self.pos
        if frm == target:
            return None
        same = frm[0] == target[0]
        yd = geo.dist(frm[1:], target[1:]) if same else 0.0
        leg = {"frm": frm, "to": target, "inst": target[0] if same else None, "yd": yd, "action": idx, "kind": "walk",
               "maps": (self.pos_map, ui_map)}
        if how == "portal":
            leg["kind"] = "portal"
            run.counters["portals"] += 1
            sec = self.p["portal_sec"]
        elif how in TRANSPORT or not same:
            leg["kind"] = "transport"
            run.counters["transports"] += 1
            cycle = self.p["transport_cycle_sec"]
            sec = cycle / 2 + (cycle / 2 - self.p["transport_dock_sec"])
        elif how == "fly":
            leg["kind"] = "fly"
            run.counters["fly_yd"] += yd
            run.counters["flights"] += 1
            sec = yd / self.p["flight_speed"] + self.p["flight_hop_sec"] + self.p["flight_overhead_sec"]
        else:
            suffix = "0" if target[0] == 0 else "1" if target[0] == 1 else "x"
            mounted = self.level >= self.p["mount_level"]
            run.counters[("mount_yd_" if mounted else "walk_yd_") + suffix] += yd
            sec = yd * instance_detour(target[0], self.p) / self._speed()
        leg["sec"] = sec
        self._add_time(run, sec)
        self.cur_module["move_sec"] += sec
        if leg["kind"] == "walk":
            self.cur_module["walk_yd"] += yd
        run.legs.append(leg)
        self.pos, self.pos_map = target, ui_map
        return leg

    def _world(self, ui_map, west, north):
        inst = self.f.frames.instance(ui_map)
        return (inst if inst is not None else -1, north, west)

    # --- playing -------------------------------------------------------------------------------

    def run(self, mode, race, cls, keys):
        run = Run(mode, race, cls, keys)
        self.cf = self._class_factor(cls)
        self.level, self.xp = 1, 0.0
        self.pos = None
        self.pos_map = None
        self.bind = None
        self.bind_map = None
        self.hearth_ready = 0.0
        self.log = []  # open quests in accept order
        self.accepted, self.completed, self.turned = set(), set(), set()
        self.announced = 0  # highest level an `xp` element announced
        levels_hi = [self.mods[k].levels()[1] for k in keys if k in self.mods and self.mods[k].levels()]
        run.target = max(levels_hi) if levels_hi else 1
        zone = None
        for key in keys:
            mod = self.mods.get(key)
            if mod is None:
                run.stuck.append((-1, "Modul %s fehlt" % key))
                continue
            if mod.filter and not mod.filter.applies(race, cls):
                continue
            self.cur_module = {"key": key, "kind": mod.kind, "levels": mod.levels(), "t0": run.time,
                               "level0": self.level + self.xp / (xp.to_level(self.level) or 1), "quest_xp": 0.0,
                               "kill_xp": 0.0, "grind_xp": 0.0, "grind_sec": 0.0, "move_sec": 0.0, "walk_yd": 0.0,
                               "accepts": 0, "turnins": 0}
            for st in mod.steps:
                if st.filter and not st.filter.applies(race, cls):
                    continue
                els = [el for el in st.elements if not el.filter or el.filter.applies(race, cls)]
                if not els:
                    continue
                zone = self._step(run, mod, st, els, zone)
            m = self.cur_module
            m["t1"] = run.time
            m["level1"] = self.level + self.xp / (xp.to_level(self.level) or 1)
            run.modules.append(m)
        # the route ends at its highest planned level: grind the rest
        self.cur_module = {"key": "(Ende)", "kind": "end", "levels": None, "t0": run.time, "quest_xp": 0.0,
                           "kill_xp": 0.0, "grind_xp": 0.0, "grind_sec": 0.0, "move_sec": 0.0, "walk_yd": 0.0,
                           "accepts": 0, "turnins": 0,
                           "level0": self.level + self.xp / (xp.to_level(self.level) or 1)}
        self._grind_to(run, run.target, len(run.actions), "Routenende", self.announced >= run.target)
        self.cur_module["t1"] = run.time
        self.cur_module["level1"] = self.level + self.xp / (xp.to_level(self.level) or 1)
        run.modules.append(self.cur_module)
        run.end_level = self.level
        for q in self.log:
            run.stuck.append((-1, "Quest %d angenommen und nie abgegeben" % q))
        run.open_at_end = list(self.log)
        return run

    def _step(self, run, mod, st, els, zone):
        travel_to = [el.args for el in els if el.verb == "travel"]
        how = travel_to[-1]["how"] if travel_to else None
        gotos = [el.args for el in els if el.verb == "goto"]
        target = self._world(gotos[0]["map"], gotos[0]["wx"], gotos[0]["wy"]) if gotos else None
        new_zone = travel_to[-1]["map"] if travel_to else (gotos[0]["map"] if gotos else None)
        if new_zone is not None:
            zone = new_zone
        idx = len(run.actions)
        for el in els:
            if el.verb == "xp":
                self.announced = max(self.announced, el.args["level"])
                run.xp_marks.append((idx, bool(gotos)))
        # grind gate: the planned level of the step and the minimum level of what it accepts
        accepts = [el.args["q"] for el in els if el.verb == "accept"]
        if accepts:
            need = st.lv or 1
            for q in accepts:
                mn = (self.f.q.get(q) or {}).get("min", {}).get("v") or 1
                need = max(need, mn)
            if self.level < need:
                self._grind_to(run, need, idx, "Stufe %d für @%s" % (need, st.id), self.announced >= need)
        hs = any(el.verb == "hs" for el in els) or how == "hearth"
        if hs:
            self._hearth(run, idx, target)
        if target is not None:
            self._move(run, target, how, idx, gotos[0]["map"])
        for el in els:
            self._element(run, mod, st, el, zone, how)
        return zone

    def _hearth(self, run, idx, target):
        if self.bind is None:
            run.hearth_errors.append((idx, "R10", "Ruhestein ohne Bindung"))
            return
        if run.time < self.hearth_ready:
            run.hearth_errors.append((idx, "R12", "Ruhestein noch %.0f s Abklingzeit" % (self.hearth_ready - run.time)))
            return
        if self.pos is not None and self.pos[0] == self.bind[0] and geo.dist(self.pos[1:], self.bind[1:]) <= 50:
            run.hearth_errors.append((idx, "R10", "Ruhestein, obwohl schon am Bindeort"))
        run.counters["hearths"] += 1
        self._add_time(run, self.p["hearth_cast_sec"])
        run.legs.append({"frm": self.pos, "to": self.bind, "inst": None, "yd": 0.0, "action": idx, "kind": "hearth",
                         "sec": self.p["hearth_cast_sec"]})
        self.pos, self.pos_map = self.bind, self.bind_map
        self.hearth_ready = run.time + self.p["hearth_cooldown_sec"]

    def _record(self, run, mod, st, el, zone, q=None):
        a = {"idx": len(run.actions), "module": mod.key, "kind": mod.kind, "step": st.id, "lv": st.lv,
             "verb": el.verb, "q": q, "pos": self.pos, "zone": zone, "t": run.time, "level": self.level,
             "xpin": self.xp, "log": len(self.log)}
        run.actions.append(a)
        return a

    def _element(self, run, mod, st, el, zone, how):
        verb = el.verb
        q = el.args.get("q")
        r = (self.f.q.get(q) or {}) if q is not None else {}
        if verb == "accept":
            a = self._record(run, mod, st, el, zone, q)
            if q in self.accepted:
                run.stuck.append((a["idx"], "Quest %d zweimal angenommen" % q))
            pre = r.get("pre", {})
            if pre.get("state") in ("secured", "conflict"):
                for group in pre.get("v", []):
                    if not any(g in self.turned for g in group):
                        run.stuck.append((a["idx"], "Quest %d vor Vorquest %s" % (q, "/".join(map(str, group)))))
            self.accepted.add(q)
            self.log.append(q)
            if len(self.log) > self.p["quest_log_limit"]:
                run.stuck.append((a["idx"], "Questlog über %d (R30)" % self.p["quest_log_limit"]))
            if len(self.log) > self.p["quest_log_work"]:
                run.log_over_work += 1
            run.log_peak = max(run.log_peak, len(self.log))
            run.counters["talks"] += 1
            self._add_time(run, self.p["talk_sec"])
            run.quest.setdefault(q, {})["a"] = a["idx"]
            run.quest[q]["lv_a"] = self.level
            self.cur_module["accepts"] += 1
        elif verb == "complete":
            a = self._record(run, mod, st, el, zone, q)
            if q not in self.accepted:
                run.stuck.append((a["idx"], "Quest %d abgeschlossen, aber nicht angenommen" % q))
            self._work(run, q, r, a["idx"])
            self.completed.add(q)
            run.quest.setdefault(q, {})["c"] = len(run.actions) - 1
            a["t_end"] = run.time
            a["pos_end"] = self.pos
        elif verb == "turnin":
            a = self._record(run, mod, st, el, zone, q)
            if q not in self.accepted:
                run.stuck.append((a["idx"], "Quest %d abgegeben, aber nicht angenommen" % q))
            run.counters["talks"] += 1
            self._add_time(run, self.p["talk_sec"])
            full = (r.get("xp") or {}).get("v") or 0
            ql = (r.get("level") or {}).get("v")
            got = xp.quest_xp(full, ql, self.level)
            info = run.quest.setdefault(q, {})
            info.update({"t": a["idx"], "lv_t": self.level, "xp_t": got, "full": full, "ql": ql,
                         "xp_plan": xp.quest_xp(full, ql, st.lv or self.level), "lv_plan": st.lv})
            self.cur_module["quest_xp"] += got
            self.cur_module["turnins"] += 1
            if q in self.log:
                self.log.remove(q)
            self.turned.add(q)
            self._add_xp(run, got)
        elif verb == "collect":
            a = self._record(run, mod, st, el, zone)
            run.counters["interacts"] += el.args["n"]
            self._add_time(run, el.args["n"] * self.p["interact_sec"])
        elif verb == "sethome":
            a = self._record(run, mod, st, el, zone)
            self.bind, self.bind_map = self.pos, self.pos_map
            run.binds.append((a["idx"], self.pos))
        elif verb == "fp":
            a = self._record(run, mod, st, el, zone)
            run.fps.append((a["idx"], self.pos))
        elif verb == "train":
            a = self._record(run, mod, st, el, zone)
            run.trains.append(a["idx"])
        elif verb in ("hs", "travel", "xp"):
            self._record(run, mod, st, el, zone)

    def _work(self, run, q, r, idx):
        """Objectives of quest q: walk to every objective position (nearest first), then work."""
        objs = r.get("obj", [])
        ql = (r.get("level") or {}).get("v") or self.level
        pts, maps = [], {}
        for o in objs:
            if o.get("pos"):
                p = self._world(o["pos"][0], o["pos"][1], o["pos"][2])
                if p not in pts and p != self.pos:
                    pts.append(p)
                    maps[p] = o["pos"][0]
        while pts:
            if self.pos is None:
                nxt = pts[0]
            else:
                same = [p for p in pts if p[0] == self.pos[0]]
                cand = same or pts
                nxt = min(cand, key=lambda p: (geo.dist(self.pos[1:], p[1:]) if p[0] == self.pos[0] else 1e9, p))
            pts.remove(nxt)
            self._move(run, nxt, None, idx, maps[nxt])
        gained = 0.0
        for o in objs:
            k, n = o.get("k"), o.get("count") or 1
            if k == "kill":
                gained += self._kill(run, n, ql)
            elif k == "item":
                gained += self._kill(run, n * self.p["item_kills"], ql)
            elif k == "object":
                run.counters["interacts"] += n
                self._add_time(run, n * self.p["interact_sec"])
            elif k == "talk":
                run.counters["talks"] += 1
                self._add_time(run, self.p["talk_sec"])
            elif k == "event":
                run.counters["escorts"] += 1
                self._add_time(run, self.p["escort_sec"])
        self.cur_module["kill_xp"] += gained
        run.quest.setdefault(q, {})["kill_xp"] = gained


def load(params=None):
    """Facts, modules, compositions and parameters of the repository."""
    facts = lint.Facts.load()
    mods, comps = lint.load_routes()
    return facts, mods, comps, params or Params.load()


def combos(comps, modes=routefmt.MODES, combo_list=None):
    """(mode, race, class, module keys) for every combination, in a fixed order."""
    out = []
    for mode in modes:
        for race, cls in combo_list or game.all_combos():
            faction = game.faction_of(race)
            comp = next((c for c in comps if c.faction == faction and mode in c.modes), None)
            keys = comp.route(mode, race, cls) if comp else None
            out.append((mode, race, cls, keys or []))
    return out


def simulate_all(facts, mods, comps, params, modes=routefmt.MODES, combo_list=None):
    sim = Simulator(facts, mods, params)
    return [sim.run(mode, race, cls, keys) for mode, race, cls, keys in combos(comps, modes, combo_list)]


def _r(x):
    return round(x, 6) if isinstance(x, float) else x


def digest(runs):
    """sha256 over everything the runs report, floats rounded to 6 decimals (P1: two runs on the
    same input give the same digest)."""
    import hashlib
    import json

    out = []
    for run in runs:
        out.append({
            "combo": [run.mode, run.race, run.cls, run.keys],
            "actions": [[a["module"], a["step"], a["verb"], a["q"], _r(a["t"]), a["level"], _r(a["xpin"]), a["log"]]
                        for a in run.actions],
            "legs": [[g["kind"], _r(g["yd"]), _r(g["sec"]), g["action"]] for g in run.legs],
            "counters": {k: _r(v) for k, v in run.counters.items()},
            "reached": {str(k): _r(v) for k, v in run.reached.items()},
            "gates": [[g["idx"], _r(g["from"]), g["to"], _r(g["xp"]), _r(g["sec"]), g["announced"]] for g in run.gates],
            "stuck": run.stuck,
            "log": [run.log_peak, run.log_over_work],
            "end": [run.end_level, _r(run.time)],
        })
    text = json.dumps(out, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()
