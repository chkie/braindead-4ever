# SPDX-License-Identifier: GPL-3.0-or-later
"""Polestar's quest corrections (forever-db/corrections/quests.json): only those with a Forever source
count (owner 2026-11-06: no new Classic data; Forever data replace Classic data)."""
import json
import os
import tempfile
import unittest

from tools.routekit.importers import polestar


def _db(corr):
    d = tempfile.mkdtemp()
    os.makedirs(os.path.join(d, "corrections"))
    with open(os.path.join(d, "corrections", "quests.json"), "w", encoding="utf-8") as fh:
        json.dump(corr, fh)
    return d


class Corrections(unittest.TestCase):
    def test_a_forever_sourced_fix_is_applied(self):
        # 98221 From the Ashes: offered only after War Banners 464 (Polestar, in-game check #225)
        quests = {98221: {"q": 98221, "start": [{"k": "npc", "id": 1}], "startPos": [[0, 1, 1]]}}
        db = _db({"98221": {"set": {"pre": [464], "preAny": [464]}, "source": {"kind": "in-game-check", "ref": "#225"}}})
        n = polestar._apply_corrections(db, quests)
        self.assertEqual({"any": [464]}, quests[98221]["pre"])
        self.assertTrue(quests[98221]["corrected"])
        self.assertEqual(1, n["quests changed"])

    def test_a_fix_with_classic_sources_only_is_skipped(self):
        quests = {151: {"q": 151, "start": [{"k": "object", "id": 696264}]}}
        db = _db({"151": {"set": {"start": {"npc": [238], "object": [], "item": []}},
                          "source": [{"kind": "cmangos", "ref": "classic-db"}, {"kind": "questie", "ref": "x"}]}})
        n = polestar._apply_corrections(db, quests)
        self.assertEqual([{"k": "object", "id": 696264}], quests[151]["start"])
        self.assertEqual(1, n["skipped (no Forever source)"])

    def test_one_forever_source_among_classic_ones_is_enough(self):
        quests = {151: {"q": 151, "start": [{"k": "object", "id": 696264}], "startPos": [[0, 2, 2]]}}
        db = _db({"151": {"set": {"start": {"npc": [238], "object": [], "item": []}},
                          "source": [{"kind": "cmangos", "ref": "classic-db"}, {"kind": "eg", "ref": "caches"}]}})
        polestar._apply_corrections(db, quests)
        self.assertEqual([{"k": "npc", "id": 238}], quests[151]["start"])
        self.assertNotIn("startPos", quests[151], "positions are computed again from the new giver")

    def test_foreverTDB_alone_does_not_count(self):
        # FD-1101: ForeverTDB is no source of this project
        quests = {7: {"q": 7, "xp": 100}}
        db = _db({"7": {"set": {"xp": 200}, "source": {"kind": "tdb", "ref": "quest_template"}}})
        n = polestar._apply_corrections(db, quests)
        self.assertEqual(100, quests[7]["xp"])
        self.assertEqual(1, n["skipped (no Forever source)"])

    def test_split_prerequisites_and_races(self):
        quests = {29: {"q": 29, "racesMask": 8, "pre": {"all": [1], "any": [2]}}}
        db = _db({"29": {"set": {"races": 4294967304, "preAll": [], "preAny": [5, 6]}, "source": {"kind": "eg", "ref": "caches"}}})
        polestar._apply_corrections(db, quests)
        self.assertEqual(4294967304, quests[29]["racesMask"])
        self.assertEqual({"any": [5, 6]}, quests[29]["pre"])

    def test_no_change_no_mark(self):
        quests = {7: {"q": 7, "xp": 100}}
        db = _db({"7": {"set": {"xp": 100}, "source": {"kind": "client", "ref": "x"}}})
        n = polestar._apply_corrections(db, quests)
        self.assertNotIn("corrected", quests[7])
        self.assertEqual(0, n["quests changed"])


if __name__ == "__main__":
    unittest.main()
