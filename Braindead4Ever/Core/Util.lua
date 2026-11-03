--[[
Braindead 4ever
Copyright (C) 2026 Braindead 4ever contributors (see Git history)

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
-- SPDX-License-Identifier: GPL-3.0-or-later WITH AdditionRef-Braindead4Ever-Ace3-Exception

-- Core/Util.lua: small helpers shared by the collector, the exchange, the report and the probe.
-- Golden rule (JourneyProbe, Questie): every value that comes from the game goes through Num/Str
-- BEFORE it is compared, concatenated, indexed or used in math, because it may be a secret value.
local _, ns = ...

local U = {}
ns.Util = U

-- Slash subcommands registered by modules: ns.Commands[name] = fn(rest, cmd). Core/Boot.lua dispatches.
ns.Commands = ns.Commands or {}

local issecret = issecretvalue or function()
	return false
end

function U.IsSecret(v)
	return v ~= nil and issecret(v) == true
end

-- A usable number: not nil, not secret, not NaN.
function U.Num(v)
	if v ~= nil and not issecret(v) and type(v) == "number" and v == v then
		return v
	end
end

-- A usable, non-empty string.
function U.Str(v)
	if v ~= nil and not issecret(v) and type(v) == "string" and v ~= "" then
		return v
	end
end

function U.Pack(...)
	return { n = select("#", ...), ... }
end

-- "Creature-0-<server>-<instance>-<zone>-<npcID>-<spawn>" -> type name, id.
-- Same layout for GameObject and Vehicle. Player and Item GUIDs carry no object ID there.
function U.ParseGUID(guid)
	guid = U.Str(guid)
	if not guid then
		return
	end
	local kind, id = guid:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)")
	return kind or guid:match("^(%a+)%-"), tonumber(id)
end

-- GUID type -> one-letter kind. Players become "p" without an ID; pets are left out on purpose,
-- because a hunter pet belongs to a player (QuestieTrace Privacy.lua keeps only a positive list).
local KIND = { Creature = "c", Vehicle = "c", GameObject = "o", Item = "i", Player = "p" }
U.KIND = KIND

-- Unit token -> kind letter, ID. "npc" yields the GameObject GUID for quest boxes and wanted
-- posters even though UnitExists("npc") is false (Polestar Recorder.lua).
function U.Ref(unit)
	if type(UnitGUID) ~= "function" then
		return
	end
	local ok, guid = pcall(UnitGUID, unit)
	if not ok then
		return
	end
	local kind, id = U.ParseGUID(guid)
	local k = kind and KIND[kind]
	if k == "p" then
		return "p"
	end
	if k and id then
		return k, id
	end
end

-- Player position: uiMapID, x, y with x/y in hundredths of a percent (0..10000, about 0.3 yd in a zone).
-- Returns nothing in instances or when the client withholds the position.
function U.Pos()
	local map = U.Num(C_Map.GetBestMapForUnit("player"))
	if not map then
		return
	end
	local v = C_Map.GetPlayerMapPosition(map, "player")
	if not v then
		return map
	end
	local x, y = U.Num(v.x), U.Num(v.y)
	if not (x and y) then
		return map
	end
	return map, math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5)
end

-- Random ID from [0-9a-z]. Never derived from name, realm or account (JourneyTracker, Polestar).
local ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyz"
function U.NewId(n, random)
	random = random or math.random
	local out = {}
	for i = 1, n do
		local k = random(1, 36)
		out[i] = ALPHABET:sub(k, k)
	end
	return table.concat(out)
end

-- Deep copy of plain data (SavedVariables).
function U.Copy(t)
	local c = {}
	for k, v in pairs(t) do
		c[k] = type(v) == "table" and U.Copy(v) or v
	end
	return c
end
