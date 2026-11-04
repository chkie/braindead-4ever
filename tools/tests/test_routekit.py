# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for tools/routekit. Run from the repository root:

  python3 -m unittest discover -s tools/tests -t .

The linter acceptance (Plan AP 5): ten prepared errors in tools/tests/fixtures/bad are each
found, the clean route in tools/tests/fixtures/good passes.
"""

import glob
import os
import unittest

from tools.routekit import compiler, game, geo, lint, routefmt
from tools.routekit.io import read_jsonl

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")
HUMAN_WARRIOR = [(1, 1)]


def fixture_facts():
    return lint.Facts(read_jsonl(os.path.join(FIX, "facts.jsonl")), geo.Frames(read_jsonl(os.path.join(FIX, "ui_map.jsonl"))))


def compose():
    with open(os.path.join(FIX, "good", "COMPOSE"), encoding="utf-8") as fh:
        return routefmt.parse_compose(fh.read(), "COMPOSE")


def lint_file(path):
    mod = routefmt.parse_file(path)
    return lint.lint_all({mod.key: mod}, [compose()], fixture_facts(), combo_list=HUMAN_WARRIOR, modes=("speed",))


class LinterAcceptance(unittest.TestCase):
    def test_clean_route_passes(self):
        errs = lint_file(os.path.join(FIX, "good", "t-speed-start-elwynn.route"))
        self.assertEqual([], [str(e) for e in errs])

    def test_unknown_prerequisite_at_a_hub_passes_in_speed(self):
        # an unknown prerequisite is allowed where the module accepts or turns in a quest with
        # secured prerequisites within lint.HUB_YARDS; the prepared error 09-speed is the same quest
        # kind at a place the route only passes for an objective
        with open(os.path.join(FIX, "good", "t-speed-start-elwynn.route"), encoding="utf-8") as fh:
            text = fh.read()
        hub = text.replace("  accept 900003 | src=polestar status=unbestätigt\n",
                           "  accept 900003 | src=polestar status=unbestätigt\n  accept 900004 | src=polestar status=unbestätigt\n", 1)
        self.assertNotEqual(text, hub)
        mod = routefmt.parse(hub, "hub.route")
        errs = lint.lint_all({mod.key: mod}, [compose()], fixture_facts(), combo_list=HUMAN_WARRIOR, modes=("speed",))
        self.assertEqual([], [str(e) for e in errs])
        # the same accept alone in a step far from every such step is refused
        far = text.replace("  complete 900002 | src=polestar status=unbestätigt\n",
                           "  complete 900002 | src=polestar status=unbestätigt\n  accept 900006 | src=polestar status=unbestätigt\n", 1)
        mod = routefmt.parse(far, "far.route")
        errs = lint.lint_all({mod.key: mod}, [compose()], fixture_facts(), combo_list=HUMAN_WARRIOR, modes=("speed",))
        self.assertEqual(["speed"], sorted({e.code for e in errs}))

    def test_ten_prepared_errors_are_found(self):
        files = sorted(glob.glob(os.path.join(FIX, "bad", "*.route")))
        self.assertEqual(10, len(files))
        found = []
        for path in files:
            expected = os.path.basename(path).split("-", 1)[1].rsplit(".", 1)[0]
            errs = lint_file(path)
            codes = sorted({e.code for e in errs})
            with self.subTest(fixture=os.path.basename(path)):
                self.assertEqual([expected], codes, [str(e) for e in errs])
            found.append(expected)
        self.assertEqual(10, len(set(found)))


class Format(unittest.TestCase):
    def test_filter_tokens(self):
        f = routefmt.Filter("race=HUMAN,DWARF class=!WARRIOR")
        self.assertEqual([], f.errors)
        self.assertTrue(f.applies(1, 2))
        self.assertFalse(f.applies(1, 1))
        self.assertFalse(f.applies(2, 2))
        self.assertTrue(routefmt.Filter("race=NOPE").errors)

    def test_skyborne_races_are_told_apart(self):
        self.assertTrue(routefmt.Filter("race=SKYBORNE_A").applies(95, 1))
        self.assertFalse(routefmt.Filter("race=SKYBORNE_A").applies(96, 1))

    def test_syntax_errors(self):
        mod = routefmt.parse("#module x\n@a1 lv=1\n  fly 1 2\n  accept abc | src=polestar status=unbestätigt\n")
        msgs = [m for _, m in mod.errors]
        self.assertTrue(any("unbekanntes Verb" in m for m in msgs))
        self.assertTrue(any("Argumente" in m for m in msgs))

    def test_goto_axes(self):
        mod = routefmt.parse("@a1 lv=1\n  goto 1429 -150.0,-8900.0 r=8 | src=polestar status=unbestätigt\n")
        el = mod.steps[0].elements[0]
        self.assertEqual((1429, -150.0, -8900.0, 8.0), (el.args["map"], el.args["wx"], el.args["wy"], el.args["r"]))

    def test_swapped_axes_are_off_the_map(self):
        facts = fixture_facts()
        self.assertTrue(facts.frames.contains(1429, -8900.0, -150.0))
        self.assertFalse(facts.frames.contains(1429, -150.0, -8900.0))


class Compose(unittest.TestCase):
    TEXT = """#faction Alliance
#mode speed
start s-human << race=HUMAN
start s-dwarf << race=DWARF,GNOME
core c1 c2
insert after start i-war << class=WARRIOR
insert after c1 i-human-mage << race=HUMAN class=MAGE
"""

    def test_route_per_combination(self):
        c = routefmt.parse_compose(self.TEXT)
        self.assertEqual([], c.errors)
        self.assertEqual(["s-human", "i-war", "c1", "c2"], c.route("speed", 1, 1))
        self.assertEqual(["s-human", "c1", "i-human-mage", "c2"], c.route("speed", 1, 8))
        self.assertEqual(["s-dwarf", "c1", "c2"], c.route("speed", 7, 8))
        self.assertIsNone(c.route("speed", 4, 1))
        self.assertIsNone(c.route("explorer", 1, 1))


class Game(unittest.TestCase):
    def test_56_combinations(self):
        combos = game.all_combos()
        self.assertEqual(56, len(combos))
        self.assertEqual(28, sum(1 for r, _ in combos if game.faction_of(r) == game.ALLIANCE))

    def test_race_mask_keeps_skyborne_bits(self):
        # Polestar quest 5 (Alliance): 2^32 + Human, Dwarf, Night Elf, Gnome
        self.assertEqual({1, 3, 4, 7, 95}, game.races_from_mask(4294967373))
        self.assertEqual({2, 5, 6, 8, 96}, game.races_from_mask(8589934770))
        self.assertIsNone(game.races_from_mask(0))


class Compiler(unittest.TestCase):
    def test_element_layout(self):
        mod = routefmt.parse(
            "@a1 lv=1\n  accept 783 | src=polestar,att status=unbestätigt\n"
            "  goto 1429 -150.5,-8900.0 r=10 | src=eglink status=unbestätigt roots=1\n"
            "  travel boat 1439 | src=plan status=unbestätigt\n"
        )
        els = [compiler._element(e) for e in mod.steps[0].elements]
        self.assertEqual("{ 1, 783, 3, 0 }", els[0])
        self.assertEqual("{ 5, 1429, -150.5, -8900, 10, 4, 0, 1 }", els[1])
        self.assertEqual("{ 6, 3, 1439, 16, 0 }", els[2])

    def test_quest_table(self):
        mod = routefmt.parse(
            "@a1 lv=1\n  accept 900002 | src=polestar status=unbestätigt\n"
            "@t1 lv=2\n  turnin 900001 | src=polestar status=unbestätigt\n"
        )
        facts = {
            900001: {"q": 900001, "level": {"v": 2}, "xp": {"v": 120}, "pre": {"v": []}},
            900002: {"q": 900002, "level": {"v": 3}, "xp": {"v": 250}, "pre": {"v": [[900001, 900005], [900003]]}},
        }
        lines = compiler._quests([mod], facts)
        self.assertEqual(
            ["\tquests = {", "\t\t[900001] = { 2, 120 },", "\t\t[900002] = { 3, 250, { { 900001, 900005 }, { 900003 } } },", "\t},"],
            lines,
        )

    def test_npc_table(self):
        """M4: one NPC per giver and turn-in, IDs with sources and status, per faction side; a fact with
        two NPCs or an item names nobody, and no name string ever reaches the file."""
        npc = lambda i: {"id": i, "k": "npc"}  # noqa: E731
        facts = {
            900001: {"q": 900001, "side": {"v": "A"}, "status": "unbestätigt",
                     "start": {"src": ["polestar", "att"], "v": [npc(196)]},
                     "end": {"src": ["polestar"], "v": [npc(197)]}},
            900002: {"q": 900002, "side": {"v": "B"}, "status": "unbestätigt",
                     "start": {"src": ["polestar"], "v": [npc(5), npc(6)]},
                     "end": {"src": ["eglink"], "v": [npc(7)]}},
            900003: {"q": 900003, "side": {"v": "H"}, "status": "unbestätigt",
                     "start": {"src": ["polestar"], "v": [{"id": 16305, "k": "item"}]},
                     "end": {"src": ["polestar"], "v": [npc(8)]}},
            900004: {"q": 900004, "side": {"v": "A"}, "status": "unbestätigt",
                     "start": {"src": ["att"], "v": [{"id": 9, "k": "object"}]}},
        }
        text = compiler.compile_npcs(facts)
        alliance, horde = text.split("ns.NpcFacts.Horde")
        self.assertIn("[900001] = { 196, 3, 197, 1, 0 },", alliance)
        self.assertIn("[900002] = { 0, 0, 7, 4, 0 },", alliance)  # two givers: no giver named
        self.assertNotIn("[900003]", alliance)
        self.assertNotIn("[900004]", alliance + horde)  # an object, no NPC at all
        self.assertIn("[900003] = { 0, 0, 8, 1, 0 },", horde)
        self.assertIn("[900002] = { 0, 0, 7, 4, 0 },", horde)
        self.assertNotIn("[900001]", horde)
        body = [ln for ln in text.splitlines() if not ln.lstrip().startswith("--") and ln != "local _, ns = ..."]
        self.assertEqual([], [ln for ln in body if '"' in ln or "'" in ln])
        self.assertEqual(text, compiler.compile_npcs(dict(reversed(list(facts.items())))))


class RepositoryData(unittest.TestCase):
    """The committed route data lints clean for all 56 combinations and the compiled files are
    up to date. Skipped where data/ is not present."""

    def setUp(self):
        if not os.path.exists(os.path.join(HERE, "..", "..", "data", "facts", "quests.jsonl")):
            self.skipTest("no data/facts")

    def test_routes_lint_clean(self):
        facts = lint.Facts.load()
        mods, comps = lint.load_routes()
        # 89 modules since 0.9.1: the routes share their modules across races and classes (before
        # 0.9.1 there were 182). Fewer than 80 means module files went missing; the check per
        # combination below is the precise one.
        self.assertGreaterEqual(len(mods), 80)
        for race, cls in game.all_combos():
            comp = next(c for c in comps if c.faction == game.faction_of(race))
            for mode in routefmt.MODES:
                keys = comp.route(mode, race, cls)
                self.assertTrue(keys, (mode, race, cls))
                self.assertEqual([], [k for k in keys if k not in mods], (mode, race, cls))
        errs = lint.lint_all(mods, comps, facts)
        self.assertEqual([], [str(e) for e in errs[:10]])

    def test_elwynn_example_route(self):
        facts = lint.Facts.load()
        mods, comps = lint.load_routes()
        elwynn = mods["a-speed-start-elwynn"]
        self.assertEqual([], [str(e) for e in lint.lint_module(elwynn, facts)])
        comp = next(c for c in comps if c.faction == game.ALLIANCE)
        for cls in game.COMBOS[1]:
            keys = comp.route("speed", 1, cls)
            self.assertEqual("a-speed-start-elwynn", keys[0])
            self.assertEqual([], [str(e) for e in lint.lint_route(mods, keys, 1, cls, facts, "speed/HUMAN")])

    def test_compiled_data_up_to_date(self):
        self.assertEqual(0, compiler.check())


if __name__ == "__main__":
    unittest.main()
