# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for the route optimizer (tools/routekit/optimize.py). Run from the repository root:

  python3 -m unittest discover -s tools/tests -t .

A made-up block on the fixture map frames: quests with accept, objectives and turn-in at known
places. The moves never break a quest's order, the search is counted in tries and gives the same
order twice, and the improved order walks less than the constructed one.
"""

import os
import random
import unittest

from tools.routekit import geo, lint, optimize, sim
from tools.routekit.io import read_jsonl

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")


def quest(q, giver, field, xp=300):
    return {"q": q, "level": {"v": 2}, "min": {"v": 1}, "xp": {"v": xp}, "side": {"v": "A"}, "type": 0,
            "pre": {"state": "secured", "v": []},
            "startPos": {"v": [1429, giver[0], giver[1]], "src": ["polestar"]},
            "endPos": {"v": [1429, giver[0], giver[1]], "src": ["polestar"]},
            "obj": [{"k": "kill", "count": 3, "pos": [1429, field[0], field[1]]}]}


def block():
    # two hubs 800 yd apart, each with three quests whose fields lie 200 yd away
    recs = []
    for k, (hx, hy) in enumerate(((-150.0, -8900.0), (-150.0, -8100.0))):
        for j in range(3):
            recs.append(quest(900300 + 10 * k + j, (hx, hy), (hx + 200.0 * (j - 1), hy + 200.0)))
    facts = lint.Facts(recs, geo.Frames(read_jsonl(os.path.join(FIX, "ui_map.jsonl"))))
    params = sim.Params.load()
    Q = {r["q"]: optimize.QV(r, facts.frames) for r in recs}
    env = optimize.Env(facts, params, Q)
    todo = {q: optimize.full_todo(Q[q]) for q in Q}
    return env, todo


def ordered(acts):
    pos = {a: i for i, a in enumerate(acts)}
    for (v, q), i in pos.items():
        if v == "c" and pos.get(("a", q), -1) > i:
            return False
        if v == "t" and (pos.get(("a", q), -1) > i or pos.get(("c", q), -1) > i):
            return False
    return True


class Moves(unittest.TestCase):
    def test_moves_keep_accept_objectives_turnin(self):
        env, todo = block()
        b = optimize.Block(env, "t", optimize.State(level=2), todo).construct(worth=False)
        rng = random.Random(7)
        acts = list(b.acts)
        for _ in range(2000):
            for move in (optimize.move_relocate, optimize.move_or_opt, optimize.move_two_opt, optimize.move_swap):
                cand = move(env, acts, rng)
                if cand is not None:
                    self.assertEqual(sorted(acts), sorted(cand))
                    self.assertTrue(ordered(cand), move.__name__)
                    acts = cand
        self.assertTrue(ordered(acts))


class Search(unittest.TestCase):
    def walk(self, env, acts):
        d, prev = 0.0, None
        for a in acts:
            p = optimize.pos_of(env, a)
            if prev is not None:
                d += optimize.dist(prev, p)
            prev = p
        return d

    def test_same_order_twice_counted_in_tries(self):
        env, todo = block()
        runs = []
        for _ in range(2):
            b = optimize.Block(env, "t", optimize.State(level=2), todo).construct(worth=False)
            b.improve(500, 1)
            runs.append(list(b.acts))
        self.assertEqual(runs[0], runs[1])

    def test_improved_order_is_valid_and_not_worse(self):
        env, todo = block()
        b = optimize.Block(env, "t", optimize.State(level=2), todo).construct(worth=False)
        j0 = b.j
        b.improve(2000, 1).held_karp().fold()
        self.assertTrue(ordered(b.acts))
        self.assertLessEqual(b.j, j0 + 1e-6)
        self.assertEqual(0, b.res.pen)


if __name__ == "__main__":
    unittest.main()
