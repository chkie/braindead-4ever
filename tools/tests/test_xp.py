# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for the experience rules (tools/routekit/xp.py). Run from the repository root:

  python3 -m unittest discover -s tools/tests -t .

The kill and quest cases are shared with spec/route_xp_spec.lua (tools/tests/fixtures/xp_cases.json):
the addon and the route tools compute the same XP.
"""

import json
import os
import unittest

from tools.routekit import xp

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


if __name__ == "__main__":
    unittest.main()
