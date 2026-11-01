#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Runs every check CI runs. Exit code 0 only if all of them pass.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BIN=.tools/lua51/bin
failed=()

run() {
	local name="$1"
	shift
	echo "== $name: $*"
	if "$@"; then
		echo "-- $name: ok"
	else
		echo "-- $name: FAILED"
		failed+=("$name")
	fi
}

run tests "$BIN/busted"
run lint "$BIN/luacheck" .
run format stylua --check .
run types lua-language-server --check . --checklevel=Warning --logpath="$ROOT/.tools/luals-log"
run secrets gitleaks git --redact --no-banner .
run workflows actionlint

if ((${#failed[@]})); then
	echo "FAILED: ${failed[*]}"
	exit 1
fi
echo "all checks passed"
