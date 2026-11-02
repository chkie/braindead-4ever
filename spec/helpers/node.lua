-- SPDX-License-Identifier: GPL-3.0-or-later
-- Node.js as the real counterpart in tests: zlib compresses like C_EncodingUtil.CompressString
-- (Deflate = raw RFC 1951, Zlib = RFC 1950), and decoder/cli.mjs decodes like the website does.
-- Node is required: a missing node fails the tests instead of skipping them.
local M = {}

local function shellQuote(s)
	return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function tmpWrite(content)
	local path = os.tmpname()
	local fh = assert(io.open(path, "wb"))
	fh:write(content)
	fh:close()
	return path
end

-- Runs a node command with input on stdin; returns stdout and stderr.
local function run(args, input)
	local inPath = tmpWrite(input or "")
	local errPath = os.tmpname()
	local p = assert(io.popen("node " .. args .. " < " .. shellQuote(inPath) .. " 2> " .. shellQuote(errPath), "r"))
	local out = p:read("*a")
	p:close()
	local fh = io.open(errPath, "rb")
	local err = fh and fh:read("*a") or ""
	if fh then
		fh:close()
	end
	os.remove(inPath)
	os.remove(errPath)
	return out, err
end

function M.version()
	local p = io.popen("node --version 2>/dev/null")
	local v = p and p:read("*a") or ""
	if p then
		p:close()
	end
	return v:match("^v(%d+)")
end

-- Raw bytes compressed like CompressString: method 0 = Deflate (raw), 1 = Zlib.
function M.compress(raw, method)
	local fn = method == 1 and "deflateSync" or "deflateRawSync"
	local out = run(
		"-e " .. shellQuote("process.stdout.write(require('zlib')." .. fn .. "(require('fs').readFileSync(0)))"),
		raw
	)
	return out
end

-- Decodes an export text with the website decoder. Returns the JSON text or nil plus the error.
function M.decode(text)
	local out, err = run("decoder/cli.mjs", text)
	if err:match("^ERROR:") or out == "" then
		return nil, (err:gsub("%s+$", ""))
	end
	return out
end

-- The run table (CSV) of an export text, as `node decoder/cli.mjs --runs` writes it. Returns the CSV
-- text or nil plus the error.
function M.runs(text)
	local out, err = run("decoder/cli.mjs --runs", text)
	if err:match("^ERROR:") or out == "" then
		return nil, (err:gsub("%s+$", ""))
	end
	return out
end

-- Parses JSON text into a Lua table through node (keeps the tests free of a Lua JSON decoder):
-- node prints the value as a Lua table constructor.
function M.parseJSON(text)
	local script = [[
const v = JSON.parse(require('fs').readFileSync(0, 'utf8'));
const lua = (x) => x === null ? 'nil' : Array.isArray(x) ? '{' + x.map(lua).join(',') + '}'
  : typeof x === 'object' ? '{' + Object.entries(x).map(([k, y]) => '[' + JSON.stringify(k) + ']=' + lua(y)).join(',') + '}'
  : typeof x === 'string' ? JSON.stringify(x) : String(x);
process.stdout.write('return ' + lua(v));
]]
	local out = run("-e " .. shellQuote(script), text)
	return assert(loadstring(out))()
end

return M
