# SPDX-License-Identifier: GPL-3.0-or-later
"""Zone sections of the RestedXP Forever guides (Welle 6b, guard P9): counts only.

  python3 -m tools.routekit rxp DIR [--json PATH]

DIR holds the Forever guide files of github.com/RestedXP/RXPGuides (`Guides/forever`, licence
CC BY-NC-SA 4.0). Decision FD-1101: the guides are read to count, never copied; nothing of them
goes into Pathmark, data/ or the package. This tool prints, per race and class combination, the
chain of guides the combination follows (from the guide marked `#defaultfor` its race that starts
at level 1, then along `#next`, with the guides' race and class filters) and two counts up to the
end level of the chain:

- sections: guides of the chain (a guide is one zone section with a level range in its name);
- zone stretches: runs of quest steps (accept, turn-in, complete) in one zone, the zone taken from
  the step's `.goto` or the last one before it; the same unit as Pathmark's zone visits (P9).

The numbers go into data/plan/zone-sections.toml by hand, with the commit of the guides.
"""

import json
import os
import re

RACES = {"Human", "Dwarf", "Gnome", "NightElf", "Orc", "Troll", "Tauren", "Undead", "Scourge", "Skyborne"}
CLASSES = {"Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid"}
# client and ruleset flags of the guides: Forever is none of the seasonal clients; the speed route
# is softcore
FLAG = {"sod": False, "som": False, "era": False, "hardcore": False, "softcore": True, "tbc": False,
        "wotlk": False, "cata": False, "season": False}
TOKENS = {
    "HUMAN": "Human", "DWARF": "Dwarf", "GNOME": "Gnome", "NIGHTELF": "NightElf", "SKYBORNE_A": "Skyborne",
    "ORC": "Orc", "TROLL": "Troll", "TAUREN": "Tauren", "UNDEAD": "Undead", "SKYBORNE_H": "Skyborne",
}
QUEST_VERBS = ("accept", "turnin", "complete")


def applies(expr, race, cls, faction):
    """RXP filter: alternatives separated by '/', each a list of conditions separated by blanks that
    must all hold (`Orc Hunter/Troll Hunter` = orc hunters and troll hunters)."""
    expr = (expr or "").strip()
    if not expr:
        return True
    for alt in expr.split("/"):
        ok = True
        for a in alt.split():
            neg = a.startswith("!")
            t = a[1:] if neg else a
            if t in ("Horde", "Alliance"):
                v = t == faction
            elif t == "Scourge":
                v = race == "Undead"
            elif t in RACES:
                v = t == race
            elif t in CLASSES:
                v = t == cls
            else:
                v = FLAG.get(t.lower(), True)
            if v == neg:
                ok = False
                break
        if ok:
            return True
    return False


def _split_filter(line):
    if " << " in line:
        a, b = line.split(" << ", 1)
        return a.strip(), b.strip()
    return line.strip(), ""


def parse(path):
    """Guides of one file: {name: {"filter", "next": [(targets, filter)], "default", "steps"}}."""
    text = open(path, encoding="utf-8").read()
    out = {}
    for chunk in text.split("RXPGuides.RegisterGuide([[")[1:]:
        body = chunk.split("]])")[0]
        g = {"filter": "", "next": [], "default": None, "steps": [], "name": None}
        head = True
        step = None
        for raw in body.splitlines():
            line = raw.strip()
            if not line or line.startswith("--"):
                continue
            if line.startswith("step"):
                head = False
                step = {"filter": line[4:].strip()[2:].strip() if line[4:].strip().startswith("<<") else "", "lines": []}
                g["steps"].append(step)
                continue
            if head:
                if line.startswith("<<") and not g["filter"]:
                    g["filter"] = line[2:].strip()
                elif line.startswith("#name"):
                    g["name"] = line[5:].strip()
                elif line.startswith("#next"):
                    targets, filt = _split_filter(line[5:])
                    g["next"].append(([t.strip() for t in targets.split(";") if t.strip()], filt))
                elif line.startswith("#defaultfor"):
                    g["default"] = line[11:].strip()
            elif step is not None:
                step["lines"].append(line)
        if g["name"]:
            out[g["name"]] = g
    return out


def load(directory):
    guides = {}
    for name in sorted(os.listdir(directory)):
        if name.endswith(".lua"):
            guides.update(parse(os.path.join(directory, name)))
    return guides


def levels(name):
    m = re.match(r"(\d+)-(\d+)\s", name)
    return (int(m.group(1)), int(m.group(2))) if m else (None, None)


def chain(guides, race, cls, faction):
    """Guide names the combination follows from level 1 along #next."""
    first = [n for n, g in sorted(guides.items()) if g["default"] and applies(g["default"], race, cls, faction)
             and applies(g["filter"], race, cls, faction) and levels(n)[0] == 1]
    if not first:
        return []
    out = [first[0]]
    while True:
        g = guides[out[-1]]
        nxt = None
        for targets, filt in g["next"]:
            if not applies(filt, race, cls, faction):
                continue
            for t in targets:
                t = t.split("\\")[-1]
                if t in guides and t not in out and applies(guides[t]["filter"], race, cls, faction):
                    nxt = t
                    break
            if nxt or targets:
                break
        if nxt is None:
            return out
        out.append(nxt)


def _zone(text):
    """`1429/0` or `1429` (uiMapID, optional floor) -> Pathmark's zone key; a name stays a name."""
    from . import lint

    head = text.split("/")[0]
    return lint.zone_key(int(head)) if head.isdigit() else text


def stretches(guides, names, race, cls, faction):
    """Runs of quest steps in one zone along the chain (zone from `.goto Zone,x,y`)."""
    zones = []
    zone = None
    for n in names:
        for st in guides[n]["steps"]:
            if not applies(st["filter"], race, cls, faction):
                continue
            has_quest = False
            for line in st["lines"]:
                el, filt = _split_filter(line)
                if not applies(filt, race, cls, faction):
                    continue
                m = re.match(r"\.goto\s+([^,]+),", el)
                if m:
                    zone = _zone(m.group(1).strip())
                if re.match(r"\.(%s)\b" % "|".join(QUEST_VERBS), el):
                    has_quest = True
            if has_quest and zone is not None and (not zones or zones[-1] != zone):
                zones.append(zone)
    return zones


def count(directory):
    from . import game

    guides = load(directory)
    out = []
    for race, cls in game.all_combos():
        rtok, faction, _ = game.RACES[race]
        r, c = TOKENS[rtok], game.CLASSES[cls].capitalize()
        names = chain(guides, r, c, faction)
        zs = stretches(guides, names, r, c, faction)
        end = levels(names[-1])[1] if names else None
        out.append({"combo": "%s/%s" % (rtok, game.CLASSES[cls]), "end": end, "sections": len(names),
                    "stretches": len(zs), "chain": names, "zones": zs})
    return out


def main(directory, json_path=None):
    rows = count(directory)
    for r in rows:
        print("%-20s bis %s: %d Abschnitte, %d Gebietsstrecken | %s | %s" % (
            r["combo"], r["end"], r["sections"], r["stretches"], " > ".join(r["chain"]), " > ".join(r["zones"])))
    if json_path:
        with open(json_path, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(rows, fh, indent=1, ensure_ascii=False)
            fh.write("\n")
    return 0
