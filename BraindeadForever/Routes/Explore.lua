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

-- Routes/Explore.lua: module "explore" (Welle 4, task 1). Keeps the player's own finds, the finds other
-- players shared through the exchange and the catalog of the route data, and shows each of them as the
-- hint level allows (rules: Routes/Discover.lua). No frame, no text of its own: the window (Welle 5)
-- reads ns.Explore. Interface: docs/ROUTE-RUNTIME.md §Explorer mode.
-- Saved: BraindeadForeverCharDB.explore = { level, style, found = { [key] = "map;x;y" }, asked = { [key] = n } }
-- per character; BraindeadForeverDB.explore = { heard = { [key] = "map;x;y;reports" } } for the account.
-- Sources: catalog = foreign data (FD-1101, unbestätigt); a report of another player is a measurement
-- in the game: one report alone stays unconfirmed, a second independent player confirms it (exchange,
-- rx2), and a report on a catalog find confirms the catalog value and replaces its position.
local _, ns = ...
local L = ns.L
local U, M, Guard, R, D = ns.Util, ns.Modules, ns.Guard, ns.Routes, ns.Discover
local Num, Str = U.Num, U.Str

local E = {
	EVENTS = { FindsChanged = true },
}
ns.Explore = E

local LISTENER = "explore-listener"
local api = {}
local listeners = {}
local char, acct -- BraindeadForeverCharDB.explore, BraindeadForeverDB.explore
local catalog -- key -> { kind, id, map, pts = { { x, y }, ... } }; built on first use
local data -- route data of the player's faction
local classic -- set of the Classic quest IDs of the data

function E.RegisterCallback(event, owner, fn)
	assert(E.EVENTS[event], "unknown explore event")
	assert(owner ~= nil and type(fn) == "function", "owner and function required")
	local list = listeners[event] or {}
	listeners[event] = list
	for _, l in ipairs(list) do
		if l.owner == owner then
			l.fn = fn
			return
		end
	end
	list[#list + 1] = { owner = owner, fn = fn }
end

function E.UnregisterCallback(event, owner)
	local list = listeners[event] or {}
	for i = #list, 1, -1 do
		if list[i].owner == owner then
			table.remove(list, i)
		end
	end
end

local function Fire(event, ...)
	for _, l in ipairs(listeners[event] or {}) do
		Guard.Call(LISTENER, l.fn, l.owner, ...)
	end
end

local function Char()
	if type(BraindeadForeverCharDB) ~= "table" then
		BraindeadForeverCharDB = {}
	end
	local c = BraindeadForeverCharDB.explore
	if type(c) ~= "table" then
		c = {}
		BraindeadForeverCharDB.explore = c
	end
	c.found = type(c.found) == "table" and c.found or {}
	c.asked = type(c.asked) == "table" and c.asked or {}
	char = c
	return c
end

local function Acct()
	local db = ns.db or (type(BraindeadForeverDB) == "table" and BraindeadForeverDB) or {}
	local a = type(db.explore) == "table" and db.explore or {}
	db.explore = a
	a.heard = type(a.heard) == "table" and a.heard or {}
	acct = a
	return a
end

-- Route data of the player's faction; not cached before the client knows the faction (before login).
local function Data()
	if data == nil then
		local faction = Str((UnitFactionGroup("player")))
		if not faction then
			return nil
		end
		data = R.Load(faction) or false
	end
	return data or nil
end

local function Catalog()
	if catalog then
		return catalog
	end
	local d = Data()
	if not d then
		return {}
	end
	catalog = {}
	for _, f in ipairs(d.finds or {}) do
		local kind = D.TYPES[f[1]]
		if kind then
			local pts = {}
			for i = 4, #f - 1, 2 do
				pts[#pts + 1] = { f[i], f[i + 1] }
			end
			catalog[D.Key(kind, f[2])] = { kind = kind, id = f[2], map = f[3], pts = pts }
		end
	end
	return catalog
end

-- Quest IDs the route data knows: route quests, dungeon quests and Classic quests are no discoveries.
local function KnownQuest(q)
	local d = Data()
	if not d then
		return true
	end
	if (d.quests and d.quests[q]) or (d.dquests and d.dquests[q]) then
		return true
	end
	if not classic then
		classic = {}
		for _, c in ipairs(d.classic or {}) do
			classic[c] = true
		end
	end
	return classic[q] == true
end

-- A message kind of the exchange (Collector/Proto.lua) as discovery: kind, id, map, x, y or nil.
-- Looted objects count only when the catalog knows them as treasure or book: ore and herbs are no
-- discoveries, and an unknown object cannot be told apart from them yet.
local function Classify(kind, f)
	if kind == "q" then
		if not KnownQuest(f[1]) then
			return "quest", f[1], f[4], f[5], f[6]
		end
	elseif kind == "o" then
		local cat = Catalog()
		for _, k in ipairs({ "treasure", "book" }) do
			if cat[D.Key(k, f[1])] then
				return k, f[1], f[2], f[3], f[4]
			end
		end
	elseif kind == "b" then
		return "book", f[1], f[2], f[3], f[4]
	elseif kind == "r" then
		return "rare", f[1], f[3], f[4], f[5]
	elseif kind == "f" then
		return "flightpath", f[2], f[3], f[4], f[5]
	end
end

local function Pos(s)
	local map, x, y, n = (s or ""):match("^(%d+);(%d+);(%d+);?(%d*)$")
	return tonumber(map), tonumber(x), tonumber(y), tonumber(n)
end

-- Own discovery, from the collector (same fields as an exchange message). True when it is new.
function E.Own(kind, ...)
	if not M.IsActive("explore") or not char then
		return false
	end
	local t, id, map, x, y = Classify(kind, { ... })
	if not t or not (map and x and y) then
		return false
	end
	local key = D.Key(t, id)
	if char.found[key] then
		return false
	end
	char.found[key] = ("%d;%d;%d"):format(map, x, y)
	Fire("FindsChanged", key)
	return true
end

-- Find of another player (Collector/Exchange.lua): first report, or confirmed by a second player.
function E.Heard(find, confirmed)
	if not M.IsActive("explore") or not acct then
		return false
	end
	local t, id, map, x, y = Classify(find.kind, find)
	if not t or not (map and x and y) then
		return false
	end
	local key = D.Key(t, id)
	local _, _, _, n = Pos(acct.heard[key])
	n = math.min(2, math.max(n or 0, confirmed and 2 or 1))
	local value = ("%d;%d;%d;%d"):format(map, x, y, n)
	if acct.heard[key] == value then
		return false
	end
	acct.heard[key] = value
	Fire("FindsChanged", key)
	return true
end

-- Hint level 0..3: chosen by the player, else the default of the route mode.
function E.Level()
	local c = char or Char()
	local level = Num(c.level)
	if level and level >= 0 and level <= 3 then
		return level
	end
	local mode = ns.Route and ns.Route.Mode and ns.Route.Mode() or "speed"
	return D.DEFAULT_LEVEL[mode] or 3
end

function E.SetLevel(level)
	level = Num(level)
	if not level or level ~= math.floor(level) or level < 0 or level > 3 then
		return false
	end
	Char().level = level
	Fire("FindsChanged")
	return true
end

-- The three play styles in the order of the first-start question: { key, mode, level }.
function E.Styles()
	local out = {}
	for i, key in ipairs(D.STYLE_ORDER) do
		local s = D.STYLES[key]
		out[i] = { key = key, mode = s.mode, level = s.level }
	end
	return out
end

-- Chosen play style or nil (first start: not asked yet).
function E.Style()
	return (char or Char()).style
end

-- Sets route mode and hint level of a play style. The level stays a slider of its own afterwards.
function E.SetStyle(key)
	local s = D.STYLES[key]
	if not s then
		return false
	end
	local c = Char()
	c.style, c.level = key, s.level
	if ns.Route and ns.Route.Mode and ns.Route.Mode() ~= s.mode then
		ns.Route.SetMode(s.mode)
	end
	Fire("FindsChanged")
	return true
end

local function ZoneName(map)
	local info = api.GetMapInfo and api.GetMapInfo(map)
	return info and Str(info.name) or nil
end

local function Size(map)
	if not api.GetMapWorldSize then
		return nil
	end
	local ok, w, h = pcall(api.GetMapWorldSize, map)
	if ok then
		return Num(w), Num(h)
	end
end

-- Merged view of one key: own find, reports of other players, catalog entry.
local function Entry(key, level)
	local cat = Catalog()[key]
	local own = char.found[key]
	local heard = acct.heard[key]
	local kind, id = key:match("^(%a+):(%d+)$")
	local map, x, y, n, source, status, pts
	if own then
		map, x, y = Pos(own)
		source, status = "own", "own"
	elseif heard then
		map, x, y, n = Pos(heard)
		source = "players"
		status = ((n or 1) >= 2 or cat) and "confirmed" or "unconfirmed"
	elseif cat then
		map, x, y = cat.map, cat.pts[1][1], cat.pts[1][2]
		source, status, pts = "data", "unconfirmed", cat.pts
	else
		return nil
	end
	local show = D.View(level, char.asked[key], own ~= nil, source)
	if not show then
		return nil
	end
	local e = { key = key, kind = kind, id = tonumber(id), map = map, source = source, status = status, show = show }
	if show == "point" then
		e.points = pts or { { x, y } }
	elseif show == "area" then
		e.area = D.Area(key, x, y, Size(map))
	else
		local zone = ZoneName(map)
		e.part = show == "riddle" and D.Part(x, y) or nil
		e.text = zone and (show == "riddle" and D.Riddle(L, kind, zone, e.part) or D.Rumor(L, kind, zone)) or nil
	end
	return e
end

-- Visible finds, on one map or everywhere: list of entries (docs/ROUTE-RUNTIME.md §Explorer mode),
-- sorted by key. Never a count of the hidden ones.
function E.List(map)
	if not M.IsActive("explore") or not char then
		return {}
	end
	local level, keys = E.Level(), {}
	for key in pairs(Catalog()) do
		keys[key] = true
	end
	for key in pairs(acct.heard) do
		keys[key] = true
	end
	for key in pairs(char.found) do
		keys[key] = true
	end
	local out = {}
	for key in pairs(keys) do
		local e = Entry(key, level)
		if e and (not map or e.map == map) then
			out[#out + 1] = e
		end
	end
	table.sort(out, function(a, b)
		return a.key < b.key
	end)
	return out
end

-- The player asks for more on one find he sees (2 = area, 3 = point). Only a find shown to him can be
-- asked for: at level 0 there is none.
function E.Ask(key, level)
	if not M.IsActive("explore") or not char or (level ~= 2 and level ~= 3) then
		return false
	end
	if not Entry(key, E.Level()) then
		return false
	end
	char.asked[key] = math.max(char.asked[key] or 0, level)
	Fire("FindsChanged", key)
	return true
end

local function Init()
	for name, path in pairs({ GetMapInfo = "C_Map.GetMapInfo", GetMapWorldSize = "C_Map.GetMapWorldSize" }) do
		api[name] = M.Optional(path)
	end
	Char()
	Acct()
end

M.Define("explore", {
	requires = { funcs = { "UnitFactionGroup" }, events = { "PLAYER_LOGIN" } },
	optional = { funcs = { "C_Map.GetMapInfo", "C_Map.GetMapWorldSize" }, events = { "PLAYER_LOGOUT" } },
	init = Init,
	events = {
		PLAYER_LOGIN = function()
			Char()
			Acct()
		end,
		-- Write the live tables back into whatever the globals hold now (Polestar trap, chapter 15).
		PLAYER_LOGOUT = function()
			if char then
				if type(BraindeadForeverCharDB) ~= "table" then
					BraindeadForeverCharDB = {}
				end
				BraindeadForeverCharDB.explore = char
			end
			if acct and type(BraindeadForeverDB) == "table" then
				BraindeadForeverDB.explore = acct
			end
		end,
	},
})
