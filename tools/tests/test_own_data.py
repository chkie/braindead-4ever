# SPDX-License-Identifier: GPL-3.0-or-later
"""Own data (Welle 4): prerequisites from player observations, the observe step, the dungeon tables
and the module times in the compiled data. Run from the repository root:

  python3 -m unittest discover -s tools/tests -t .
"""

import base64
import json
import os
import random
import unittest
import zlib

from tools.routekit import compiler, merge, observe, prereq
from tools.routekit.io import read_jsonl

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")
DATA = os.path.join(HERE, "..", "..", "data")


def cases():
    with open(os.path.join(FIX, "prereq_cases.json"), encoding="utf-8") as fh:
        return json.load(fh)["cases"]


def pm1(payload, method="d"):
    """An export text like Pathmark/Collector/Export.lua builds it, with real DEFLATE."""
    raw = json.dumps(payload).encode("utf-8")
    if method == "d":
        c = zlib.compressobj(9, zlib.DEFLATED, -15)
        z = c.compress(raw) + c.flush()
    else:
        z = zlib.compress(raw)
    body = base64.b64encode(z).decode("ascii")
    return "PM1:%s:%d:%s:%s" % (method, len(body), observe.adler32(body), body)


class PrereqRule(unittest.TestCase):
    def test_shared_cases(self):
        for c in cases():
            with self.subTest(case=c["name"]):
                o = prereq.Observations()
                for ob in c["obs"]:
                    o.add(c["q"], ob["t"], ob["l"], ob["u"], ob["d"], ob["n"])
                state, groups, _ = o.result(c["q"])
                self.assertEqual(c["state"], state)
                self.assertEqual(c["pre"], groups)


class Observe(unittest.TestCase):
    def payload(self, install, seq, lines):
        return {"format": "pathmark", "v": 1, "install": install, "own": ["chunk\t0\t%d\t20762\n" % seq + "\n".join(lines)], "net": []}

    def test_decodes_both_methods_and_rejects_changed_text(self):
        p = self.payload("inst", 1, ["zone\t1\t1429\t10\t20"])
        self.assertEqual([p], observe.decode(pm1(p, "d")))
        self.assertEqual([p], observe.decode(pm1(p, "z")))
        text = pm1(p)
        broken = text[:-3] + ("A" if text[-3] != "A" else "B") + text[-2:]
        self.assertEqual([], observe.decode(broken))
        self.assertEqual([], observe.decode(text[:-10]), "truncated")

    def test_collects_accepts_received_observations_and_module_times(self):
        def accept(q, token, link, unlock=1, done=""):
            return "accept\t5\t1429\t100\t200\t%d\tc\t197\t\tName\t5\t40\t%s\t%d\t%d\t%s\t" % (q, token, link, unlock, done)

        texts = []
        for i, tok in enumerate(("aaaaaa", "bbbbbb")):
            lines = [accept(900002, tok, 900001), "split\t9\t\t\t\ta-speed-start-elwynn\t%d\tspeed" % (3000 + i * 600)]
            texts.append(pm1(self.payload("inst%d" % i, 1, lines)))
        # A third player's observation arrives through the in-game exchange of player 0.
        net = {"format": "pathmark", "v": 1, "install": "inst0", "own": [], "net": ["chunk\t0\t7\t20762\nrx\t3\tp\tcccccc\t900002\t0\t0\t900001\t"]}
        texts.append(pm1(net))
        texts.append(texts[0])  # the same export pasted twice counts once
        obs, splits = observe.collect([p for t in texts for p in observe.decode(t)])
        self.assertEqual(("observed", [[900001]], 3), obs.result(900002))
        pre, times = observe.results(obs, splits)
        self.assertEqual([{"q": 900002, "pre": [[900001]], "basis": "observed", "observers": 3}], pre)
        self.assertEqual([{"module": "a-speed-start-elwynn", "runs": 2, "seconds": 3600}], times)


class MergeOwnRoot(unittest.TestCase):
    def test_observed_prerequisite_secures_a_new_quest(self):
        pre = merge.prereq_state(None, {"q": 95000}, {"pre": [[94999]], "basis": "observed"}, set(), True, False)
        self.assertEqual({"v": [[94999]], "src": ["own"], "state": "secured"}, pre)

    def test_observed_none_secures_only_without_a_stated_prerequisite(self):
        o = {"pre": [], "basis": "observed-none"}
        self.assertEqual("secured", merge.prereq_state(None, {"q": 1}, o, set(), True, False)["state"])
        stated = merge.prereq_state(None, {"q": 1, "pre": {"all": [5]}}, o, set(), True, False)
        self.assertEqual([[5]], stated["v"], "a stated prerequisite is not dropped by an observed none")

    def test_own_and_att_disagree(self):
        pre = merge.prereq_state(None, {"q": 1, "pre": {"all": [5]}}, {"pre": [[6]], "basis": "observed"}, set(), True, False)
        self.assertEqual("conflict", pre["state"])

    def test_unknown_without_any_root(self):
        self.assertEqual("unknown", merge.prereq_state(None, {"q": 1}, None, set(), True, False)["state"])


class DungeonTables(unittest.TestCase):
    def facts(self):
        def q(i, lv, xp, side="A", **kw):
            r = {"q": i, "level": {"v": lv}, "min": {"v": lv - 5}, "xp": {"v": xp}, "side": {"v": side}, "type": kw.pop("type", 81)}
            r["startPos"] = {"v": [1436, -1000.0, 500.0]}
            r["pre"] = {"v": kw.pop("pre", []), "state": "secured"}
            r.update(kw)
            return r

        f = {
            1: q(1, 18, 2000),
            2: q(2, 20, 3000, pre=[[1]]),
            3: q(3, 22, 4000),
            4: q(4, 20, 1500, side="H"),
            5: q(5, 21, 900, startItem=77),
        }
        for i, lv in ((10, 18), (11, 18), (12, 18), (13, 20), (14, 22)):
            f[i] = {"q": i, "level": {"v": lv}, "xp": {"v": 1000}, "type": 0}
        return f

    def test_band_faction_and_forever_xp(self):
        d = [{"id": 63, "area": 1581, "min": 10, "quests": [1, 2, 3, 4, 5], "entrance": [1436, 1539.7, -11327.3]}]
        dl, ql, used = compiler._dungeon_tables("Alliance", self.facts(), d)
        # median quest level 20 - 3 = 17 (above the instance minimum 10); highest 22 + 2 = 24
        self.assertEqual(
            "\t\t[63] = { area = 1581, min = 10, lo = 17, hi = 24, entrance = { 1436, 1539.7, -11327.3 }, quests = { 1, 2, 3 } },", dl[1]
        )
        self.assertEqual({1, 2, 3}, used, "Horde quest and item-started quest left out")
        # normal XP at 18 is 1000: 1000 + (2000 - 1000) / 2 = 1500
        self.assertIn("\t\t[1] = { 18, 13, 1500, 1436, -1000, 500 },", ql)
        self.assertIn("\t\t[2] = { 20, 15, 2000, 1436, -1000, 500, pre = { { 1 } } },", ql)

    def test_forever_rule_keeps_values_without_a_normal_quest(self):
        self.assertEqual(2000, compiler.forever_dungeon_xp(2000, 40, {18: 1000}))
        self.assertEqual(800, compiler.forever_dungeon_xp(800, 18, {18: 1000}), "below the normal value nothing changes")

    def test_classic_quests_for_the_explorer(self):
        facts = {5: {"q": 5}, 90001: {"q": 90001, "new": True}, 7: {"q": 7, "new": False}}
        self.assertEqual(["\tclassic = {", "\t\t5, 7,", "\t},"], compiler._classic(facts))

    def test_continent_of_goto_and_giver_maps(self):
        class El:
            verb, args = "goto", {"map": 1411}

        class St:
            elements = [El()]

        class Mod:
            steps = [St()]

        lines = compiler._maps([Mod()], [1454, 9999], {1411: 1, 1454: 1, 1453: 0})
        self.assertEqual(["\tmaps = {", "\t\t[1411] = 1, [1454] = 1,", "\t},"], lines, "unknown maps are left out")

    def test_unsure_and_times(self):
        facts = {7: {"pre": {"state": "unknown"}}, 8: {"pre": {"state": "secured"}}, 9: {"pre": {"state": "conflict"}}}
        self.assertEqual(["\tunsure = {", "\t\t7, 9,", "\t},"], compiler._unsure([], facts, {7, 8, 9}))
        lines = compiler._times([{"module": "a-speed-start-elwynn", "runs": 20, "seconds": 3600}])
        self.assertEqual('\t\t["a-speed-start-elwynn"] = { 20, 3600 },', lines[1])


class SimulatedRuns(unittest.TestCase):
    """Players run the new Forever quests of levels 21 to 30 the way the game offers them: they visit
    NPCs in a random order, the NPC lists its offers, they turn in what it takes (after each turn-in
    the NPC offers what that unlocked) and take the rest. Every offer and accept is observed (link,
    unlock, recent turn-ins, checks of the candidates known so far) and shared like in the game.
    Hidden truth: the prerequisites the sources state; quests no source states anything for are
    played as quests without a prerequisite (in reality unknown). Run twice: the addon knows the
    source chains (as with the compiled data), and it knows nothing (chains only from players).
    Fails on any wrong prerequisite or wrong "none"; prints the share before and after."""

    PLAYERS = 12

    def setUp(self):
        path = os.path.join(DATA, "facts", "quests.jsonl")
        if not os.path.exists(path):
            self.skipTest("no data/facts")
        self.facts = {r["q"]: r for r in read_jsonl(path)}

    def band(self, r):
        lv = (r.get("level") or {}).get("v") or (r.get("min") or {}).get("v")
        return r["new"] and lv is not None and 21 <= lv <= 30

    def npc(self, q, field):
        v = (self.facts[q].get(field) or {}).get("v") or []
        return (v[0]["k"], v[0]["id"]) if v else ("q", q)

    def play(self, quests, truth, obs, player, rng, hide=False):
        givers = {q: self.npc(q, "start") for q in quests}
        enders = {q: self.npc(q, "end") for q in quests}
        done, log, recent = set(), set(), []

        def available(q):
            return q not in done and q not in log and all(any(g in done for g in grp) for grp in truth.get(q, []))

        def offered(here):
            return [q for q in quests if givers[q] == here and available(q)]

        def observe(q, link=0, unlock=0):
            known = set(obs.candidates(q))
            if not hide:
                known |= {c for grp in truth.get(q, []) for c in grp}
            checked = [c for c in sorted(known) if c != link]
            d = [c for c in checked if c in done] + [c for c in recent[: prereq.LIST_MAX] if c not in checked and c != link]
            token = "p%02d%06d" % (player, q % 1000000)
            obs.add(q, token, link, unlock, d, [c for c in checked if c not in done])

        for _ in range(10 * len(quests)):
            spots = sorted({enders[q] for q in log} | {givers[q] for q in quests if available(q)})
            if not spots:
                break
            here = rng.choice(spots)
            listed = set(offered(here))
            for q in sorted(listed):  # the NPC lists its offers when the player talks to it
                observe(q)
            last = 0
            turn = [q for q in sorted(log) if enders[q] == here]
            rng.shuffle(turn)
            for t in turn:
                log.discard(t)
                done.add(t)
                recent.insert(0, t)
                last = t
                # After each turn-in the NPC offers the unlocked follow-up at once (or lists again).
                new = [q for q in offered(here) if q not in listed]
                rng.shuffle(new)
                for q in new:
                    observe(q, t, 1)
                    log.add(q)
                listed = set(offered(here))
            rest = offered(here)
            rng.shuffle(rest)
            for q in rest:
                link = last if last and enders[last] == givers[q] else 0
                observe(q, link, 0)  # offered before the last turn-in: no unlock
                log.add(q)
                last = 0  # the next accept follows an accept, not a turn-in

    def simulate(self, seed, hide):
        rng = random.Random(seed)
        everything, before, after, found, wrong = set(), set(), set(), 0, []
        for side in ("A", "H"):
            quests = sorted(q for q, r in self.facts.items() if self.band(r) and (r.get("side") or {}).get("v") in ("B", side))
            inside = set(quests)
            truth = {}
            for q in quests:
                pre = self.facts[q]["pre"]
                groups = [g for g in pre["v"] if all(c in inside for c in g)] if pre["state"] == "secured" else []
                if groups:
                    truth[q] = groups
            obs = prereq.Observations()
            for player in range(self.PLAYERS):
                self.play(quests, truth, obs, player, rng, hide)
            for q in quests:
                everything.add(q)
                state, groups, _ = obs.result(q)
                secured = self.facts[q]["pre"]["state"] == "secured"
                if secured:
                    before.add(q)
                if secured or state != "unknown":
                    after.add(q)
                want = {c for g in truth.get(q, []) for c in g}
                got = {c for g in groups for c in g}
                if state == "observed":
                    found += 1
                    if not got <= want:
                        wrong.append((q, sorted(got), sorted(want)))
                if state == "observed-none" and want:
                    wrong.append((q, "none", sorted(want)))
        return everything, before, after, found, wrong

    def test_share_before_and_after(self):
        lines = []
        for hide in (False, True):
            for seed in (20261101, 1, 2):
                everything, before, after, found, wrong = self.simulate(seed, hide)
                with self.subTest(hide=hide, seed=seed):
                    self.assertEqual([], wrong, "wrong prerequisites derived")
                    self.assertGreater(len(after), len(before))
                lines.append(
                    "%s seed %d: %d of %d secured before, %d after, %d chains found by players"
                    % ("chains hidden" if hide else "chains known", seed, len(before), len(everything), len(after), found)
                )
        print("\nsimulated runs (%d players), new quests 21-30:\n  %s" % (self.PLAYERS, "\n  ".join(lines)))
