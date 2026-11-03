# SPDX-License-Identifier: GPL-3.0-or-later
"""Parser for the Braindead Forever route format (docs/ROUTE-FORMAT.md).

The parser only reads and reports syntax errors; every content rule lives in lint.py.
"""

import re

from . import game

VERBS = {
    # verb: (argument pattern, data element?)
    "accept": (r"(?P<q>\d+)", True),
    "complete": (r"(?P<q>\d+)", True),
    "turnin": (r"(?P<q>\d+)", True),
    "collect": (r"(?P<item>\d+)\s+(?P<n>\d+)", True),
    "goto": (r"(?P<map>\d+)\s+(?P<wx>-?\d+(?:\.\d+)?),(?P<wy>-?\d+(?:\.\d+)?)(?:\s+r=(?P<r>\d+(?:\.\d+)?))?", True),
    "travel": (r"(?P<how>walk|fly|boat|zeppelin|airship|tram|portal|hearth)\s+(?P<map>\d+)", False),
    "hs": (r"", False),
    "sethome": (r"", False),
    "fp": (r"", False),
    "train": (r"", False),
    "xp": (r"(?P<level>\d+)", False),
    "note": (r'"(?P<text>[^"]*)"', False),
}
HEADERS_REQUIRED = ("module", "kind", "faction", "mode", "levels", "label", "version", "sources")
HEADERS = set(HEADERS_REQUIRED) | {"for", "text"}
KINDS = ("start", "core", "class")
MODES = ("speed", "explorer")
LABELS = ("vorläufig", "stabil")
STATUS = ("unbestätigt", "bestätigt")


class Filter:
    """race=TOKENS class=TOKENS, each list optionally negated with a leading '!'.
    Dimensions are ANDed, tokens within a dimension ORed."""

    def __init__(self, text):
        self.text = text.strip()
        self.races = None  # set of raceIDs that pass
        self.classes = None
        self.errors = []
        for part in self.text.split():
            m = re.fullmatch(r"(race|class)=(!?)([A-Z_,]+)", part)
            if not m:
                self.errors.append("unbekannter Filter '%s'" % part)
                continue
            dim, neg, tokens = m.groups()
            table = game.RACE_BY_TOKEN if dim == "race" else game.CLASS_BY_TOKEN
            ids = set()
            for t in tokens.split(","):
                if t not in table:
                    self.errors.append("unbekanntes Filter-Token '%s'" % t)
                else:
                    ids.add(table[t])
            universe = set(game.RACES) if dim == "race" else set(game.CLASSES)
            if neg:
                ids = universe - ids
            if dim == "race":
                self.races = ids if self.races is None else self.races & ids
            else:
                self.classes = ids if self.classes is None else self.classes & ids

    def applies(self, race, cls):
        return (self.races is None or race in self.races) and (self.classes is None or cls in self.classes)


class Element:
    def __init__(self, verb, args, line, filt=None, prov=None):
        self.verb = verb
        self.args = args
        self.line = line
        self.filter = filt
        self.prov = prov or {}

    @property
    def src(self):
        return self.prov.get("src", [])

    @property
    def status(self):
        return self.prov.get("status")


class Step:
    def __init__(self, sid, line, lv=None, filt=None, ret=None):
        self.id = sid
        self.line = line
        self.lv = lv
        self.filter = filt
        self.ret = ret  # reason for returning to a zone left earlier
        self.elements = []


class Module:
    def __init__(self, path):
        self.path = path
        self.header = {}
        self.header_lines = {}
        self.steps = []
        self.errors = []  # (line, message)
        self.filter = None

    @property
    def key(self):
        return self.header.get("module")

    @property
    def faction(self):
        return self.header.get("faction")

    @property
    def mode(self):
        return self.header.get("mode")

    @property
    def kind(self):
        return self.header.get("kind")

    def levels(self):
        m = re.fullmatch(r"(\d+)-(\d+)", self.header.get("levels", ""))
        return (int(m.group(1)), int(m.group(2))) if m else None


PROV_RE = re.compile(r"\|\s*(?P<prov>.*)$")
STEP_RE = re.compile(r"^@(?P<id>[a-z0-9]+)(?P<rest>.*)$")


def _strip_comment(line):
    # "--" starts a comment unless it sits inside a quoted note text.
    out, inq = [], False
    i = 0
    while i < len(line):
        c = line[i]
        if c == '"':
            inq = not inq
        if not inq and line.startswith("--", i):
            break
        out.append(c)
        i += 1
    return "".join(out).rstrip()


def _parse_prov(text):
    prov = {}
    for part in text.split():
        if "=" not in part:
            return None, "Herkunftsangabe '%s' ist kein key=value" % part
        k, v = part.split("=", 1)
        if k == "src":
            prov["src"] = [s for s in v.split(",") if s]
        elif k in ("status", "roots"):
            prov[k] = v
        else:
            return None, "unbekannter Herkunftsschlüssel '%s'" % k
    return prov, None


def parse(text, path="<route>"):
    mod = Module(path)
    step = None
    for no, raw in enumerate(text.splitlines(), 1):
        line = _strip_comment(raw)
        if not line.strip():
            continue
        if line.startswith("#"):
            m = re.fullmatch(r"#(\w+)\s+(.*)", line.strip())
            if not m:
                mod.errors.append((no, "Kopfzeile ohne Wert"))
                continue
            k, v = m.group(1), m.group(2).strip()
            if k not in HEADERS:
                mod.errors.append((no, "unbekannte Kopfzeile #%s" % k))
            elif step is not None:
                mod.errors.append((no, "Kopfzeile #%s nach dem ersten Schritt" % k))
            elif k in mod.header:
                mod.errors.append((no, "Kopfzeile #%s doppelt" % k))
            else:
                mod.header[k] = v
                mod.header_lines[k] = no
                if k == "for":
                    mod.filter = Filter(v)
                    for e in mod.filter.errors:
                        mod.errors.append((no, e))
            continue
        sm = STEP_RE.match(line.strip())
        if sm:
            rest = sm.group("rest")
            ret = None
            rm = re.search(r'!return\s+"([^"]+)"', rest)
            if rm:
                ret = rm.group(1)
                rest = rest[: rm.start()] + rest[rm.end() :]
            elif "!return" in rest:
                mod.errors.append((no, "!return ohne Grund in Anführungszeichen"))
                rest = rest.replace("!return", "")
            filt = None
            if "<<" in rest:
                rest, ftext = rest.split("<<", 1)
                filt = Filter(ftext)
                for e in filt.errors:
                    mod.errors.append((no, e))
            lv = None
            for tok in rest.split():
                lm = re.fullmatch(r"lv=(\d+)", tok)
                if lm:
                    lv = int(lm.group(1))
                else:
                    mod.errors.append((no, "unbekannte Schrittangabe '%s'" % tok))
            step = Step(sm.group("id"), no, lv, filt, ret)
            mod.steps.append(step)
            continue
        if step is None:
            mod.errors.append((no, "Element vor dem ersten Schritt"))
            continue
        body = line.strip()
        prov = None
        pm = PROV_RE.search(body)
        if pm:
            prov, err = _parse_prov(pm.group("prov"))
            if err:
                mod.errors.append((no, err))
            body = body[: pm.start()].strip()
        filt = None
        if "<<" in body:
            body, ftext = body.split("<<", 1)
            body = body.strip()
            filt = Filter(ftext)
            for e in filt.errors:
                mod.errors.append((no, e))
        verb, _, rest = body.partition(" ")
        if verb not in VERBS:
            mod.errors.append((no, "unbekanntes Verb '%s'" % verb))
            continue
        m = re.fullmatch(VERBS[verb][0], rest.strip())
        if not m:
            mod.errors.append((no, "Argumente von '%s' passen nicht: '%s'" % (verb, rest.strip())))
            continue
        args = {k: v for k, v in m.groupdict().items() if v is not None}
        for k in ("q", "item", "n", "map", "level"):
            if k in args:
                args[k] = int(args[k])
        for k in ("wx", "wy", "r"):
            if k in args:
                args[k] = float(args[k])
        step.elements.append(Element(verb, args, no, filt, prov))
    return mod


def parse_file(path):
    with open(path, encoding="utf-8") as fh:
        return parse(fh.read(), path)


# --- composition file -------------------------------------------------------------------------


class Compose:
    """data/routes/<faction>/COMPOSE: which modules make the route for a race and class.

    #faction Alliance
    #mode speed
    start a-speed-start-elwynn << race=HUMAN
    core a-speed-core-01-1436 a-speed-core-02-1432 ...
    insert after a-speed-core-01-1436 a-speed-class-human-warrior-01 << race=HUMAN class=WARRIOR

    The route of a combination is: the first start module whose filter applies, then for each
    anchor ("start", then every core module in order) the core module and the inserts that
    follow it and apply.
    """

    def __init__(self, path):
        self.path = path
        self.errors = []
        self.faction = None
        self.modes = {}  # mode -> {"starts": [(Filter, key)], "core": [keys], "inserts": [(Filter, after, key)]}

    def route(self, mode, race, cls):
        """Module keys in order for one combination, or None if no start module applies."""
        c = self.modes.get(mode)
        if not c:
            return None
        start = [k for f, k in c["starts"] if f.applies(race, cls)]
        if not start:
            return None
        out = [start[0]]
        for anchor in ["start"] + c["core"]:
            if anchor != "start":
                out.append(anchor)
            for f, after, key in c["inserts"]:
                if after == anchor and f.applies(race, cls):
                    out.append(key)
        return out


def parse_compose(text, path="<compose>"):
    comp = Compose(path)
    cur = None
    for no, raw in enumerate(text.splitlines(), 1):
        line = _strip_comment(raw).strip()
        if not line:
            continue
        if line.startswith("#"):
            m = re.fullmatch(r"#(\w+)\s+(.*)", line)
            if not m:
                comp.errors.append((no, "Kopfzeile ohne Wert"))
                continue
            k, v = m.groups()
            if k == "faction":
                comp.faction = v
            elif k == "mode":
                if v not in MODES:
                    comp.errors.append((no, "unbekannter Modus '%s'" % v))
                cur = comp.modes.setdefault(v, {"starts": [], "core": [], "inserts": []})
            else:
                comp.errors.append((no, "unbekannte Kopfzeile #%s" % k))
            continue
        if cur is None:
            comp.errors.append((no, "Zeile vor #mode"))
            continue
        body, _, ftext = line.partition("<<")
        parts = body.split()
        f = Filter(ftext) if ftext.strip() else Filter("")
        comp.errors.extend((no, e) for e in f.errors)
        if parts and parts[0] == "start" and len(parts) == 2:
            cur["starts"].append((f, parts[1]))
        elif parts and parts[0] == "core" and len(parts) >= 2 and not ftext.strip():
            cur["core"].extend(parts[1:])
        elif parts and parts[0] == "insert" and len(parts) == 4 and parts[1] == "after":
            cur["inserts"].append((f, parts[2], parts[3]))
        else:
            comp.errors.append((no, "unbekannte Zeile '%s'" % line))
    return comp
