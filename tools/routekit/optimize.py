# SPDX-License-Identifier: GPL-3.0-or-later
"""Route optimizer (Welle 6b): builds the order and the choice of quests of every module by
replaying it in the time and XP model of the simulator, instead of the old nearest-action greed.

Method (brain chapter 21 §4, report DR 22c), all counted in tries, never in seconds:

1. Every block (a start zone, or one visit of a core zone) is a selective pickup-and-delivery
   problem: accept, objectives and turn-in of every chosen quest, with prerequisites, the quest
   log (working limit 35), the minimum level and quest level at most 2 above the level at the
   accept (R27, P8), and the turn-in at most 5 levels above the quest level (R01).
2. Construction: nearest feasible action among the quests that pass the worth test
   ("Lohnt-sich-Test", Factoruide): a quest is worth taking when its XP (quest and objective
   kills) per second of its own time beats the grind rate at that level divided by the grind
   weight w_g.
3. Large neighbourhood search (ALNS after Ropke/Pisinger 2006): destroy (random, related by place
   "Shaw", worst) and repair (cheapest insertion), plus moves of single actions and 2-opt, with
   record-to-record acceptance falling to 0; adaptive weights per segment of 100 tries. Every
   candidate is replayed from the block's entry state; hard rules are penalties large enough that
   no accepted solution keeps one (ThPi: the cost never sees an invalid tour).
4. Fine tuning: Held-Karp for runs of up to 10 actions at one hub (ThPi), then folding: an accept
   or turn-in moves to the earliest visit of its place where it is possible (R04, R05, Polestar
   "fold"); then worthwhile pick-ups next to the walked line (Polestar §6, P6).
5. Zone order: a beam search over the next zone visit, scored by model time plus the grind the
   rest would still need (w_g), within the zone-change budget of the start route (guard P9).
6. Plan steps: flight paths passed on the way (R13), hearthstone bound at a hub the route comes
   back to and used when that saves time (R10-R12), class trainers on the way (R25, G9), the
   announced grind with place and target (R17, R19).

The objective is the brain's J (chapter 21 §3.3): model seconds + (w_g - 1) x grind seconds,
with XP converted at the grind rate: a block's J = T - w_g x XP / grind rate(level). Every weight
is in data/plan/params.toml (`opt.*`) with its source.

Deterministic: one random.Random per block, seeded from the block's key; no clock, no set order
over strings.
"""

import math
import random
import zlib

from . import game, geo, lint, sim, xp

BIG = 36000.0  # model seconds charged for a broken hard rule: no accepted solution keeps one
NEAR = 15.0  # yards: actions this close share one step (same NPC), as build.SAME_SPOT
HUB = 60.0  # yards: a run of actions this close is one hub for Held-Karp
FP_SAME = 50.0  # yards: a flight master this close to a step's place is learnt in that step (R13: 65.6)


def xp_at(level):
    """Total XP at a fractional level (11.05 = level 11 and 5 % of its XP)."""
    lv = int(math.floor(level))
    return xp.total_to(lv) + (level - lv) * (xp.to_level(lv) or 0)


def stable_seed(text, base):
    return (zlib.crc32(text.encode("utf-8")) ^ (base * 2654435761)) & 0xFFFFFFFF


class QV:
    """What the optimizer needs of one quest (data/facts record)."""

    __slots__ = ("q", "rec", "ql", "mn", "xp", "start", "start_map", "end", "end_map", "objs", "kills", "inter",
                 "talk", "esc", "pre", "races", "classes", "zones", "start_zone", "end_zone", "obj_pos",
                 "start_ids", "end_ids", "new", "breadcrumb", "unsure")

    def __init__(self, r, frames):
        self.q = r["q"]
        self.rec = r
        self.mn = (r.get("min") or {}).get("v") or 1
        self.ql = (r.get("level") or {}).get("v") or self.mn
        self.xp = (r.get("xp") or {}).get("v") or 0
        sp, ep = r["startPos"]["v"], r["endPos"]["v"]
        self.start_map, self.end_map = sp[0], ep[0]
        self.start = world(frames, sp)
        self.end = world(frames, ep)
        self.objs = []
        seen = set()
        for o in r.get("obj", []):
            if o.get("pos"):
                w = world(frames, o["pos"])
                if w not in seen:
                    seen.add(w)
                    self.objs.append((o["pos"][0], w))
        self.obj_pos = self.objs[0][1] if self.objs else None
        self.kills, self.inter, self.talk, self.esc = [], 0, 0, 0
        for o in r.get("obj", []):
            k, n = o.get("k"), o.get("count") or 1
            if k == "kill":
                self.kills.append((n, "kill"))
            elif k == "item":
                self.kills.append((n, "item"))
            elif k == "object":
                self.inter += n
            elif k == "talk":
                self.talk += 1
            elif k == "event":
                self.esc += 1
        pre = r.get("pre", {})
        self.pre = [frozenset(g) for g in pre.get("v", [])] if pre.get("state") in ("secured", "conflict") else []
        self.unsure = pre.get("state") != "secured"
        self.breadcrumb = bool(r.get("breadcrumb"))
        self.races = frozenset(r["races"]["v"]) if (r.get("races") or {}).get("v") is not None else None
        self.classes = frozenset(r["classes"]["v"]) if (r.get("classes") or {}).get("v") is not None else None
        self.start_zone = lint.zone_key(sp[0])
        self.end_zone = lint.zone_key(ep[0])
        self.zones = {self.start_zone, self.end_zone} | {lint.zone_key(m) for m, _ in self.objs}
        self.start_ids = {e.get("id") for e in (r.get("start") or {}).get("v", []) if e.get("k") == "npc"}
        self.end_ids = {e.get("id") for e in (r.get("end") or {}).get("v", []) if e.get("k") == "npc"}
        self.new = game.is_new_quest(self.q)


def world(frames, posv):
    inst = frames.instance(posv[0])
    return (inst if inst is not None else -1, posv[2], posv[1])


def dist(a, b):
    if a is None or b is None:
        return 0.0
    if a[0] != b[0]:
        return 1e6
    return math.hypot(a[1] - b[1], a[2] - b[2])


def pos_of(env, act):
    verb, q = act
    Q = env.Q[q]
    if verb in ("a", "A"):
        return Q.start
    if verb == "t":
        return Q.end
    return Q.obj_pos or Q.start


class Env:
    """Parameters and quest views shared by all blocks of one build."""

    def __init__(self, facts, params, quests):
        self.f = facts
        self.p = params
        self.Q = quests
        P = params
        self.run = P["run_speed"]
        self.det = {0: P["detour_eastern_kingdoms"], 1: P["detour_kalimdor"]}
        self.det_x = P["detour_other"]
        self.talk = P["talk_sec"]
        self.interact = P["interact_sec"]
        self.escort = P["escort_sec"]
        self.k1, self.k60 = P["kill_sec_1"], P["kill_sec_60"]
        self.extra = P["extra_kills"]
        self.item_kills = P["item_kills"]
        self.lvl_over = P["level_overhead_sec"]
        self.grind_eff = P["grind_eff"]
        cycle = P["transport_cycle_sec"]
        self.transport = cycle / 2 + (cycle / 2 - P["transport_dock_sec"])
        self.log_work = P["quest_log_work"]
        o = params.raw.get("opt", {})
        self.w_grind = o.get("grind_weight", {}).get("value", 1.5)
        self.w_zone = o.get("zone_change_sec", {}).get("value", 240.0)
        self.r01_margin = o.get("turnin_margin", {}).get("value", 1)
        self.gate_sec = o.get("gate_sec", {}).get("value", 60.0)
        self.w_over = o.get("grind_over_weight", {}).get("value", 4.0)
        self.grind_cap = params.limit.get("p2_grind_share", {}).get("value", 0.10)
        self.gate_levels = o.get("gate_levels", {}).get("value", 0.5)
        self.gate_value = o.get("gate_value", {}).get("value", 3.0)
        self.w_return = 0.0  # seconds per avoidable return in the objective; set for the polish (P5)
        self.return_sec = o.get("return_sec", {}).get("value", 900.0)
        self.cf = 1.0
        self._kill = {}

    def detour(self, inst):
        return self.det.get(inst, self.det_x)

    def kill(self, level, mob):
        """(seconds, xp) of one objective kill incl. kills on the way, class factor self.cf."""
        key = (level, mob)
        v = self._kill.get(key)
        if v is None:
            a, b = sim.kill_weights(level, mob, self.p)
            w = 1 + self.extra
            v = (w * (self.k1 * a + self.k60 * b), w * xp.kill_xp(level, mob))
            self._kill[key] = v
        return v[0] * self.cf, v[1]

    def grind_rate(self, level):
        """XP per model second when grinding creatures of the own level (sim grind fill)."""
        a, b = sim.kill_weights(level, level, self.p)
        sec = self.cf * (self.k1 * a + self.k60 * b) / self.grind_eff
        return xp.kill_xp(level, level) / sec

    def walk_sec(self, a, b):
        if a is None or b is None or a == b:
            return 0.0
        if a[0] != b[0]:
            return self.transport
        return math.hypot(a[1] - b[1], a[2] - b[2]) * self.detour(a[0]) / self.run


class State:
    __slots__ = ("pos", "t", "level", "xp", "acc", "comp", "done", "log", "zone")

    def __init__(self, pos=None, t=0.0, level=1, xpv=0.0, acc=None, comp=None, done=None, log=0, zone=None):
        self.pos, self.t, self.level, self.xp = pos, t, level, xpv
        self.acc = set(acc or ())
        self.comp = set(comp or ())
        self.done = set(done or ())
        self.log = log
        self.zone = zone

    def copy(self):
        return State(self.pos, self.t, self.level, self.xp, self.acc, self.comp, self.done, self.log, self.zone)

    def flevel(self):
        need = xp.to_level(self.level)
        return self.level + (self.xp / need if need else 0.0)


class Result:
    __slots__ = ("T", "qxp", "kxp", "pen", "grind", "end", "levels", "info", "zones", "acc")


def replay(env, st0, acts, record=False, margin=None):
    """Plays acts [(verb, q)] from a copy of st0. Returns a Result: model seconds T, quest and kill
    XP, penalty seconds for broken hard rules, grind seconds (minimum level gates), end state;
    with record=True also the level before every action."""
    st = st0.copy()
    t0 = st.t
    acc = Acc()
    margin = env.r01_margin if margin is None else margin
    levels = [] if record else None
    track = env.w_return > 0
    near, left = set(), set()
    for k, act in enumerate(acts):
        if record:
            levels.append(st.flevel())
        if track and k in left:
            acc.returns += 1
        lv, t = st.level, st.t
        step(env, st, act, acc, margin)
        acc.lt[lv] = acc.lt.get(lv, 0.0) + st.t - t
        if track and st.pos is not None:
            # avoidable returns (P5, brain J: 900 s each): an action of the next RETURN_LOOK ones
            # that is possible while the character stands within 400 yd of its place, and is done
            # only after the character went farther away
            for j in range(k + 1, min(len(acts), k + 1 + RETURN_LOOK)):
                p = pos_of(env, acts[j])
                d = dist(st.pos, p)
                if d <= RETURN_YD:
                    if j not in near and _possible(env, st, acts[j]):
                        near.add(j)
                elif j in near:
                    left.add(j)
    res = Result()
    res.T = st.t - t0
    res.qxp, res.kxp, res.pen, res.grind, res.end = acc.qxp, acc.kxp, acc.pen, acc.grind, st
    res.levels = levels
    res.zones = acc.zones
    res.acc = acc
    return res


def _possible(env, st, act):
    verb, q = act
    R = env.Q[q]
    if verb in ("a", "A"):
        return (q not in st.acc and q not in st.done and st.level >= max(R.mn, R.ql - 2)
                and all(g & st.done for g in R.pre))
    if verb == "c":
        return q in st.acc
    return q in st.acc and (q in st.comp or not needs_work(R))


def pull_forward(env, b, budget=800):
    """Accepts, objectives and turn-ins go to the first earlier moment the character stands within
    RETURN_YD of their place while they are possible, when the objective (with the return weight)
    gets better; at most `budget` evaluations."""
    evals = 0
    changed = True
    while changed and evals < budget:
        changed = False
        st = b.st0.copy()
        acc = Acc()
        before = []
        for act in b.acts:
            before.append((st.pos, st.copy()))
            step(env, st, act, acc, env.r01_margin)
        for idx in range(len(b.acts) - 1, -1, -1):
            v, q = b.acts[idx]
            p = pos_of(env, (v, q))
            lo, _ = _window(b.acts, idx)
            for k in range(lo, idx):
                pos, stk = before[k]
                if pos is None or dist(pos, p) > RETURN_YD or not _possible(env, stk, (v, q)):
                    continue
                cand = b.acts[:idx] + b.acts[idx + 1:]
                cand.insert(k, (v, q))
                j, r = b.goal(cand)
                evals += 1
                if j < b.j - 1e-6:
                    b.acts, b.j, b.res = cand, j, r
                    changed = True
                break
            if changed or evals >= budget:
                break
    return b


RETURN_LOOK = 40  # actions ahead checked for avoidable returns
RETURN_YD = 400.0  # yards: a visit ends this far away (P5, Polestar judge)


class Acc:
    __slots__ = ("qxp", "kxp", "pen", "grind", "zones", "lt", "lg", "returns")

    def __init__(self):
        self.qxp = self.kxp = self.pen = self.grind = 0.0
        self.zones = 0
        self.returns = 0
        self.lt = {}  # level -> model seconds spent in it
        self.lg = {}  # level -> grind seconds in it

    def over_cap(self, share):
        """Grind seconds above `share` of the time of each level (brain J: grind over 10 %/level)."""
        return sum(max(0.0, g - share * self.lt.get(lv, 0.0)) for lv, g in self.lg.items())


def needs_work(R):
    return bool(R.objs or R.kills or R.inter or R.talk or R.esc)


def step(env, st, act, acc, margin):
    """One action, in place on st; sums into acc."""
    verb, q = act
    R = env.Q[q]
    if verb in ("a", "A"):
        if q in st.acc or q in st.done:
            acc.pen += BIG
        for g in R.pre:
            if not (g & st.done):
                acc.pen += BIG
        need = max(R.mn, R.ql - 2)
        if need > st.level:
            # grind gate (the sim grinds up to the planned level of the step): announced with an
            # `xp` step, charged with the grind weight
            sec = _grind_to(env, st, need, acc.lg)
            acc.grind += sec
            acc.pen += sec * (env.w_grind - 1) + env.gate_sec
        acc.zones += _move(env, st, R.start, R.start_zone)
        st.t += env.talk
        st.log += 1
        if st.log > env.log_work:
            acc.pen += BIG
        st.acc.add(q)
    elif verb == "c":
        if q not in st.acc:
            acc.pen += BIG
        if len(R.objs) == 1:
            acc.zones += _move(env, st, R.objs[0][1], lint.zone_key(R.objs[0][0]))
        elif R.objs:
            pts = list(R.objs)
            while pts:
                nxt = min(pts, key=lambda p: (dist(st.pos, p[1]), p[1]))
                pts.remove(nxt)
                acc.zones += _move(env, st, nxt[1], lint.zone_key(nxt[0]))
        for n, kind in R.kills:
            if kind == "item":
                n = n * env.item_kills
            left = float(n)
            while left > 1e-9:
                k = 1.0 if left >= 1.0 else left
                left -= k
                sec, gx = env.kill(st.level, R.ql)
                st.t += sec * k
                acc.kxp += gx * k
                _gain(env, st, gx * k)
        st.t += R.inter * env.interact + R.talk * env.talk + R.esc * env.escort
        st.comp.add(q)
    else:
        if q not in st.acc or (needs_work(R) and q not in st.comp):
            acc.pen += BIG
        acc.zones += _move(env, st, R.end, R.end_zone)
        st.t += env.talk
        if st.level > R.ql + 5 - margin:
            acc.pen += BIG / 4
        got = xp.quest_xp(R.xp, R.ql, st.level)
        acc.qxp += got
        st.log -= 1
        st.acc.discard(q)
        st.done.add(q)
        _gain(env, st, got)


def _move(env, st, target, zone):
    """Walk (or take a transport across instances). Returns 1 on a zone change."""
    if target is None:
        return 0
    if st.pos is not None and target != st.pos:
        st.t += env.walk_sec(st.pos, target)
    st.pos = target
    if zone is not None and zone != st.zone:
        changed = st.zone is not None
        st.zone = zone
        return 1 if changed else 0
    return 0


def _gain(env, st, amount):
    st.xp += amount
    while st.level < xp.MAX_LEVEL:
        need = xp.to_level(st.level)
        if need is None or st.xp < need:
            break
        st.xp -= need
        st.level += 1
        st.t += env.lvl_over


def entry_grind(env, st, level):
    """State at the start of a module with a level floor: the character grinds to `level` at the
    last place of the module before (the simulator grinds before it walks to the step). Returns
    (state, grind seconds); st itself is not changed."""
    if not level or st.level >= level:
        return st, 0.0
    st = st.copy()
    return st, _grind_to(env, st, level)


def _grind_to(env, st, level, per_level=None):
    sec = 0.0
    while st.level < level:
        need = xp.to_level(st.level) - st.xp
        s = need / env.grind_rate(st.level)
        if per_level is not None:
            per_level[st.level] = per_level.get(st.level, 0.0) + s
        sec += s
        _gain(env, st, need)
    st.t += sec
    return sec


# --- block objective ------------------------------------------------------------------------------


class Goal:
    """J of a block: T + penalties - w_g x XP / grind rate, plus the weight on grind above the
    share per level. With a target level (start modules) XP above the target is worth little, so
    the block stops near the target (G7). `credit`: quests accepted here and handed in later
    count their XP here (carried quests)."""

    def __init__(self, env, st0, target=None, credit=None):
        self.env = env
        self.st0 = st0
        self.target = target
        self.credit = credit or {}
        self.value = env.w_grind / env.grind_rate(st0.level)
        if target is not None:
            self.need = xp_at(target) - (xp.total_to(st0.level) + st0.xp)

    def __call__(self, acts):
        res = replay(self.env, self.st0, acts)
        gained = res.qxp + res.kxp
        if self.credit:
            gained += sum(self.credit.get(q, 0.0) for v, q in acts if v == "a")
        if self.target is not None:
            short = max(0.0, self.need - gained)
            over = max(0.0, gained - self.need)
            j = res.T + res.pen + self.value * short + 0.25 * self.value * over
        else:
            j = res.T + res.pen - self.value * gained + self.env.w_zone * res.zones
        j += (self.env.w_over - self.env.w_grind) * res.acc.over_cap(self.env.grind_cap)
        j += self.env.w_return * res.acc.returns
        return j, res


# --- moves ------------------------------------------------------------------------------------------


def quests_of(acts):
    seen, out = set(), []
    for _, q in acts:
        if q not in seen:
            seen.add(q)
            out.append(q)
    return out


def _delta(env, acts, i, p):
    """Extra yards of putting a point p between acts[i-1] and acts[i] (i == len: at the end)."""
    prev = pos_of(env, acts[i - 1]) if i > 0 else None
    nxt = pos_of(env, acts[i]) if i < len(acts) else None
    if prev is None:
        return dist(p, nxt) if nxt is not None else 0.0
    if nxt is None:
        return dist(prev, p)
    return dist(prev, p) + dist(p, nxt) - dist(prev, nxt)


def insert_quest(env, acts, q, verbs=("a", "c", "t")):
    """Cheapest insertion (by yards) of the given actions of q, in their order."""
    R = env.Q[q]
    out = list(acts)
    pts = {"a": R.start, "c": R.obj_pos or R.start, "t": R.end}
    lo = 0
    if "a" in verbs:
        # a follow-up goes after the turn-in of its prerequisites
        for g in R.pre:
            idx = [i for i, (v, qq) in enumerate(out) if v == "t" and qq in g]
            if idx:
                lo = max(lo, min(idx) + 1)
    for verb in verbs:
        p = pts[verb]
        best, bi = None, None
        for i in range(lo, len(out) + 1):
            d = _delta(env, out, i, p)
            if best is None or d < best - 1e-9:
                best, bi = d, i
        out.insert(bi, (verb, q))
        lo = bi + 1
    return out


def remove_quests(acts, qs):
    s = set(qs)
    return [a for a in acts if a[1] not in s]


def _window(acts, i):
    """Positions an action at index i may move to without passing its own quest's other actions."""
    verb, q = acts[i]
    lo, hi = 0, len(acts) - 1
    for j in range(i - 1, -1, -1):
        if acts[j][1] == q:
            lo = j + 1
            break
    for j in range(i + 1, len(acts)):
        if acts[j][1] == q:
            hi = j - 1
            break
    return lo, hi


def move_relocate(env, acts, rng):
    if len(acts) < 3:
        return None
    i = rng.randrange(len(acts))
    act = acts[i]
    lo, hi = _window(acts, i)
    rest = acts[:i] + acts[i + 1:]
    hi = min(hi, len(rest))
    p = pos_of(env, act)
    best, bi = None, None
    for k in range(lo, hi + 1):
        if k == i:
            continue
        d = _delta(env, rest, k, p)
        if best is None or d < best - 1e-9:
            best, bi = d, k
    if bi is None:
        return None
    return rest[:bi] + [act] + rest[bi:]


def move_or_opt(env, acts, rng):
    """Moves a run of 2 to 6 consecutive actions to its cheapest place (by yards), keeping every
    quest's accept < objectives < turn-in order."""
    n = len(acts)
    if n < 5:
        return None
    L = rng.randint(2, min(6, n - 2))
    i = rng.randrange(n - L + 1)
    seg = acts[i:i + L]
    rest = acts[:i] + acts[i + L:]
    lo, hi = 0, len(rest)
    for verb, q in seg:
        for j, (v2, q2) in enumerate(rest):
            if q2 != q:
                continue
            if RANK[v2] < RANK[verb]:
                lo = max(lo, j + 1)
            elif RANK[v2] > RANK[verb]:
                hi = min(hi, j)
    if lo > hi:
        return None
    p0, p1 = pos_of(env, seg[0]), pos_of(env, seg[-1])
    best, bk = None, None
    for k in range(lo, hi + 1):
        if k == i:
            continue
        prev = pos_of(env, rest[k - 1]) if k > 0 else None
        nxt = pos_of(env, rest[k]) if k < len(rest) else None
        d = (dist(prev, p0) if prev else 0.0) + (dist(p1, nxt) if nxt else 0.0) - (dist(prev, nxt) if prev and nxt else 0.0)
        if best is None or d < best - 1e-9:
            best, bk = d, k
    if bk is None:
        return None
    return rest[:bk] + seg + rest[bk:]


RANK = {"a": 0, "A": 0, "c": 1, "t": 2}


def move_two_opt(env, acts, rng):
    n = len(acts)
    if n < 4:
        return None
    i = rng.randrange(n - 2)
    k = min(n - 1, i + 2 + rng.randrange(min(30, n - i - 2) or 1))
    seg = acts[i:k + 1]
    qs = [q for _, q in seg]
    if len(qs) != len(set(qs)):
        return None
    a = pos_of(env, acts[i - 1]) if i > 0 else None
    b = pos_of(env, acts[i])
    c = pos_of(env, acts[k])
    d = pos_of(env, acts[k + 1]) if k + 1 < n else None
    before = (dist(a, b) if a else 0) + (dist(c, d) if d else 0)
    after = (dist(a, c) if a else 0) + (dist(b, d) if d else 0)
    if after >= before - 1e-6:
        return None
    return acts[:i] + seg[::-1] + acts[k + 1:]


def move_swap(env, acts, rng):
    n = len(acts)
    if n < 2:
        return None
    i = rng.randrange(n - 1)
    if acts[i][1] == acts[i + 1][1]:
        return None
    return acts[:i] + [acts[i + 1], acts[i]] + acts[i + 2:]


# --- block optimisation -----------------------------------------------------------------------------


def full_todo(R):
    return ("a", "c", "t") if needs_work(R) else ("a", "t")


class Block:
    """One block: the actions to plan per quest (`todo`), entry state, the chosen order.

    todo[q] lists the actions of q that belong to this block, in order: ("a", "c", "t") for a quest
    done here, ("a",) or ("a", "c") for one carried to a later zone visit, ("c", "t") or ("t",) for
    one carried in. `fixed` quests cannot be left out (carried in: they are in the log)."""

    def __init__(self, env, key, st0, todo, target=None, fixed=(), credit=None):
        self.env = env
        self.key = key
        self.st0 = st0
        self.todo = dict(todo)
        self.cands = sorted(self.todo)
        self.target = target
        self.fixed = set(fixed)
        self.acts = []
        self.res = None
        self.goal = Goal(env, st0, target, credit)

    def complete_quests(self, acts):
        n = {}
        for v, q in acts:
            n[q] = n.get(q, 0) + 1
        return {q for q, k in n.items() if k == len(self.todo[q])}

    # construction: nearest feasible action, worth test on the quests
    def construct(self, worth=True, gate_levels=None, gate_value=None):
        env, Q = self.env, self.env.Q
        gate_levels = env.gate_levels if gate_levels is None else gate_levels
        gate_value = env.gate_value if gate_value is None else gate_value
        st = self.st0.copy()
        chosen = set(self.worthwhile() if worth else self.cands) | self.fixed
        acc = Acc()
        acts = []
        nxt = {q: 0 for q in chosen}
        while True:
            best = None
            lvl = st.level
            for q in sorted(nxt):
                k = nxt[q]
                todo = self.todo[q]
                if k >= len(todo):
                    continue
                R = Q[q]
                v = todo[k]
                if v == "a":
                    if R.mn > lvl or R.ql > lvl + 2 or st.log >= env.log_work:
                        continue
                    if any(not (g & st.done) for g in R.pre):
                        continue
                    if self.target is None and lvl > R.ql + 5 - env.r01_margin:
                        continue
                    p = R.start
                elif v == "c":
                    p = R.obj_pos or R.start
                else:
                    p = R.end
                d = dist(st.pos, p) if st.pos is not None else 0.0
                key = (d > NEAR, d, {"t": 0, "a": 1, "c": 2}[v], q)
                if best is None or key < best[0]:
                    best = (key, (v, q))
            if best is None:
                # nothing possible: grind to the lowest level that opens a chosen quest, if close
                gate = None
                for q in sorted(nxt):
                    if nxt[q] != 0 or self.todo[q][0] != "a" or st.log >= env.log_work:
                        continue
                    R = Q[q]
                    if any(not (g & st.done) for g in R.pre):
                        continue
                    need = max(R.mn, R.ql - 2)
                    if need > lvl and need - st.flevel() <= gate_levels:
                        k = (need, dist(st.pos, R.start), q)
                        if gate is None or k < gate[0]:
                            gate = (k, ("a", q))
                if gate is None or gate_levels <= 0:
                    break
                need = gate[0][0]
                grind_xp = xp.total_to(need) - (xp.total_to(st.level) + st.xp)
                opened = sum(Q[q].xp for q in nxt if nxt[q] == 0 and max(Q[q].mn, Q[q].ql - 2) <= need)
                if opened < gate_value * grind_xp:
                    break
                best = gate
            act = best[1]
            acts.append(act)
            nxt[act[1]] += 1
            step(env, st, act, acc, env.r01_margin)
        whole = self.complete_quests(acts) | self.fixed
        acts = [a for a in acts if a[1] in whole]
        self.acts = acts
        self.j, self.res = self.goal(acts)
        return self

    def worthwhile(self):
        """Quests whose XP per second of their own time beats grind rate / w_g at their level
        (half of it: the search decides the rest)."""
        env, Q = self.env, self.env.Q
        out = []
        for q in self.cands:
            R = Q[q]
            if self.todo[q][0] != "a":
                continue
            lv = max(self.st0.level, R.mn, R.ql - 2)
            sec = env.talk * 2 + env.walk_sec(R.start, R.obj_pos or R.start) + env.walk_sec(R.obj_pos or R.start, R.end)
            gx = 0.0
            for n, kind in R.kills:
                n = n * (env.item_kills if kind == "item" else 1)
                s, g = env.kill(lv, R.ql)
                sec += s * n
                gx += g * n
            sec += R.inter * env.interact + R.talk * env.talk + R.esc * env.escort
            value = xp.quest_xp(R.xp, R.ql, lv) + gx
            if sec <= 0 or value / sec >= env.grind_rate(lv) / env.w_grind * 0.5:
                out.append(q)
        return out

    def improve(self, tries, seed, ops=("destroy", "relocate", "or_opt", "two_opt", "swap", "add", "drop")):
        """ALNS with record-to-record acceptance (brain chapter 21 Code D)."""
        env = self.env
        rng = random.Random(stable_seed(self.key, seed))
        cur = list(self.acts)
        jc, rc = self.goal(cur)
        best, jb, rb = cur, jc, rc
        inside = set(quests_of(cur))
        bank = [q for q in self.cands if q not in inside and q not in self.fixed]
        scale = max(600.0, abs(rc.T))
        weights = [1.0] * len(ops)
        score = [0.0] * len(ops)
        used = [0] * len(ops)
        todo = self.todo
        for it in range(tries):
            k = rng.choices(range(len(ops)), weights=weights)[0]
            op = ops[k]
            cand = None
            if op == "destroy":
                qs = [q for q in quests_of(cur) if q not in self.fixed]
                if qs:
                    n = max(1, min(len(qs), int(len(qs) * rng.uniform(0.05, 0.3))))
                    if rng.random() < 0.4:
                        rem = rng.sample(qs, n)
                    else:
                        seed_q = rng.choice(qs)
                        p0 = env.Q[seed_q].obj_pos or env.Q[seed_q].start
                        rem = sorted(qs, key=lambda q: (dist(p0, env.Q[q].obj_pos or env.Q[q].start), q))[:n]
                    cand = remove_quests(cur, rem)
                    pool = rem + [q for q in bank if rng.random() < 0.3]
                    rng.shuffle(pool)
                    for q in pool:
                        if q in rem or rng.random() < 0.85:
                            cand = insert_quest(env, cand, q, todo[q])
            elif op == "relocate":
                cand = move_relocate(env, cur, rng)
            elif op == "or_opt":
                cand = move_or_opt(env, cur, rng)
            elif op == "two_opt":
                cand = move_two_opt(env, cur, rng)
            elif op == "swap":
                cand = move_swap(env, cur, rng)
            elif op == "add":
                if bank:
                    q = rng.choice(bank)
                    cand = insert_quest(env, cur, q, todo[q])
            elif op == "drop":
                qs = [q for q in quests_of(cur) if q not in self.fixed]
                if qs:
                    cand = remove_quests(cur, [rng.choice(qs)])
            used[k] += 1
            if cand is not None:
                j, r = self.goal(cand)
                thr = 0.004 * scale * (1 - it / tries)
                if j < jb - 1e-6:
                    score[k] += 33
                elif j < jc - 1e-6:
                    score[k] += 9
                elif j <= jc + thr:
                    score[k] += 2
                if j <= jc + thr:
                    cur, jc, rc = cand, j, r
                    inside = set(quests_of(cur))
                    bank = [q for q in self.cands if q not in inside and q not in self.fixed]
                    if j < jb - 1e-6:
                        best, jb, rb = cand, j, r
            if (it + 1) % 100 == 0:
                for i in range(len(ops)):
                    if used[i]:
                        weights[i] = max(0.05, weights[i] * 0.8 + 0.2 * score[i] / used[i])
                score = [0.0] * len(ops)
                used = [0] * len(ops)
        self.acts, self.j, self.res = best, jb, rb
        return self

    def held_karp(self):
        """Exact order of every run of up to 10 actions within HUB yards (precedence kept)."""
        env = self.env
        acts = self.acts
        out = []
        i = 0
        while i < len(acts):
            j = i + 1
            p0 = pos_of(env, acts[i])
            while j < len(acts) and j - i < 10 and dist(p0, pos_of(env, acts[j])) <= HUB:
                j += 1
            run = acts[i:j]
            if len(run) >= 3:
                prev = pos_of(env, out[-1]) if out else None
                nxt = pos_of(env, acts[j]) if j < len(acts) else None
                run = _hk(env, run, prev, nxt)
            out.extend(run)
            i = j
        j, r = self.goal(out)
        if j <= self.j + 1e-6:
            self.acts, self.j, self.res = out, j, r
        return self

    def fold(self):
        """Accepts and turn-ins move to the earliest visit of their place where they are possible
        (R04, R05; Polestar "fold")."""
        env = self.env
        for _ in range(3):
            changed = False
            acts = self.acts
            for idx in range(len(acts)):
                verb, q = acts[idx]
                if verb not in ("a", "t"):
                    continue
                p = pos_of(env, (verb, q))
                lo, _ = _window(acts, idx)
                for k in range(lo, idx):
                    if dist(pos_of(env, acts[k]), p) <= NEAR:
                        cand = acts[:idx] + acts[idx + 1:]
                        cand.insert(k + 1, (verb, q))
                        j, r = self.goal(cand)
                        if j <= self.j + 1e-6:
                            self.acts, self.j, self.res = cand, j, r
                            changed = True
                        break
                if changed:
                    break
            if not changed:
                break
        return self


def _hk(env, run, prev, nxt):
    """Held-Karp over a short run of actions with precedence (accept < objectives < turn-in)."""
    n = len(run)
    pts = [pos_of(env, a) for a in run]
    rank = RANK
    need = [0] * n
    for i, (v, q) in enumerate(run):
        for k, (v2, q2) in enumerate(run):
            if q2 == q and rank[v2] < rank[v]:
                need[i] |= 1 << k
    INF = float("inf")
    dp = {}
    for i in range(n):
        if need[i] == 0:
            dp[(1 << i, i)] = (dist(prev, pts[i]) if prev else 0.0, None)
    for mask in range(1, 1 << n):
        for i in range(n):
            cur = dp.get((mask, i))
            if cur is None:
                continue
            for k in range(n):
                if mask >> k & 1 or (need[k] & mask) != need[k]:
                    continue
                nm = mask | (1 << k)
                c = cur[0] + dist(pts[i], pts[k])
                old = dp.get((nm, k))
                if old is None or c < old[0] - 1e-9:
                    dp[(nm, k)] = (c, i)
    full = (1 << n) - 1
    best, bi = INF, None
    for i in range(n):
        v = dp.get((full, i))
        if v is None:
            continue
        c = v[0] + (dist(pts[i], nxt) if nxt else 0.0)
        if c < best - 1e-9:
            best, bi = c, i
    if bi is None:
        return run
    order, mask, i = [], full, bi
    while i is not None:
        order.append(i)
        prev_i = dp[(mask, i)][1]
        mask &= ~(1 << i)
        i = prev_i
    return [run[i] for i in reversed(order)]


# --- audiences: which race/class combinations see a quest -------------------------------------------


def applicable(R, race, cls):
    return (R.races is None or race in R.races) and (R.classes is None or cls in R.classes)


def audience_filter(aud, universe):
    """A filter (races, classes) whose product (within the valid combinations) is a subset of aud,
    as large as possible; None means no restriction in that dimension. Returns (races, classes,
    kept combinations)."""
    if not aud:
        return None, None, set()
    all_r = {r for r, _ in universe}
    all_c = {c for _, c in universe}

    def product(races):
        classes = {c for c in all_c if any((r, c) in aud for r in races)
                   and all((r, c) in aud or (r, c) not in universe for r in races)}
        return classes, {(r, c) for r in races for c in classes if (r, c) in universe}

    races = {r for r, _ in aud}
    classes, kept = product(races)
    while kept != aud and len(races) > 1:
        best = None
        for r in sorted(races):
            cl, k = product(races - {r})
            if best is None or len(k) > len(best[2]):
                best = (races - {r}, cl, k)
        if len(best[2]) <= len(kept):
            break
        races, classes, kept = best
    if not kept:
        return None, None, set()
    rf = None if races == all_r else set(races)
    covered = {c for r in races for (rr, c) in universe if rr == r}
    cf = None if classes >= covered else set(classes)
    return rf, cf, kept


def filter_text(races, classes, universe_races):
    parts = []
    if races is not None:
        rs = sorted(races)
        rest = sorted(set(universe_races) - set(rs))
        if len(rest) < len(rs) and rest:
            parts.append("race=!" + ",".join(game.RACES[r][0] for r in rest))
        else:
            parts.append("race=" + ",".join(game.RACES[r][0] for r in rs))
    if classes is not None:
        cs = sorted(classes)
        rest = sorted(set(game.CLASSES) - set(cs))
        if len(rest) < len(cs) and rest:
            parts.append("class=!" + ",".join(game.CLASSES[c] for c in rest))
        else:
            parts.append("class=" + ",".join(game.CLASSES[c] for c in cs))
    return " ".join(parts)


# --- faction plan --------------------------------------------------------------------------------------


CAPITALS = {1453, 1454, 1455, 1456, 1457, 1458}


class Module:
    """A planned module: kind, key, actions [(verb, q)], audience per quest, planned level per
    action (the lowest level of the combinations that see it), plan elements, header levels."""

    def __init__(self, key, kind, zone=None):
        self.key, self.kind, self.zone = key, kind, zone
        self.acts = []  # (verb, q)
        self.aud = {}  # q -> (races, classes) filter, None = everybody of the module
        self.lv = []  # planned level per action
        self.xp_marks = {}  # (verb, q) -> level announced in the step of that action (R17, R19)
        self.fps = {}  # (verb, q) -> flight masters (id, uiMap, west, north, src) visited after its step (R13)
        self.for_races = None
        self.for_classes = None
        self.levels = None
        self.ret = None
        self.travel_first = None
        self.anchor = None
        self.last = False
        self.min_lv = None  # level the module starts at: ground at the end of the module before (P9 band)
        self.entry = self.exit = None
        self.after = {}  # combination -> (state, done) after this module
        self.aud_early = {}  # q -> filter of an early accept ("A"): combinations already at its level
        self.aud_main = {}  # q -> filter of the main accept when an early accept takes the others


class Planner:
    def __init__(self, facts, params, plan, mode, exclude, tries=None, seed=1, baseline_zone_changes=None):
        self.f = facts
        self.p = params
        self.plan = plan
        self.mode = mode
        self.faction = plan["faction"]
        self.px = plan["prefix"]
        self.races = game.races_of(self.faction)
        self.universe = {(r, c) for r in self.races for c in game.COMBOS[r]}
        opt = params.raw.get("opt", {})
        self.tries_per_quest = tries or opt.get("tries_per_quest", {}).get("value", 400)
        self.tries_max = opt.get("tries_max", {}).get("value", 30000)
        self.beam = opt.get("beam_width", {}).get("value", 8)
        self.gate_variants = [tuple(g) for g in opt.get("gate_variants", {}).get(
            "value", [[0.0, 0.0], [0.5, 3.0], [1.0, 2.0], [2.0, 1.5], [3.0, 1.0], [5.0, 0.8]])]
        self.seed = seed
        self.debug = False
        self.report = {"zones": [], "dropped_inserts": [], "starts": {}}
        from . import build

        pool = build.Pool(facts, self.faction, self.races, mode, exclude)
        Q = {}
        for r in facts.q.values():
            if not pool.usable(r, True):
                continue
            if not ((r.get("xp") or {}).get("v") or 0) and not r.get("obj"):
                pass
            Q[r["q"]] = QV(r, facts.frames)
        self.Q = Q
        self.env = Env(facts, params, Q)
        self.zone_budget = baseline_zone_changes
        self.start_zones = {lint.zone_key(z) for st in plan["start"] for z in st["zones"]}
        self.start_instances = {}
        for st in plan["start"]:
            for t in st["races"]:
                self.start_instances[game.RACE_BY_TOKEN[t]] = facts.frames.instance(st["zones"][0])
        self.prev_instance = None
        self.arrive_margin = opt.get("arrive_margin", {}).get("value", 0.05)
        self.arrive_top = opt.get("arrive_top", {}).get("value", 0.9)
        self.repair_rounds = opt.get("repair_rounds", {}).get("value", 12)
        self.sources = None
        self._fms = None
        self._draw_envs = None
        self.baseline = None

    def flight_master(self, fid):
        """(id, uiMap, west, north, sources) of a flight master of data/facts/finds.jsonl."""
        if self._fms is None:
            from .io import read_jsonl, repo_path

            self._fms = {}
            for rec in read_jsonl(repo_path("data", "facts", "finds.jsonl")):
                if rec.get("type") != "flightpath" or rec["id"] in self._fms:
                    continue
                for m, x, y in rec.get("pos", []):
                    if m in game.CHANGED_FRAMES:
                        continue
                    w = self.f.frames.to_world(m, x / 100.0, y / 100.0)
                    if w:
                        self._fms[rec["id"]] = (rec["id"], m, w[2], w[1], ",".join(rec.get("src", [])))
                        break
        return self._fms.get(fid)

    def tries(self, n):
        return int(min(self.tries_max, max(200, self.tries_per_quest * n)))

    # quests whose start, objectives and end lie in `zones`
    def inside(self, zones, pred):
        zs = {lint.zone_key(z) for z in zones}
        return sorted(q for q, R in self.Q.items() if R.zones <= zs and pred(R))

    def optimize_block(self, key, st0, todo, target=None, fixed=(), credit=None, gate=(None, None)):
        b = Block(self.env, key, st0, todo, target, fixed, credit).construct(gate_levels=gate[0], gate_value=gate[1])
        n = len(quests_of(b.acts))
        b.improve(self.tries(max(n, 10)), self.seed).held_karp().fold()
        return self.mind_returns(b)

    def mind_returns(self, b):
        """A last search on the order with the brain's 900 s per avoidable return in the objective
        (P5, chapter 21 §3.3): accepts and turn-ins pulled to the first earlier moment the character
        stands within 400 yd of their NPC while they are possible, then the tries; the choice of
        quests stays."""
        tries = self.p.raw.get("opt", {}).get("polish_tries", {}).get("value", 4000)
        self.env.w_return = self.env.return_sec
        try:
            b.j, b.res = b.goal(b.acts)
            pull_forward(self.env, b)
            b.improve(tries, self.seed + 1, ops=("relocate", "or_opt", "two_opt", "swap"))
        finally:
            self.env.w_return = 0.0
        b.j, b.res = b.goal(b.acts)
        return b

    def add_filtered(self, acts, st0, extra, credit=None):
        """Inserts quests the reference combination cannot take (other races or classes) where they
        are worth their extra time; returns the new order."""
        env = self.env
        goal = Goal(env, st0, credit=credit)
        j0, _ = goal(acts)
        for q in sorted(extra, key=lambda q: (-self.Q[q].xp, q)):
            cand = insert_quest(env, acts, q, full_todo(self.Q[q]))
            j, r = goal(cand)
            if j <= j0 + 1e-6 and r.pen <= 0:
                acts, j0 = cand, j
        return acts

    def audiences(self, acts, combos, done_by, aud):
        """Per quest the combinations that can take it here: own race/class and prerequisites handed
        in before (earlier modules of that combination or earlier in this one). Updates aud."""
        Q = self.Q
        seen = {c: set() for c in combos}
        for verb, q in acts:
            if verb == "a":
                R = Q[q]
                ok = set()
                for c in combos:
                    if not applicable(R, *c) or q in done_by[c]:
                        continue
                    if all(g & (done_by[c] | seen[c]) for g in R.pre):
                        ok.add(c)
                aud[q] = audience_filter(ok, combos)
            elif verb == "t" and q in aud:
                for c in aud[q][2]:
                    seen[c].add(q)
        return aud

    def combo_replay(self, st0, acts, aud, combo):
        """Replays the actions a combination sees (its audience), from st0."""
        mine = [a for a in acts if combo in aud.get(a[1], (None, None, set()))[2]]
        return replay(self.env, st0, mine), mine

    def carry_plan(self, R, seq, i):
        """Visits for the objectives and the turn-in of a quest accepted at visit i whose other
        actions lie in zones visited later: [(verb, visit)], or None."""
        z = seq[i]
        plan = [("a", i)]
        k = i
        if needs_work(R):
            ozones = {lint.zone_key(m) for m, _ in R.objs} or {z}
            if len(ozones) != 1:
                return None
            zo = next(iter(ozones))
            k = next((j for j in range(i, len(seq)) if seq[j] == zo), None)
            if k is None:
                return None
            plan.append(("c", k))
        kt = next((j for j in range(k, len(seq)) if seq[j] == R.end_zone), None)
        if kt is None:
            return None
        plan.append(("t", kt))
        if all(v == i for _, v in plan):
            return None
        return plan

    # --- the whole faction -------------------------------------------------------------------------

    def run(self):
        """Start modules, core, class inserts; then the repair rounds against the metrics."""
        self.modules = self.plan_starts()
        self.finalize()
        warrior = game.CLASS_BY_TOKEN["WARRIOR"]
        # reference of the core: the start with the lowest arrival, warrior (fewest class quests)
        ref = min((self.state_by[(r, warrior)].flevel(), r) for r in self.races)[1]
        self.ref = (ref, warrior)
        st = self.state_by[self.ref].copy()
        st.zone = None
        self.modules += self.plan_core(st)
        if self.modules[-1].kind == "core":
            self.modules[-1].last = True
        self.finalize()
        self.inserts = class_inserts(self)
        self.finalize()
        self.trim_inserts()
        if self.sources is not None and self.repair_rounds:
            Repair(self, self.sources).run(self.repair_rounds)
        return self.modules

    def plan_starts(self):
        """Start modules in one arrival window for all combinations of the faction (G7). When a
        combination cannot reach the planned window with the quests of its start zone, the window
        moves down to the level it reaches."""
        arrive = self.plan.get("arrive", 11)
        out = self._plan_starts(arrive)
        low = min(v for lv in self.report["starts"].values() for v in lv.values())
        if low < arrive:
            arrive = int(math.floor(low))
            self.report["arrive_window"] = "moved to %d: lowest arrival %.2f" % (arrive, low)
            out = self._plan_starts(arrive)
        self.report["arrive"] = arrive
        return out

    def _plan_starts(self, arrive):
        """One start module per start zone, planned for the first race's warrior; then every
        combination of the start is brought into the window [arrive, arrive + 1): quests are added
        for a combination below it and its own extras dropped above it."""
        out = []
        low_bound = arrive + self.arrive_margin
        cap = arrive + 1 - self.arrive_margin
        target = arrive + self.arrive_top  # plan near the top: combinations with fewer quests stay in
        warrior = game.CLASS_BY_TOKEN["WARRIOR"]
        for st in self.plan["start"]:
            races = [game.RACE_BY_TOKEN[t] for t in st["races"]]
            combos = sorted((r, c) for r in races for c in game.COMBOS[r])
            ref = (races[0], warrior)
            key = "%s-%s-start-%s" % (self.px, self.mode, st["module"])
            st0 = State(level=1)
            todo = {q: full_todo(self.Q[q]) for q in self.inside(st["zones"], lambda R: applicable(R, *ref))}
            b = self.optimize_block(key, st0, todo, target=target)
            extra = self.inside(st["zones"], lambda R: not applicable(R, *ref) and any(applicable(R, *c) for c in combos))
            acts = self.add_filtered(b.acts, st0, extra)
            pool = self.inside(st["zones"], lambda R: any(applicable(R, *c) for c in combos))
            for _ in range(60):
                lv = self.start_levels(acts, combos)
                low = [c for c in combos if lv[c] < low_bound - 1e-9]
                high = [c for c in combos if lv[c] > cap]
                if not low and not high:
                    break
                changed = False
                for c in low:
                    inside = set(quests_of(acts))
                    cands = [q for q in pool if q not in inside and applicable(self.Q[q], *c)]
                    best = None
                    for q in cands:
                        cand = insert_quest(self.env, acts, q, full_todo(self.Q[q]))
                        lv2 = self.start_levels(cand, [c])[c]
                        if lv2 <= lv[c] + 1e-9:
                            continue
                        res = replay(self.env, st0, [a for a in cand if applicable(self.Q[a[1]], *c)])
                        if res.grind > 0 or lv2 > cap:
                            continue
                        k = (res.T / (lv2 - lv[c]), q)
                        if best is None or k < best[0]:
                            best = (k, cand)
                    if best is not None:
                        acts = best[1]
                        changed = True
                        break
                for c in high[:1]:
                    own = [q for q in quests_of(acts) if applicable(self.Q[q], *c)
                           and not all(applicable(self.Q[q], *x) for x in combos)]
                    if own:
                        acts = remove_quests(acts, [min(own, key=lambda q: (self.Q[q].xp, q))])
                        changed = True
                if not changed:
                    break
            m = Module(key, "start", lint.zone_key(st["zones"][0]))
            m.acts = acts
            m.for_races = set(races)
            out.append(m)
            self.report["starts"][key] = {"%s %s" % (game.RACES[r][0], game.CLASSES[c]): round(v, 2)
                                          for (r, c), v in sorted(self.start_levels(acts, combos).items())}
        return out

    def start_levels(self, acts, combos):
        """Arrival level of every combination after a start module (its audience of each quest)."""
        aud = self.audiences(acts, combos, {c: set() for c in combos}, {})
        out = {}
        for c in combos:
            mine = [a for a in acts if c in aud.get(a[1], (None, None, set()))[2]]
            out[c] = replay(self.env, State(level=1), mine).end.flevel()
        return out

    def plan_core(self, st):
        """Zone visits by beam search, every visit optimised in order, then additions over the
        chain (carried quests, worthwhile pick-ups) and quests of other races and classes."""
        ref = self.ref
        universe = sorted(self.universe)
        visits = self.beam_zones(st, ref, self.zone_budget or 7, self.section_caps())
        seq = [v[0] for v in visits]
        self.seq = seq
        self.core_min_lv = {i: v[6] for i, v in enumerate(visits) if len(v) > 6 and v[6]}
        self.report["zones"] = [game.ZONES.get(z, z) for z in seq]
        blocks = [(v[0], list(v[3])) for v in visits]
        cur = st.copy()
        for i, (z, acts) in enumerate(blocks):
            key = "%s-%s-core-%02d-%d" % (self.px, self.mode, i + 1, z)
            cur, _ = entry_grind(self.env, cur, self.core_min_lv.get(i))
            todo = {q: full_todo(self.Q[q]) for q in quests_of(acts)}
            b = Block(self.env, key, cur, todo)
            b.acts = acts
            b.j, b.res = b.goal(acts)
            b.improve(self.tries(len(todo)), self.seed, ops=("relocate", "or_opt", "two_opt", "swap")).held_karp().fold()
            self.mind_returns(b)
            blocks[i] = (z, b.acts)
            cur = b.res.end
        blocks = self.add_to_chain(st, blocks, ref, seq)
        out = []
        taken = {q for _, acts in blocks for q in quests_of(acts)} | set(st.done)
        cur = st.copy()
        for i, (z, acts0) in enumerate(blocks):
            key = "%s-%s-core-%02d-%d" % (self.px, self.mode, i + 1, z)
            cur, _ = entry_grind(self.env, cur, self.core_min_lv.get(i))
            extra = self.inside([z], lambda R: R.q not in taken and not applicable(R, *ref)
                                and any(applicable(R, *c) for c in universe))
            acts = self.add_filtered(acts0, cur, extra)
            taken |= set(quests_of(acts))
            cur = replay(self.env, cur, [a for a in acts if applicable(self.Q[a[1]], *ref)]).end
            m = Module(key, "core", z)
            m.min_lv = self.core_min_lv.get(i)
            m.travel_first = z
            if z in seq[:i]:
                m.ret = "neue Quests"  # R09: a return needs quests that were not possible before
            m.acts = acts
            out.append(m)
        return out

    def group_spots(self):
        """Actions at one spot (within NEAR yards of each other, one after the other) go into the
        order turn-ins, accepts, objectives, precedence kept (accept < objectives < turn-in of a
        quest, a prerequisite's turn-in before the follow-up's accept): accepts and turn-ins at one
        NPC then share a step (R04, R05), and an accept takes the XP of the turn-ins there first.
        Returns the number of modules changed."""
        env, Q = self.env, self.Q
        rank = {"t": 0, "a": 1, "A": 1, "c": 2}
        changed = 0
        for m in self.modules + list(getattr(self, "inserts", [])):
            acts = m.acts
            out, i = [], 0
            while i < len(acts):
                p0 = pos_of(env, acts[i])
                j = i + 1
                while j < len(acts) and dist(p0, pos_of(env, acts[j])) <= NEAR:
                    j += 1
                run = acts[i:j]
                if len(run) > 2:
                    left = list(run)
                    placed = set()
                    order = []
                    while left:
                        pick = None
                        for k, (v, q) in enumerate(left):
                            before = [(v2, q2) for (v2, q2) in left[:k] if q2 == q]
                            if before:
                                continue  # an earlier action of the same quest is still waiting
                            if v in ("a", "A") and any(("t", g) in left for grp in Q[q].pre for g in grp):
                                continue  # a prerequisite is handed in here later
                            if pick is None or rank[v] < rank[left[pick][0]]:
                                pick = k
                        if pick is None:
                            pick = 0
                        order.append(left.pop(pick))
                        placed.add(order[-1])
                    run = order
                out.extend(run)
                i = j
            if out != acts:
                m.acts = out
                changed += 1
        return changed

    def trim_inserts(self):
        """Guard P9 for the class inserts: an insert in another zone adds zone sections; while a
        combination has more sections in a band than its cap, its last insert leaves the route
        (reported in dropped_inserts)."""
        if not self.baseline or not getattr(self, "inserts", None) or self.sources is None:
            return
        while True:
            rows, _ = Repair(self, self.sources).evaluate()
            over = {(r["race"], r["class"]) for r in rows if (r.get("p9_vs_base") or 0) > 0}
            drop = []
            for rtok, ctok in sorted(over):
                mine = [m for m in self.inserts if game.RACES[next(iter(m.for_races))][0] == rtok
                        and game.CLASSES[next(iter(m.for_classes))] == ctok]
                if mine:
                    drop.append(mine[-1])
            if not drop:
                return
            for m in drop:
                self.inserts.remove(m)
                self.report["dropped_inserts"].append("%s: P9 zone sections over the cap" % m.key)
            self.finalize()

    def route_of(self, combo):
        """Modules of a combination in route order (start, its inserts, core with inserts)."""
        out = []
        start = next(m for m in self.modules if m.kind == "start" and combo[0] in m.for_races)
        out.append(start)
        ins = [m for m in getattr(self, "inserts", []) if combo[0] in m.for_races and combo[1] in m.for_classes]
        out += [m for m in ins if m.anchor == "start"]
        for m in self.modules:
            if m.kind == "core":
                out.append(m)
                out += [x for x in ins if x.anchor == m.key]
        return out

    def finalize(self):
        """Audiences, planned levels and per-combination states from the actions of all modules:
        every combination plays its own route (start, inserts, core); a quest's audience is the
        combinations that can take it where it is accepted. The planned level of an action is the
        lowest level of the combinations that see it, so no combination meets a level it lacks."""
        universe = sorted(self.universe)
        done_by = {c: set() for c in universe}
        state = {c: State(level=1) for c in universe}
        aud = {}
        aud_main = {}  # q -> audience of the main accept when an early accept takes the rest
        levels = {}  # (module key, index) -> [levels of the combinations that see it]
        entries = {}
        exits = {}
        mods = [m for m in self.modules if m.kind in ("start", "core")]
        inserts = list(getattr(self, "inserts", []))

        early = {}  # (module key, index of "A") -> combinations that take the quest there
        whole = set()  # quests every combination takes at the early accept
        aud_a = {}  # q -> audience of a quest's early accept candidates

        def play(m, combos):
            per = {}  # index -> {combination: level before the action}
            for c in combos:
                mine_idx = [i for i, a in enumerate(m.acts) if a[0] != "A" and c in aud.get(a[1], (None, None, set()))[2]]
                mine = [m.acts[i] for i in mine_idx]
                state[c], _ = entry_grind(self.env, state[c], getattr(m, "min_lv", None))
                entries.setdefault(m.key, []).append(state[c].flevel())
                r = replay(self.env, state[c], mine, record=True)
                for i, lv in zip(mine_idx, r.levels):
                    levels.setdefault((m.key, i), []).append(lv)
                    per.setdefault(i, {})[c] = lv
                done_by[c] |= {q for v, q in mine if v == "t"}
                state[c] = r.end
                exits.setdefault(m.key, []).append(state[c].flevel())
                m.after[c] = (state[c].copy(), set(done_by[c]))
            # early accepts (R05, P6): the combinations already at the quest's level take it here,
            # the others at its accept; both audiences must be expressible as filters
            for i, (v, q) in enumerate(m.acts):
                if v != "A" or q not in aud:
                    continue
                full = aud[q][2]
                at = {}
                for c in full & aud_a.get(q, set()):
                    k = next((k for k in range(i + 1, len(m.acts)) if c in per.get(k, {})), None)
                    at[c] = per[k][c] if k is not None else (m.after[c][0].flevel() if c in m.after else 0.0)
                want = {c for c, lv in at.items() if lv + 1e-9 >= _req(self.Q[q])}
                ef = audience_filter(want, set(combos)) if want else (None, None, set())
                rest = full - ef[2]
                if not ef[2]:
                    continue
                if not rest:
                    whole.add(q)  # every combination takes it early: the early accept is the accept
                    levels[(m.key, i)] = [at[c] for c in ef[2]]
                    continue
                mf = audience_filter(rest, set(combos))
                if mf[2] != rest:
                    continue
                early[(m.key, i)] = ef
                aud_main[q] = mf
                levels[(m.key, i)] = [at[c] for c in ef[2]]

        def play_inserts(anchor, combos):
            for x in inserts:
                if x.anchor != anchor:
                    continue
                cs = [c for c in combos if c[0] in x.for_races and c[1] in x.for_classes]
                for c in cs:
                    aud.update({q: (None, None, {c}) for q in quests_of(x.acts)})
                play(x, cs)

        for m in mods:
            m.after = {}
            if m.kind == "start":
                combos = [c for c in universe if c[0] in m.for_races]
            else:
                combos = universe
            seen = {c: set() for c in combos}
            for verb, q in m.acts:
                if verb in ("a", "A"):
                    R = self.Q[q]
                    ok = set()
                    for c in combos:
                        if not applicable(R, *c) or q in done_by[c]:
                            continue
                        if all(g & (done_by[c] | seen[c]) for g in R.pre):
                            ok.add(c)
                    if verb == "A":
                        aud_a[q] = ok
                    else:
                        aud[q] = audience_filter(ok, set(combos))
                elif verb == "t" and q in aud:
                    for c in aud[q][2]:
                        seen[c].add(q)
            play(m, combos)
            play_inserts("start" if m.kind == "start" else m.key, combos)
        for m in mods + inserts:
            keep = [i for i, a in enumerate(m.acts) if (m.key, i) in levels
                    and not (a[0] == "a" and a[1] in whole)]
            m.aud_early = {m.acts[i][1]: (early[(m.key, i)][0], early[(m.key, i)][1]) for i in keep if (m.key, i) in early}
            m.acts = [("a", a[1]) if a[0] == "A" and a[1] in whole else a for a in (m.acts[i] for i in keep)]
            m.lv = [int(math.floor(min(levels[(m.key, i)]) + 1e-9)) for i in keep]
            if m.kind != "class":
                m.aud = {q: (aud[q][0], aud[q][1]) for q in quests_of(m.acts) if q in aud}
                m.aud_main = {q: (aud_main[q][0], aud_main[q][1]) for q in m.aud if q in aud_main}
            m.entry = min(entries.get(m.key, [1.0]))
            m.exit = max(exits.get(m.key, [1.0]))
            m.entries = entries.get(m.key, [])
        self.done_by, self.state_by, self.aud = done_by, state, aud

    def section_caps(self):
        """Zone sections the core may have per level band (guard P9, decision of 2026-11-02): for
        every combination its cap (up to the end level of the RestedXP Forever guides at most
        max(RestedXP's sections, the start route's), above it the start route's plus
        limit.p9_sections_extra) minus the sections of its start module; the core takes the
        smallest. Returns (end level, cap up to it, cap above it), or None without a baseline."""
        from . import metrics

        base = (self.baseline or {}).get("combos", {})
        if not base:
            return None
        secs = metrics.load_sections()
        extra = self.p.lim("p9_sections_extra")
        ends, cap_a, cap_b = [], [], []
        start_secs = {}
        for m in self.modules:
            if m.kind != "start":
                continue
            zs = [z for z in (act_zone(self, a) for a in m.acts) if z is not None]
            n = sum(1 for i, z in enumerate(zs) if i == 0 or z != zs[i - 1])
            for r in m.for_races:
                start_secs[r] = max(1, n)
        for r, c in sorted(self.universe):
            label = "%s/%s" % (game.RACES[r][0], game.CLASSES[c])
            b = base.get("%s/%s" % (self.mode, label))
            if not b or "p9_sections" not in b:
                continue
            sa, sb = b["p9_sections"]
            sec = secs.get(label, {})
            ends.append(sec.get("end", self.plan.get("target", 30)))
            cap_a.append(max(sec.get("sections", sa + extra), sa) - start_secs.get(r, 1))
            cap_b.append(sb + extra)
        if not ends:
            return None
        return min(ends), max(0, min(cap_a)), min(cap_b)

    def draw_times(self, st0, path):
        """Model seconds of a core path to the target level (the rest ground) in the 16 held-out
        parameter draws of P3: the worth test of an additional zone (decision of 2026-11-02)."""
        from . import metrics

        if self._draw_envs is None:
            self._draw_envs = [Env(self.f, d, self.Q) for d in metrics._draws(self.p)]
        target = self.plan.get("target", 30)
        out = []
        for env in self._draw_envs:
            st, t = st0, 0.0
            for v in path:
                st, pre = entry_grind(env, st, v[6] if len(v) > 6 else None)
                t += pre
                r = replay(env, st, v[3])
                t += r.T
                st = r.end
            st = st.copy()
            t0 = st.t
            _grind_to(env, st, target)
            out.append(t + st.t - t0)
        return out

    def beam_zones(self, st, ref, budget, caps=None):
        """Zone visits of the core: beam search over the next zone (not the zone just left; a
        revisit needs 3 quests, R09). A path costs model time + penalties of its visits (grind
        gates with the grind weight, grind above the share per level with w_over, w_zone per
        change) + the rest to the target as grind (w_rest). Every visit is built with several gate
        settings: no grind, or grind up to `gate_levels` levels when the quests it opens are worth
        `gate_value` x its XP.

        Guard P9 (decision of 2026-11-02): with `caps` (end level, sections up to it, sections
        above it) a path keeps within the zone sections of every band; the best path with at most
        `budget` visits (the start route's zone changes) is the start, and a path with one more
        visit replaces it only when it reaches the target faster in all 16 parameter draws of P3
        (worth test). Without caps the depth is `budget`."""
        env = self.env
        target = self.plan.get("target", 30)

        def cands_of(z, done):
            return {q: full_todo(self.Q[q]) for q in self.inside([z], lambda R: applicable(R, *ref) and R.q not in done)}

        zones = sorted({R.start_zone for R in self.Q.values() if len(R.zones) == 1}
                       - self.start_zones - CAPITALS)
        w_rest = env.w_grind + (env.w_over - env.w_grind) * (1 - env.grind_cap)

        def rest_cost(s):
            rest = max(0.0, xp.total_to(target) - (xp.total_to(s.level) + s.xp))
            return w_rest * rest / env.grind_rate(min(s.level, target - 1))

        end, cap_a, cap_b = caps if caps else (None, budget, 0)

        def band_a(seq):
            return sum(1 for v in seq if int(math.floor(v[4] + 1e-9)) <= end)

        def fits(seq):
            """Sections of a path per band within the caps (a visit counts in each band it touches)."""
            if end is None:
                return len(seq) <= budget
            a = sum(1 for v in seq if int(math.floor(v[4] + 1e-9)) <= end)
            b = sum(1 for v in seq if int(math.floor(v[5] + 1e-9)) > end)
            return a <= cap_a and b <= cap_b

        # (cost so far without the rest, path, end state)
        beam = [(0.0, [], st)]
        done_paths = [(rest_cost(st), [], st)]
        gates = self.gate_variants
        for depth in range(cap_a + cap_b if caps else budget):
            new = []
            for cum, seq, s in beam:
                for z in zones:
                    if seq and z == seq[-1][0]:
                        continue
                    cs = cands_of(z, s.done)
                    if len(cs) < 3:
                        continue
                    seen_b = set()
                    # band of the first RestedXP levels used up: the visit starts above it, the
                    # character grinds there at the end of the visit before (announced, R17/R19)
                    floor_lv = end + 1 if caps and seq and band_a(seq) >= cap_a and s.level <= end else None
                    s_in, pre = entry_grind(env, s, floor_lv)
                    pre_cost = pre * env.w_grind + env.gate_sec if pre else 0.0
                    for gl, gv in gates:
                        b = Block(env, "beam-%d" % z, s_in, cs).construct(gate_levels=gl, gate_value=gv)
                        sig = tuple(b.acts)
                        if len(quests_of(b.acts)) < 3 or sig in seen_b:
                            continue
                        seen_b.add(sig)
                        e = b.res.end
                        # planned levels of the visit: at its first action (after a grind gate) and
                        # before its last one
                        lv0 = replay(env, s_in, b.acts[:1]).end.flevel()
                        path = seq + [(z, gl, gv, b.acts, lv0, replay(env, s_in, b.acts[:-1]).end.flevel(), floor_lv)]
                        if not fits(path):
                            continue
                        over = (env.w_over - env.w_grind) * b.res.acc.over_cap(env.grind_cap)
                        c = cum + pre_cost + b.res.T + b.res.pen + over + (env.w_zone if seq else 0.0)
                        new.append((c, path, e))
            if not new:
                break
            new.sort(key=lambda x: (x[0] + rest_cost(x[2]), [(v[0], v[1] or 0.0) for v in x[1]]))
            beam, seen = [], set()
            for x in new:
                k = (tuple(v[0] for v in x[1]), round(x[2].flevel(), 1))
                if k not in seen:
                    seen.add(k)
                    beam.append(x)
                if len(beam) >= self.beam:
                    break
            if self.debug:
                print("beam depth", depth, [(round(x[0] + rest_cost(x[2])), [game.ZONES.get(v[0], v[0]) for v in x[1]], round(x[2].flevel(), 2)) for x in beam])
            done_paths.extend((c + rest_cost(e), p, e) for c, p, e in beam)
        key = lambda x: (x[0], len(x[1]), [v[0] for v in x[1]])  # noqa: E731
        best = min((x for x in done_paths if len(x[1]) <= budget), key=key)
        worth = []
        if caps:
            # worth test of every visit beyond the start route's budget: the best path with one more
            # visit replaces the accepted one only when it is faster in every parameter draw
            t_best = self.draw_times(st, best[1])
            for k in sorted({len(x[1]) for x in done_paths}):
                if k <= len(best[1]):
                    continue
                # every path of the beam with k visits; the one with the largest smallest gain
                top = None
                for cand in sorted((x for x in done_paths if len(x[1]) == k), key=key):
                    t_cand = self.draw_times(st, cand[1])
                    gain = [b - c for b, c in zip(t_best, t_cand)]
                    if top is None or min(gain) > min(top[2]):
                        top = (cand, t_cand, gain)
                cand, t_cand, gain = top
                ok = all(g > 1e-6 for g in gain)
                worth.append({"visits": k, "zones": [game.ZONES.get(v[0], v[0]) for v in cand[1]],
                              "gain_min_h": round(min(gain) / 3600.0, 3), "gain_max_h": round(max(gain) / 3600.0, 3),
                              "taken": ok})
                if ok:
                    best, t_best = cand, t_cand
        self.report["zone_caps"] = list(caps) if caps else None
        self.report["zone_worth"] = worth
        return best[1]

    # --- the core as one chain of zone visits -------------------------------------------------------

    def chain(self, st0, blocks, record=False):
        """Replays the core visits in order. Returns (J, results, end state): J = model seconds +
        penalties + w_zone per zone change + the grind weight above the share per level + the rest to
        the target as grind (the beam's score)."""
        env = self.env
        st = st0
        out = []
        j = 0.0
        over = 0.0
        zones = 0
        for i, (_, acts) in enumerate(blocks):
            st, pre = entry_grind(env, st, getattr(self, "core_min_lv", {}).get(i))
            j += pre * env.w_grind + (env.gate_sec if pre else 0.0)
            r = replay(env, st, acts, record=record)
            out.append(r)
            j += r.T + r.pen
            over += r.acc.over_cap(env.grind_cap)
            zones += r.zones
            st = r.end
        target = self.plan.get("target", 30)
        w_rest = env.w_grind + (env.w_over - env.w_grind) * (1 - env.grind_cap)
        rest = max(0.0, xp.total_to(target) - (xp.total_to(st.level) + st.xp))
        j += (env.w_over - env.w_grind) * over + env.w_zone * zones
        j += w_rest * rest / env.grind_rate(min(st.level, target - 1))
        return j, out, st

    def add_to_chain(self, st0, blocks, ref, seq):
        """Worthwhile additions over the whole chain: quests left out by the visits (P6, Polestar
        "lohnende Mitnahmen") and quests whose actions lie in two zones visited in order (carried).
        A candidate goes in where it is cheapest; it stays when J of the chain falls."""
        env, Q = self.env, self.Q
        j0, res, _ = self.chain(st0, blocks)
        inside = {q for _, acts in blocks for q in quests_of(acts)}
        zone_set = set(seq)
        cands = []
        for q, R in Q.items():
            if q in inside or q in st0.done or not applicable(R, *ref) or R.start_zone not in zone_set:
                continue
            if not R.zones <= zone_set:
                continue
            cands.append(q)
        cands.sort(key=lambda q: (-Q[q].xp, q))
        added = 0
        for q in cands:
            R = Q[q]
            best = None
            for i, z in enumerate(seq):
                if z != R.start_zone:
                    continue
                if R.zones == {z}:
                    plan = [("a", i), ("c", i), ("t", i)] if needs_work(R) else [("a", i), ("t", i)]
                else:
                    plan = self.carry_plan(R, seq, i)
                if not plan:
                    continue
                trial = [(zz, list(acts)) for zz, acts in blocks]
                ok = True
                for k in sorted({k for _, k in plan}):
                    verbs = tuple(v for v, kk in plan if kk == k)
                    trial[k] = (trial[k][0], insert_quest(env, trial[k][1], q, verbs))
                if not ok:
                    continue
                j, rr, _ = self.chain(st0, trial)
                if sum(r.pen for r in rr) > sum(r.pen for r in res) + 1e-6:
                    continue
                if j < j0 - 1e-6 and (best is None or j < best[0]):
                    best = (j, trial, rr)
            if best:
                j0, blocks, res = best
                added += 1
        self.report.setdefault("added", 0)
        self.report["added"] += added
        return blocks


# --- route files -------------------------------------------------------------------------------------

VERB = {"a": "accept", "A": "accept", "c": "complete", "t": "turnin"}


def _req(R):
    """Lowest planned level at which a quest may be accepted (min level, quest level - 2)."""
    return max(R.mn, R.ql - lint.LEVEL_ABOVE)


def emit_module(planner, m, sources, universe_races):
    """Text lines of one module: header, steps (accepts and turn-ins at one NPC share a step,
    each element with the filter of its audience), travel steps at zone changes, `xp`
    announcements and flight path steps (m.xp_marks, m.fps)."""
    from . import build

    facts = planner.f
    Q = planner.Q
    steps = []
    for i, (verb, q) in enumerate(m.acts):
        R = Q[q]
        if verb == "A":
            races, classes = m.aud_early.get(q, (None, None))
        elif verb == "a" and q in getattr(m, "aud_main", {}):
            races, classes = m.aud_main[q]
        else:
            races, classes = m.aud.get(q, (None, None))
        if m.for_races is not None and races is not None and set(races) >= set(m.for_races):
            races = None
        if m.for_classes is not None and classes is not None and set(classes) >= set(m.for_classes):
            classes = None
        filt = filter_text(races, classes, universe_races)
        p = pos_of(planner.env, (verb, q))
        if verb in ("a", "A"):
            posv, zone = R.rec["startPos"]["v"], R.start_zone
        elif verb == "t":
            posv, zone = R.rec["endPos"]["v"], R.end_zone
        else:
            o = next(o for o in R.rec["obj"] if o.get("pos")) if R.objs else None
            posv = o["pos"] if o else None
            zone = lint.zone_key(posv[0]) if o else None
            if not o:
                p = None
        lv = m.lv[i]
        req = _req(R) if verb in ("a", "A") else 0
        act = {"verb": "a" if verb == "A" else verb, "q": q, "filter": filt, "lv": lv, "req": req, "i": i, "v0": verb}
        if steps:
            last = steps[-1]
            if (verb in ("a", "t") and last["verbs"] <= {"a", "t"} and last["zone"] == zone and p is not None
                    and last["p"] is not None and dist(last["p"], p) <= NEAR):
                trial = last["acts"] + [act]
                lvs = _step_level(trial)
                if all(lvs <= x["lv"] or x["lv"] < x["req"] for x in trial if x["verb"] == "a"):
                    last["acts"].append(act)
                    last["verbs"].add(verb)
                    continue
        steps.append({"acts": [act], "verbs": {verb}, "zone": zone, "p": p, "posv": posv, "first": verb})
    for s in steps:
        s["lv"] = _step_level(s["acts"])
    lo = min((s["lv"] for s in steps), default=1)
    hi = max((s["lv"] for s in steps), default=lo)
    if m.kind == "start":
        lo = 1
    top = max(int(math.floor((m.exit or lo) + 1e-9)), hi - lint.LEVEL_ABOVE, lo)
    if m.last:
        top = max(top, planner.plan.get("target", 30))  # the route ends at the target
    m.levels = (lo, top)
    used = set()

    def new_id(base):
        sid = base
        while sid in used:
            sid += "x"
        used.add(sid)
        return sid

    out = []
    zone = lint.zone_key(m.zone) if m.kind == "start" else None
    ship = "boat" if planner.faction == game.ALLIANCE else "zeppelin"
    for k, s in enumerate(steps):
        if s["zone"] is not None and (zone is None or s["zone"] != zone):
            if zone is not None or m.travel_first is not None:
                inst = facts.frames.instance(s["posv"][0])
                head = "@%s lv=%d" % (new_id("r%d" % s["zone"]), s["lv"])
                if m.ret:
                    head += ' !return "%s"' % m.ret
                out.append(head)
                if zone is None and m.kind == "core" and planner.start_instances:
                    prev = getattr(m, "prev_instance", None)
                    if prev is not None:
                        same, other = (sorted(planner.start_instances), []) if prev == inst else ([], sorted(planner.start_instances))
                    else:
                        same = sorted(r for r, i in planner.start_instances.items() if i == inst)
                        other = sorted(r for r, i in planner.start_instances.items() if i != inst)
                    for how, rs in (("walk", same), (ship, other)):
                        if not rs:
                            continue
                        filt = "" if len(rs) == len(planner.start_instances) else " << race=" + ",".join(game.RACES[r][0] for r in rs)
                        out.append("  travel %s %d%s | src=plan status=unbestätigt" % (how, s["zone"], filt))
                else:
                    prevp = None
                    for kk in range(k - 1, -1, -1):
                        if steps[kk]["posv"] is not None:
                            prevp = steps[kk]["posv"]
                            break
                    if prevp is None:
                        prev = getattr(m, "prev_instance", None)
                    else:
                        prev = facts.frames.instance(prevp[0])
                    how = "walk" if prev is None or prev == inst else ship
                    out.append("  travel %s %d | src=plan status=unbestätigt" % (how, s["zone"]))
            zone = s["zone"]
        a0 = s["acts"][0]
        sid = new_id({"a": "a", "A": "a", "c": "c", "t": "t"}[a0["verb"]] + str(a0["q"]))
        head = "@%s lv=%d" % (sid, s["lv"])
        filts = {x["filter"] for x in s["acts"]}
        step_filt = next(iter(filts)) if len(filts) == 1 else ""
        if step_filt:
            head += " << " + step_filt
        out.append(head)
        for x in s["acts"]:
            line = build._el_line(VERB[x["verb"]], x["q"], facts)
            if x["filter"] and not step_filt:
                line = line.replace(" | ", " << %s | " % x["filter"], 1)
            out.append(line)
        marks = [m.xp_marks[(x["v0"], x["q"])] for x in s["acts"] if (x["v0"], x["q"]) in m.xp_marks]
        if marks and s["posv"] is not None:
            out.append("  xp %d | src=plan status=unbestätigt" % max(marks))
        later = []
        for x in s["acts"]:
            for fm in m.fps.get((x["v0"], x["q"]), []):
                # a flight master next to the step's place is taken in the step itself (R13 radius)
                if s["p"] is not None and dist(s["p"], (s["p"][0], fm[3], fm[2])) <= FP_SAME:
                    out.append("  fp | src=plan status=unbestätigt")
                else:
                    later.append(fm)
        if s["posv"] is not None:
            out.append(build._goto_line(VERB[a0["verb"]], a0["q"], s["posv"], facts))
        for fid, fmap, fx, fy, fsrc in later:
            out.append("@%s lv=%d" % (new_id("fp%d" % fid), s["lv"]))
            out.append("  fp | src=plan status=unbestätigt")
            out.append("  goto %d %.1f,%.1f r=10 | src=%s status=unbestätigt" % (fmap, fx, fy, fsrc))
    for_filter = None
    if m.for_races is not None:
        for_filter = "race=" + ",".join(game.RACES[r][0] for r in sorted(m.for_races))
        if m.for_classes is not None:
            for_filter += " class=" + ",".join(game.CLASSES[c] for c in sorted(m.for_classes))
    head = build._header(m.key, m.kind, planner.faction, planner.mode, m.levels, sources, for_filter)
    return head + out


def _step_level(acts):
    """Planned level of a step: at least what its accepts require, else the lowest level of the
    combinations that see its actions."""
    lv = min(x["lv"] for x in acts)
    req = max((x["req"] for x in acts if x["verb"] == "a"), default=0)
    return max(lv, req)


def emit_all(planner, sources):
    """Files {key: lines} and the COMPOSE lines of one faction and mode."""
    universe_races = game.races_of(planner.faction)
    files = {}
    compose = ["#mode %s" % planner.mode]
    core_keys = []
    prev = None
    for m in planner.modules:
        if m.kind == "core":
            m.prev_instance = prev
        files[m.key] = emit_module(planner, m, sources, universe_races)
        if m.kind == "start":
            compose.append("start %s << race=%s" % (m.key, ",".join(game.RACES[r][0] for r in sorted(m.for_races))))
        else:
            core_keys.append(m.key)
            if m.acts:
                prev = pos_of(planner.env, m.acts[-1])[0]
    compose.append("core " + " ".join(core_keys))
    for m in getattr(planner, "inserts", []):
        files[m.key] = emit_module(planner, m, sources, universe_races)
        compose.append("insert after %s %s << race=%s class=%s" % (
            m.anchor, m.key, game.RACES[next(iter(m.for_races))][0], game.CLASSES[next(iter(m.for_classes))]))
    return files, compose


def class_inserts(planner):
    """Class quests in zones the route does not visit (capitals, Moonglade ...), per race and
    class, after the first module whose end level reaches them. An insert stays only within the
    limits of G8 (model seconds per insert and per combination); the others are reported."""
    env, Q = planner.env, planner.Q
    lim = planner.p.limit
    one = lim["g8_insert_sec"]["value"]
    total_max = lim["g8_insert_total_sec"]["value"]
    visited = set(planner.start_zones) | set(planner.seq)
    out = []
    for race, cls in sorted(planner.universe):
        combo = (race, cls)
        # anchored after a core block: an insert before the first one would lift the arrival (G7)
        anchors = [m for m in planner.modules if m.kind == "core" and combo in getattr(m, "after", {})]
        done = set(anchors[-1].after[combo][1]) if anchors else set()
        cq = [q for q, R in sorted(Q.items()) if R.classes is not None and cls in R.classes and applicable(R, race, cls)
              and q not in done and not (R.zones & visited)]
        if not cq:
            continue
        groups = {}
        for q in cq:
            R = Q[q]
            need = max(R.mn, R.ql - 2)
            anchor = next((m for m in anchors if m.after[combo][0].flevel() >= need), anchors[-1])
            groups.setdefault(anchor.key, []).append(q)
        total = 0.0
        taken = set()
        for idx, m in enumerate(anchors):
            qs = groups.get(m.key)
            if not qs:
                continue
            st0, done0 = m.after[combo]
            st0 = st0.copy()
            st0.done = set(done0) | taken
            env.cf = planner.p["class_factor"][game.CLASSES[cls]]
            todo = {q: full_todo(Q[q]) for q in qs}
            key = "%s-%s-class-%s-%s-%02d" % (planner.px, planner.mode, game.RACES[race][0].lower().replace("_", ""),
                                              game.CLASSES[cls].lower(), idx)
            b = Block(env, key, st0, todo).construct(worth=True)
            if b.acts:
                b.improve(planner.tries(len(todo)), planner.seed).held_karp()
            env.cf = 1.0
            if not b.acts:
                continue
            T = b.res.T
            # guard P9 (zone sections per band) is checked on the whole route afterwards
            # (Planner.trim_inserts)
            if T > one or total + T > total_max or b.res.pen > 0:
                planner.report["dropped_inserts"].append("%s %s: %s (%.0f s)" % (
                    game.RACES[race][0], game.CLASSES[cls], ",".join(str(q) for q in quests_of(b.acts)), T))
                continue
            total += T
            taken |= {q for v, q in b.acts if v == "t"}
            mod = Module(key, "class", None)
            mod.acts = b.acts
            mod.aud = {q: (None, None) for q in quests_of(b.acts)}
            mod.for_races, mod.for_classes = {race}, {cls}
            mod.ret = "Klassenquest"
            mod.travel_first = True
            mod.anchor = "start" if m.kind == "start" else m.key
            r = replay(env, st0, b.acts, record=True)
            mod.lv = [int(math.floor(x)) for x in r.levels]
            mod.res = r
            out.append(mod)
    return out


def act_zone(planner, act):
    """Zone of an action: the giver's, the first objective's or the ender's zone."""
    verb, q = act
    R = planner.Q[q]
    if verb in ("a", "A"):
        return R.start_zone
    if verb == "t":
        return R.end_zone
    return lint.zone_key(R.objs[0][0]) if R.objs else None


def plan_faction(facts, params, plan, mode, exclude, sources, zone_budget, baseline, log=None):
    """Plans one faction and mode with each grind weight setting (most quests first) and keeps the
    first plan that meets the guards against the start route (P3 in every parameter draw, P11 with
    the slow and the fast class profile); without one, the plan with the fewest guard breaches.
    The weights are policy (brain chapter 21 §3.3), the guards are hard."""
    from . import metrics

    opt = params.raw.get("opt", {})
    weights = [tuple(x) for x in opt.get("weight_settings", {}).get(
        "value", [[1.5, 4.0], [1.5, 2.0], [1.3, 1.3], [1.0, 1.0]])]
    margins = opt.get("arrive_margins", {}).get("value", [0.05, 0.02])
    settings = [(wg, wo, mg) for wg, wo in weights for mg in margins]
    best = None
    tried = []
    import time

    for wg, wo, mg in settings:
        t0 = time.perf_counter()  # measured for the report only; the search stops after tries, never on time
        pl = Planner(facts, params, plan, mode, exclude, baseline_zone_changes=zone_budget)
        pl.baseline = baseline
        pl.env.w_grind, pl.env.w_over = wg, wo
        pl.arrive_margin = mg
        pl.sources = sources
        pl.run()
        rows, _ = Repair(pl, sources).evaluate()
        metrics._cross(rows, params, baseline)
        guard = sum(1 for r in rows if r.get("p3_worse_draws")) + sum(1 for r in rows if (r.get("p11_vs_base") or 0) > 0)
        guard += sum(1 for r in rows if max(r.get("p5_vs_base") or 0, r.get("p9_vs_base") or 0, r.get("p4_vs_base") or 0) > 0)
        g7 = sum(1 for r in rows if r["g7_dev"] is not None and abs(r["g7_dev"]) > params.lim("g7_arrival"))
        key = (guard, g7, Repair(pl, sources).score(rows))
        g3 = {band: round(min(r["g3"][band] for r in rows), 3) for band in ("1-10", "11-20", "21-30")}
        h30 = round(sorted(r["h30"] for r in rows)[len(rows) // 2], 2)
        sec = round(time.perf_counter() - t0, 1)
        tried.append({"weights": [wg, wo], "arrive_margin": mg, "guard_breaches": guard, "g7_breaches": g7,
                      "rule_breaches": key[2], "g3_min": g3, "h30_median": h30, "seconds": sec})
        if log:
            log("%s %s weights %.2f/%.2f margin %.2f: guard breaches %d, G7 breaches %d, rule breaches %d, G3 min %s, "
                "Modellstunden 1-30 median %.2f, %.0f s" % (plan["faction"], mode, wg, wo, mg, guard, g7, key[2], g3, h30, sec))
        if best is None or key < best[0]:
            best = (key, pl)
        if guard == 0 and g7 == 0:
            break
    pl = best[1]
    pl.report["weights"] = tried
    pl.report["chosen"] = {"weights": [pl.env.w_grind, pl.env.w_over], "arrive_margin": pl.arrive_margin}
    return pl


def derive_explorer(speed, facts, params, plan, exclude, sources):
    """Explorer mode (owner point 2, plan Welle 6 task 6): the speed route plus the new Forever
    quests next to it. Every speed module is taken over (key -explorer-); a new quest of the
    explorer pool (breadcrumbs and quests with unconfirmed prerequisites included) goes in where
    its extra time is small (`opt.explorer_detour_sec`). Finds on the way come from ns.Explore in
    the client, not from the route."""
    import time

    t0 = time.perf_counter()  # measured for the report only
    pl = Planner(facts, params, plan, "explorer", exclude, baseline_zone_changes=speed.zone_budget)
    pl.baseline = getattr(speed, "baseline", None)
    pl.sources = sources
    pl.env.w_grind, pl.env.w_over = speed.env.w_grind, speed.env.w_over
    pl.arrive_margin = speed.arrive_margin
    limit = params.raw.get("opt", {}).get("explorer_detour_sec", {}).get("value", 180.0)
    cap = speed.report.get("arrive", 10) + 1 - speed.arrive_margin
    pl.report["arrive"] = speed.report.get("arrive", 10)
    rename = lambda key: key.replace("-speed-", "-explorer-")  # noqa: E731
    mods = []
    for m in speed.modules:
        x = Module(rename(m.key), m.kind, m.zone)
        x.acts = list(m.acts)
        x.for_races, x.for_classes = m.for_races, m.for_classes
        x.travel_first, x.ret, x.last = m.travel_first, m.ret, m.last
        x.min_lv = getattr(m, "min_lv", None)
        x.xp_marks = dict(m.xp_marks)
        x.fps = {k: list(v) for k, v in m.fps.items()}
        mods.append(x)
    pl.modules = mods
    pl.seq = list(getattr(speed, "seq", []))
    pl.start_zones = speed.start_zones
    pl.finalize()
    pl.ref = speed.ref
    # quests of the explorer pool (breadcrumbs, prerequisites not yet confirmed) that make a module
    # faster by the objective J go in first, as quests of other races and classes do in speed
    in_route = {q for m in mods for q in quests_of(m.acts)}
    pool_added = []
    rep0 = Repair(pl, sources)
    for m in mods:
        entry = rep0.entry_state(m)
        if entry is None:
            continue
        zones = {lint.zone_key(m.zone)}
        if m.kind == "start":
            st = next(s for s in plan["start"] if rename("%s-speed-start-%s" % (plan["prefix"], s["module"])) == m.key)
            zones = {lint.zone_key(z) for z in st["zones"]}
        extra = [q for q, R in sorted(pl.Q.items()) if q not in in_route and R.zones <= zones and not R.new
                 and any(applicable(R, *c) for c in pl.universe) and (m.kind != "start" or m.for_races & (R.races or m.for_races))]
        before = list(m.acts)
        m.acts = pl.add_filtered(m.acts, entry, extra)
        if m.kind == "start":
            combos = sorted(c for c in pl.universe if c[0] in m.for_races)
            if max(pl.start_levels(m.acts, combos).values()) > speed.report.get("arrive", 10) + 1 - speed.arrive_margin:
                m.acts = before  # the arrival window holds (G7)
        pool_added += [(0.0, q) for q in quests_of(m.acts) if q not in in_route]
        in_route |= set(quests_of(m.acts))
    pl.finalize()
    pl.report["explorer_pool_added"] = len(pool_added)
    added = []
    for m in mods:
        zone = {lint.zone_key(m.zone)}
        if m.kind == "start":
            st = next(s for s in plan["start"] if rename("%s-speed-start-%s" % (plan["prefix"], s["module"])) == m.key)
            zone = {lint.zone_key(z) for z in st["zones"]}
        cands = [q for q, R in sorted(pl.Q.items()) if R.new and q not in in_route and R.zones <= zone
                 and any(applicable(R, *c) for c in pl.universe)]
        for q in cands:
            R = pl.Q[q]
            trial = insert_quest(pl.env, m.acts, q, full_todo(R))
            ia = trial.index(("a", q))
            if pl_lv(m, min(ia, len(m.lv) - 1)) < _req(R):
                continue
            st0 = State(level=max(1, pl_lv(m, 0)))
            extra = replay(pl.env, st0, trial).T - replay(pl.env, st0, m.acts).T
            if m.kind == "start" and extra <= limit:
                # the arrival window of the speed route holds in explorer too (G7)
                combos = sorted(c for c in pl.universe if c[0] in m.for_races)
                if max(pl.start_levels(trial, combos).values()) > cap:
                    continue
            if extra <= limit:
                m.acts = trial
                in_route.add(q)
                added.append((extra, q))
        pl.finalize()
    pl.report["explorer_added"] = len(added)
    added = [(e, q) for e, q in added + pool_added if any(q in quests_of(m.acts) for m in pl.modules)]
    pl.report["explorer_seconds_before_repair"] = round(time.perf_counter() - t0, 1)
    pl.inserts = class_inserts(pl)
    pl.finalize()
    pl.trim_inserts()
    # the order of the speed route stays; the repair only announces grinds and takes flight paths
    rep = Repair(pl, sources)
    rep.best, rep.history = None, []
    rep.rounds(3, ("gates", "r13"))
    rep.restore(rep.best[1])
    pl.finalize()
    # the guards against the start route hold in explorer too: while one breaks, the new quest with
    # the largest extra time leaves the route again (never one another quest needs; counted)
    dropped = []
    rows, _ = rep.evaluate()
    breaches = sum(1 for r in rows if guard_breach(r))
    for q in [q for _, q in sorted(added, reverse=True)]:
        if breaches == 0:
            break
        needed = any(q in g for m in pl.modules for v, qq in m.acts if v in ("a", "A") for g in pl.Q[qq].pre)
        if needed:
            continue
        snap = rep.snapshot()
        for m in pl.modules:
            if q in quests_of(m.acts):
                m.acts = [a for a in m.acts if a[1] != q]
        pl.finalize()
        rows, _ = rep.evaluate()
        now = sum(1 for r in rows if guard_breach(r))
        if now < breaches:  # the quest goes only when that ends a guard breach
            breaches = now
            dropped.append(q)
        else:
            rep.restore(snap)
            pl.finalize()
    pl.report["explorer_guard_breaches"] = breaches
    pl.report["explorer_dropped_for_guards"] = dropped
    pl.report["repair"] = rep.history
    pl.report["explorer_seconds"] = round(time.perf_counter() - t0, 1)
    return pl


def guard_breach(r):
    """A guard against the start route breaks (P3 in a draw, P11, P4b, P5b, P9b)."""
    if not r.get("baseline"):
        return False
    return bool(r.get("p3_worse_draws") or (r.get("p11_vs_base") or 0) > 0 or (r.get("p4_vs_base") or 0) > 0
                or (r.get("p5_vs_base") or 0) > 0 or (r.get("p9_vs_base") or 0) > 0)


def pl_lv(m, i):
    return m.lv[i] if 0 <= i < len(m.lv) else (m.lv[-1] if m.lv else 1)


# --- repair rounds against the metrics (the guards and rules as hard limits) ------------------------

VCODE = {"accept": "a", "complete": "c", "turnin": "t"}
GUARD = 50  # weight of one guard breach in the repair score


class Repair:
    """Plays the emitted route of every combination of the faction in the simulator, reads which
    rules broke (tools/routekit/metrics.py, the same code as the CI job) and changes the modules:
    announce grinds (R17, R19), take flight paths on the way (R13), take a follow-up quest in the
    turn-in step (R04), take a quest at the first visit of its giver (R05, P6 later), work an
    objective when passing it (R06), take quests passed on the way (P6, R18), do work on the first
    visit (P5). Counted in rounds, never in seconds."""

    def __init__(self, planner, sources):
        self.pl = planner
        self.sources = sources
        self.banned = set()  # quests the repair took out for P4; never put back by P6 or R18
        self.p4_tries = {}
        self.batch = planner.p.raw.get("opt", {}).get("repair_batch", {}).get("value", 10000)
        self.polish_tries = planner.p.raw.get("opt", {}).get("polish_tries", {}).get("value", 4000)
        self.guard_rounds = planner.p.raw.get("opt", {}).get("guard_rounds", {}).get("value", 3)
        self.baseline = getattr(planner, "baseline", None)

    # one evaluation of the whole faction
    def evaluate(self):
        from . import metrics, routefmt, sim

        pl = self.pl
        files, compose = emit_all(pl, self.sources)
        mods = {k: routefmt.parse("\n".join(v) + "\n", k) for k, v in files.items()}
        comp = routefmt.parse_compose("\n".join(["#faction %s" % pl.faction] + compose) + "\n", "COMPOSE")
        ctx = metrics.Context(pl.f, mods, [comp], pl.p, detail=True)
        simu = sim.Simulator(pl.f, mods, pl.p)
        rows, runs = [], []
        for race, cls in sorted(pl.universe):
            keys = comp.route(pl.mode, race, cls) or []
            run = simu.run(pl.mode, race, cls, keys)
            runs.append(run)
            rows.append(metrics.evaluate(ctx, run))
        if self.baseline:
            metrics._cross(rows, pl.p, self.baseline)
        return rows, runs

    def score(self, rows):
        """Hard violations summed over the combinations (lower is better)."""
        n = 0
        for r in rows:
            ru = r["rules"]
            n += sum(ru.get(k, 0) for k in ("R04", "R05", "R06", "R07", "R09", "R10", "R11", "R12", "R13", "R17", "R18",
                                            "R19", "R23", "R26", "R30"))
            n += r["p6_never"] + r["p6_later"] + r["p5_wasted"] + r["p8_above"] + r["p8_gray"] + r["g1_errors"] + r["g2_stuck"]
            n += r["p7_open_end"] + r["p4_long"]
            n += 0 if r["g7_dev"] is None or abs(r["g7_dev"]) <= 1.0 else 5
            # guards against the start route weigh most: a breach here is never accepted
            if r.get("baseline"):
                n += GUARD * (int((r.get("p3_worse_draws") or 0) > 0) + int((r.get("p11_vs_base") or 0) > 0)
                              + max(0, r.get("p9_vs_base") or 0))
                n += GUARD * (max(0, r.get("p5_vs_base") or 0) + max(0, r.get("p4_vs_base") or 0))
        return n

    def locate(self, verb, q):
        for m in self.pl.modules + list(getattr(self.pl, "inserts", [])):
            for i, a in enumerate(m.acts):
                if a == (verb, q):
                    return m, i
        if verb == "a":  # a quest every combination takes at its early accept
            return self.locate("A", q)
        return None, None

    def action(self, run, idx):
        """(verb, q) of the quest action at run index idx or the nearest quest action before it."""
        k = min(idx, len(run.actions) - 1)
        while k >= 0:
            a = run.actions[k]
            if a["verb"] in VCODE and a["q"] is not None:
                return (VCODE[a["verb"]], a["q"]), k
            k -= 1
        return None, None

    CONTENT = ("p6_never", "r18", "long_legs")
    ORDER = ("p6_never", "r18", "r04", "r05", "p6_later", "r06", "p5_returns", "r07", "r13", "gates", "long_legs")

    def run(self, rounds):
        """Three phases, each counted in rounds: (A) content: take the passed quests worth it (P6,
        R18), drop long low-value trips (P4); (B) polish the walking order of every module; (C)
        order rules: R04, R05, P6 later, R06, P5, R07, flight paths (R13) and grind announcements
        (R17, R19). The best state by hard breaches is kept."""
        pl = self.pl
        self.best = None
        self.history = []
        content = max(1, rounds // 3)
        self.rounds(content, self.CONTENT + ("gates",))
        if self.polish():
            pl.finalize()
        self.rounds(rounds - content, self.ORDER)
        self.restore(self.best[1])
        pl.finalize()
        # guard phase: while a combination returns more often than on its start route (P5b),
        # polish again and move the possible actions of each return to the earlier visit
        for _ in range(self.guard_rounds):
            rows, runs = self.evaluate()
            if not any((r.get("p5_vs_base") or 0) > 0 for r in rows):
                break
            self.polish()
            pl.finalize()
            self.rounds(2, ("p5_returns", "gates"))
            self.restore(self.best[1])
            pl.finalize()
        pl.report["repair"] = self.history
        return self.best[0]

    def rounds(self, n, kinds):
        pl = self.pl
        for _ in range(n + 1):
            rows, runs = self.evaluate()
            sc = self.score(rows)
            self.history.append(sc)
            if self.best is None or sc < self.best[0]:
                self.best = (sc, self.snapshot())
            if sc == 0 or _ == n:
                break
            if not self.fix(rows, runs, kinds):
                break
            pl.finalize()

    def polish(self):
        """Reorders the actions of every module by walking time (relocate, or-opt, 2-opt), with the
        same objective as the block search; the quest choice stays."""
        pl = self.pl
        changed = False
        for m in pl.modules:
            if len(m.acts) < 4:
                continue
            entry = self.entry_state(m)
            if entry is None:
                continue
            todo = {q: tuple(v for v, qq in m.acts if qq == q) for q in quests_of(m.acts)}
            pl.env.w_return = pl.env.return_sec
            try:
                b = Block(pl.env, "polish-" + m.key, entry, todo)
                b.acts = list(m.acts)
                b.j, b.res = b.goal(b.acts)
                j0 = b.j
                pull_forward(pl.env, b)
                b.improve(min(pl.tries(len(todo)), self.polish_tries), pl.seed, ops=("relocate", "or_opt", "two_opt", "swap"))
            finally:
                pl.env.w_return = 0.0
            if b.j < j0 - 1e-6 and b.acts != m.acts:
                m.acts = list(b.acts)
                changed = True
        return changed

    def entry_state(self, m):
        """State of the reference combination when it enters module m (start: level 1)."""
        pl = self.pl
        if m.kind == "start":
            return State(level=1)
        prev = None
        for x in pl.modules:
            if x is m:
                break
            prev = x
        if prev is None or pl.ref not in prev.after:
            return None
        st = prev.after[pl.ref][0].copy()
        st.done = set(prev.after[pl.ref][1])
        st, _ = entry_grind(pl.env, st, getattr(m, "min_lv", None))
        return st

    def snapshot(self):
        return [(m.key, list(m.acts), list(m.lv), dict(m.xp_marks), {k: list(v) for k, v in m.fps.items()})
                for m in self.pl.modules + list(getattr(self.pl, "inserts", []))]

    def restore(self, snap):
        by = {m.key: m for m in self.pl.modules + list(getattr(self.pl, "inserts", []))}
        for key, acts, lv, marks, fps in snap:
            m = by[key]
            m.acts, m.lv, m.xp_marks, m.fps = list(acts), list(lv), dict(marks), {k: list(v) for k, v in fps.items()}

    # --- the fixes --------------------------------------------------------------------------------

    def fix(self, rows, runs, kinds):
        changed = False
        done = set()
        fixes = {"r04": self.fix_r04, "r05": self.fix_r05, "p6_later": self.fix_later, "r06": self.fix_r06,
                 "p6_never": self.fix_never, "r18": self.fix_r18, "p5_returns": self.fix_wasted, "r07": self.fix_r07,
                 "r13": self.fix_r13, "gates": self.fix_gate, "long_legs": self.fix_p4}
        budget = self.batch
        for row, run in zip(rows, runs):
            d = row.get("detail", {})
            for kind in kinds:
                fn = fixes[kind]
                for item in d.get(kind, []):
                    if budget <= 0:
                        return changed
                    key = (kind, repr(item) if kind != "gates" else (repr(item), row["label"]))
                    if kind in ("r13", "gates", "p5_returns", "r18"):
                        key = (kind, repr(self._key(run, kind, item)))
                    if key in done:
                        continue
                    done.add(key)
                    if fn(run, item):
                        changed = True
                        budget -= 1
        return changed

    def _key(self, run, kind, item):
        if kind == "r13":
            return item[0]
        if kind == "gates":
            a, _ = self.action(run, item[0])
            return (a, item[1])
        if kind == "r18":
            a, _ = self.action(run, item[0])
            return (a, tuple(item[1]))
        if kind == "p5_returns":
            return tuple(self.action(run, i)[0] for i, _ in item)
        return item

    def lv_at(self, m, i):
        return m.lv[i] if 0 <= i < len(m.lv) else (m.lv[-1] if m.lv else 1)

    def zone_ok(self, act, m):
        """An action may only stand in a module of its own zone (no hidden zone change, R09, P9)."""
        z = act_zone(self.pl, act)
        return z is None or z == lint.zone_key(m.zone) if m.zone is not None else True

    def move(self, act, m2, i2):
        """Moves an action to module m2 at index i2 (before what stands there)."""
        m1, i1 = self.locate(*act)
        if m1 is None or not self.zone_ok(act, m2) or m1.kind == "class" or m2.kind == "class":
            return False
        if (m1.kind == "start" or m2.kind == "start") and m1 is not m2:
            return False  # the start modules keep their XP: arrival window (G7)
        if act[0] == "t" and self.lv_at(m2, i2) + 1 > self.pl.Q[act[1]].ql + 5:
            return False  # the turn-in keeps full quest XP for every combination (R01, P8)
        del m1.acts[i1]
        lv1 = m1.lv.pop(i1)
        if m1 is m2 and i1 < i2:
            i2 -= 1
        m2.acts.insert(i2, act)
        m2.lv.insert(i2, self.lv_at(m2, i2))
        if not self.order_ok(act[1]):
            del m2.acts[i2]
            del m2.lv[i2]
            m1.acts.insert(i1, act)
            m1.lv.insert(i1, lv1)
            return False
        if m1 is not m2:  # announcements and flight paths travel with their action (R19, R13)
            if act in m1.xp_marks:
                m2.xp_marks[act] = max(m2.xp_marks.get(act, 0), m1.xp_marks.pop(act))
            if act in m1.fps:
                m2.fps.setdefault(act, []).extend(m1.fps.pop(act))
        return True

    def order_ok(self, q):
        """accept < objectives < turn-in of quest q along the route (modules in route order)."""
        pos = {}
        for k, m in enumerate(self.pl.modules):
            for i, (v, qq) in enumerate(m.acts):
                if qq == q:
                    pos[v] = (k, i)
        seq = [pos[v] for v in ("a", "c", "t") if v in pos]
        if "A" in pos and any(pos["A"] > pos[v] for v in ("c", "t") if v in pos):
            return False
        return seq == sorted(seq)

    def fix_r04(self, run, item):
        q, f = item
        Q = self.pl.Q
        mt, it = self.locate("t", q)
        ma, ia = self.locate("a", f)
        if mt is None or ma is None:
            return False
        lv_after = self.lv_at(mt, it + 1)
        if lv_after >= _req(Q[f]):
            return self.move(("a", f), mt, it + 1)
        if self.early(f, mt, it + 1):
            return True
        # else hand in q right before the follow-up's accept (same NPC), if it still pays
        if self.lv_at(ma, ia) <= Q[q].ql + 4:
            return self.move(("t", q), ma, ia)
        return False

    def early(self, q, m, i):
        """An early accept of q after index i of module m for the combinations already at its level
        (the finalize step keeps it only for them, R05, P6)."""
        if self.locate("A", q)[0] is not None or m.kind == "class" or not self.zone_ok(("a", q), m):
            return False
        m.acts.insert(i, ("A", q))
        m.lv.insert(i, self.lv_at(m, i))
        if not self.order_ok(q):
            del m.acts[i]
            del m.lv[i]
            return False
        return True

    def fix_r05(self, run, item):
        q, j = item
        aj, _ = self.action(run, j)
        if aj is None:
            return False
        mj, ij = self.locate(*aj)
        if mj is None:
            return False
        if self.lv_at(mj, ij) < _req(self.pl.Q[q]):
            return self.early(q, mj, ij + 1)
        return self.move(("a", q), mj, ij + 1)

    def fix_later(self, run, item):
        q, i = item
        ai, _ = self.action(run, i)
        if ai is None:
            return False
        mi, ii = self.locate(*ai)
        if mi is None:
            return False
        # the leg to action i passed the giver: take it before that action
        if self.lv_at(mi, ii) < _req(self.pl.Q[q]):
            return self.early(q, mi, ii)
        return self.move(("a", q), mi, ii)

    def fix_r06(self, run, item):
        q, i = item
        a_i = run.actions[i] if i < len(run.actions) else None
        if a_i is None or a_i["verb"] not in VCODE:
            return False
        act = (VCODE[a_i["verb"]], a_i["q"])
        mi, ii = self.locate(*act)
        mc, ic = self.locate("c", q)
        if mi is None or mc is None:
            return False
        R = self.pl.Q[q]
        if len({lint.zone_key(z) for z, _ in R.objs}) != 1 or lint.zone_key(R.objs[0][0]) != mi.zone and mi.kind == "core":
            return False
        ma, ia = self.locate("a", q)
        if ma is mi and ia >= ii:
            return False
        return self.move(("c", q), mi, ii)

    def _insert_quest(self, q, mi, ii):
        """Takes quest q: accept before index ii of module mi, objectives and turn-in at their
        cheapest place after it, in this module or (carried) in the next core module of their zone."""
        pl = self.pl
        R = pl.Q.get(q)
        if R is None or q in self.banned or self.locate("a", q)[0] is not None or self.locate("A", q)[0] is not None:
            return False
        if mi.kind == "class":
            return False
        mods = pl.modules
        k0 = mods.index(mi)

        def zone_of(m):
            return {lint.zone_key(m.zone)}
        plan = []
        verbs = full_todo(R)[1:]
        k = k0
        for v in verbs:
            z = lint.zone_key(R.objs[0][0]) if v == "c" and R.objs else (R.end_zone if v == "t" else None)
            if v == "c" and len({lint.zone_key(zz) for zz, _ in R.objs}) > 1:
                return False
            while k < len(mods) and z is not None and z not in zone_of(mods[k]):
                k += 1
                if k < len(mods) and mods[k].kind == "start":
                    return False
            if k >= len(mods):
                return False
            plan.append((v, k))
        if R.start_zone not in zone_of(mi):
            return False
        snap = self.snapshot()
        mi.acts.insert(ii, ("a", q))
        mi.lv.insert(ii, self.lv_at(mi, ii))
        lo = {k0: ii + 1}
        for v, k in plan:
            m = mods[k]
            start = lo.get(k, 0)
            # cheapest place at or after `start`; a turn-in only where it keeps full quest XP (R01)
            p = pos_of(pl.env, (v, q))
            best, bi = None, None
            for j in range(start, len(m.acts) + 1):
                if v == "t" and self.lv_at(m, j) + 1 > R.ql + 5:
                    break
                d = _delta(pl.env, m.acts, j, p)
                if best is None or d < best - 1e-9:
                    best, bi = d, j
            if bi is None:
                self.restore(snap)
                return False
            m.acts.insert(bi, (v, q))
            m.lv.insert(bi, self.lv_at(m, bi))
            lo = {k: bi + 1}
        if mi.kind == "start" and not self.window_ok(mi):
            self.restore(snap)
            return False
        return True

    def window_ok(self, m):
        """Every combination of a start module still arrives inside the window (G7)."""
        pl = self.pl
        if "arrive" not in pl.report:
            return True
        cap = pl.report["arrive"] + 1 - pl.arrive_margin
        combos = sorted(c for c in pl.universe if c[0] in m.for_races)
        acts = [a if a[0] != "A" else ("a", a[1]) for a in m.acts]
        seen, clean = set(), []
        for a in acts:  # an early and a main accept of one quest count once
            if a[0] == "a" and a[1] in seen:
                continue
            seen.add(a[1]) if a[0] == "a" else None
            clean.append(a)
        lv = pl.start_levels(clean, combos).values()
        return max(lv) <= cap and min(lv) >= pl.report["arrive"] - 1e-9

    def fix_never(self, run, item):
        q, i = item
        if self.pl.Q.get(q) is None:
            return False
        ai, _ = self.action(run, i)
        if ai is None:
            return False
        mi, ii = self.locate(*ai)
        if mi is None or self.lv_at(mi, ii) < _req(self.pl.Q[q]):
            return False
        return self._insert_quest(q, mi, ii)

    def fix_r18(self, run, item):
        idx, qs = item
        ai, _ = self.action(run, idx)
        if ai is None:
            return False
        mi, ii = self.locate(*ai)
        if mi is None:
            return False
        ok = False
        for q in qs:
            if self.pl.Q.get(q) is None or self.lv_at(mi, ii) < _req(self.pl.Q[q]):
                continue
            if self.locate("a", q)[0] is not None:
                ok = self.move(("a", q), mi, ii) or ok  # in the route later: take it before the grind
            else:
                ok = self._insert_quest(q, mi, ii) or ok
        return ok

    def fix_wasted(self, run, item):
        ok = False
        for i, j in item:
            ai, _ = self.action(run, i)
            aj, _ = self.action(run, j)
            if ai is None or aj is None or ai == aj:
                continue
            mj, ij = self.locate(*aj)
            mi, ii = self.locate(*ai)
            if mj is None or mi is None:
                continue
            if ai[0] == "a" and self.lv_at(mj, ij) < _req(self.pl.Q[ai[1]]):
                continue
            ok = self.move(ai, mj, ij + 1) or ok
        return ok

    def fix_r13(self, run, item):
        fid, i = item
        pl = self.pl
        fm = pl.flight_master(fid)
        if fm is None:
            return False
        a, k = self.action(run, i - 1)
        if a is None:
            return False
        m, idx = self.locate(*a)
        if m is None:
            return False
        z = lint.zone_key(fm[1])
        az = run.actions[k]["zone"]
        if az is None or lint.zone_key(az) != z:
            return False
        lst = m.fps.setdefault(a, [])
        if any(x[0] == fid for x in lst):
            return False
        lst.append(fm)
        return True

    def replace(self, q):
        """Objectives and turn-in of q to their cheapest places (yards) after its accept, in the
        module of each and keeping the order."""
        pl = self.pl
        changed = False
        for v in ("c", "t"):
            m, i = self.locate(v, q)
            if m is None or m.kind == "class":
                continue
            ma, ia = self.locate("a", q)
            lo = ia + 1 if ma is m else 0
            if v == "t":
                mc, ic = self.locate("c", q)
                if mc is m:
                    lo = max(lo, ic + 1)
            acts = m.acts[:i] + m.acts[i + 1:]
            lo = lo - 1 if lo > i else lo
            p = pos_of(pl.env, (v, q))
            best, bj = None, None
            for j in range(max(0, lo), len(acts) + 1):
                if v == "t" and self.lv_at(m, j) + 1 > pl.Q[q].ql + 5:
                    break
                d = _delta(pl.env, acts, j, p)
                if best is None or d < best - 1e-9:
                    best, bj = d, j
            if bj is None:
                continue
            j_old = i
            if bj != j_old and self.move((v, q), m, bj if bj < i else bj + 1):
                changed = True
        return changed

    def fix_r07(self, run, item):
        """Two objectives close together with a turn-in far away between them (R07): the second
        objective follows the first."""
        i1, i2 = item
        a1, _ = self.action(run, i1)
        a2, _ = self.action(run, i2)
        if a1 is None or a2 is None:
            return False
        m1, k1 = self.locate(*a1)
        if m1 is None:
            return False
        return self.move(a2, m1, k1 + 1)

    def fix_p4(self, run, item):
        """A long trip inside a zone for one quest worth less than half the route's XP rate (P4):
        first its objectives and turn-in go to their cheapest places after the accept; when the
        trip is still long, the quest leaves the route, unless a quest of the route needs it."""
        q = item[0]
        pl = self.pl
        if self.locate("a", q)[0] is None:
            return False
        self.p4_tries[q] = self.p4_tries.get(q, 0) + 1
        if self.p4_tries[q] == 1 and self.replace(q):
            return True
        needed = any(q in g for m in pl.modules for v, qq in m.acts if v == "a" for g in pl.Q[qq].pre)
        if needed:
            return False
        snap = self.snapshot()
        for m in pl.modules + list(getattr(pl, "inserts", [])):
            keep = [i for i, a in enumerate(m.acts) if a[1] != q]
            if len(keep) != len(m.acts):
                m.acts = [m.acts[i] for i in keep]
                m.lv = [m.lv[i] for i in keep]
                if m.kind == "start" and not self.window_ok(m):
                    self.restore(snap)
                    return False
        self.banned.add(q)
        return True

    def fix_gate(self, run, item):
        idx, to, announced = item
        if announced:
            return False
        pl = self.pl
        if idx >= len(run.actions):
            # the grind at the end of the route: announced at the last step every combination sees
            m = [x for x in pl.modules if x.kind == "core"][-1]
            for v, q in reversed(m.acts):
                if m.aud.get(q, (None, None)) == (None, None) and (v != "c" or pl.Q[q].objs):
                    if m.xp_marks.get((v, q), 0) < to:
                        m.xp_marks[(v, q)] = to
                        return True
                    return False
            return False
        a, _ = self.action(run, idx)
        if a is None:
            return False
        m, i = self.locate(*a)
        if m is None:
            return False
        if m.xp_marks.get(a, 0) >= to:
            return False
        m.xp_marks[a] = to
        return True
