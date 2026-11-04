# SPDX-License-Identifier: GPL-3.0-or-later
"""Facts on service NPCs and flights (tools/routekit/services.py, lint.lint_facts) and the role
and side rules of the Polestar importer. Run from the repository root:

  python3 -m unittest discover -s tools/tests -t .

Counter-checks: a fact without sources, with a foreign source, without status, off its map, in no
route zone, a trainer without class and a leg to an unknown flight point are each found with their
code; the committed facts pass.
"""

import collections
import copy
import os
import unittest

from tools.routekit import compiler, geo, lint, observe, routefmt, services
from tools.routekit.importers import polestar
from tools.routekit.io import read_jsonl

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")


def fixture_frames():
    return geo.Frames(read_jsonl(os.path.join(FIX, "ui_map.jsonl")))


TRAINER = {
    "id": 900101,
    "role": {"v": "trainer", "src": ["polestar", "eglink"]},
    "class": {"v": 1, "src": ["polestar"]},
    "side": {"v": "A", "src": ["eglink", "polestar"]},
    "pos": {"v": [1429, -120.0, -8880.0], "src": ["eglink", "polestar"], "seen": ["eglink", "polestar"], "roots": 1},
    "zone": 1429,
    "status": "unbestätigt",
}
NODE_A = {"node": 900, "src": ["att"], "pos": {"v": [1429, -100.0, -8800.0], "src": ["att"], "seen": ["att"], "roots": 1}, "zone": 1429, "status": "unbestätigt"}
NODE_B = {"node": 901, "src": ["eglink"], "status": "unbestätigt"}
EDGE = {"key": "900>901", "from": 900, "to": 901, "src": ["eglink"], "trips": 1, "seconds": {"v": 120, "basis": "model"}, "status": "unbestätigt"}


def run_lint(npcs=None, nodes=None, edges=None):
    npcs = [TRAINER] if npcs is None else npcs
    nodes = [NODE_A, NODE_B] if nodes is None else nodes
    edges = [EDGE] if edges is None else edges
    return lint.lint_facts(npcs, nodes, edges, fixture_frames(), zones={1429, 1436})


def codes(errs):
    return sorted({e.code for e in errs})


class FactLinter(unittest.TestCase):
    def test_clean_facts_pass(self):
        self.assertEqual([], [str(e) for e in run_lint()])

    def test_committed_facts_pass(self):
        facts = lint.Facts.load()
        sf = lint.load_service_facts()
        self.assertTrue(sf["npcs"] and sf["flightnodes"] and sf["flightedges"])
        errs = lint.lint_facts(sf["npcs"], sf["flightnodes"], sf["flightedges"], facts.frames)
        self.assertEqual([], [str(e) for e in errs])

    def test_fact_without_sources_fails(self):
        bad = copy.deepcopy(TRAINER)
        del bad["pos"]["src"]
        self.assertEqual(["herkunft"], codes(run_lint(npcs=[bad])))
        bad = copy.deepcopy(NODE_B)
        del bad["src"]
        self.assertEqual(["herkunft"], codes(run_lint(nodes=[NODE_A, bad])))

    def test_model_value_needs_its_mark(self):
        bad = copy.deepcopy(EDGE)
        del bad["seconds"]["basis"]
        self.assertEqual(["herkunft"], codes(run_lint(edges=[bad])))

    def test_foreign_source_fails(self):
        bad = copy.deepcopy(TRAINER)
        bad["side"]["src"] = ["wowhead"]
        self.assertEqual(["quelle"], codes(run_lint(npcs=[bad])))

    def test_status(self):
        bad = copy.deepcopy(TRAINER)
        del bad["status"]
        self.assertEqual(["status"], codes(run_lint(npcs=[bad])))
        bad["status"] = "bestätigt"
        self.assertEqual(["status"], codes(run_lint(npcs=[bad])))

    def test_position_off_its_map_or_zone(self):
        bad = copy.deepcopy(TRAINER)
        bad["pos"]["v"] = [1429, -8880.0, -120.0]  # axes swapped
        self.assertEqual(["karte"], codes(run_lint(npcs=[bad])))
        bad = copy.deepcopy(TRAINER)
        bad["zone"] = 1436
        self.assertEqual(["karte"], codes(run_lint(npcs=[bad])))
        self.assertEqual(["karte"], codes(lint.lint_facts([TRAINER], [NODE_A, NODE_B], [EDGE], fixture_frames(), zones={1436})))

    def test_trainer_needs_a_class(self):
        bad = copy.deepcopy(TRAINER)
        del bad["class"]
        self.assertEqual(["fakt"], codes(run_lint(npcs=[bad])))

    def test_leg_needs_known_flight_points(self):
        bad = copy.deepcopy(EDGE)
        bad["to"] = 999
        self.assertEqual(["beleg"], codes(run_lint(edges=[bad])))


class Rules(unittest.TestCase):
    def test_titles(self):
        self.assertEqual(("trainer", 3), polestar.npc_role("Hunter Trainer"))
        self.assertEqual(("innkeeper", None), polestar.npc_role("Innkeeper"))
        self.assertEqual(("flightmaster", None), polestar.npc_role("Bat Handler"))
        for title in ("Pet Trainer", "Assistant Innkeeper", "Wargryphon Master", "Stable Master", None):
            self.assertEqual((None, None), polestar.npc_role(title))

    def test_template_sides(self):
        votes = {
            12: collections.Counter(A=947, H=2, B=77),  # Stormwind
            29: collections.Counter(A=2, H=508, B=31),  # Orgrimmar
            69: collections.Counter(A=3, H=24, B=60),  # a neutral town in Horde lands
            3562: collections.Counter(A=3, H=1),  # too few and mixed: no side
            7: collections.Counter(B=40),  # quests for both only: no side
        }
        self.assertEqual({12: "A", 29: "H", 69: "B"}, polestar.template_sides(votes))

    def test_legs_and_direct_seconds(self):
        legs, timed = {}, {}
        trips = [
            {"key": "1>2", "paths": [[1, 2]], "seconds": {"100": 3, "104": 1}},
            {"key": "1>3", "paths": [[1, 2, 3]], "seconds": {"300": 2}},
            {"key": "3>1", "paths": [[3, 1], [3, 2, 1]], "seconds": {"200": 1}},
            {"key": "2>3|frequentFlier:1", "paths": [[2, 3]], "seconds": {"50": 5}, "talent": "frequentFlier:1"},
        ]
        services._legs(trips, "eglink", legs, timed)
        self.assertEqual({(1, 2), (2, 3), (3, 1), (3, 2), (2, 1)}, set(legs))
        self.assertEqual({"1>2", "1>3"}, legs[(1, 2)]["trips"])
        # Only trips flown without a stop, on one path and without the talent give seconds.
        self.assertEqual({("eglink", 1, 2)}, set(timed))
        self.assertEqual(100, services._median(timed[("eglink", 1, 2)]))

    def test_zone_vote_beats_the_smallest_frame(self):
        frames = geo.Frames(
            [
                {"ui_map": 1431, "map": 0, "top": 0, "bottom": -1000, "left": 1000, "right": 0},
                {"ui_map": 1430, "map": 0, "top": 0, "bottom": -500, "left": 500, "right": 0},
            ]
        )
        z = services.ZoneOf.__new__(services.ZoneOf)
        z.frames, z.points = frames, collections.defaultdict(list)
        self.assertEqual(1430, z(0, 100, -100))  # no measured point near: smallest frame
        z.points[0] = [(-110.0, 110.0, 1431), (-90.0, 95.0, 1431), (-400.0, 400.0, 1430)]
        self.assertEqual(1431, z(0, 100, -100))


class OwnFlights(unittest.TestCase):
    def payload(self, install, lines):
        return {"install": install, "own": ["chunk\t0\t1\t20762\n" + "\n".join(lines)], "net": []}

    def test_flights_from_exports(self):
        lines = [
            "taxilegs\t1\t1429\t10\t20\t2\t2>4;4>6",
            "flight\t2\t1429\t10\t20\t2\t6\t2;4;6",
            "land\t130\t1432\t10\t20\t6\t128",
            "flight\t200\t1432\t10\t20\t6\t4\t6;4",
            "land\t320\t1432\t10\t20\t4\t119",
            "land\t400\t1432\t10\t20\t4\t60",  # no flight chosen before it
            "flight\t500\t1432\t10\t20\t4\t2\t4;2",
            "land\t501\t1432\t10\t20\t2\t2",  # too short to be a flight
            "flight\t600\t1432\t10\t20\t2\t4\t",  # points unknown
            "land\t700\t1432\t10\t20\t4\t100",
        ]
        p = self.payload("inst", lines)
        trips = {t["key"]: t for t in observe.flights([p, p])}  # the same export twice counts once
        self.assertEqual({"leg:2>4", "leg:4>6", "2>6", "6>4", "4>2"}, set(trips))
        self.assertEqual({"key": "2>6", "paths": [[2, 4, 6]], "seconds": {"128": 1}}, trips["2>6"])
        self.assertEqual({"128": 1}, trips["2>6"]["seconds"])
        self.assertEqual({"119": 1}, trips["6>4"]["seconds"])
        self.assertNotIn("seconds", trips["4>2"])
        # Own measured seconds win over EG Link's for the same leg.
        legs, timed = {}, {}
        services._legs([{"key": "6>4", "paths": [[6, 4]], "seconds": {"140": 3}}], "eglink", legs, timed)
        services._legs(list(trips.values()), "own", legs, timed)
        self.assertEqual({"eglink", "own"}, legs[(6, 4)]["src"])
        self.assertEqual({("eglink", 6, 4), ("own", 6, 4)}, set(timed))
        self.assertEqual({(6, 4): {"v": 119, "src": ["own"], "flights": 1}}, services.measured_seconds(timed))

    def test_flight_legs_received_from_other_players(self):
        # Two exports of one install that overlap (the second one with "all") and one of another install.
        a = {"install": "inst", "flightsFrom": 1, "flights": ["h;1;2;4;0", "h;1;6;4;121"]}
        b = {"install": "inst", "flightsFrom": 1, "flights": ["h;1;2;4;0", "h;1;6;4;121", "h;1;6;4;117"]}
        c = {"install": "other", "flightsFrom": 7, "flights": ["h;1;6;4;121", "h;1;4;4;50", "h;1;9;8;3", "x;1;6;4;9"]}
        trips = {t["key"]: t for t in observe.flights([a, b, c])}
        self.assertEqual({"leg:2>4", "leg:6>4", "net:6>4", "leg:9>8"}, set(trips))
        self.assertEqual({"key": "net:6>4", "paths": [[6, 4]], "seconds": {"117": 1, "121": 2}}, trips["net:6>4"])
        self.assertNotIn("seconds", trips["leg:9>8"])  # 3 s is no flight: the connection only
        # Received seconds count with the own ones for the leg.
        legs, timed = {}, {}
        services._legs(list(trips.values()), "own", legs, timed)
        self.assertEqual({(6, 4): {"v": 121, "src": ["own"], "flights": 3}}, services.measured_seconds(timed))
        self.assertEqual({(2, 4), (6, 4), (9, 8)}, set(legs))


class FlightFacts(unittest.TestCase):
    def test_compiled_for_the_checks_of_the_exchange(self):
        nodes = [
            {"node": 5, "pos": {"v": [1429, 10.4, -20.6]}},
            {"node": 2, "pos": {"v": [1453, 482.6, -8835.2]}},
            {"node": 9},  # no position
        ]
        edges = [
            {"from": 5, "to": 2, "seconds": {"v": 135, "src": ["eglink"], "flights": 2}},
            {"from": 2, "to": 5, "seconds": {"v": 135, "basis": "model"}},
            {"from": 2, "to": 9},
        ]
        text = compiler.compile_flights(nodes, edges, {"secondsPerYard": 0.0484}, {1429: 0, 1453: 0})
        self.assertIn("\tsecondsPerYard = 0.0484,", text)
        self.assertIn("\t\t[2] = { 0, 483, -8835 },\n\t\t[5] = { 0, 10, -21 },\n\t\t[9] = {},", text)
        self.assertIn('\t\t["2>5"] = 0,\n\t\t["2>9"] = 0,\n\t\t["5>2"] = 2,', text)
        self.assertEqual(text, compiler.compile_flights(list(reversed(nodes)), list(reversed(edges)), {"secondsPerYard": 0.0484}, {1429: 0, 1453: 0}))


ROUTE = """#module t-speed-start-elwynn
#kind start
#faction Alliance
#mode speed
#levels 1-10
#label vorläufig
#version 1
#sources polestar=test eglink=test
@x1 lv=4
  goto 1429 -120.5,-8880.0 r=5 | src=polestar status=unbestätigt
  train | src=plan status=unbestätigt
"""


class GotoBackedByServiceNpcs(unittest.TestCase):
    def facts(self, npcs):
        return lint.Facts([], fixture_frames(), npcs, [NODE_A])

    def errs(self, text, npcs):
        mod = routefmt.parse(text, "t.route")
        return [e for e in lint.lint_module(mod, self.facts(npcs)) if e.code == "beleg"]

    def test_trainer_backs_the_goto_of_a_train_step(self):
        self.assertEqual([], self.errs(ROUTE, [TRAINER]))

    def test_without_the_train_element_the_goto_is_not_backed(self):
        self.assertEqual(1, len(self.errs(ROUTE.replace("train |", "note \"x\" |"), [TRAINER])))

    def test_trainer_of_the_other_faction_does_not_back_it(self):
        horde = copy.deepcopy(TRAINER)
        horde["side"]["v"] = "H"
        self.assertEqual(1, len(self.errs(ROUTE, [horde])))

    def test_flight_point_backs_the_goto_of_an_fp_step(self):
        text = ROUTE.replace("-120.5,-8880.0", "-100.0,-8800.0").replace("src=polestar status", "src=att status").replace("train |", "fp |")
        self.assertEqual([], self.errs(text, []))

    def test_flight_point_backs_the_landing_of_a_flight(self):
        # a flight lands at the flight master: `travel fly` backs the goto like `fp`; a walk does not
        at_point = ROUTE.replace("-120.5,-8880.0", "-100.0,-8800.0").replace("src=polestar status", "src=att status")
        fly = at_point.replace("  train | src=plan status=unbestätigt", "  travel fly 1429 | src=plan status=unbestätigt")
        self.assertEqual([], self.errs(fly, []))
        self.assertEqual(1, len(self.errs(fly.replace("travel fly", "travel walk"), [])))


if __name__ == "__main__":
    unittest.main()
