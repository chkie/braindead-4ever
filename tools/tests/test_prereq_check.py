# SPDX-License-Identifier: GPL-3.0-or-later
"""Prerequisites after the cross-check (owner 2026-11-05: nothing unchecked).

Failure case of record: 788 Cutting Teeth. Polestar states 787 The New Horde (Orgrimmar) as a
hard prerequisite, ATT only the breadcrumb 4641; a fresh orc gets 788 from Gornek at once.
"""

import os
import unittest

from tools.routekit import geo, lint, merge, routefmt
from tools.routekit.io import read_jsonl

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")

PS_788 = {"pre": {"all": [787], "bc": [4641]}}
ATT_788 = {"pre": {"all": [4641]}}


class MergeRefuted(unittest.TestCase):
    def test_without_check_one_root_secures_787(self):
        pre = merge.prereq_state(PS_788, ATT_788, None, {4641}, False, False)
        self.assertEqual([[787]], pre["v"])
        self.assertEqual("secured", pre["state"])

    def test_refuted_group_is_dropped_and_kept_on_record(self):
        pre = merge.prereq_state(PS_788, ATT_788, None, {4641}, False, False, {"polestar": [[787]]})
        self.assertEqual([], pre["v"])
        self.assertEqual("secured", pre["state"])
        self.assertEqual("check-refuted", pre["basis"])
        self.assertEqual({"polestar": [[787]]}, pre["refuted"])

    def test_check_leaves_other_groups_alone(self):
        p = {"pre": {"all": [787, 790]}}
        pre = merge.prereq_state(p, None, None, set(), False, False, {"polestar": [[787]]})
        self.assertEqual([[790]], pre["v"])
        self.assertEqual({"polestar": [[787]]}, pre["refuted"])


class GameFindings(unittest.TestCase):
    def test_add_puts_a_seen_prerequisite_on_top(self):
        pre, held = merge.apply_finding({"v": [], "src": ["polestar", "att"], "state": "secured"},
                                        {"q": 96656, "add": [[382]], "ref": "in game"})
        self.assertEqual([[382]], pre["v"])
        self.assertIn("finding", pre["src"])
        self.assertIsNone(held)

    def test_hold_keeps_the_quest_out(self):
        pre, held = merge.apply_finding({"v": [[97281]], "src": ["att"], "state": "secured"},
                                        {"q": 97282, "hold": "not offered at level 10"})
        self.assertEqual([[97281]], pre["v"])
        self.assertEqual({"why": "not offered at level 10"}, held)

    def test_drop_removes_a_group_the_game_refuted(self):
        pre, held = merge.apply_finding({"v": [[91208]], "src": ["att"], "state": "secured"},
                                        {"q": 91209, "drop": [[91208]], "ref": "in game"})
        self.assertEqual([], pre["v"])
        self.assertIn("finding", pre["src"])
        self.assertIsNone(held)

    def test_no_finding_changes_nothing(self):
        pre = {"v": [[1]], "src": ["att"], "state": "secured"}
        self.assertEqual((pre, None), merge.apply_finding(pre, None))


def _facts(pre):
    recs = [
        {"q": 788, "zone": 1411, "side": {"v": "H", "src": ["polestar"]}, "pre": pre,
         "level": {"v": 2, "src": ["polestar"]}, "min": {"v": 1, "src": ["polestar"]},
         "start": {"v": [{"k": "npc", "id": 3143}], "src": ["polestar"]}},
        {"q": 787, "zone": 1454, "side": {"v": "H", "src": ["polestar"]}, "pre": {"v": [], "state": "secured", "src": ["polestar"]}},
    ]
    return lint.Facts(recs, geo.Frames(read_jsonl(os.path.join(FIX, "ui_map.jsonl"))))


MODULE = """#module h-speed-start-test
#kind start
#faction Horde
#mode speed
#levels 1-11
#label vorläufig
#version 1
#sources polestar=x

@a788 lv=2
  accept 788 | src=polestar status=unbestätigt
"""


class LintZonePrerequisite(unittest.TestCase):
    def codes(self, pre):
        mod = routefmt.parse(MODULE, "t.route")
        return [e for e in lint.lint_module(mod, _facts(pre)) if e.code == "vorquest-zone"]

    def test_one_root_from_another_zone_is_an_error(self):
        errs = self.codes({"v": [[787]], "src": ["polestar"], "state": "secured"})
        self.assertEqual(1, len(errs), [str(e) for e in errs])
        self.assertIn("787", errs[0].msg)

    def test_two_roots_pass(self):
        self.assertEqual([], self.codes({"v": [[787]], "src": ["polestar", "att"], "state": "secured"}))

    def test_after_the_check_788_passes(self):
        self.assertEqual([], self.codes({"v": [], "src": ["polestar"], "state": "secured", "basis": "check-refuted"}))


if __name__ == "__main__":
    unittest.main()
