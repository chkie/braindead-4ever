# SPDX-License-Identifier: GPL-3.0-or-later
"""Route linter (docs/ROUTE-FORMAT.md §Linter). Every error has a code, a file, a line and,
where it concerns a quest, the quest ID.

Checks per file: syntax, header, labels, provenance (source present, source allowed by
decision FD-1101, source backed by data/facts), status, block list of phrases, map frames,
faction, filters, levels, Speed rule.
Checks per combination (all 56 races x classes, per mode): a route exists, quest order
(accept before turn-in, prerequisite before follow-up), items before turn-in, travel on
every zone change, no return to a zone left earlier without a stated reason.
"""

import glob
import os
import re
import sys

from . import game, geo, routefmt
from .io import read_jsonl, repo_path

# Decision FD-1101: data may be taken from these sources only. "own" = our own measurement.
DATA_SOURCES = {"polestar", "att", "eglink", "own"}
# Route logic written by the team (travel, notes, planned levels) carries "plan".
LOGIC_SOURCES = DATA_SOURCES | {"plan"}
DATA_VERBS = {"accept", "complete", "turnin", "collect", "goto"}
AGREE_YARDS = 10.0
FRAME_MARGIN = 50.0
LEVEL_ABOVE = 2  # DR 20 §5.6: quest level at most 2 above the planned level

# Block list (Plan §Sprache Nr. 5): typical AI phrases, exclamation marks, emoji.
BLOCKED_PHRASES = [
    "tauche ein",
    "taucht ein",
    "tauchen sie ein",
    "nahtlos",
    "mühelos",
    "episch",
    "unvergesslich",
    "spannende reise",
    "abenteuer erwartet",
    "lass dich",
    "entfessle",
    "dive into",
    "seamless",
    "effortless",
    "epic journey",
    "embark",
]
EMOJI_RE = re.compile("[\U0001f300-\U0001faff☀-➿⭐⬆↔-↪]")


class Error:
    def __init__(self, code, path, line, msg, quest=None, module=None):
        self.code, self.path, self.line, self.msg, self.quest, self.module = code, path, line, msg, quest, module

    def __str__(self):
        return "%s:%s: [%s] %s" % (self.path, self.line, self.code, self.msg)


class Facts:
    def __init__(self, records, frames):
        self.q = {r["q"]: r for r in records}
        self.frames = frames

    @classmethod
    def load(cls, facts_path=None, frames_path=None):
        facts_path = facts_path or repo_path("data", "facts", "quests.jsonl")
        frames_path = frames_path or repo_path("data", "sources", "polestar", "ui_map.jsonl")
        return cls(read_jsonl(facts_path), geo.Frames(read_jsonl(frames_path)))

    def sources_of(self, q):
        r = self.q.get(q)
        if not r:
            return set()
        out = set()
        for f in ("level", "min", "side", "start", "end", "races", "classes", "startPos", "endPos"):
            v = r.get(f)
            if isinstance(v, dict):
                out.update(v.get("src", []))
                out.update(v.get("seen", []))
        return out

    def positions(self, q):
        """[(uiMap, west, north, seen sources)] known for a quest: giver, ender, objectives."""
        r = self.q.get(q)
        out = []
        if not r:
            return out
        for f in ("startPos", "endPos"):
            p = r.get(f)
            if p:
                out.append((p["v"][0], p["v"][1], p["v"][2], set(p.get("seen", p.get("src", [])))))
        for o in r.get("obj", []):
            if o.get("pos"):
                out.append((o["pos"][0], o["pos"][1], o["pos"][2], set(o.get("src", []))))
        return out

    def races(self, q):
        v = (self.q.get(q) or {}).get("races", {}).get("v")
        return None if v is None else set(v)

    def classes(self, q):
        v = (self.q.get(q) or {}).get("classes", {}).get("v")
        return None if v is None else set(v)

    def side(self, q):
        return (self.q.get(q) or {}).get("side", {}).get("v")

    def pre(self, q):
        return (self.q.get(q) or {}).get("pre", {"v": [], "state": "unknown"})

    def items(self, q):
        return (self.q.get(q) or {}).get("items", [])


def zone_key(ui_map):
    """Zephras has two uiMapIDs (2521, 2665); both are one zone for the route rules."""
    return 2521 if ui_map == 2665 else ui_map


def blocked(text):
    t = text.lower()
    hits = [p for p in BLOCKED_PHRASES if p in t]
    if "!" in text:
        hits.append("Ausrufezeichen")
    if EMOJI_RE.search(text):
        hits.append("Emoji")
    return hits


def _effective(mod_filter, step_filter, el_filter, universe_races, universe_classes):
    races, classes = set(universe_races), set(universe_classes)
    for f in (mod_filter, step_filter, el_filter):
        if f is None:
            continue
        if f.races is not None:
            races &= f.races
        if f.classes is not None:
            classes &= f.classes
    return races, classes


def lint_module(mod, facts):
    errs = []
    path = mod.path

    def E(code, line, msg, quest=None):
        errs.append(Error(code, path, line, msg, quest, mod.key))

    for line, msg in mod.errors:
        E("syntax", line, msg)
    for k in routefmt.HEADERS_REQUIRED:
        if k not in mod.header:
            E("kopf", 1, "Kopfzeile #%s fehlt" % k)
    h = mod.header
    if h.get("kind") and h["kind"] not in routefmt.KINDS:
        E("kopf", mod.header_lines["kind"], "unbekannte Art '%s'" % h["kind"])
    if h.get("mode") and h["mode"] not in routefmt.MODES:
        E("kopf", mod.header_lines["mode"], "unbekannter Modus '%s'" % h["mode"])
    if h.get("faction") and h["faction"] not in (game.ALLIANCE, game.HORDE):
        E("kopf", mod.header_lines["faction"], "unbekannte Fraktion '%s'" % h["faction"])
    if h.get("version") and not h["version"].isdigit():
        E("kopf", mod.header_lines["version"], "#version ist keine ganze Zahl")
    if h.get("label"):
        if h["label"] not in routefmt.LABELS:
            E("label", mod.header_lines["label"], "unbekanntes Etikett '%s'" % h["label"])
        elif h["label"] == "stabil":
            E("label", mod.header_lines["label"], "Etikett 'stabil' braucht 20 eigene Messläufe; es gibt keine")
    if h.get("sources"):
        for part in h["sources"].split():
            key = part.split("=", 1)[0]
            if key not in DATA_SOURCES:
                E("quelle", mod.header_lines["sources"], "Quelle '%s' ist nach FD-1101 keine Datenquelle" % key)
    if h.get("text"):
        hits = blocked(h["text"])
        if hits:
            E("sperrliste", mod.header_lines["text"], "Sperrliste: %s" % ", ".join(hits))
    levels = mod.levels()
    if h.get("levels") and not levels:
        E("kopf", mod.header_lines["levels"], "#levels nicht im Format a-b")

    faction = h.get("faction")
    universe_races = game.races_of(faction) if faction in (game.ALLIANCE, game.HORDE) else list(game.RACES)
    universe_classes = list(game.CLASSES)
    if mod.filter and mod.filter.races is not None and faction:
        foreign = mod.filter.races - set(universe_races)
        if foreign:
            E("filter", mod.header_lines["for"], "#for nennt Völker der anderen Fraktion")

    seen = {}
    for st in mod.steps:
        if st.id in seen:
            E("schritt", st.line, "Schritt-ID @%s doppelt (erste in Zeile %d)" % (st.id, seen[st.id]))
        seen[st.id] = st.line
        if not st.elements:
            E("schritt", st.line, "Schritt @%s ohne Element" % st.id)
        if st.lv is not None and levels and not (levels[0] <= st.lv <= levels[1] + LEVEL_ABOVE):
            E("stufe", st.line, "geplante Stufe %d liegt außerhalb #levels %s" % (st.lv, h["levels"]))
        step_quests = [el.args["q"] for el in st.elements if "q" in el.args]
        for el in st.elements:
            line = el.line
            src = el.src
            q = el.args.get("q")
            # provenance
            if not src:
                E("herkunft", line, "'%s' ohne Herkunft (src=)" % el.verb, q)
            else:
                allowed = DATA_SOURCES if el.verb in DATA_VERBS else LOGIC_SOURCES
                bad = [s for s in src if s not in allowed]
                if bad:
                    E("quelle", line, "Quelle %s ist für '%s' nach FD-1101 nicht zugelassen" % (",".join(bad), el.verb), q)
            if el.status is None:
                E("status", line, "'%s' ohne status=" % el.verb, q)
            elif el.status not in routefmt.STATUS:
                E("status", line, "unbekannter Status '%s'" % el.status, q)
            elif el.status == "bestätigt" and "own" not in src:
                E("status", line, "'bestätigt' nur mit eigener Messung (src=own)", q)
            if el.verb == "note":
                hits = blocked(el.args.get("text", ""))
                if hits:
                    E("sperrliste", line, "Sperrliste: %s" % ", ".join(hits))
            # backed by facts
            ext = [s for s in src if s in DATA_SOURCES and s != "own"]
            if q is not None:
                if q not in facts.q:
                    if "own" not in src:
                        E("beleg", line, "Quest %d steht in keiner Quelle (data/facts)" % q, q)
                    continue
                known = facts.sources_of(q)
                missing = [s for s in ext if s not in known]
                if missing:
                    E("beleg", line, "Quest %d: Quelle %s führt sie nicht" % (q, ",".join(missing)), q)
                side = facts.side(q)
                if faction and side and side != "B" and side != faction[0]:
                    E("fraktion", line, "Quest %d gehört zur anderen Fraktion" % q, q)
                qr, qc = facts.races(q), facts.classes(q)
                races, classes = _effective(mod.filter, st.filter, el.filter, universe_races, universe_classes)
                if qr is not None and not races <= qr:
                    E("filter", line, "Quest %d nur für Völker %s; Filter fehlt oder ist zu weit" % (q, sorted(qr)), q)
                if qc is not None and not classes <= qc:
                    E("filter", line, "Quest %d nur für Klassen %s; Filter fehlt oder ist zu weit" % (q, sorted(qc)), q)
                if el.verb == "accept":
                    pre = facts.pre(q)
                    if mod.mode == "speed" and pre.get("state") != "secured":
                        E("speed", line, "Quest %d ohne gesicherte Vorbedingung (%s) im Speed-Modus" % (q, pre.get("state")), q)
                    rec = facts.q[q]
                    mn = rec.get("min", {}).get("v")
                    lvl = rec.get("level", {}).get("v")
                    if st.lv is not None:
                        if mn is not None and mn > st.lv:
                            E("stufe", line, "Quest %d verlangt Stufe %d, geplant %d" % (q, mn, st.lv), q)
                        if lvl is not None and lvl > st.lv + LEVEL_ABOVE:
                            E("stufe", line, "Quest %d hat Stufe %d, mehr als %d über geplant %d" % (q, lvl, LEVEL_ABOVE, st.lv), q)
            if el.verb == "goto":
                m, wx, wy = el.args["map"], el.args["wx"], el.args["wy"]
                if m not in facts.frames.by_map:
                    E("karte", line, "uiMap %d unbekannt" % m)
                elif not facts.frames.contains(m, wy, wx, FRAME_MARGIN):
                    E("karte", line, "Punkt %.1f,%.1f liegt nicht auf uiMap %d (Achsen vertauscht?)" % (wx, wy, m))
                if ext:
                    cands = [p for qq in step_quests for p in facts.positions(qq)]
                    ok = any(
                        zone_key(p[0]) == zone_key(m) and geo.dist((p[2], p[1]), (wy, wx)) <= AGREE_YARDS and set(ext) <= p[3]
                        for p in cands
                    )
                    if not ok:
                        E("beleg", line, "Koordinate ist durch die genannten Quellen nicht belegt", step_quests[0] if step_quests else None)
            if el.verb == "travel" and el.args["map"] not in game.ZONES and el.args["map"] not in facts.frames.by_map:
                E("karte", line, "Reiseziel uiMap %d unbekannt" % el.args["map"])
    return errs


def _step_zone(step):
    z = None
    for el in step.elements:
        if el.verb == "travel":
            z = el.args["map"]
    for el in step.elements:
        if el.verb == "goto":
            z = el.args["map"] if z is None else z
    return z


def lint_route(mods, keys, race, cls, facts, label):
    """Sequence rules on the composed route of one combination."""
    errs = []
    accepted, completed, turned, collected = set(), set(), set(), {}
    zone, left = None, set()
    for key in keys:
        mod = mods.get(key)
        if mod is None:
            errs.append(Error("compose", label, 0, "Modul '%s' fehlt" % key))
            continue
        if mod.filter and not mod.filter.applies(race, cls):
            continue
        for st in mod.steps:
            if st.filter and not st.filter.applies(race, cls):
                continue
            els = [el for el in st.elements if not el.filter or el.filter.applies(race, cls)]
            if not els:
                continue

            def E(code, line, msg, quest=None):
                errs.append(Error(code, mod.path, line, "%s [%s]" % (msg, label), quest, mod.key))

            travel_to = [el.args["map"] for el in els if el.verb == "travel"]
            gotos = [el.args["map"] for el in els if el.verb == "goto"]
            new_zone = travel_to[-1] if travel_to else (gotos[0] if gotos else None)
            if new_zone is not None:
                for g in gotos:
                    if zone_key(g) != zone_key(new_zone):
                        E("reise", st.line, "Schritt @%s führt in zwei Gebiete (%d, %d)" % (st.id, new_zone, g))
                if zone is not None and zone_key(new_zone) != zone_key(zone):
                    if not travel_to:
                        E("reise", st.line, "Gebietswechsel %d -> %d ohne Reiseschritt (travel)" % (zone, new_zone))
                    if zone_key(new_zone) in left and not st.ret:
                        E("ruecksprung", st.line, "Rückkehr in das verlassene Gebiet %d ohne Grund (!return)" % new_zone)
                    left.add(zone_key(zone))
                zone = new_zone
            for el in els:
                q = el.args.get("q")
                if el.verb == "accept":
                    if q in accepted:
                        E("reihenfolge", el.line, "Quest %d zweimal angenommen" % q, q)
                    qr, qc, side = facts.races(q), facts.classes(q), facts.side(q)
                    if (qr is not None and race not in qr) or (qc is not None and cls not in qc):
                        E("filter", el.line, "Quest %d ist für diese Kombination nicht verfügbar" % q, q)
                    if side and side != "B" and side != game.faction_of(race)[0]:
                        E("fraktion", el.line, "Quest %d gehört zur anderen Fraktion" % q, q)
                    pre = facts.pre(q)
                    if pre.get("state") in ("secured", "conflict"):
                        for group in pre.get("v", []):
                            if not any(g in turned for g in group):
                                E("vorquest", el.line, "Quest %d vor ihrer Vorquest %s angenommen" % (q, "/".join(map(str, group))), q)
                    accepted.add(q)
                elif el.verb == "complete":
                    if q not in accepted:
                        E("reihenfolge", el.line, "Quest %d abgeschlossen, aber nicht angenommen" % q, q)
                    completed.add(q)
                elif el.verb == "collect":
                    collected[el.args["item"]] = collected.get(el.args["item"], 0) + el.args["n"]
                elif el.verb == "turnin":
                    if q not in accepted:
                        E("reihenfolge", el.line, "Quest %d abgegeben, aber nicht angenommen" % q, q)
                    if q not in completed:
                        for it in facts.items(q):
                            if collected.get(it["id"], 0) < it.get("count", 1):
                                E("gegenstand", el.line, "Quest %d abgegeben ohne Gegenstand %d x%d (complete oder collect fehlt)" % (q, it["id"], it.get("count", 1)), q)
                    turned.add(q)
    return errs


def load_routes(root=None):
    root = root or repo_path("data", "routes")
    mods = {}
    files = sorted(glob.glob(os.path.join(root, "**", "*.route"), recursive=True))
    for f in files:
        m = routefmt.parse_file(f)
        mods[m.key or f] = m
    comps = []
    for f in sorted(glob.glob(os.path.join(root, "*", "COMPOSE"))):
        with open(f, encoding="utf-8") as fh:
            comps.append(routefmt.parse_compose(fh.read(), f))
    return mods, comps


def lint_all(mods, comps, facts, combos=True, combo_list=None, modes=routefmt.MODES):
    errs = []
    keys_seen = {}
    for key, m in mods.items():
        if key in keys_seen:
            errs.append(Error("kopf", m.path, 1, "#module '%s' doppelt (%s)" % (key, keys_seen[key])))
        keys_seen[key] = m.path
        errs.extend(lint_module(m, facts))
    if not combos:
        return errs
    for c in comps:
        for line, msg in c.errors:
            errs.append(Error("syntax", c.path, line, msg))
    for mode in modes:
        for race, cls in combo_list or game.all_combos():
            faction = game.faction_of(race)
            comp = next((c for c in comps if c.faction == faction and mode in c.modes), None)
            label = "%s/%s/%s" % (mode, game.RACES[race][0], game.CLASSES[cls])
            if comp is None:
                errs.append(Error("compose", "data/routes", 0, "keine Zusammenstellung für %s" % label))
                continue
            keys = comp.route(mode, race, cls)
            if not keys:
                errs.append(Error("compose", comp.path, 0, "keine Route für %s" % label))
                continue
            for k in keys:
                m = mods.get(k)
                if m and (m.faction != faction or m.mode != mode):
                    errs.append(Error("compose", comp.path, 0, "Modul %s passt nicht zu %s" % (k, label)))
            errs.extend(lint_route(mods, keys, race, cls, facts, label))
    return errs


def main(files=None, combos=True, facts=None, out=sys.stdout):
    facts = facts or Facts.load()
    if files:
        mods = {}
        for f in files:
            m = routefmt.parse_file(f)
            mods[m.key or f] = m
        comps = []
        combos = False
    else:
        mods, comps = load_routes()
    errs = lint_all(mods, comps, facts, combos=combos)
    # identical messages from several combinations are reported once
    seen = set()
    for e in errs:
        s = str(e)
        if s not in seen:
            seen.add(s)
            print(s, file=out)
    print("%d Datei(en), %d Fehler" % (len(mods) + len(comps), len(seen)), file=out)
    return 0 if not errs else 1
