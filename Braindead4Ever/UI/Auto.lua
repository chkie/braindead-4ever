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

-- UI/Auto.lua: module "auto", the optional automation (requirement A74, plan "Optionale Automatik").
-- Off by default; one switch on the main settings page (UI.DEFAULTS.auto). It acts only in dialogs the
-- player opened himself and only on the quests the current part of the route takes or hands in
-- (Route.DialogQuests: the current step and the next three open ones, without skipped quests):
--   * accept a route quest (AcceptQuest; AcknowledgeAutoAcceptQuest for a quest the server already put
--     into the log), never a quest of an item or an area (Blizzard turns those into a pop-up itself) and
--     never a PvP quest (Blizzard asks first),
--   * go on to the reward page of a route quest that can be handed in (CompleteQuest),
--   * hand it in (GetQuestReward) only with no reward choice or exactly one, never with several and never
--     when the quest costs money (Blizzard asks first),
--   * in gossip and greeting lists choose only the line of such a quest, never another gossip option.
-- Never in a fight, never during a loading screen; Shift held at any step pauses the rest of the dialog;
-- in the hardcore-safe mode no quest the route warns about (UI/Connect.lua, Routes/Hardcore.lua).
-- None of these calls needs a key press or is protected (brain chapter 11 §3.3, chapter 06 §5 and §6).
-- The addon never closes, declines or hides a dialog: when the server ignores a call, the dialog stays as
-- it was and the player goes on with mouse or gamepad (requirement A40). Each call runs at most once per
-- quest within RETRY seconds, so repeated dialog events cannot loop. A blocked action right after an own
-- call turns the module off.
local ADDON, ns = ...
local L, UI = ns.L, ns.UI
local M, U = ns.Modules, ns.Util

local A = {
	RETRY = 10, -- seconds before the same call for the same quest may run again (chosen value)
	QUIET = 10, -- seconds without a dialog event that end a dialog (chosen value)
}
ns.Auto = A

local tried = {} -- "<call>:<questID>" -> GetTime() of the last own call
local open = { gossip = false, quest = false }
local paused = false -- Shift was held in this dialog
local last -- GetTime() of the last dialog event
local loading = false -- between LOADING_SCREEN_ENABLED and LOADING_SCREEN_DISABLED
local lastCall = -math.huge

local function EndDialog()
	open.gossip, open.quest, paused, last = false, false, false, nil
	local now = GetTime()
	for key, at in pairs(tried) do
		if now - at >= A.RETRY then
			tried[key] = nil
		end
	end
end

-- A dialog event: the dialog starts or goes on.
local function Touch(kind)
	local now = GetTime()
	if last and now - last > A.QUIET then
		EndDialog()
	end
	last = now
	open[kind] = true
	if IsShiftKeyDown() then
		paused = true
	end
end

-- The quests the automation may act on now, or nil (switch off, paused, fight, loading screen, no route).
local function Wanted()
	if UI.Get("auto") ~= true or paused or loading or InCombatLockdown() then
		return nil
	end
	return ns.Route and ns.Route.DialogQuests() or nil
end

local function Try(call, q)
	local key = call .. ":" .. q
	local now = GetTime()
	if tried[key] and now - tried[key] < A.RETRY then
		return false
	end
	tried[key] = now
	lastCall = now
	return true
end

-- The hardcore-safe mode takes no quest the route warns about (elite, too far above).
local function Safe(q)
	return not (ns.Connect.Hardcore() and ns.Route.QuestDanger(q))
end

local function NoCost()
	return (U.Num(GetQuestMoneyToGet()) or 0) <= 0
end

local function DialogQuest()
	local q = U.Num(GetQuestID())
	return q and q > 0 and q or nil
end

function A.Gossip()
	Touch("gossip")
	local want = Wanted()
	if not want then
		return
	end
	for _, info in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
		local q = U.Num(info.questID)
		if q and info.isComplete == true and want.turnin[q] and Try("active", q) then
			C_GossipInfo.SelectActiveQuest(q) -- Blizzard passes the questID too (GossipFrameShared.lua)
			return
		end
	end
	for _, info in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
		local q = U.Num(info.questID)
		if q and want.accept[q] and Safe(q) and Try("available", q) then
			C_GossipInfo.SelectAvailableQuest(q)
			return
		end
	end
end

-- NPC without gossip and more than one quest: two separate lists, by index (Mainline/QuestFrame.lua).
function A.Greeting()
	Touch("quest")
	local want = Wanted()
	if not want then
		return
	end
	for i = 1, U.Num(GetNumActiveQuests()) or 0 do
		local _, isComplete = GetActiveTitle(i)
		local q = U.Num(GetActiveQuestID(i))
		if q and isComplete == true and want.turnin[q] and Try("active", q) then
			-- Blizzard passes the index (Mainline/QuestFrame.lua); the pinned annotation lacks the argument
			---@diagnostic disable-next-line: redundant-parameter
			SelectActiveQuest(i)
			return
		end
	end
	for i = 1, U.Num(GetNumAvailableQuests()) or 0 do
		local q = U.Num((select(5, GetAvailableQuestInfo(i))))
		if q and want.accept[q] and Safe(q) and Try("available", q) then
			---@diagnostic disable-next-line: redundant-parameter
			SelectAvailableQuest(i)
			return
		end
	end
end

function A.Detail(startItem)
	Touch("quest")
	local want = Wanted()
	local q = DialogQuest()
	if not (want and q) then
		return
	end
	-- From an item or an area Blizzard makes a pop-up and closes the dialog itself (QuestFrame.lua).
	local auto = QuestGetAutoAccept() == true
	if (U.Num(startItem) or 0) ~= 0 or (auto and QuestIsFromAreaTrigger() == true) then
		return
	end
	if auto then
		-- The server put the quest into the log already; the dialog only asks to acknowledge it.
		if (want.accept[q] or ns.Route.Quests()[q]) and Try("acknowledge", q) then
			AcknowledgeAutoAcceptQuest()
		end
		return
	end
	if QuestFlagsPVP() == true then
		return -- Blizzard asks before a PvP quest
	end
	if want.accept[q] and Safe(q) and Try("accept", q) then
		AcceptQuest()
	end
end

function A.Progress()
	Touch("quest")
	local want = Wanted()
	local q = DialogQuest()
	if want and q and want.turnin[q] and IsQuestCompletable() == true and NoCost() and Try("complete", q) then
		CompleteQuest() -- only goes on to the reward page
	end
end

function A.Reward()
	Touch("quest")
	local want = Wanted()
	local q = DialogQuest()
	if not (want and q and want.turnin[q]) then
		return
	end
	local n = U.Num(GetNumQuestChoices()) or 0
	if n > 1 or not NoCost() then
		return -- several rewards: the player chooses
	end
	if Try("reward", q) then
		GetQuestReward(n == 1 and 1 or 0) -- the same choice Blizzard's button passes
	end
end

local function Blocked(_, _, addon, func)
	if addon == ADDON and GetTime() - lastCall < 1 then
		M.Disable("auto", L.WHY_BLOCKED:format(tostring(func)))
	end
end

M.Define("auto", {
	requires = {
		funcs = {
			"AcceptQuest",
			"AcknowledgeAutoAcceptQuest",
			"QuestGetAutoAccept",
			"QuestIsFromAreaTrigger",
			"QuestFlagsPVP",
			"CompleteQuest",
			"IsQuestCompletable",
			"GetQuestReward",
			"GetNumQuestChoices",
			"GetQuestMoneyToGet",
			"GetQuestID",
			"C_GossipInfo.GetActiveQuests",
			"C_GossipInfo.GetAvailableQuests",
			"C_GossipInfo.SelectActiveQuest",
			"C_GossipInfo.SelectAvailableQuest",
			"GetNumActiveQuests",
			"GetActiveTitle",
			"GetActiveQuestID",
			"GetNumAvailableQuests",
			"GetAvailableQuestInfo",
			"SelectActiveQuest",
			"SelectAvailableQuest",
			"IsShiftKeyDown",
			"InCombatLockdown",
		},
		events = {
			"GOSSIP_SHOW",
			"GOSSIP_CLOSED",
			"QUEST_GREETING",
			"QUEST_DETAIL",
			"QUEST_PROGRESS",
			"QUEST_COMPLETE",
			"QUEST_FINISHED",
			"LOADING_SCREEN_ENABLED",
			"LOADING_SCREEN_DISABLED",
		},
	},
	optional = { events = { "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" } },
	events = {
		GOSSIP_SHOW = function()
			A.Gossip()
		end,
		QUEST_GREETING = function()
			A.Greeting()
		end,
		QUEST_DETAIL = function(_, _, startItem)
			A.Detail(startItem)
		end,
		QUEST_PROGRESS = function()
			A.Progress()
		end,
		QUEST_COMPLETE = function()
			A.Reward()
		end,
		GOSSIP_CLOSED = function(_, _, continuing)
			open.gossip = false
			if continuing ~= true and not open.quest then
				EndDialog()
			end
		end,
		QUEST_FINISHED = function()
			open.quest = false
			if not open.gossip then
				EndDialog()
			end
		end,
		LOADING_SCREEN_ENABLED = function()
			loading = true
			EndDialog()
		end,
		LOADING_SCREEN_DISABLED = function()
			loading = false
		end,
		ADDON_ACTION_BLOCKED = Blocked,
		ADDON_ACTION_FORBIDDEN = Blocked,
	},
})
