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

-- UI/QuestWatch.lua: module "questwatch", the option "Blizzard's quest tracker" (owner reading point
-- 15, Welle 5b task 8): unchanged | only the quests of the route | hidden (default since Welle 5c, owner
-- reading 16: while Braindead 4ever guides, the step window takes the tracker's place).
--   * Before the first change the check marks (watch list) of the character are saved; "unchanged",
--     the guidance pause, a module turned off and every logout put them back. The logout covers an
--     addon switched off in the AddOns list: the next session without Braindead 4ever finds the old marks.
--   * A check mark the player sets himself stays, one he removes stays removed (also after a pause).
--     Blizzard sets marks on its own after an accept and on progress (Blizzard_ObjectiveTracker.lua,
--     QuestMapFrame.lua, CVar autoQuestWatch); such a mark is not the player's.
--   * "Hidden" sets the tracker's alpha to 0 and leaves the marks alone: the minimap draws quest areas
--     only for marked quests (report in #bug-reports, 2026-11-08); marks changed under "only the route"
--     come back first. Hide() is not used: Blizzard's container shows itself again whenever a module
--     has content (Blizzard_ObjectiveTrackerContainer.lua) and a Hide from addon code runs its
--     managed-frame layout tainted (RealUI tracker rewrite 2026-10-05).
--   * Every call waits for the end of a fight (UI.OutOfCombat). Whether the calls from addon code cause
--     taint is unconfirmed (docs/TESTING-RETAIL.md, taintLog 2); a blocked action reported for Braindead 4ever
--     during a call turns only this module off.
-- Saved per character: BraindeadForeverCharDB.watch = { saved = { questID, ... } or nil, kept = { [q] = true },
-- dropped = { [q] = true } }.
local ADDON, ns = ...
local L, UI, C = ns.L, ns.UI, ns.Connect
local M, Guard, U = ns.Modules, ns.Guard, ns.Util

local QW = {
	MODES = { "keep", "route", "hide" },
	DELAY = 0.2, -- bursts of quest events become one pass
	AUTO = 2, -- seconds after QUEST_ACCEPTED or QUEST_WATCH_UPDATE in which a new mark is Blizzard's
	MAX = 25, -- MAX_QUEST_WATCHES (QuestConstantsDocumentation.lua) when the client has no constant
}
ns.QuestWatch = QW

local state -- BraindeadForeverCharDB.watch
local auto = {} -- questID -> GetTime() of its last accept or progress
local last -- watch set after the last pass, nil while nothing is managed
local busy = false -- true while Braindead 4ever's own call runs
local lastCall = -math.huge -- GetTime() of Braindead 4ever's last own call
local queued = false

local function Char()
	if type(BraindeadForeverCharDB) ~= "table" then
		BraindeadForeverCharDB = {}
	end
	local w = BraindeadForeverCharDB.watch
	if type(w) ~= "table" then
		w = {}
		BraindeadForeverCharDB.watch = w
	end
	w.kept = type(w.kept) == "table" and w.kept or {}
	w.dropped = type(w.dropped) == "table" and w.dropped or {}
	if type(w.saved) ~= "table" then
		w.saved = nil
	end
	state = w
	return w
end

local function InLog(q)
	return U.Num(C_QuestLog.GetLogIndexForQuestID(q)) ~= nil
end

local function Max()
	local c = type(Constants) == "table" and Constants.QuestWatchConsts
	return c and tonumber(c.MAX_QUEST_WATCHES) or QW.MAX
end

-- The watch list in order and as a set.
function QW.Watched()
	local list, set = {}, {}
	for i = 1, U.Num(C_QuestLog.GetNumQuestWatches()) or 0 do
		local q = U.Num(C_QuestLog.GetQuestIDForQuestWatchIndex(i))
		if q and not set[q] then
			list[#list + 1] = q
			set[q] = true
		end
	end
	return list, set
end

local function Own(fn, q)
	busy, lastCall = true, GetTime()
	local ok, r = pcall(fn, q)
	busy = false
	if not ok then
		error(r, 0)
	end
	return r == true
end

-- What the option asks for now: "keep" also before the first start, while paused, without a route.
function QW.Mode()
	local m = UI.Get("tracker")
	if m ~= "route" and m ~= "hide" then
		return "keep"
	end
	if UI.Paused() or not UI.DB().setupDone then
		return "keep"
	end
	if m == "route" and (C.Missing() or next(C.RouteQuests()) == nil) then
		return "keep" -- no route: nothing to follow, the player's marks stay
	end
	return m
end

-- Player changes since the last pass. A new mark Blizzard did not set itself is the player's; a mark
-- gone from a quest still in the log was removed by him.
local function Notice(set)
	if not last then
		return
	end
	local now = GetTime()
	for q in pairs(set) do
		if not last[q] and not (auto[q] and now - auto[q] <= QW.AUTO) then
			state.kept[q], state.dropped[q] = true, nil
		end
	end
	for q in pairs(last) do
		if not set[q] and InLog(q) then
			state.dropped[q], state.kept[q] = true, nil
		end
	end
end

-- Marks of quests that left the log are forgotten.
local function Prune()
	for _, t in ipairs({ state.kept, state.dropped }) do
		for q in pairs(t) do
			if not InLog(q) then
				t[q] = nil
			end
		end
	end
end

-- Alpha of Blizzard's tracker: 0 for "hidden", the old value back otherwise.
function QW.SetTracker(hide)
	local f = ObjectiveTrackerFrame
	if not (f and f.SetAlpha) then
		return
	end
	if hide and not QW.hidden then
		local a = f.GetAlpha and f:GetAlpha()
		QW.alpha = (type(a) == "number" and not U.IsSecret(a)) and a or 1
		f:SetAlpha(0)
		QW.hidden = true
	elseif not hide and QW.hidden then
		f:SetAlpha(QW.alpha or 1)
		QW.hidden = nil
	end
end

-- The old marks back: the saved list without what the player removed, plus what he set himself.
function QW.Restore()
	QW.SetTracker(false)
	if not (state and state.saved) then
		last = nil
		return false
	end
	local list, set = QW.Watched()
	Notice(set)
	local target = {}
	for _, q in ipairs(state.saved) do
		if not state.dropped[q] then
			target[q] = true
		end
	end
	for q in pairs(state.kept) do
		target[q] = true
	end
	for _, q in ipairs(list) do
		if not target[q] then
			Own(C_QuestLog.RemoveQuestWatch, q)
		end
	end
	local n = #QW.Watched()
	for _, q in ipairs(state.saved) do
		if target[q] and not set[q] and InLog(q) and n < Max() and Own(C_QuestLog.AddQuestWatch, q) then
			n = n + 1
		end
	end
	state.saved, last = nil, nil
	Prune()
	return true
end

-- One pass: save the marks once, then only the route's quests plus the player's own.
function QW.Apply()
	if not (state and M.IsActive("questwatch")) then
		return
	end
	local mode = QW.Mode()
	if mode == "keep" then
		QW.Restore()
		return
	end
	if mode == "hide" then
		-- only the tracker goes: the marks stay, the game keeps setting its own, and the quest areas
		-- on the minimap follow them (report in #bug-reports, 2026-11-08)
		QW.Restore()
		QW.SetTracker(true)
		return
	end
	local list, set = QW.Watched()
	if state.saved then
		Notice(set)
	else
		state.saved = list
	end
	local wanted = {}
	if mode == "route" then
		for q in pairs(C.RouteQuests()) do
			if InLog(q) then
				wanted[q] = true
			end
		end
	end
	for _, q in ipairs(list) do
		if not wanted[q] and not state.kept[q] then
			Own(C_QuestLog.RemoveQuestWatch, q)
		end
	end
	local adds = {}
	for q in pairs(wanted) do
		if not set[q] and not state.dropped[q] then
			adds[#adds + 1] = q
		end
	end
	table.sort(adds)
	local n = #QW.Watched()
	for _, q in ipairs(adds) do
		if n >= Max() then
			break
		end
		if Own(C_QuestLog.AddQuestWatch, q) then
			n = n + 1
		end
	end
	QW.SetTracker(mode == "hide")
	Prune()
	local _, now = QW.Watched()
	last = now
end

local function Run()
	Guard.Call("questwatch", QW.Apply)
end

-- After a burst of events, and never in a fight.
function QW.Queue()
	if queued or not M.IsActive("questwatch") then
		return
	end
	queued = true
	C_Timer.After(QW.DELAY, function()
		queued = false
		UI.OutOfCombat("questwatch", Run)
	end)
end

-- For tests and the problem report.
function QW.State()
	return state, last
end

local function Init()
	Char()
	for _, key in ipairs({ "tracker", "paused", "style" }) do
		UI.OnChange(key, QW, QW.Queue)
	end
	C.Register("StepChanged", QW, QW.Queue)
	C.Register("RouteRecalculated", QW, QW.Queue)
end

M.Define("questwatch", {
	requires = {
		funcs = {
			"C_QuestLog.AddQuestWatch",
			"C_QuestLog.RemoveQuestWatch",
			"C_QuestLog.GetNumQuestWatches",
			"C_QuestLog.GetQuestIDForQuestWatchIndex",
			"C_QuestLog.GetLogIndexForQuestID",
		},
		events = { "PLAYER_LOGIN", "QUEST_ACCEPTED", "QUEST_WATCH_LIST_CHANGED" },
	},
	optional = {
		events = {
			"QUEST_WATCH_UPDATE",
			"PLAYER_ENTERING_WORLD",
			"PLAYER_LOGOUT",
			"ADDON_ACTION_BLOCKED",
			"ADDON_ACTION_FORBIDDEN",
		},
	},
	init = Init,
	-- Turned off by errors: the old marks come back after the fight.
	disable = function()
		UI.OutOfCombat("questwatch", function()
			pcall(QW.Restore)
		end)
		UI.Changed("tracker") -- the tracker shows again: the step window moves beside it (owner reading 16)
	end,
	events = {
		PLAYER_LOGIN = function()
			Char()
			QW.Queue()
		end,
		PLAYER_ENTERING_WORLD = QW.Queue,
		QUEST_ACCEPTED = function(_, _, q)
			q = U.Num(q)
			if q then
				auto[q] = GetTime()
			end
			QW.Queue()
		end,
		QUEST_WATCH_UPDATE = function(_, _, q)
			q = U.Num(q)
			if q then
				auto[q] = GetTime()
			end
		end,
		QUEST_WATCH_LIST_CHANGED = function()
			if not busy then
				QW.Queue()
			end
		end,
		-- A blocked call while Braindead 4ever changes the tracker: only this module goes off.
		ADDON_ACTION_BLOCKED = function(_, _, addon, func)
			if addon == ADDON and (busy or GetTime() - lastCall < 1) then
				M.Disable("questwatch", L.WHY_BLOCKED:format(tostring(func)))
			end
		end,
		ADDON_ACTION_FORBIDDEN = function(_, _, addon, func)
			if addon == ADDON and (busy or GetTime() - lastCall < 1) then
				M.Disable("questwatch", L.WHY_BLOCKED:format(tostring(func)))
			end
		end,
		-- Logout and /reload: the old marks back (out of combat), the table into whatever the client holds
		-- now (Polestar trap, brain chapter 15). The next login saves and applies again.
		PLAYER_LOGOUT = function()
			if not InCombatLockdown() then
				pcall(QW.Restore)
			end
			if state then
				if type(BraindeadForeverCharDB) ~= "table" then
					BraindeadForeverCharDB = {}
				end
				BraindeadForeverCharDB.watch = state
			end
		end,
	},
})
