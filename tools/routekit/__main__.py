# SPDX-License-Identifier: GPL-3.0-or-later
"""Route tools. Run from the repository root:

  python3 -m tools.routekit import --polestar DIR --eglink DIR --att DIR [--lua PATH]
  python3 -m tools.routekit merge          data/sources -> data/facts
  python3 -m tools.routekit build          data/plan + data/facts -> data/routes
  python3 -m tools.routekit lint [FILES]   check route files (default: data/routes)
  python3 -m tools.routekit compile        data/routes -> Pathmark/Routes
  python3 -m tools.routekit check          lint + compile into a temp dir and compare
  python3 -m tools.routekit stats          counts per combination and level band
  python3 -m tools.routekit metrics        simulate all 56 combinations, report P1-P11, G1-G12, R rules
  python3 -m tools.routekit observe PATHS  player exports -> data/sources/own (run merge after)
  python3 -m tools.routekit runs CSV...     run times from the exchange: medians per section, class, mode

Foreign repositories are read from wherever they were cloned; nothing outside data/ is written
by the importers.
"""

import argparse
import sys

from .io import repo_path


def main(argv=None):
    ap = argparse.ArgumentParser(prog="routekit")
    sub = ap.add_subparsers(dest="cmd", required=True)
    imp = sub.add_parser("import")
    imp.add_argument("--polestar")
    imp.add_argument("--eglink")
    imp.add_argument("--att")
    imp.add_argument("--lua", default=repo_path(".tools", "lua51", "bin", "lua"))
    sub.add_parser("merge")
    sub.add_parser("build")
    lint = sub.add_parser("lint")
    lint.add_argument("files", nargs="*")
    lint.add_argument("--no-combos", action="store_true", help="skip the per-combination checks")
    sub.add_parser("compile")
    sub.add_parser("check")
    sub.add_parser("stats")
    met = sub.add_parser("metrics")
    met.add_argument("--json", help="write the full report as JSON")
    met.add_argument("--md", help="write the report as Markdown")
    met.add_argument("--summary", help="append the Markdown report (GitHub step summary)")
    met.add_argument("--write-baseline", action="store_true", help="store this run as the start route (data/plan)")
    obs = sub.add_parser("observe")
    obs.add_argument("paths", nargs="+")
    rn = sub.add_parser("runs")
    rn.add_argument("paths", nargs="+")
    rn.add_argument("--json", help="write the medians as JSON")
    args = ap.parse_args(argv)

    if args.cmd == "import":
        from .importers import att, eglink, polestar

        if args.polestar:
            print("polestar", polestar.run(args.polestar, repo_path("data", "sources", "polestar")))
        if args.eglink:
            print("eglink", eglink.run(args.eglink, repo_path("data", "sources", "eglink")))
        if args.att:
            print("att", att.run(args.att, repo_path("data", "sources", "att"), args.lua))
        return 0
    if args.cmd == "merge":
        from . import merge

        print(merge.run())
        return 0
    if args.cmd == "build":
        from . import build

        print(build.run())
        return 0
    if args.cmd == "lint":
        from . import lint as linter

        return linter.main(args.files, combos=not args.no_combos)
    if args.cmd == "compile":
        from . import compiler

        print(compiler.run())
        return 0
    if args.cmd == "check":
        from . import compiler
        from . import lint as linter

        rc = linter.main([], combos=True)
        return rc or compiler.check()
    if args.cmd == "observe":
        from . import observe

        print(observe.run(args.paths))
        return 0
    if args.cmd == "runs":
        from . import runs

        counts, out = runs.run(args.paths, args.json)
        print(counts)
        for g in out:
            print(
                "%s %-8s class %2d mode %s %-7s runs %4d median %6d s %7d XP/h  %s"
                % (g["kind"], g["section"], g["class"], g["mode"], g["group"], g["runs"], g["seconds"], g["xpPerHour"], g["module"] or "")
            )
        return 0
    if args.cmd == "stats":
        from . import stats

        return stats.main()
    if args.cmd == "metrics":
        from . import metrics

        return metrics.main(args.json, args.md, args.summary, args.write_baseline)
    return 2


if __name__ == "__main__":
    sys.exit(main())
