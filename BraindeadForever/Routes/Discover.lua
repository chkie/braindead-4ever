--[[
Braindead Forever
Copyright (C) 2026 Braindead Forever contributors (see Git history)

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
-- SPDX-License-Identifier: GPL-3.0-or-later WITH AdditionRef-BraindeadForever-Ace3-Exception

-- Routes/Discover.lua: rules of the explorer mode (Welle 4, task 1). Pure Lua, no WoW API: which
-- discovery a player sees how, at which hint level. The module "explore" (Routes/Explore.lua) feeds
-- it with the catalog, the player's own finds and the finds of other players. Interface and rules:
-- docs/ROUTE-RUNTIME.md §Explorer mode.
--
-- Hint levels (ARBEITSPAKETE, Befund DR 21; brain chapter 20 §3.3):
--   0  only my own finds (default in explorer mode): nothing of the catalog or of other players
--   1  a sentence per find: the catalog as riddle (type, zone, part of the zone), finds of other
--      players as rumor (type and zone only)
--   2  the area: a circle of about 100 yards that holds the point, its centre moved away from it
--   3  the point (default in speed mode)
-- A player can ask for more on one find he already sees (level 2 or 3 for that find); without that
-- request no point is visible below level 3. There is never a count of what remains (chapter 20).
-- Sentences come only from the templates in Locales/ with values from the data (type, zone name from
-- the client, part of the zone from the coordinates): no free text, nothing invented.
local _, ns = ...

local D = {}
ns.Discover = D

-- Discovery types; the index is the code in the compiled catalog (tools/routekit/compiler.py FIND_CODE).
D.TYPES = { "quest", "treasure", "book", "rare", "flightpath", "place" }
D.CODE = {}
for code, name in ipairs(D.TYPES) do
	D.CODE[name] = code
end

-- Play styles of the first start (ENTWURF-LESUNG point 13): route mode and hint level.
D.STYLES = {
	arrow = { mode = "speed", level = 3 }, -- "follow the arrow": everything visible
	hints = { mode = "explorer", level = 1 }, -- "with hints"
	self = { mode = "explorer", level = 0 }, -- "discover myself"
}
D.STYLE_ORDER = { "arrow", "hints", "self" }
D.DEFAULT_LEVEL = { speed = 3, explorer = 0 }

-- Chosen values, not measured: radius of the area hint and the fallback radius in map units
-- (hundredths of a percent) when the client gives no map size; the centre moves up to half a radius.
D.AREA_YARDS = 100
D.AREA_MAP = 300
D.AREA_SHIFT = 0.5

function D.Key(kind, id)
	return kind .. ":" .. tostring(id)
end

-- Part of a zone from map coordinates (0..10000, x west to east, y north to south): thirds per axis.
local ROWS, COLS = { "n", "", "s" }, { "w", "", "e" }
function D.Part(x, y)
	local row = ROWS[math.min(3, math.floor(y * 3 / 10000) + 1)]
	local col = COLS[math.min(3, math.floor(x * 3 / 10000) + 1)]
	local part = row .. col
	return part == "" and "c" or part
end

-- Fills {name} placeholders; a template with a placeholder without value gives nil (never half a
-- sentence).
function D.Fill(template, values)
	if type(template) ~= "string" then
		return nil
	end
	local missing = false
	local text = template:gsub("{(%w+)}", function(k)
		local v = values[k]
		if v == nil then
			missing = true
			return ""
		end
		return tostring(v)
	end)
	if missing then
		return nil
	end
	return text
end

-- Level-1 sentence for a catalog find: template per type, zone name and part of the zone.
function D.Riddle(L, kind, zone, part)
	local where = D.Fill(L["WHERE_" .. part], { zone = zone })
	return where and D.Fill(L["RIDDLE_" .. kind], { where = where })
end

-- Level-1 sentence for a find of another player: type and zone, no part.
function D.Rumor(L, kind, zone)
	return D.Fill(L["RUMOR_" .. kind], { zone = zone })
end

local function hash(s)
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + s:byte(i)) % 2147483647
	end
	return h
end

local function clamp(v)
	return math.max(0, math.min(10000, v))
end

-- Area of level 2: a circle that holds the point (x, y in map units). The centre is moved by a stable
-- amount per find, so the circle does not tell the point. width, height: map size in yards or nil.
function D.Area(key, x, y, width, height)
	local rx, ry = D.AREA_MAP, D.AREA_MAP
	if width and width > 0 and height and height > 0 then
		rx, ry = D.AREA_YARDS / width * 10000, D.AREA_YARDS / height * 10000
	end
	local h = hash(key)
	local angle = (h % 360) * math.pi / 180
	local shift = D.AREA_SHIFT * ((math.floor(h / 360) % 1000) / 1000)
	return {
		x = math.floor(clamp(x + math.cos(angle) * shift * rx) + 0.5),
		y = math.floor(clamp(y + math.sin(angle) * shift * ry) + 0.5),
		rx = math.floor(rx + 0.5),
		ry = math.floor(ry + 0.5),
	}
end

-- How a find is shown: "point", "area", "riddle" (catalog), "rumor" (other players) or nil (hidden).
-- level: the player's hint level; asked: what he asked for on this find (2, 3 or nil); own: he found
-- it himself; source: "data" (catalog) or "players".
function D.View(level, asked, own, source)
	if own then
		return "point"
	end
	if not level or level <= 0 then
		return nil -- level 0: only own finds, also no request (the player cannot know the find)
	end
	local eff = math.max(level, asked or 0)
	if eff >= 3 then
		return "point"
	elseif eff == 2 then
		return "area"
	end
	return source == "data" and "riddle" or "rumor"
end
