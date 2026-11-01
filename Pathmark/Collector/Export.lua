--[[
Pathmark
Copyright (C) 2026 Pathmark contributors (see Git history)

This program is free software: you can redistribute it and/or modify it under the
terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

Additional permission under GNU GPL version 3 section 7

If you modify this Program, or any covered work, by linking or combining it with
the Ace3 libraries (or a modified version of that library), containing parts
covered by the terms of the Ace3 license, the licensors of this Program grant you
additional permission to convey the resulting work. Corresponding Source for a
non-source form of such a combination shall include the source code for the parts
of the Ace3 libraries used as well as that of the covered work.
]]
-- SPDX-License-Identifier: GPL-3.0-or-later WITH AdditionRef-Pathmark-Ace3-Exception

-- Collector/Export.lua: build and check the export text. Encoding goes through C_EncodingUtil in the game;
-- frame and checksum are plain Lua 5.1, so the tests check the frame without the game.
-- Format:  PM1:<m>:<length>:<adler32-hex>:<base64(compressed(json))>
--   PM1      format and version, visible without decoding
--   m        d = Enum.CompressionMethod.Deflate (raw DEFLATE, RFC 1951, browser "deflate-raw"; proven by
--               QuestieTrace exports), z = Enum.CompressionMethod.Zlib (RFC 1950, browser "deflate";
--               only after the probe check enc.zlib passed in the client)
--   length   length of the Base64 part: a truncated paste shows up at once
--   adler32  over the Base64 part: a changed character shows up before decompressing
local _, ns = ...

local Export = {}
ns.Export = Export

Export.PREFIX = "PM1"

-- Adler-32 (RFC 1950) without bit operators; the modulo per byte keeps the numbers small.
-- One loop pass per character: only run on demand.
function Export.Adler32(s)
	local a, b, byte = 1, 0, string.byte
	for i = 1, #s do
		a = (a + byte(s, i)) % 65521
		b = (b + a) % 65521
	end
	return string.format("%04x%04x", b, a)
end

-- codec: { m = "d" | "z", json = fn(tbl) -> str, zip = fn(str) -> str | nil, b64 = fn(str) -> str | nil }
-- In the game Export.GameCodec(m); in tests stand-ins.
function Export.GameCodec(m)
	local E, CM = C_EncodingUtil, Enum.CompressionMethod
	local method = (m == "z") and CM.Zlib or CM.Deflate
	return {
		m = (m == "z") and "z" or "d",
		json = function(t)
			return E.SerializeJSON(t)
		end,
		zip = function(s)
			return E.CompressString(s, method, Enum.CompressionLevel.OptimizeForSize)
		end,
		b64 = function(s)
			return E.EncodeBase64(s, Enum.Base64Variant.Standard)
		end,
	}
end

local function Encode(payload, codec)
	local json = codec.json(payload)
	local zipped = json and codec.zip(json) -- MayReturnNothing: catch nil
	return zipped and codec.b64(zipped)
end

-- Returns the export text or nil plus the reason.
function Export.Build(payload, codec)
	local ok, text = pcall(Encode, payload, codec)
	if not ok then
		return nil, "encode: " .. tostring(text)
	end
	if type(text) ~= "string" or text == "" then
		return nil, "encode: empty"
	end
	return table.concat({ Export.PREFIX, codec.m, #text, Export.Adler32(text), text }, ":")
end

-- Read a frame, check length and checksum. Line breaks from copying are ignored.
-- Returns the Base64 part and the method, or nil plus the reason.
function Export.Parse(s)
	if type(s) ~= "string" then
		return nil, "no text"
	end
	s = s:gsub("%s+", "")
	local prefix, m, len, sum, body = s:match("^(%w+):([dz]):(%d+):(%x+):(.*)$")
	if prefix ~= Export.PREFIX then
		return nil, "not a " .. Export.PREFIX .. " export"
	end
	if #body ~= tonumber(len) then
		return nil, ("truncated: %d of %s characters"):format(#body, len)
	end
	if Export.Adler32(body) ~= sum:lower() then
		return nil, "checksum mismatch"
	end
	return body, m
end
