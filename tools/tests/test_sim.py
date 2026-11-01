# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for the experience rules (tools/routekit/xp.py) and the route simulator
(tools/routekit/sim.py). Run from the repository root:

  python3 -m unittest discover -s tools/tests -t .

The kill and quest cases are shared with spec/route_xp_spec.lua (tools/tests/fixtures/xp_cases.json):
the addon and the route tools compute the same XP.
"""

import json
import math
import os
import subprocess
import sys
import unittest

from tools.routekit import game, geo, lint, routefmt, sim, xp
from tools.routekit.io import read_jsonl, repo_path

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")


def xp_cases():
    with open(os.path.join(FIX, "xp_cases.json"), encoding="utf-8") as fh:
        return json.load(fh)


class XPRules(unittest.TestCase):
    def test_level_table(self):
        self.assertEqual(4084700, sum(xp.TO_LEVEL))
        self.assertEqual(59, len(xp.TO_LEVEL))
        self.assertEqual(167200, xp.total_to(20))  # DR 22b: XP to level 20
        self.assertEqual(499000, xp.total_to(30))  # DR 22b: XP to level 30
        self.assertIsNone(xp.to_level(60))

    def test_shared_kill_cases(self):
        cases = xp_cases()["kill"]
        self.assertGreaterEqual(len(cases), 10)
        for c in cases:
            with self.subTest(case=c["name"]):
                self.assertEqual(c["xp"], xp.kill_xp(c["level"], c["mob"], c["elite"]))

    def test_forever_bug_138(self):
        # Forever beta: level 10 against level 5 gives 40 XP rested; Classic Era gave 54.
        self.assertEqual(20, xp.kill_xp(10, 5))
        self.assertEqual(40, 2 * xp.kill_xp(10, 5))

    def test_shared_quest_cases(self):
        for c in xp_cases()["quest"]:
            with self.subTest(case=c):
                self.assertEqual(c["xp"], xp.quest_xp(c["full"], c["ql"], c["level"]))

    def test_halves_round_up_like_lua(self):
        # 145 * 1.05 = 152.25 -> 152; Python's round() would round 0.5 to even, Lua rounds up
        self.assertEqual(3, xp._round(2.5))
        self.assertEqual(4, xp._round(3.5))


# A made-up route (quest IDs 900101 and up) on the fixture map frames, small enough to price by hand.
MINI_ROUTE = """
#module t-speed-start-mini
#kind start
#faction Alliance
#mode speed
#levels 1-4
#label vorläufig
#version 1
#sources polestar=test

@a1 lv=1
  accept 900101 | src=polestar status=unbestätigt
  goto 1429 -150.0,-8900.0 | src=polestar status=unbestätigt
@t1 lv=1
  turnin 900101 | src=polestar status=unbestätigt
  accept 900102 | src=polestar status=unbestätigt
  goto 1429 -150.0,-8900.0 | src=polestar status=unbestätigt
@c2 lv=2
  complete 900102 | src=polestar status=unbestätigt
  goto 1429 -100.0,-8800.0 | src=polestar status=unbestätigt
@t2 lv=2
  turnin 900102 | src=polestar status=unbestätigt
  goto 1429 -150.0,-8900.0 | src=polestar status=unbestätigt
@a3 lv=4
  accept 900103 | src=polestar status=unbestätigt
  goto 1429 -150.0,-8900.0 | src=polestar status=unbestätigt
@t3 lv=4
  turnin 900103 | src=polestar status=unbestätigt
  goto 1429 -150.0,-8900.0 | src=polestar status=unbestätigt
"""


def _quest(q, level, mn, full, pre=(), obj=None):
    pos = {"v": [1429, -150.0, -8900.0], "src": ["polestar"]}
    r = {"q": q, "level": {"v": level}, "min": {"v": mn}, "xp": {"v": full}, "startPos": pos, "endPos": pos,
         "pre": {"state": "secured", "v": [list(pre)] if pre else []}, "side": {"v": "A"}}
    if obj:
        r["obj"] = obj
    return r


def mini():
    facts = lint.Facts(
        [
            _quest(900101, 1, 1, 400),
            _quest(900102, 2, 1, 100, pre=(900101,), obj=[{"k": "kill", "count": 4, "pos": [1429, -100.0, -8800.0]}]),
            _quest(900103, 4, 3, 0),
        ],
        geo.Frames(read_jsonl(os.path.join(FIX, "ui_map.jsonl"))),
    )
    mod = routefmt.parse(MINI_ROUTE, "mini.route")
    return facts, {mod.key: mod}


class Simulator(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.params = sim.Params.load()

    def test_every_parameter_names_source_date_and_forever_status(self):
        self.assertEqual([], self.params.errors())
        self.assertEqual(7.0, self.params["run_speed"])
        self.assertEqual(40, self.params["quest_log_limit"])
        self.assertEqual(35, self.params["quest_log_work"])

    def test_a_parameter_without_source_is_reported(self):
        raw = {"param": {"x": {"value": 1, "date": "2026-11-01", "forever": "ja"}}}
        self.assertEqual(["param.x: no source"], sim.Params(raw).errors())
        raw = {"param": {"x": {"value": 1, "date": "2026-11-01", "source": "a", "forever": "vielleicht"}}}
        self.assertEqual(1, len(sim.Params(raw).errors()))

    def test_mini_route_by_hand(self):
        facts, mods = mini()
        run = sim.Simulator(facts, mods, self.params).run("speed", 1, 1, ["t-speed-start-mini"])
        p = self.params
        self.assertEqual([], run.stuck)
        # accept 6 s, turn-in 6 s: 400 XP is level 2 at 12 s, then 60 s for the level-up
        self.assertAlmostEqual(12.0, run.reached[2])
        # two legs of 111.8 yd (100 north, 50 west) on the Eastern Kingdoms at 7 yd/s x 1.35
        leg = math.hypot(100, 50)
        self.assertEqual(["walk", "walk"], [g["kind"] for g in run.legs])
        self.assertAlmostEqual(2 * leg, run.counters["walk_yd_0"])
        self.assertAlmostEqual(leg * 1.35 / 7.0, run.legs[0]["sec"])
        # 4 kills at level 2 against level 2, each with 0.043 kills on the way: 55 XP each
        self.assertAlmostEqual(4 * 1.043 * 55, run.quest[900102]["kill_xp"])
        self.assertAlmostEqual(4 * 1.043 * 58 / 59, run.counters["kill_a"])
        # the step @a3 plans level 4: the character grinds from level 2 to 4 (not announced)
        self.assertEqual(1, len(run.gates))
        self.assertEqual((4, False), (run.gates[0]["to"], run.gates[0]["announced"]))
        self.assertEqual(4, run.end_level)
        self.assertEqual(3, run.counters["levelups"])
        self.assertEqual(6, run.counters["talks"])
        # model time equals counters x parameters, also at every level reached
        self.assertAlmostEqual(run.time, sim.time_from(run.counters, p, 1.15), places=6)
        for level in (2, 3, 4):
            self.assertAlmostEqual(run.reached[level], sim.time_from(run.counters_at[level], p, 1.15), places=6)

    def test_quest_log_limit(self):
        facts, mods = mini()
        p = self.params.with_values({"quest_log_limit": 0, "quest_log_work": 0})
        run = sim.Simulator(facts, mods, p).run("speed", 1, 1, ["t-speed-start-mini"])
        self.assertTrue(any("R30" in text for _, text in run.stuck))
        self.assertEqual(3, run.log_over_work)


class SimulatorOnRouteData(unittest.TestCase):
    """The committed routes: every one of the 56 combinations in both modes (G2)."""

    @classmethod
    def setUpClass(cls):
        cls.facts, cls.mods, cls.comps, cls.params = sim.load()
        cls.runs = sim.simulate_all(cls.facts, cls.mods, cls.comps, cls.params)

    def test_all_112_runs_reach_level_30_without_getting_stuck(self):
        self.assertEqual(112, len(self.runs))
        for run in self.runs:
            label = "%s/%s/%s" % (run.mode, game.RACES[run.race][0], game.CLASSES[run.cls])
            with self.subTest(combo=label):
                self.assertTrue(run.keys)
                self.assertEqual([], run.stuck)
                self.assertGreaterEqual(run.end_level, 30)
                self.assertIn(30, run.reached)

    def test_counters_give_the_played_time(self):
        for run in self.runs:
            cf = self.params["class_factor"][game.CLASSES[run.cls]]
            self.assertAlmostEqual(run.time, sim.time_from(run.counters, self.params, cf), delta=1e-6 * run.time)
            self.assertAlmostEqual(run.reached[30], sim.time_from(run.counters_at[30], self.params, cf), delta=1e-6 * run.time)

    def test_deterministic_in_one_process(self):
        again = sim.simulate_all(self.facts, self.mods, self.comps, self.params)
        self.assertEqual(sim.digest(self.runs), sim.digest(again))

    def test_deterministic_across_processes_and_hash_seeds(self):
        code = "from tools.routekit import sim; f, m, c, p = sim.load(); print(sim.digest(sim.simulate_all(f, m, c, p)))"
        out = []
        for seed in ("1", "2"):
            env = dict(os.environ, PYTHONHASHSEED=seed)
            res = subprocess.run([sys.executable, "-c", code], cwd=repo_path(), env=env, capture_output=True, text=True, check=True)
            out.append(res.stdout.strip())
        self.assertEqual(out[0], out[1])
        self.assertEqual(sim.digest(self.runs), out[0])


if __name__ == "__main__":
    unittest.main()
