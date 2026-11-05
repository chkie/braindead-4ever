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

-- UI/NpcNames.lua: module "npcnames" (M4), the quest giver and the turn-in NPC in the step texts
-- ("Accept “X” from <name>"). Which NPC gives or takes a quest comes from the facts as NPC IDs
-- (Routes/Data_Npcs.lua, docs/ROUTE-FORMAT.md §NPCs of the step texts); the name always comes from the
-- client in the player's language: from the client's creature cache through the tooltip data of a unit
-- link (brain chapter 13 §4, probe check name.npctooltip) or learned when the player meets the NPC
-- (UnitName at the quest dialog, gossip or target, probe check name.npc). Learned names are kept per
-- client language in BraindeadForeverDB.npcNames[locale], and only the client's language is read, so a
-- name of another language never shows. Without a name the step reads as before.
-- Cost: lookups go through a table per NPC; the client is asked at most once per NPC until the current
-- step changes, never per frame. Unit identity can be secret (brain chapter 05 §8): every value passes
-- U.Str or U.Ref, which drop secrets.
local _, ns = ...
local U, M, Guard = ns.Util, ns.Modules, ns.Guard

local N = {
	LINK = "unit:Creature-0-0-0-0-%d-0000000000", -- the probe's link (Probe/Checks.lua name.npctooltip)
	MAX_SAVED = 5000, -- names kept per language: more than the givers and turn-ins of both factions
}
ns.NpcNames = N

local facts -- [questID] = { giver, sources, turn-in, sources, status } of the played faction
local needed -- [npcID] = true for every giver and turn-in of the played faction
local cache = {} -- [npcID] = name, or false while the client did not know it
local demo -- developer preview: { giver = { [questID] = name }, turnin = { ... } }

-- Facts of the played faction, built on first use (the faction is known after login) and the builder
-- functions dropped, like Routes.Release.
local function Facts()
	if facts then
		return facts
	end
	local faction = U.Str((UnitFactionGroup("player")))
	local build = ns.NpcFacts and faction and ns.NpcFacts[faction]
	if type(build) ~= "function" then
		return nil
	end
	facts, needed = build(), {}
	for _, f in pairs(facts) do
		if f[1] > 0 then
			needed[f[1]] = true
		end
		if f[3] > 0 then
			needed[f[3]] = true
		end
	end
	ns.NpcFacts = nil
	return facts
end
N.Facts = Facts

-- Learned names of the client's language; never the table of another language.
function N.Saved()
	local db = ns.db
	if not db then
		return nil
	end
	if type(db.npcNames) ~= "table" then
		db.npcNames = {}
	end
	local locale = U.Str(GetLocale()) or "enUS"
	local t = db.npcNames[locale]
	if type(t) ~= "table" then
		t = { n = 0 }
		db.npcNames[locale] = t
	end
	return t
end

local function Keep(id, name)
	local t = N.Saved()
	if not t or t[id] == name then
		return
	end
	if t[id] == nil then
		if (tonumber(t.n) or 0) >= N.MAX_SAVED then
			return
		end
		t.n = (tonumber(t.n) or 0) + 1
	end
	t[id] = name
end

-- Placeholders the client shows while it has no data are no names.
local function Real(name)
	if not name or name == RETRIEVING_DATA or name == UNKNOWNOBJECT or name == UNKNOWN then
		return nil
	end
	return name
end

-- The client's creature cache through the tooltip data of a unit link. MayReturnNothing; a secret or
-- forbidden table raises inside the pcall and counts as "not known".
function N.FromClient(id)
	local get = C_TooltipInfo and C_TooltipInfo.GetHyperlink
	if type(get) ~= "function" then
		return nil
	end
	local ok, name = pcall(function()
		local data = get(N.LINK:format(id))
		local lines = type(data) == "table" and data.lines
		local first = type(lines) == "table" and lines[1]
		return type(first) == "table" and U.Str(first.leftText) or nil
	end)
	return ok and Real(name) or nil
end

-- Name of an NPC in the client's language, or nil. Learned names first, then the client's cache.
function N.Name(id)
	if not id or id <= 0 then
		return nil
	end
	local c = cache[id]
	if c ~= nil then
		return c or nil
	end
	local saved = N.Saved()
	local name = saved and Real(U.Str(saved[id]))
	if not name then
		name = N.FromClient(id)
		if name then
			Keep(id, name)
		end
	end
	cache[id] = name or false
	return name
end

local function Lookup(kind, at, q)
	if not M.IsActive("npcnames") or not q then
		return nil
	end
	if demo then
		return demo[kind] and demo[kind][q] or nil
	end
	local f = Facts()
	f = f and f[q]
	return f and N.Name(f[at]) or nil
end

-- Name of the quest giver of a quest, or nil.
function N.Giver(q)
	return Lookup("giver", 1, q)
end

-- NPC ID of the single quest giver of a quest (Routes/Data_Npcs.lua), or nil. Not tied to the module
-- state: the route uses it to see whether an NPC that lists its quests is the giver (Route.Offers).
function N.GiverID(q)
	local f = q and Facts()
	f = f and f[q]
	return f and f[1] and f[1] > 0 and f[1] or nil
end

-- Name of the NPC that takes the quest, or nil.
function N.TurnIn(q)
	return Lookup("turnin", 3, q)
end

-- The player meets an NPC (dialog or target): its name is learned when it gives or takes a quest of
-- the faction. A new name redraws the step window once.
function N.Learn(unit)
	local k, id = U.Ref(unit)
	if k ~= "c" or not id then
		return false
	end
	Facts()
	if not (needed and needed[id]) then
		return false
	end
	local name = Real(U.Str((UnitName(unit))))
	if not name or cache[id] == name then
		return false
	end
	cache[id] = name
	Keep(id, name)
	local sf = ns.StepFrame
	if sf and sf.Queue and M.IsActive("window") then
		sf.Queue()
	end
	return true
end

-- A new current step asks the client again for the NPCs it did not know (it may have seen them since).
function N.Retry()
	for id, name in pairs(cache) do
		if name == false then
			cache[id] = nil
		end
	end
end

-- Developer preview (Probe/Preview.lua): names for demo quests, nil ends it.
function N.SetDemo(t)
	demo = t
end

local function Dialog()
	N.Learn("npc")
end

local function Init()
	cache, demo = {}, nil
	ns.Connect.Register("StepChanged", N, N.Retry)
	ns.Connect.Register("RouteRecalculated", N, N.Retry)
end

M.Define("npcnames", {
	requires = {
		funcs = { "C_TooltipInfo.GetHyperlink", "UnitName", "UnitGUID", "UnitFactionGroup", "GetLocale" },
		events = { "QUEST_DETAIL", "GOSSIP_SHOW", "PLAYER_TARGET_CHANGED" },
	},
	optional = {
		events = { "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_GREETING" },
	},
	init = Init,
	disable = function()
		cache = {}
		local sf = ns.StepFrame
		if sf and sf.Queue and M.IsActive("window") then
			Guard.Call("window", sf.Queue)
		end
	end,
	events = {
		QUEST_DETAIL = Dialog,
		QUEST_PROGRESS = Dialog,
		QUEST_COMPLETE = Dialog,
		QUEST_GREETING = Dialog,
		GOSSIP_SHOW = Dialog,
		PLAYER_TARGET_CHANGED = function()
			N.Learn("target")
		end,
	},
})
