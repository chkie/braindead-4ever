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

-- UI/StepText.lua: the words of the step window, built from step info (docs/ROUTE-RUNTIME.md) and the
-- client. Quest, item and zone names come from the client in the player's language (concept §2.10);
-- names are never stored. Steps in the infinitive (plan §Sprache Nr. 4). Pure text, no frames.
local _, ns = ...
local L, U, R = ns.L, ns.Util, ns.Routes
local V = R.VERB
local Num, Str = U.Num, U.Str

local ST = {}
ns.StepText = ST

-- Index of the sources bit field per verb (docs/ROUTE-FORMAT.md §Compiled form); status follows it.
local SRC_AT =
	{ [1] = 3, [2] = 3, [3] = 3, [4] = 4, [5] = 6, [6] = 4, [7] = 2, [8] = 2, [9] = 2, [10] = 2, [11] = 3, [12] = 3 }
ST.SRC_AT = SRC_AT
-- Order in texts: as named in the design ("ATT, EG Link und Polestar forever-db").
local SOURCE_ORDER = { "att", "eglink", "polestar", "own", "plan" }
local SOURCE_KEY =
	{ polestar = "SRC_POLESTAR", att = "SRC_ATT", eglink = "SRC_EGLINK", own = "SRC_OWN", plan = "SRC_PLAN" }

local function bit(v, b)
	return v % (b * 2) >= b
end

-- Quoted quest title; asks the client to load it when it is not cached yet.
function ST.Quest(q)
	local title = ns.Connect.Title(q) or (C_QuestLog.GetTitleForQuestID and Str(C_QuestLog.GetTitleForQuestID(q)))
	if not title then
		if C_QuestLog.RequestLoadQuestByID then
			C_QuestLog.RequestLoadQuestByID(q)
		end
		title = L.QUEST_FALLBACK:format(q)
	end
	return L.QUOTE:format(title)
end

function ST.MapName(map)
	local info = map and C_Map.GetMapInfo(map)
	return info and Str(info.name) or nil
end

-- Area name (dungeons): C_Map.GetAreaInfo(areaID) -> name.
function ST.Area(area)
	return area and C_Map.GetAreaInfo and Str(C_Map.GetAreaInfo(area)) or nil
end

function ST.Item(id)
	local name = C_Item.GetItemNameByID and Str(C_Item.GetItemNameByID(id))
	return name or L.ITEM_FALLBACK:format(id)
end

-- First open objective of a quest in the log: text without the counter, done, needed.
function ST.Objective(q)
	if not q or not Num(C_QuestLog.GetLogIndexForQuestID(q)) then
		return nil
	end
	local objs = C_QuestLog.GetQuestObjectives(q)
	if type(objs) ~= "table" or #objs == 0 then
		return nil
	end
	local pick = objs[#objs]
	for _, o in ipairs(objs) do
		if not o.finished then
			pick = o
			break
		end
	end
	local text = Str(pick.text)
	if text then
		text = text:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub("[:%s]*%d+%s*/%s*%d+%s*$", "")
		if text == "" then
			text = nil
		end
	end
	return text, Num(pick.numFulfilled), Num(pick.numRequired), pick.finished == true
end

-- Zone of a step: target of its travel, else the map of its goto.
function ST.ZoneMap(info)
	local step = info and info.step
	if not step then
		return nil
	end
	local map
	for _, el in ipairs(step) do
		if el[1] == V.TRAVEL then
			return el[3]
		elseif el[1] == V.GOTO then
			map = el[2]
		end
	end
	return map
end

local TRAVEL_KEY = {
	"TRAVEL_WALK",
	"TRAVEL_FLY",
	"TRAVEL_BOAT",
	"TRAVEL_ZEPPELIN",
	"TRAVEL_AIRSHIP",
	"TRAVEL_TRAM",
	"TRAVEL_PORTAL",
	"TRAVEL_HEARTH",
}

local function Phrase(el, withObjective)
	local v = el[1]
	if v == V.ACCEPT then
		return L.STEP_ACCEPT:format(ST.Quest(el[2]))
	elseif v == V.COMPLETE then
		local text, have, need = nil, nil, nil
		if withObjective then
			text, have, need = ST.Objective(el[2])
		end
		if text then
			return L.STEP_OBJECTIVE:format(ST.Quest(el[2]), text), have, need, el[2]
		end
		return L.STEP_COMPLETE:format(ST.Quest(el[2])), nil, nil, el[2]
	elseif v == V.TURNIN then
		return L.STEP_TURNIN:format(ST.Quest(el[2]))
	elseif v == V.COLLECT then
		return L.STEP_COLLECT:format(el[3], ST.Item(el[2]))
	elseif v == V.TRAVEL then
		return L[TRAVEL_KEY[el[2]] or "TRAVEL_WALK"]:format(ST.MapName(el[3]) or L.ZONE_FALLBACK)
	elseif v == V.HS then
		return L.STEP_HS
	elseif v == V.SETHOME then
		return L.STEP_SETHOME
	elseif v == V.FP then
		return L.STEP_FP
	elseif v == V.TRAIN then
		return L.STEP_TRAIN
	elseif v == V.XP then
		return L.STEP_XP:format(el[2])
	elseif v == V.NOTE then
		return Str(el[2])
	end
end

-- Text of a step and the counter of its first open objective: text, done, needed, questID.
function ST.Step(info, withObjective)
	local step = info and info.step
	if not step then
		return ""
	end
	local parts, have, need, quest = {}, nil, nil, nil
	for _, el in ipairs(step) do
		local text, h, n, q = Phrase(el, withObjective)
		if text then
			parts[#parts + 1] = text
			if n and not need then
				have, need, quest = h, n, q
			end
		end
	end
	if #parts == 0 then
		parts[1] = L.STEP_GOTO
	end
	return table.concat(parts, L.JOIN), have, need, quest
end

-- "Elwynn Forest • 4/48"; the word "step" is in the tooltip.
function ST.Header(info)
	local zone = ST.MapName(ST.ZoneMap(info)) or ST.MapName(Num(C_Map.GetBestMapForUnit("player"))) or ""
	if not info then
		return zone
	end
	return L.HEADER:format(zone, info.index, info.total)
end

-- "Wolves in the fields • 42 yd": place (zone of the target) and distance.
function ST.Detail(target, dist)
	local place = target and ST.MapName(target.map)
	if place and dist then
		return L.DETAIL:format(place, ns.Theme.Distance(dist))
	end
	return place or ""
end

local function SourceNames(bits)
	local names = {}
	for _, key in ipairs(SOURCE_ORDER) do
		if bit(bits, R.SOURCE[key]) then
			names[#names + 1] = L[SOURCE_KEY[key]]
		end
	end
	return names
end

-- "A, B and C"
function ST.List(names)
	if #names <= 1 then
		return names[1] or ""
	end
	return table.concat(names, ", ", 1, #names - 1) .. L.LIST_AND .. names[#names]
end

local EL_LABEL = {
	[V.ACCEPT] = "TT_GIVER",
	[V.COMPLETE] = "TT_OBJECTIVE",
	[V.TURNIN] = "TT_TURNIN",
	[V.COLLECT] = "TT_ITEM",
	[V.GOTO] = "TT_PLACE",
	[V.TRAVEL] = "TT_TRAVEL",
	[V.XP] = "TT_LEVEL",
}

-- Origin tooltip of a step: title, lines (concept §2.2: source and status of each value).
function ST.Origin(info)
	local step = info.step or {}
	local title
	for _, el in ipairs(step) do
		if el[1] == V.ACCEPT or el[1] == V.COMPLETE or el[1] == V.TURNIN then
			title = ST.Quest(el[2])
			break
		end
	end
	local lines, seen = {}, {}
	for _, el in ipairs(step) do
		local at = SRC_AT[el[1]]
		local bits, status = at and el[at], at and el[at + 1]
		if type(bits) == "number" then
			local label = L[EL_LABEL[el[1]] or "TT_HINT"]
			local line = L.TT_LINE:format(
				label,
				ST.List(SourceNames(bits)),
				status == R.STATUS.CONFIRMED and L.ST_CONFIRMED or L.ST_UNCONFIRMED
			)
			if not seen[line] then
				seen[line] = true
				lines[#lines + 1] = line
			end
		end
	end
	return title or ST.Step(info, false), L.TT_STEP:format(info.index, info.total), lines
end

-- "Provisional" tooltip of a module: own runs and the union of its sources.
function ST.Provisional(module, runs)
	local bits = 0
	for _, step in ipairs(module and module.steps or {}) do
		for _, el in ipairs(step) do
			local at = SRC_AT[el[1]]
			local b = at and el[at]
			if type(b) == "number" then
				for _, key in ipairs(SOURCE_ORDER) do
					local v = R.SOURCE[key]
					if bit(b, v) and not bit(bits, v) then
						bits = bits + v
					end
				end
			end
		end
	end
	return L.PROV_TEXT:format(runs or 0, ST.List(SourceNames(bits)))
end

-- XP line: "Level 3 • 620 XP to go • this step +260 XP"; numbers in white.
function ST.XP(b)
	if not b then
		return nil
	end
	local W = function(v)
		return ns.Theme.Wrap(HIGHLIGHT_FONT_COLOR, v)
	end
	local word = XP or "XP"
	local parts = { L.XP_LEVEL:format(W(b.level)) }
	if not b.stopped then
		parts[#parts + 1] = L.XP_TOGO:format(W(ns.Theme.Number(b.toLevel)), word)
		local s = b.step
		if s and s.xp and s.xp > 0 then
			local n = ns.Theme.Number(s.xp)
			if s.source ~= "log" then
				n = L.ABOUT:format(n)
			end
			parts[#parts + 1] = L.XP_STEP:format(W(n), word)
		end
	end
	return table.concat(parts, L.SEP)
end

-- "1 h 25 min", "25 min", "under 1 min".
function ST.Duration(seconds)
	local m = math.floor((tonumber(seconds) or 0) / 60 + 0.5)
	if m < 1 then
		return L.TIME_LESS
	elseif m < 60 then
		return L.TIME_M:format(m)
	end
	return L.TIME_HM:format(math.floor(m / 60), m % 60)
end

-- Tooltip of the XP line (Welle 5b, owner guideline 7 and wish 13): planned level of this step against
-- the character's level, then the time forecast. Values only from data; a part without enough real runs
-- says "collecting data". Returns title and a list of { text, gold } lines.
function ST.XPTip(info, b, f)
	local lines = {}
	local function add(text, gold)
		lines[#lines + 1] = { text = text, gold = gold }
	end
	local level = b and b.level
	if info and info.lv then
		add(L.TT_PLAN_LEVEL:format(info.lv))
		if level then
			local d = level - info.lv
			local dev = d == 0 and L.DEV_ON
				or d == 1 and L.DEV_ABOVE_1
				or d > 1 and L.DEV_ABOVE_N:format(d)
				or d == -1 and L.DEV_BELOW_1
				or L.DEV_BELOW_N:format(-d)
			add(L.TT_OWN_LEVEL:format(level, dev))
		end
	end
	if f and f.state ~= "done" then
		add(L.TT_FORECAST, true)
		if f.state == "ready" and f.seconds then
			local dur = ST.Duration(f.seconds)
			add(f.level and L.TT_ROUTE_END:format(f.level, dur) or L.TT_ROUTE_END_WAIT:format(dur))
			local delta = f.plan and f.plan.delta
			if delta and math.abs(delta) >= 60 then
				add((delta > 0 and L.TT_AHEAD or L.TT_BEHIND):format(ST.Duration(math.abs(delta))))
			end
		else
			add(L.TT_ROUTE_END_WAIT:format(L.STATUS_COLLECTING))
		end
		local n = f.nextLevel
		if n and level and b and not b.stopped then
			if n.state == "ready" and n.seconds then
				add(L.TT_NEXT_LEVEL:format(level + 1, ST.Duration(n.seconds), ns.Theme.Number(n.perHour or 0)))
			else
				add(L.TT_NEXT_LEVEL_WAIT:format(level + 1, L.STATUS_COLLECTING))
			end
		end
	end
	return L.TT_XP_TITLE, lines
end

-- "The route falls short of Westfall …" when the route to the next zone does not reach its level.
function ST.Reach(b)
	local z = b and b.zone
	if not z or z.enough ~= false or not z.shortfall or z.shortfall <= 0 then
		return nil
	end
	return L.REACH:format(
		ST.MapName(z.nextMap) or L.ZONE_FALLBACK,
		ns.Theme.Number(z.shortfall),
		ns.Theme.Number(z.kills or 0),
		tostring(b.level)
	)
end

-- Right-click menu: "Undo: checked off “Wolves …”".
function ST.Undo(act)
	if not act then
		return L.UNDO
	end
	local fmt = L["ACT_" .. tostring(act.kind)]
	if act.kind == "unknown" or not fmt or fmt == "ACT_" .. tostring(act.kind) then
		return L.UNDO
	end
	if act.kind == "back" then
		return L.UNDO_ACTION:format(fmt)
	end
	return L.UNDO_ACTION:format(fmt:format(act.quest and ST.Quest(act.quest) or ""))
end
