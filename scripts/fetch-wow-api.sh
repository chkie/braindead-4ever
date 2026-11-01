#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Downloads the WoW API type annotations (Ketho/vscode-wow-api, MIT) used by the
# Lua Language Server type check. Pinned to a commit so CI and local runs match.
# Target: .tools/wow-api (git-ignored, never committed or packaged).
set -euo pipefail

REPO="https://github.com/Ketho/vscode-wow-api"
REF="56fbef8adacfe978b4b6eea5fdb6fab4bb707e2b" # tag 0.22.3 (WoW 12.0.1)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/.tools/wow-api"

if [[ -f "$DEST/.ref" && "$(cat "$DEST/.ref")" == "$REF" ]]; then
	echo "wow-api annotations already at $REF"
	exit 0
fi

rm -rf "$DEST"
git init -q "$DEST"
git -C "$DEST" remote add origin "$REPO"
git -C "$DEST" sparse-checkout set Annotations/Core
git -C "$DEST" fetch -q --depth 1 origin "$REF"
git -C "$DEST" checkout -q FETCH_HEAD
echo "$REF" >"$DEST/.ref"
echo "wow-api annotations ready: $(find "$DEST/Annotations/Core" -name '*.lua' | wc -l | tr -d ' ') files"
