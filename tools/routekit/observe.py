# SPDX-License-Identifier: GPL-3.0-or-later
"""Own data from player exports: prerequisites observed at quest accepts, measured module times and
flights. Reads PM1 export texts (BraindeadForever/Collector/Export.lua; one or more per file, separated by
whitespace), writes data/sources/own/prereq.jsonl, times.jsonl and flights.jsonl. Run before `merge`:

  python3 -m tools.routekit observe EXPORT_DIR_OR_FILES...

Records used (docs/STATUS.md, data collector):
  accept  kind, dt, map, x, y, quest, giverKind, giverID, item, npcName, level, questXP,
          token, link, unlock, done, missing    (lists: quest IDs separated by ".")
  offer   kind, dt, map, x, y, quest, token, done, missing     (an NPC offered the quest)
  rx      kind, dt, "p", token, quest, link, unlock, done, missing   (from another player)
  split   kind, dt, map, x, y, module, seconds, mode          (one module played start to end)
  taxilegs kind, dt, map, x, y, node, legs                    (legs "a>b;b>c" of a flight master's map)
  flight  kind, dt, map, x, y, from, to, points               (a chosen flight, points "a;b;c")
  land    kind, dt, map, x, y, to, seconds                    (the landing of the chosen flight)
Exports overlap when a player exports "all"; chunks are counted once per install and sequence.
"""

import base64
import glob
import json
import os
import re
import zlib

from . import prereq
from .io import repo_path, write_json, write_jsonl

# Plausible seconds of one flight (chosen values): a landing outside them is a broken pair (a
# /reload in the air, a flight that never started), not a measurement.
FLIGHT_SECONDS_MIN = 5
FLIGHT_SECONDS_MAX = 1800

FRAME = re.compile(r"PM1:([dz]):(\d+):([0-9a-fA-F]+):([A-Za-z0-9+/=\s]+)")
MAX_JSON = 8 * 1024 * 1024


def adler32(s):
    a, b = 1, 0
    for ch in s.encode("ascii"):
        a = (a + ch) % 65521
        b = (b + a) % 65521
    return "%04x%04x" % (b, a)


def decode(text):
    """All payloads in a text; frames with a wrong length or checksum are skipped."""
    out = []
    for m in FRAME.finditer(text):
        method, length, checksum = m.group(1), int(m.group(2)), m.group(3).lower()
        body = re.sub(r"\s+", "", m.group(4))[:length]
        if len(body) != length or adler32(body) != checksum:
            continue
        raw = base64.b64decode(body)
        data = zlib.decompressobj(-15 if method == "d" else 15).decompress(raw, MAX_JSON)
        out.append(json.loads(data.decode("utf-8")))
    return out


def ids(field):
    return [int(x) for x in (field or "").split(".") if x.isdigit()]


def _link(field):
    return int(field) if field and field.isdigit() else 0


def _records(chunk):
    for line in chunk.split("\n"):
        if line:
            yield line.split("\t")


def collect(payloads):
    obs = prereq.Observations()
    splits = {}
    seen = set()
    for p in payloads:
        install = p.get("install") or ""
        for part in ("own", "net"):
            for chunk in p.get(part) or []:
                first = chunk.split("\n", 1)[0].split("\t")
                key = (install, part, first[2] if len(first) > 2 else chunk)
                if key in seen:
                    continue
                seen.add(key)
                for f in _records(chunk):
                    kind = f[0]
                    if kind == "accept" and len(f) >= 17 and f[5].isdigit() and f[12]:
                        obs.add(int(f[5]), f[12], _link(f[13]), f[14] == "1", ids(f[15]), ids(f[16]))
                    elif kind == "offer" and len(f) >= 9 and f[5].isdigit() and f[6]:
                        obs.add(int(f[5]), f[6], 0, 0, ids(f[7]), ids(f[8]))
                    elif kind == "rx" and len(f) >= 9 and f[2] == "p" and f[4].isdigit():
                        obs.add(int(f[4]), f[3], _link(f[5]), f[6] == "1", ids(f[7]), ids(f[8]))
                    elif kind == "split" and part == "own" and len(f) >= 7 and f[6].isdigit():
                        splits.setdefault(f[5], []).append(int(f[6]))
    return obs, splits


def _own_chunks(payloads):
    """Own chunks in order, each once per install and sequence: (install, chunk)."""
    seen = set()
    for p in payloads:
        install = p.get("install") or ""
        for chunk in p.get("own") or []:
            first = chunk.split("\n", 1)[0].split("\t")
            key = (install, first[2] if len(first) > 2 else chunk)
            if key not in seen:
                seen.add(key)
                yield install, chunk


def flights(payloads):
    """Trips and legs in the layout of data/sources/eglink/flights.jsonl: trips "from>to" with the
    flight points flown and the counted seconds of a landing paired with the flight chosen before
    it; legs "leg:a>b" from the flight master's map."""
    trips, last = {}, {}

    def trip(key):
        return trips.setdefault(key, {"key": key, "paths": set(), "seconds": {}})

    for install, chunk in _own_chunks(payloads):
        for f in _records(chunk):
            kind = f[0]
            if kind == "taxilegs" and len(f) >= 7:
                for leg in f[6].split(";"):
                    a, _, b = leg.partition(">")
                    if a.isdigit() and b.isdigit():
                        trip("leg:%s>%s" % (a, b))["paths"].add((int(a), int(b)))
            elif kind == "flight" and len(f) >= 7 and f[5].isdigit() and f[6].isdigit():
                points = tuple(int(x) for x in (f[7] if len(f) > 7 else "").split(";") if x.isdigit())
                ok = len(points) >= 2 and points[0] == int(f[5]) and points[-1] == int(f[6])
                last[install] = (int(f[5]), int(f[6]), points if ok else None)
                if ok:
                    trip("%d>%d" % (int(f[5]), int(f[6])))["paths"].add(points)
            elif kind == "land" and len(f) >= 7 and f[5].isdigit() and f[6].isdigit():
                chosen = last.pop(install, None)
                secs = int(f[6])
                if chosen and chosen[1] == int(f[5]) and chosen[2] and FLIGHT_SECONDS_MIN <= secs <= FLIGHT_SECONDS_MAX:
                    t = trip("%d>%d" % chosen[:2])
                    t["seconds"][str(secs)] = t["seconds"].get(str(secs), 0) + 1
    out = []
    for t in trips.values():
        if not t["paths"]:
            continue
        rec = {"key": t["key"], "paths": sorted(list(p) for p in t["paths"])}
        if t["seconds"]:
            rec["seconds"] = dict(sorted(t["seconds"].items(), key=lambda kv: int(kv[0])))
        out.append(rec)
    return out


def results(obs, splits):
    pre = []
    for q in obs.quests():
        state, groups, n = obs.result(q)
        if state != "unknown":
            pre.append({"q": q, "pre": groups, "basis": state, "observers": n})
    times = []
    for module, secs in sorted(splits.items()):
        secs = sorted(secs)
        times.append({"module": module, "runs": len(secs), "seconds": secs[len(secs) // 2]})
    return pre, times


def run(paths):
    files = []
    for p in paths:
        files += sorted(glob.glob(os.path.join(p, "*"))) if os.path.isdir(p) else [p]
    payloads = []
    for f in files:
        with open(f, encoding="utf-8", errors="replace") as fh:
            payloads += decode(fh.read())
    obs, splits = collect(payloads)
    pre, times = results(obs, splits)
    trips = flights(payloads)
    out = repo_path("data", "sources", "own")
    write_json(
        os.path.join(out, "SOURCE.json"),
        {
            "source": "own",
            "name": "Braindead Forever players: data collector exports",
            "license": "GPL-3.0-or-later",
            "exports": len(payloads),
            "files": ["prereq.jsonl", "times.jsonl", "flights.jsonl"],
            "rules": {
                "minLinks": prereq.MIN_LINKS,
                "minSupport": prereq.MIN_SUPPORT,
                "minNone": prereq.MIN_NONE,
                "flightSeconds": [FLIGHT_SECONDS_MIN, FLIGHT_SECONDS_MAX],
            },
            "status": "unbestätigt",
        },
    )
    write_jsonl(os.path.join(out, "prereq.jsonl"), pre)
    write_jsonl(os.path.join(out, "times.jsonl"), times, key="module")
    write_jsonl(os.path.join(out, "flights.jsonl"), trips, key="key")
    return {
        "exports": len(payloads),
        "quests observed": len(obs.quests()),
        "prerequisites": len(pre),
        "timed modules": len(times),
        "flight trips and legs": len(trips),
    }
