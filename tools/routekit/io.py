# SPDX-License-Identifier: GPL-3.0-or-later
"""Small file helpers shared by the importers, the merge step and the route builder."""

import json
import os

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def repo_path(*parts):
    return os.path.join(REPO, *parts)


def write_jsonl(path, records, key="q"):
    """One JSON object per line, sorted by `key`, keys sorted, no spaces: stable diffs."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    rows = sorted(records, key=lambda r: r[key])
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        for r in rows:
            fh.write(json.dumps(r, sort_keys=True, separators=(",", ":"), ensure_ascii=False))
            fh.write("\n")
    return len(rows)


def read_jsonl(path):
    with open(path, encoding="utf-8") as fh:
        return [json.loads(line) for line in fh if line.strip()]


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(obj, fh, sort_keys=True, indent=1, ensure_ascii=False)
        fh.write("\n")


def read_json(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def git_head(path):
    """Commit and commit date of a checkout, read from .git without running git."""
    import subprocess

    out = subprocess.run(
        ["git", "-C", path, "log", "-1", "--format=%H %cI"], capture_output=True, text=True, check=True
    ).stdout.split()
    return out[0], out[1]
