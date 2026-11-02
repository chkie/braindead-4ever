# SPDX-License-Identifier: GPL-3.0-or-later
"""Run times from the in-game exchange (docs/RUN-TIMES.md): module numbers shared with the addon,
the run table the website decoder writes, medians per section, class, mode and group. Run from the
repository root:

  python3 -m unittest discover -s tools/tests -t .
"""

import csv
import json
import os
import tempfile
import unittest

from tools.routekit import lint, runs

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")


def table(rows):
    """A run table as decoder/cli.mjs --runs writes it; returns the file path."""
    fh = tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, newline="", encoding="utf-8")
    w = csv.writer(fh)
    w.writerow(runs.COLUMNS)
    for r in rows:
        w.writerow(r)
    fh.close()
    return fh.name


def row(token, kind, section, seconds, xp=400, mode="s", in_order=100, cls=1, source="net"):
    return [token, 1, cls, mode, kind, section, 0, seconds, xp, in_order, 2, 20762, source]


class ModuleNumbers(unittest.TestCase):
    def test_same_numbers_as_the_addon(self):
        with open(os.path.join(FIX, "module_numbers.json"), encoding="utf-8") as fh:
            cases = json.load(fh)["cases"]
        for c in cases:
            self.assertEqual(c["number"], runs.module_number(c["module"]), c["module"])

    def test_every_route_module_has_its_own_number(self):
        mods, _ = lint.load_routes()
        numbers = {}
        for key in mods:
            n = runs.module_number(key)
            self.assertNotIn(n, numbers, "%s and %s share number %d" % (key, numbers.get(n), n))
            self.assertTrue(1 <= n <= 9999991)
            numbers[n] = key
        self.assertEqual(len(mods), len(runs.module_names()))


class Table(unittest.TestCase):
    def test_one_row_per_section_and_conflicts_drop_both(self):
        a = table([row("aaaaaa", "l", 1, 400), row("bbbbbb", "l", 1, 500), row("cccccc", "l", 1, 600)])
        b = table(
            [
                row("aaaaaa", "l", 1, 400, source="own"),  # the same values from a second export
                row("bbbbbb", "l", 1, 999),  # another value for the same section
                ["broken"] + [""] * 12,
            ]
        )
        try:
            rows = runs.read([a, b])
        finally:
            os.remove(a)
            os.remove(b)
        self.assertEqual(["aaaaaa", "cccccc"], sorted(r["token"] for r in rows))

    def test_rejects_a_file_that_is_not_a_run_table(self):
        fh = tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, encoding="utf-8")
        fh.write("a,b\n1,2\n")
        fh.close()
        try:
            with self.assertRaises(ValueError):
                runs.read([fh.name])
        finally:
            os.remove(fh.name)


class Summary(unittest.TestCase):
    def test_medians_per_section_class_mode_and_group(self):
        number = runs.module_number("a-speed-start-elwynn")
        rows = [
            {**dict(zip(runs.COLUMNS, r)), **{k: int(v) for k, v in zip(runs.COLUMNS, r) if k in runs.NUMBERS}}
            for r in (
                row("aaaaaa", "l", 1, 300),
                row("bbbbbb", "l", 1, 500),
                row("cccccc", "l", 1, 400),
                row("dddddd", "l", 1, 900, mode="f", in_order=0),
                row("eeeeee", "l", 1, 700, in_order=50),
                row("ffffff", "l", 1, 200, cls=8),
                row("aaaaaa", "m", number, 1200, xp=2400),
            )
        ]
        out = runs.summary(rows, {number: "a-speed-start-elwynn"})
        got = {(g["kind"], g["section"], g["class"], g["mode"], g["group"]): (g["runs"], g["seconds"]) for g in out}
        self.assertEqual((3, 400), got[("l", 1, 1, "s", "follows")])
        self.assertEqual((1, 900), got[("l", 1, 1, "f", "free")])
        self.assertEqual((1, 700), got[("l", 1, 1, "s", "partial")])
        self.assertEqual((1, 200), got[("l", 1, 8, "s", "follows")])
        module = next(g for g in out if g["kind"] == "m")
        self.assertEqual(("a-speed-start-elwynn", 7200), (module["module"], module["xpPerHour"]))
        self.assertEqual(runs.FOLLOW_MIN, 80)


if __name__ == "__main__":
    unittest.main()
