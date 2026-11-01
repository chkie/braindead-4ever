# SPDX-License-Identifier: GPL-3.0-or-later
"""Own data from player exports: prerequisites observed at quest accepts and measured module
times. Reads PM1 export texts (Pathmark/Collector/Export.lua; one or more per file, separated by
whitespace), writes data/sources/own/prereq.jsonl and times.jsonl. Run before `merge`:

  python3 -m tools.routekit observe EXPORT_DIR_OR_FILES...

Records used (docs/STATUS.md, data collector):
  accept  kind, dt, map, x, y, quest, giverKind, giverID, item, npcName, level, questXP,
          token, link, unlock, done, missing    (lists: quest IDs separated by ".")
  offer   kind, dt, map, x, y, quest, token, done, missing     (an NPC offered the quest)
  rx      kind, dt, "p", token, quest, link, unlock, done, missing   (from another player)
  split   kind, dt, map, x, y, module, seconds, mode          (one module played start to end)
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
    out = repo_path("data", "sources", "own")
    write_json(
        os.path.join(out, "SOURCE.json"),
        {
            "source": "own",
            "name": "Pathmark players: data collector exports",
            "license": "GPL-3.0-or-later",
            "exports": len(payloads),
            "files": ["prereq.jsonl", "times.jsonl"],
            "rules": {"minLinks": prereq.MIN_LINKS, "minSupport": prereq.MIN_SUPPORT, "minNone": prereq.MIN_NONE},
            "status": "unbestätigt",
        },
    )
    write_jsonl(os.path.join(out, "prereq.jsonl"), pre)
    write_jsonl(os.path.join(out, "times.jsonl"), times, key="module")
    return {"exports": len(payloads), "quests observed": len(obs.quests()), "prerequisites": len(pre), "timed modules": len(times)}
