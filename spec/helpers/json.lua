-- SPDX-License-Identifier: GPL-3.0-or-later
-- Minimal JSON encoder and Base64 for tests (stand-ins for C_EncodingUtil.SerializeJSON and
-- EncodeBase64/DecodeBase64). Arrays are tables with keys 1..n only; everything else is an object
-- with sorted keys, so the output is stable.
local M = {}

local ESC =
	{ ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function str(s)
	return '"' .. s:gsub('[%c"\\]', function(c)
		return ESC[c] or ("\\u%04x"):format(c:byte())
	end) .. '"'
end

local function isArray(t)
	local n = 0
	for k in pairs(t) do
		if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
			return false
		end
		n = n + 1
	end
	for i = 1, n do
		if t[i] == nil then
			return false
		end
	end
	return true
end

function M.encode(v)
	local t = type(v)
	if t == "nil" then
		return "null"
	elseif t == "boolean" then
		return v and "true" or "false"
	elseif t == "number" then
		if v == math.floor(v) then
			return ("%d"):format(v)
		end
		return ("%.14g"):format(v)
	elseif t == "string" then
		return str(v)
	elseif t == "table" then
		local parts = {}
		if isArray(v) and next(v) ~= nil then
			for i = 1, #v do
				parts[i] = M.encode(v[i])
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		if next(v) == nil then
			return "[]" -- like an empty Lua table in CBOR/JSON of the client: ambiguous, arrays win
		end
		local keys = {}
		for k in pairs(v) do
			keys[#keys + 1] = tostring(k)
		end
		table.sort(keys)
		for _, k in ipairs(keys) do
			local value = v[k]
			if value == nil then
				value = v[tonumber(k)]
			end
			parts[#parts + 1] = str(k) .. ":" .. M.encode(value)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	error("cannot encode " .. t)
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function M.b64encode(s)
	local out = {}
	for i = 1, #s, 3 do
		local a, b, c = s:byte(i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local c1 = math.floor(n / 262144) % 64
		local c2 = math.floor(n / 4096) % 64
		local c3 = math.floor(n / 64) % 64
		local c4 = n % 64
		out[#out + 1] = B64:sub(c1 + 1, c1 + 1)
			.. B64:sub(c2 + 1, c2 + 1)
			.. (b and B64:sub(c3 + 1, c3 + 1) or "=")
			.. (c and B64:sub(c4 + 1, c4 + 1) or "=")
	end
	return table.concat(out)
end

function M.b64decode(s)
	s = s:gsub("[^%w%+/=]", "")
	local out = {}
	for i = 1, #s, 4 do
		local n, pad = 0, 0
		for j = 0, 3 do
			local ch = s:sub(i + j, i + j)
			local v = 0
			if ch == "=" or ch == "" then
				pad = pad + 1
			else
				v = B64:find(ch, 1, true) - 1
			end
			n = n * 64 + v
		end
		local bytes = string.char(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
		out[#out + 1] = bytes:sub(1, 3 - pad)
	end
	return table.concat(out)
end

-- Small JSON reader for test fixtures (objects, arrays, strings without escapes beyond \" and \\,
-- numbers, true, false, null).
function M.decode(s)
	local pos = 1
	local value
	local function ws()
		pos = s:find("[^%s]", pos) or #s + 1
	end
	local function str_()
		local out, i = {}, pos + 1
		while true do
			local c = s:sub(i, i)
			if c == '"' then
				pos = i + 1
				return table.concat(out)
			elseif c == "\\" then
				out[#out + 1] = s:sub(i + 1, i + 1)
				i = i + 2
			elseif c == "" then
				error("unterminated string")
			else
				out[#out + 1] = c
				i = i + 1
			end
		end
	end
	function value()
		ws()
		local c = s:sub(pos, pos)
		if c == "{" then
			local t = {}
			pos = pos + 1
			ws()
			if s:sub(pos, pos) == "}" then
				pos = pos + 1
				return t
			end
			while true do
				ws()
				local k = str_()
				ws()
				pos = pos + 1 -- ':'
				t[k] = value()
				ws()
				local d = s:sub(pos, pos)
				pos = pos + 1
				if d == "}" then
					return t
				end
			end
		elseif c == "[" then
			local t = {}
			pos = pos + 1
			ws()
			if s:sub(pos, pos) == "]" then
				pos = pos + 1
				return t
			end
			while true do
				t[#t + 1] = value()
				ws()
				local d = s:sub(pos, pos)
				pos = pos + 1
				if d == "]" then
					return t
				end
			end
		elseif c == '"' then
			return str_()
		elseif s:sub(pos, pos + 3) == "true" then
			pos = pos + 4
			return true
		elseif s:sub(pos, pos + 4) == "false" then
			pos = pos + 5
			return false
		elseif s:sub(pos, pos + 3) == "null" then
			pos = pos + 4
			return nil
		end
		local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
		pos = pos + #num
		return tonumber(num)
	end
	return value()
end

return M
