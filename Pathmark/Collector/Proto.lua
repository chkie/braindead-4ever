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

-- Collector/Proto.lua: the in-game exchange protocol. Plain Lua, no WoW API.
-- A message carries one find as printable ASCII with IDs and numbers only: no names, no localized
-- text (players run different client languages), no NUL, at most 255 bytes.
--   <kind>;<proto>;<field>;<field>...
-- Kinds and fields (x, y in hundredths of a percent of the map, 0..10000):
--   q  quest start   questID, giverKind, giverID, map, x, y
--   t  quest turn-in questID, giverKind, giverID, map, x, y
--   o  looted object objectID, map, x, y          (chests, ore, herbs, glittering book objects)
--   b  readable obj. objectID, map, x, y
--   r  rare enemy    npcID, class, map, x, y      (class r = rare, e = rare elite, w = world boss)
--   f  flight master npcID, nodeID, map, x, y
--   v  vignette      vignetteID, map, x, y
--   p  prerequisite observation (Routes/Prereq.lua): token, questID, link (quest turned in directly
--      before at the giver, 0 = none), unlock (0/1), done IDs, missing IDs (lists of at most 10
--      quest IDs separated by ".", may be empty). No position: it says nothing about where a player is.
-- giverKind: c = creature, o = game object, i = item, n = none (giverID 0).
-- Readers skip unknown kinds and other protocol versions without counting them as broken, so a
-- newer addon version can add kinds without muting older ones.
local _, ns = ...

local Proto = {}
ns.Proto = Proto

Proto.PREFIX = "Pathmark" -- at most 16 characters
Proto.VERSION = 1

local GIVER = { c = true, o = true, i = true, n = true }
local CLASS = { r = true, e = true, w = true }

-- Field types: "id" 1..9999999, "gid" 0..9999999, "map" 1..999999, "xy" 0..10000, "giver", "class",
-- "tok" six characters [0-9a-z], "flag" 0 or 1, "ids" up to 10 IDs joined by "." (may be empty)
local KINDS = {
	q = { "id", "giver", "gid", "map", "xy", "xy" },
	t = { "id", "giver", "gid", "map", "xy", "xy" },
	o = { "id", "map", "xy", "xy" },
	b = { "id", "map", "xy", "xy" },
	r = { "id", "class", "map", "xy", "xy" },
	f = { "id", "id", "map", "xy", "xy" },
	v = { "id", "map", "xy", "xy" },
	p = { "tok", "id", "gid", "flag", "ids", "ids" },
}
Proto.KINDS = KINDS

local IDS_MAX = 10

local function Valid(ftype, v)
	if ftype == "giver" then
		return GIVER[v] == true
	elseif ftype == "class" then
		return CLASS[v] == true
	elseif ftype == "tok" then
		return type(v) == "string" and v:match("^[0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z]$") ~= nil
	elseif ftype == "ids" then
		if v == "" then
			return true
		end
		if type(v) ~= "string" or not v:match("^%d+[%d%.]*$") or v:find("..", 1, true) or v:sub(-1) == "." then
			return false
		end
		local n = 0
		for x in v:gmatch("%d+") do
			n = n + 1
			local id = tonumber(x)
			if n > IDS_MAX or id < 1 or id > 9999999 then
				return false
			end
		end
		return true
	elseif ftype == "flag" then
		return v == 0 or v == 1 or v == "0" or v == "1"
	end
	local n = type(v) == "number" and v or (type(v) == "string" and v:match("^%d+$") and tonumber(v))
	if not n or n ~= math.floor(n) then
		return false
	end
	if ftype == "id" then
		return n >= 1 and n <= 9999999
	elseif ftype == "gid" then
		return n >= 0 and n <= 9999999
	elseif ftype == "map" then
		return n >= 1 and n <= 999999
	elseif ftype == "xy" then
		return n >= 0 and n <= 10000
	end
	return false
end

-- Map kind of the rare classification as returned by UnitClassification.
Proto.CLASS_OF = { rare = "r", rareelite = "e", worldboss = "w" }

-- Build a message. Returns nil when a field is missing or out of range (nothing half-valid is sent).
function Proto.Format(kind, ...)
	local spec = KINDS[kind]
	if not spec or select("#", ...) ~= #spec then
		return nil
	end
	local parts = { kind, tostring(Proto.VERSION) }
	for i = 1, #spec do
		local v = select(i, ...)
		if not Valid(spec[i], v) then
			return nil
		end
		parts[#parts + 1] = tostring(v)
	end
	local msg = table.concat(parts, ";")
	if #msg > 255 then
		return nil
	end
	return msg
end

-- Parse a message. Returns { kind = "q", ... fields as numbers or letters } or nil plus
-- "skip" (unknown kind or other protocol version, not an error) or "bad" (broken message).
function Proto.Parse(msg)
	if type(msg) ~= "string" or #msg > 255 then
		return nil, "bad"
	end
	local kind, proto, rest = msg:match("^(%a);(%d+);(.*)$")
	if not kind then
		return nil, "bad"
	end
	if tonumber(proto) ~= Proto.VERSION then
		return nil, "skip"
	end
	local spec = KINDS[kind]
	if not spec then
		return nil, "skip"
	end
	local find, i = { kind = kind }, 0
	for part in (rest .. ";"):gmatch("([^;]*);") do
		i = i + 1
		local ftype = spec[i]
		if not ftype or not Valid(ftype, part) then
			return nil, "bad"
		end
		find[i] = (ftype == "giver" or ftype == "class" or ftype == "tok" or ftype == "ids") and part or tonumber(part)
	end
	if i ~= #spec then
		return nil, "bad"
	end
	find.n = i
	return find
end

-- Dedup key of a find: what it is and roughly where (1 % grid of the map), so two players who report
-- the same chest a few steps apart count as the same find. Quest givers and flight masters do not move.
function Proto.Key(find)
	local k = find.kind
	if k == "q" or k == "t" then
		return table.concat({ k, find[1], find[2], find[3], find[4] }, ";")
	elseif k == "p" then
		return table.concat({ k, find[2], find[1] }, ";")
	elseif k == "f" then
		return table.concat({ k, find[1], find[2] }, ";")
	end
	local n = find.n or #KINDS[k]
	local x, y, map = find[n - 1], find[n], find[n - 2]
	local parts = { k }
	for i = 1, n - 3 do
		parts[#parts + 1] = find[i]
	end
	parts[#parts + 1] = map
	parts[#parts + 1] = math.floor(x / 100)
	parts[#parts + 1] = math.floor(y / 100)
	return table.concat(parts, ";")
end
