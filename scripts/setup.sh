#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Local toolchain in .tools/ (git-ignored): Lua 5.1.5 + LuaRocks via hererocks,
# busted and luacheck, WoW API annotations for the type check.
# Homebrew tools (not installed here): stylua gitleaks actionlint lua-language-server
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Some macOS Python builds lack a CA bundle for the hererocks downloads.
if [[ -z "${SSL_CERT_FILE:-}" && -f /etc/ssl/cert.pem ]]; then
	export SSL_CERT_FILE=/etc/ssl/cert.pem
fi

if [[ ! -x .tools/lua51/bin/lua ]]; then
	python3 -m venv .tools/venv
	.tools/venv/bin/pip install --quiet hererocks==0.25.1
	.tools/venv/bin/hererocks .tools/lua51 --lua 5.1 --luarocks 3.8.0
fi

.tools/lua51/bin/luarocks install busted 2.3.0-1
.tools/lua51/bin/luarocks install luacheck 1.2.0-1

scripts/fetch-wow-api.sh

for tool in stylua gitleaks actionlint lua-language-server; do
	command -v "$tool" >/dev/null || echo "missing: $tool (brew install $tool)"
done
echo "setup done"
