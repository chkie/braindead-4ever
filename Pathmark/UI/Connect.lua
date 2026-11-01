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

-- UI/Connect.lua: the only place where the interface reads the logic. Every window asks this adapter,
-- never ns.Route or the discovery logic directly, so a change of either interface lands here.
--   * Route logic (docs/ROUTE-RUNTIME.md, ns.Route): steps, check, skip, back, undo, abandon question,
--     XP balance, mode.
--   * Discovery logic of Welle 4 (ns.Explore, docs/ROUTE-RUNTIME.md §Explorer mode) and the dungeon hint
--     (Route.DungeonHint): rumor line, revealed find, map items per hint level, hint level, optional
--     dungeon step. Without them these return nothing and the windows show nothing for them.
-- A different source can be set (C.Use), so the developer preview and the tests render the real
-- windows with fixed content.
local _, ns = ...
local UI = ns.UI

local C = {}
ns.Connect = C

-- Play styles of the setup and the settings (owner reading point 13): route mode and start hint level.
C.STYLES = {
	arrow = { mode = "speed", hint = 3 },
	hints = { mode = "explorer", hint = 1 },
	self = { mode = "explorer", hint = 0 },
}
C.STYLE_ORDER = { "arrow", "hints", "self" }

local source -- nil = ns.Route
local findsGen = 0 -- counts changes of finds, hint level and style; the riddle is looked up after one

function C.Use(src)
	source = src
	findsGen = findsGen + 1
end

local function R()
	return source or ns.Route
end

local function call(name, ...)
	local r = R()
	local fn = r and r[name]
	if type(fn) == "function" then
		return fn(...)
	end
end

-- Discovery logic of Welle 4 (ns.Explore), optional.
local function X(name, ...)
	local e = ns.Explore
	local fn = e and e[name]
	if type(fn) == "function" then
		return fn(...)
	end
end

-- Route ---------------------------------------------------------------------------------------------

function C.Current()
	return call("Current")
end

function C.Upcoming(n)
	if n <= 0 then
		return {}
	end
	return call("Upcoming", n) or {}
end

function C.StepState(key)
	return call("StepState", key)
end

function C.Balance()
	return call("Balance")
end

-- Time forecast (docs/ROUTE-RUNTIME.md §Time forecast), or nil.
function C.Forecast()
	return call("Forecast")
end

function C.Pending()
	return call("Pending")
end

function C.Check(key)
	return call("Check", key) == true
end

function C.Skip(key)
	return call("Skip", key) == true
end

function C.Back()
	return call("Back") == true
end

function C.Undo()
	return call("Undo") == true
end

function C.ResolveAbandon(choice)
	return call("ResolveAbandon", choice) == true
end

-- Follow-up quests a skip would take with it (list of quest IDs), or nil.
function C.SkipPreview(key)
	return call("SkipPreview", key)
end

function C.AbandonPreview()
	return call("AbandonPreview")
end

function C.LastAction()
	return call("LastAction")
end

function C.Mode()
	return call("Mode")
end

function C.SetMode(mode)
	return call("SetMode", mode) == true
end

-- Quests the route follows (set of quest IDs, skipped ones and their follow-ups left out).
function C.RouteQuests()
	return call("Quests") or {}
end

-- Why there is no route (race without start module), or nil.
function C.Missing()
	local r = R()
	return r and r.missing
end

-- Compiled module of a step (read only): label, sources, own runs.
function C.Module(key)
	return call("Module", key)
end

-- Number of own measured runs of a module; the route data carries none yet (0 until AP 10).
function C.Runs(key)
	local m = C.Module(key)
	return m and tonumber(m.runs) or 0
end

-- Quest title from the source, if it brings its own (developer preview); nil = ask the client.
function C.Title(q)
	local r = source
	return r and type(r.Title) == "function" and r.Title(q) or nil
end

function C.Register(event, owner, fn)
	local r = R()
	if r and r.RegisterCallback then
		r.RegisterCallback(event, owner, fn)
	end
end

-- Play style ------------------------------------------------------------------------------------------

-- Sets the style and puts the hint level to the style's start value; the route follows at once.
function C.SetStyle(style)
	local s = C.STYLES[style]
	if not s then
		return false
	end
	UI.Set("style", style)
	if UI.Get("hint") ~= s.hint then
		UI.Set("hint", s.hint)
	end
	C.ApplyStyle()
	return true
end

-- Route mode of the chosen style for this character. Only after the setup, so a first login does not
-- switch the route before the player chose.
function C.ApplyStyle()
	if not UI.DB().setupDone then
		return false
	end
	local style = UI.Get("style")
	local s = C.STYLES[style]
	if not s then
		return false
	end
	if ns.Explore and X("Style") ~= style then
		X("SetStyle", style) -- sets route mode and the style's level
	end
	local level = style == "arrow" and 3 or UI.Get("hint") -- "just follow the arrow" shows everything
	if ns.Explore and X("Level") ~= level then
		X("SetLevel", level)
	end
	if C.Mode() and C.Mode() ~= s.mode then
		return C.SetMode(s.mode)
	end
	return false
end

-- Discovery and dungeon hint (Welle 4, docs/ROUTE-RUNTIME.md §Explorer mode, §Dungeon hint) ---------
-- The settings page keeps play style and hint level account-wide (PathmarkDB.ui); ns.Explore keeps them
-- per character. The adapter hands every change and, at login, the account values to ns.Explore.

function C.HintLevel()
	if UI.Get("style") == "arrow" then
		return 3 -- "just follow the arrow" shows everything
	end
	local v = X("Level")
	if v == nil then
		v = UI.Get("hint")
	end
	return v
end

function C.SetHintLevel(n)
	UI.Set("hint", math.max(0, math.min(3, math.floor(tonumber(n) or 1))))
end

-- The discovery logic follows every change of the hint level, wherever it comes from.
UI.OnChange("hint", C, function(_, _, value)
	findsGen = findsGen + 1
	if X("Level") ~= value then
		X("SetLevel", value)
	end
end)

-- A style chosen on the settings page: hint level to the style's start value, route mode follows.
UI.OnChange("style", C, function(_, _, value)
	findsGen = findsGen + 1
	local s = C.STYLES[value]
	if s and UI.Get("hint") ~= s.hint then
		UI.Set("hint", s.hint)
	end
	C.ApplyStyle()
end)

-- Rumors (hint level 1, finds of other players): the newest one arrives with FindsChanged(key); the
-- step window shows it once, then it is used up.
local rumor -- { id = key, text, map }
local seen = {}

local function Entry(key)
	for _, e in ipairs(X("List") or {}) do
		if e.key == key then
			return e
		end
	end
end

function C.OnFindsChanged(_, key)
	findsGen = findsGen + 1
	if not key or seen[key] then
		return
	end
	local e = Entry(key)
	if e and e.show == "rumor" and e.text then
		rumor = { id = key, text = e.text, map = e.map }
	end
end

-- Newest unseen rumor { id, text, map } or nil; never with "just follow the arrow".
function C.Rumor()
	if UI.Get("style") == "arrow" then
		return nil
	end
	if source and type(source.Rumor) == "function" then
		return source.Rumor()
	end
	return rumor
end

-- Subscribes a window to new finds (rumors, own finds, requests); fn(owner, key?).
function C.OnFinds(owner, fn)
	local e = ns.Explore
	if e and type(e.RegisterCallback) == "function" then
		e.RegisterCallback("FindsChanged", owner, function(o, key)
			C.OnFindsChanged(o, key)
			fn(o, key)
		end)
	end
end

-- The rumor went by (shown and the next step done): it does not come again.
function C.RumorDone(id)
	if id then
		seen[id] = true
	end
	if rumor and (not id or rumor.id == id) then
		rumor = nil
	end
end

-- "Show location": asks the discovery logic for the point of this one find and returns a target
-- { map, wx, wy, title } for pin and arrow, or nil.
function C.Reveal(id)
	if not X("Ask", id, 3) then
		return nil
	end
	local e = Entry(id)
	local p = e and e.show == "point" and e.points and e.points[1]
	if not p then
		return nil
	end
	local t = ns.Nav.FromMap(e.map, p[1] / 10000, p[2] / 10000)
	if t then
		t.title = ns.L["FIND_" .. tostring(e.kind)] or ""
	end
	return t
end

-- Riddles (hint level 1, catalog finds): one sentence for the zone the player is in, shown as its own
-- line in the step window; it goes after the next completed step and the next riddle of the zone
-- follows (Welle 5b). Never with "just follow the arrow" (level 3 shows the points).
local riddleSeen = {}
local riddleCache = {} -- map, gen, value: the step window asks on every quest log update

local function Finds(map)
	if source and type(source.Finds) == "function" then
		return source.Finds(map) or {}
	end
	return X("List", map) or {}
end

-- First riddle { id, text } of the player's zone not used up yet, or nil.
function C.Riddle()
	if UI.Get("style") == "arrow" then
		return nil
	end
	if source and type(source.Riddle) == "function" then
		return source.Riddle()
	end
	local map = ns.Util.Num(C_Map.GetBestMapForUnit("player"))
	if not map then
		return nil
	end
	local cache = riddleCache
	if cache.map == map and cache.gen == findsGen then
		return cache.value
	end
	local value
	for _, e in ipairs(Finds(map)) do
		if e.show == "riddle" and e.text and not riddleSeen[e.key] then
			value = { id = e.key, text = e.text }
			break
		end
	end
	cache.map, cache.gen, cache.value = map, findsGen, value
	return value
end

function C.RiddleDone(id)
	if id then
		riddleSeen[id] = true
	end
	findsGen = findsGen + 1
end

-- Map items for one shown map (x, y, rx, ry 0..1): { kind = "own" | "point", x, y, title } and, at hint
-- level 2, { kind = "area", x, y, rx, ry, title, text }: the circle that holds a find (Welle 5b).
function C.MapItems(map)
	local out = {}
	for _, e in ipairs(Finds(map)) do
		if e.show == "area" and e.area then
			out[#out + 1] = {
				kind = "area",
				x = e.area.x / 10000,
				y = e.area.y / 10000,
				rx = e.area.rx / 10000,
				ry = e.area.ry / 10000,
				title = ns.L.TT_AREA,
				text = ns.L["AREA_" .. tostring(e.kind)],
			}
		elseif e.show == "point" then
			for _, p in ipairs(e.points or {}) do
				out[#out + 1] = {
					kind = e.source == "own" and "own" or "point",
					x = p[1] / 10000,
					y = p[2] / 10000,
					title = ns.L["FIND_" .. tostring(e.kind)],
				}
			end
		end
	end
	return out
end

-- Dungeon hint (owner wish 11): the first dungeon that fits now, or nil. Shown as an optional step.
function C.Dungeon()
	local list = call("DungeonHint")
	return type(list) == "table" and list[1] or nil
end

function C.SkipDungeon(id)
	return call("SkipDungeon", id) == true
end

-- Newer addon version seen (version notice, concept §1.5), or nil.
function C.NewerVersion()
	return ns.newerVersion
end
