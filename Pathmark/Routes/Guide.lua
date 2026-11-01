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

-- Routes/Guide.lua: module "route". Connects the route runtime (Runtime.lua) with the game: picks
-- the route for faction, race and class, feeds quest, level, zone and XP events in, saves progress
-- per character and offers the interface the step window (AP 6) will use. No frame, no text: the
-- window waits for the owner's design approval. Interface: docs/ROUTE-RUNTIME.md.
-- Quest events: abandon vs. turn-in after QUEST_REMOVED via the completion flag 1 s later, because
-- Forever sends QUEST_TURNED_IN late or not at all (brain chapter 06 §3, §4).
local _, ns = ...
local U, M, Guard = ns.Util, ns.Modules, ns.Guard
local R, RT = ns.Routes, ns.Runtime
local Num, Str = U.Num, U.Str

local Route = {
	MODES = { speed = true, explorer = true },
	EVENTS = { StepChanged = true, RouteRecalculated = true, XPBalance = true, QuestAbandoned = true },
	EVALUATE_DELAY = 0.1, -- quest events come in bursts; one evaluation per burst
	REMOVED_DELAY = 1, -- completion flag check after QUEST_REMOVED (Questie, chapter 06 §3)
	SAVE_FORMAT = 1,
}
ns.Route = Route

local LISTENER = "route-listener" -- errors of other modules' callbacks are recorded under this name
local api = {} -- optional client functions
local listeners = {} -- event -> { { owner, fn }, ... }
local rt, root -- runtime; PathmarkCharDB.route
local turnedIn = {} -- quests handed in this session (QUEST_TURNED_IN), the flag can lag behind
local levelSeen -- PLAYER_LEVEL_UP payload; UnitLevel can lag behind
local evalQueued, balanceQueued = false, false
local lastXP, lastMax

-- Callbacks -------------------------------------------------------------------------------------

-- fn(owner, ...) like Blizzard's CallbackRegistry. One callback per owner and event.
function Route.RegisterCallback(event, owner, fn)
	assert(Route.EVENTS[event], "unknown route event")
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

function Route.UnregisterCallback(event, owner)
	local list = listeners[event] or {}
	for i = #list, 1, -1 do
		if list[i].owner == owner then
			table.remove(list, i)
		end
	end
end

-- A failing listener is recorded in the error buffer and does not stop the others.
local function Fire(event, ...)
	for _, l in ipairs(listeners[event] or {}) do
		Guard.Call(LISTENER, l.fn, l.owner, ...)
	end
end

-- World: the client state the runtime reads. Every value goes through Num/Str (secret values).
local world = {
	IsFlagged = function(q)
		return turnedIn[q] == true or C_QuestLog.IsQuestFlaggedCompleted(q) == true
	end,
	InLog = function(q)
		return Num(C_QuestLog.GetLogIndexForQuestID(q)) ~= nil
	end,
	IsComplete = function(q)
		return C_QuestLog.IsComplete(q) == true
	end,
	Level = function()
		local level = Num(UnitLevel("player")) or 1
		return math.max(level, levelSeen or 0)
	end,
	Map = function()
		return Num(C_Map.GetBestMapForUnit("player"))
	end,
	MapParent = function(map)
		local info = api.GetMapInfo and api.GetMapInfo(map)
		return info and Num(info.parentMapID) or nil
	end,
	XP = function()
		local rested = api.GetXPExhaustion and Num(api.GetXPExhaustion()) or 0
		return Num(UnitXP("player")) or 0, Num(UnitXPMax("player")) or 0, rested
	end,
	-- GetQuestLogRewardXP is undocumented and may vanish (Polestar): optional, only for quests in the log.
	RewardXP = function(q)
		if not api.GetQuestLogRewardXP or Num(C_QuestLog.GetLogIndexForQuestID(q)) == nil then
			return nil
		end
		local ok, xp = pcall(api.GetQuestLogRewardXP, q)
		return ok and Num(xp) or nil
	end,
	ItemCount = function(item)
		return api.GetItemCount and Num(api.GetItemCount(item)) or 0
	end,
}
Route.world = world

-- Balance and evaluation, bundled per burst of events ---------------------------------------------

local function SendBalance()
	balanceQueued = false
	if rt then
		Fire("XPBalance", rt:Balance())
	end
end

local function QueueBalance()
	if balanceQueued then
		return
	end
	balanceQueued = true
	C_Timer.After(Route.EVALUATE_DELAY, Guard.Wrap("route", SendBalance))
end

local function Evaluate()
	evalQueued = false
	if rt then
		rt:Evaluate()
	end
end

local function QueueEvaluate()
	if evalQueued or not rt then
		return
	end
	evalQueued = true
	C_Timer.After(Route.EVALUATE_DELAY, Guard.Wrap("route", Evaluate))
end

local function OnRuntime(event, ...)
	if event == "StepChanged" then
		QueueBalance()
	end
	Fire(event, ...)
end

-- Saved state: PathmarkCharDB.route = { mode = "speed", speed = {...}, explorer = {...} }.
local function Root()
	if type(PathmarkCharDB) ~= "table" then
		PathmarkCharDB = {}
	end
	if type(PathmarkCharDB.route) ~= "table" then
		PathmarkCharDB.route = {}
	end
	return PathmarkCharDB.route
end

local function Build()
	rt, Route.missing = nil, nil
	root = Root()
	local mode = Route.MODES[root.mode] and root.mode or "speed"
	root.mode = mode
	local faction = Str((UnitFactionGroup("player")))
	local _, _, raceID = UnitRace("player")
	local _, _, classID = UnitClass("player")
	raceID, classID = Num(raceID), Num(classID)
	local steps = faction and raceID and classID and R.Steps(faction, mode, raceID, classID)
	if not steps then
		-- New race/class pairs are announced (brain chapter 14 §1): report, do not fail.
		Route.missing = ("no route for %s %s/%s"):format(tostring(faction), tostring(raceID), tostring(classID))
		Fire("RouteRecalculated", "missing")
		return
	end
	local data = R.Load(faction)
	R.Release()
	local saved = root[mode]
	if type(saved) ~= "table" or saved.v ~= Route.SAVE_FORMAT or saved.race ~= raceID or saved.class ~= classID then
		saved = { v = Route.SAVE_FORMAT, race = raceID, class = classID }
		root[mode] = saved
	end
	rt = RT.New(steps, data.quests, world, saved, { race = raceID, class = classID, modules = data.modules })
	rt.notify = OnRuntime
	Fire("RouteRecalculated", "start")
	rt:Evaluate()
	QueueBalance()
end

-- Public interface (docs/ROUTE-RUNTIME.md) --------------------------------------------------------

local function Call(fn, ...)
	if not rt or not M.IsActive("route") then
		return nil
	end
	return Guard.Call("route", fn, ...)
end

function Route.Current()
	return Call(function()
		return rt:Current()
	end)
end

function Route.Upcoming(n)
	return Call(function()
		return rt:Upcoming(n or 3)
	end) or {}
end

function Route.StepState(key)
	return Call(function()
		local i = rt.index[key]
		return i and rt:StepState(i) or nil
	end)
end

function Route.Check(key)
	return Call(rt and rt.Check, rt, key) == true
end

function Route.Skip(key)
	return Call(rt and rt.Skip, rt, key) == true
end

function Route.Back()
	return Call(rt and rt.Back, rt) == true
end

function Route.Undo()
	return Call(rt and rt.Undo, rt) == true
end

function Route.Pending()
	return rt and rt:Pending() or nil
end

function Route.ResolveAbandon(choice)
	return Call(rt and rt.ResolveAbandon, rt, choice) == true
end

function Route.Balance()
	return Call(function()
		return rt:Balance()
	end)
end

function Route.Mode()
	return root and root.mode or nil
end

function Route.SetMode(mode)
	if not Route.MODES[mode] or not M.IsActive("route") then
		return false
	end
	Root().mode = mode
	Guard.Call("route", Build)
	return rt ~= nil
end

-- Last XP gain seen (for the probe check xp.kill).
function Route.LastGain()
	return Route.lastGain
end

-- For diagnostics and tests: the runtime object, nil without a route.
function Route.Runtime()
	return rt
end

-- Current step for the problem report (Core/Report.lua).
ns.CurrentStep = function()
	local c = rt and rt:Current()
	return c and c.key or (rt and "end") or Route.missing
end

-- Events ----------------------------------------------------------------------------------------

local function Init()
	for name, path in pairs({
		GetQuestLogRewardXP = "GetQuestLogRewardXP",
		GetXPExhaustion = "GetXPExhaustion",
		GetMapInfo = "C_Map.GetMapInfo",
		GetItemCount = "C_Item.GetItemCount",
	}) do
		api[name] = M.Optional(path)
	end
	root = Root()
end

local function TrackXP()
	local xp, max = Num(UnitXP("player")), Num(UnitXPMax("player"))
	if xp and lastXP then
		local gain = xp - lastXP
		if gain < 0 then -- level-up between two updates: rest of the old level plus the new XP
			gain = (lastMax or lastXP) - lastXP + xp
		end
		if gain > 0 then
			Route.lastGain = { xp = gain, level = Num(UnitLevel("player")), at = GetTime() }
		end
	end
	lastXP, lastMax = xp, max
end

local events = {
	PLAYER_LOGIN = function()
		lastXP, lastMax = Num(UnitXP("player")), Num(UnitXPMax("player"))
		Build()
	end,
	PLAYER_LOGOUT = function()
		-- Write the live table back into whatever PathmarkCharDB holds now (Polestar trap, chapter 15).
		Root()
		if root then
			PathmarkCharDB.route = root
		end
	end,
	QUEST_ACCEPTED = function(_, _, questID)
		local q = Num(questID)
		if q and rt then
			rt:OnAccepted(q)
		end
		QueueEvaluate()
	end,
	QUEST_TURNED_IN = function(_, _, questID)
		local q = Num(questID)
		if q then
			turnedIn[q] = true
		end
		QueueEvaluate()
	end,
	QUEST_REMOVED = function(_, _, questID)
		local q = Num(questID)
		if not q then
			return
		end
		C_Timer.After(
			Route.REMOVED_DELAY,
			Guard.Wrap("route", function()
				if rt and not world.IsFlagged(q) and not world.InLog(q) then
					rt:OnAbandoned(q)
				end
				QueueEvaluate()
			end)
		)
	end,
	QUEST_LOG_UPDATE = QueueEvaluate,
	QUEST_WATCH_UPDATE = QueueEvaluate,
	-- Forever duel and emote quests progress only with this event and QUEST_LOG_UPDATE (Questie).
	QUEST_LOG_CRITERIA_UPDATE = QueueEvaluate,
	UNIT_QUEST_LOG_CHANGED = function(_, _, unit)
		if unit == "player" then
			QueueEvaluate()
		end
	end,
	ZONE_CHANGED_NEW_AREA = QueueEvaluate,
	BAG_UPDATE_DELAYED = QueueEvaluate,
	PLAYER_LEVEL_UP = function(_, _, level)
		levelSeen = Num(level)
		QueueEvaluate()
		QueueBalance()
	end,
	PLAYER_XP_UPDATE = function(_, _, unit)
		if unit ~= "player" then
			return
		end
		TrackXP()
		QueueBalance()
	end,
	UPDATE_EXHAUSTION = QueueBalance,
	UI_INFO_MESSAGE = function(_, _, _, message)
		if rt and Str(message) and message == ERR_NEWTAXIPATH then
			rt:MarkEvent(R.VERB.FP)
		end
	end,
	HEARTHSTONE_BOUND = function()
		if rt then
			rt:MarkEvent(R.VERB.SETHOME)
		end
	end,
}

M.Define("route", {
	core = true,
	requires = {
		funcs = {
			"C_QuestLog.IsQuestFlaggedCompleted",
			"C_QuestLog.GetLogIndexForQuestID",
			"C_QuestLog.IsComplete",
			"C_Map.GetBestMapForUnit",
			"UnitLevel",
			"UnitRace",
			"UnitClass",
			"UnitFactionGroup",
			"UnitXP",
			"UnitXPMax",
		},
		events = { "PLAYER_LOGIN", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_LOG_UPDATE" },
	},
	optional = {
		funcs = { "GetQuestLogRewardXP", "GetXPExhaustion", "C_Map.GetMapInfo", "C_Item.GetItemCount" },
		events = {
			"PLAYER_LOGOUT",
			"QUEST_TURNED_IN",
			"QUEST_WATCH_UPDATE",
			"QUEST_LOG_CRITERIA_UPDATE",
			"UNIT_QUEST_LOG_CHANGED",
			"ZONE_CHANGED_NEW_AREA",
			"BAG_UPDATE_DELAYED",
			"PLAYER_LEVEL_UP",
			"PLAYER_XP_UPDATE",
			"UPDATE_EXHAUSTION",
			"UI_INFO_MESSAGE",
			"HEARTHSTONE_BOUND",
		},
	},
	init = Init,
	events = events,
})
