# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for the route metrics (tools/routekit/metrics.py). Run from the repository root:

  python3 -m unittest discover -s tools/tests -t .

A made-up route on the fixture map frames (quest IDs 900201 and up) carries known defects: a
return to the hub for a quest that was available on the first visit (P5, R05) and a quest giver
next to the walked line that the route never takes (P6). The same route without the defect
reports none. On the committed routes the report covers every combination and every rule.
"""

import os
import re
import unittest

from tools.routekit import geo, lint, metrics, routefmt, sim, stats
from tools.routekit.io import read_jsonl

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")

HUB = "1429 -150.0,-8900.0"
FIELD = "1429 -150.0,-8300.0"  # 600 yd north of the hub

HEAD = """
#module t-speed-start-hub
#kind start
#faction Alliance
#mode speed
#levels 1-3
#label vorläufig
#version 1
#sources polestar=test
"""


def el(verb, q):
    return "  %s %d | src=polestar status=unbestätigt\n" % (verb, q)


def goto(where):
    return "  goto %s | src=polestar status=unbestätigt\n" % where


def route(take_late):
    """q1 and q2: accept at the hub, kill in the field, hand in at the hub. q2 has no prerequisite
    and is available at the hub from the start: taken with q1 (clean) or only after coming back
    from the field (defect: a return to the hub and a second trip to the field)."""
    text = HEAD + "@a1 lv=1\n" + el("accept", 900201)
    if not take_late:
        text += el("accept", 900202)
    text += goto(HUB) + "@c1 lv=1\n" + el("complete", 900201)
    if not take_late:
        text += el("complete", 900202)
    text += goto(FIELD) + "@t1 lv=1\n" + el("turnin", 900201)
    if not take_late:
        text += el("turnin", 900202)
    text += goto(HUB)
    if take_late:
        text += "@a2 lv=1\n" + el("accept", 900202) + goto(HUB)
        text += "@c2 lv=1\n" + el("complete", 900202) + goto(FIELD)
        text += "@t2 lv=1\n" + el("turnin", 900202) + goto(HUB)
    return text


def quest(q, start, end, full, obj=None):
    r = {"q": q, "level": {"v": 1}, "min": {"v": 1}, "xp": {"v": full}, "side": {"v": "A"}, "type": 0,
         "pre": {"state": "secured", "v": []},
         "startPos": {"v": [1429, start[0], start[1]], "src": ["polestar"]},
         "endPos": {"v": [1429, end[0], end[1]], "src": ["polestar"]}}
    if obj:
        r["obj"] = obj
    return r


def facts():
    hub = (-150.0, -8900.0)
    return lint.Facts(
        [
            quest(900201, hub, hub, 100, obj=[{"k": "kill", "count": 2, "pos": [1429, -150.0, -8300.0]}]),
            quest(900202, hub, hub, 100, obj=[{"k": "kill", "count": 2, "pos": [1429, -150.0, -8300.0]}]),
            # a giver 100 yd beside the way to the field, never part of the route
            quest(900203, (-50.0, -8600.0), (-50.0, -8600.0), 100),
        ],
        geo.Frames(read_jsonl(os.path.join(FIX, "ui_map.jsonl"))),
    )


def evaluate(take_late):
    f = facts()
    mod = routefmt.parse(route(take_late), "hub.route")
    params = sim.Params.load()
    run = sim.Simulator(f, {mod.key: mod}, params).run("speed", 1, 1, [mod.key])
    ctx = metrics.Context(f, {mod.key: mod}, [], params)
    return run, metrics.evaluate(ctx, run)


class MiniRoute(unittest.TestCase):
    def test_return_for_a_quest_available_earlier(self):
        run, row = evaluate(take_late=True)
        self.assertEqual([], run.stuck)
        self.assertEqual(1, row["p5_returns"])
        self.assertEqual(0, row["p5_wasted"])  # the visit also hands in q1, which was not possible before
        self.assertEqual(1, row["rules"]["R05"])

    def test_no_return_when_taken_at_once(self):
        run, row = evaluate(take_late=False)
        self.assertEqual([], run.stuck)
        self.assertEqual(0, row["p5_returns"])
        self.assertEqual(0, row["rules"]["R05"])

    def test_giver_beside_the_way_is_passed_by(self):
        _, row = evaluate(take_late=False)
        self.assertEqual(1, row["p6_never"])
        self.assertEqual([900203], row["p6_never_quests"])
        # two legs of 600 yd: hub -> field -> hub
        self.assertAlmostEqual(600.0, row["p4_longest_zone_yd"])


class OnRouteData(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.facts, cls.mods, cls.comps, cls.params = sim.load()
        cls.report = metrics.collect(cls.facts, cls.mods, cls.comps, cls.params, baseline=None)

    def test_p1_two_runs_same_digest(self):
        self.assertTrue(self.report["p1"]["equal"])
        self.assertEqual(64, len(self.report["p1"]["digest"]))

    def test_every_combination_in_both_modes(self):
        self.assertEqual(112, len(self.report["rows"]))
        self.assertEqual(56, len({r["combo"] for r in self.report["rows"]}))

    def test_every_metric_and_rule_is_reported_or_named_as_not_checkable(self):
        ids = {s["id"] for s in self.report["summary"]}
        for p in ("P2", "P3", "P4", "P5", "P6", "P7", "P8", "P9", "P11"):
            self.assertIn(p, ids)
        self.assertTrue(self.report["p10"])
        for g in range(1, 12):
            self.assertIn("G%d" % g, ids)
        self.assertEqual(4, len(self.report["g12"]))
        for n in range(1, 36):
            rid = "R%02d" % n
            self.assertTrue(rid in ids or rid in metrics.NOT_CHECKABLE, rid)
        self.assertFalse(ids & set(metrics.NOT_CHECKABLE))

    def test_five_worst_per_metric_and_mode(self):
        for s in self.report["summary"]:
            if s["status"] != "offen" and not s["status"].startswith("offen ("):
                self.assertEqual(5, len(s["worst"]), s["id"])

    def test_quest_counts_agree_with_routekit_stats(self):
        # G5 counts accepts by the planned level like `routekit stats` (DR 22d measured 1.45 and 1.73)
        rows = stats.collect(self.mods, self.comps, self.facts)
        want = {}
        for mode, faction, race, cls, _, c in rows:
            want[(mode, race, cls)] = (c["1-20", "accepts"], c["21-30", "accepts"])
        for r in self.report["rows"]:
            got = (r["g5"]["1-20"], r["g5"]["21-30"])
            self.assertEqual(want[(r["mode"], r["race"], r["class"])], got, r["label"])

    def test_model_check_xp_per_hour_1_20(self):
        lo, hi = self.params.check["xph_1_20"]["value"]
        for r in self.report["rows"]:
            self.assertTrue(lo <= r["xph_1_20"] <= hi, (r["label"], r["xph_1_20"]))

    def test_markdown_names_every_combination(self):
        md = metrics.markdown(self.report)
        for r in self.report["rows"]:
            self.assertIn("| %s |" % r["combo"], md)
        self.assertTrue(re.search(r"P1 Determinismus: Prüfsumme `[0-9a-f]{64}`, zweiter Lauf gleich", md))

    def test_committed_baseline_covers_every_combination(self):
        import json

        with open(metrics.BASELINE_PATH, encoding="utf-8") as fh:
            base = json.load(fh)
        self.assertEqual({r["label"] for r in self.report["rows"]}, set(base["combos"]))
        for label, c in base["combos"].items():
            self.assertEqual(set(sim.COUNTERS), set(c["counters30"]), label)

    def test_baseline_compares_equal_with_itself(self):
        base = metrics.baseline_of(self.report)
        again = metrics.collect(self.facts, self.mods, self.comps, self.params, baseline=base)
        for s in again["summary"]:
            if s["kind"] == "base":
                self.assertEqual("erfüllt", s["status"], (s["id"], s["mode"]))


class Gate(unittest.TestCase):
    """The CI job "Route quality" (python3 -m tools.routekit metrics --check): the committed routes
    pass, every breach is covered by a measured exception; a route made worse breaks it."""

    @classmethod
    def setUpClass(cls):
        import json

        cls.facts, cls.mods, cls.comps, cls.params = sim.load()
        with open(metrics.BASELINE_PATH, encoding="utf-8") as fh:
            cls.baseline = json.load(fh)
        cls.exceptions = metrics.load_exceptions()

    def breaches(self, mods, comps):
        report = metrics.collect(self.facts, mods, comps, self.params, self.baseline)
        return [b for b in metrics.gate(report, self.params, self.exceptions) if not b["covered"]]

    def test_committed_routes_pass(self):
        self.assertEqual([], self.breaches(self.mods, self.comps))

    def test_every_exception_names_its_measurement(self):
        for e in self.exceptions:
            for k in ("id", "modes", "reason", "measured"):
                self.assertIn(k, e, e)
            self.assertTrue("max" in e or "min" in e, e)

    def test_swapped_core_blocks_break_the_gate(self):
        # counter-check: the Horde speed route with its first two core blocks in the wrong order
        import copy

        comps = copy.deepcopy(self.comps)
        core = next(c for c in comps if c.faction == "Horde").modes["speed"]["core"]
        core[0], core[1] = core[1], core[0]
        before = {(b["id"], b["label"]) for b in self.breaches(self.mods, self.comps)}
        open_ = [b for b in self.breaches(self.mods, comps) if (b["id"], b["label"]) not in before]
        self.assertTrue(open_, "a route in the wrong order must break the gate")
        self.assertEqual({"speed"}, {b["label"].split("/")[0] for b in open_})
        self.assertTrue({b["label"].split("/")[1] for b in open_} <= {"ORC", "TROLL", "TAUREN", "UNDEAD", "SKYBORNE_H"})


if __name__ == "__main__":
    unittest.main()
