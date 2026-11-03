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

-- Probe/Checks.lua: what the probe checks. One entry per function, event, value, atlas or CVar that a
-- planned feature needs (docs/STATUS.md maps every id to its feature; spec/status_spec.lua keeps both in
-- sync). The modules' own requirements are added automatically (ids mod.<module>.<name>).
-- kind: func (call with args) | exists (function exists, never called: actions and protected calls) |
--       value (global value) | event | atlas | cvar | test (own code)
-- when: run automatically when this event fires (quest dialog, loot window, flight map, combat start)
-- manual: only via /bd4 probe check <id> (costly or needs the player)
-- Arguments are evaluated at run time; an argument that fails gives ARGERROR, never a Lua error.
local ADDON, ns = ...
local Probe = ns.Probe
local U = ns.Util

-- First quest in the log (questID, log index) or 0.
local function FirstQuest()
	local shown = U.Num((C_QuestLog.GetNumQuestLogEntries())) or 0
	for i = 1, shown do
		local info = C_QuestLog.GetInfo(i)
		local q = info and not info.isHeader and U.Num(info.questID)
		if q and q > 0 then
			return q, i
		end
	end
	return 0, 0
end

local function QuestID()
	return (FirstQuest())
end

local function Map()
	return U.Num(C_Map.GetBestMapForUnit("player")) or 0
end

local function Player()
	return "player"
end

local function NpcID(unit)
	local _, id = U.ParseGUID(UnitGUID(unit))
	return id
end

-- In-game round trip of the export codec. Returns pass and the PM1 text: paste it into the website
-- decoder (browser "deflate-raw" or "deflate") as the browser counter-check.
local function RoundTrip(m)
	local sample = { t = "Prüfung äöü ß", n = 42, list = { 1, 2, 3 } }
	local codec = ns.Export.GameCodec(m)
	local text, err = ns.Export.Build(sample, codec)
	if not text then
		return false, err
	end
	local body = ns.Export.Parse(text)
	local E = C_EncodingUtil
	local method = m == "z" and Enum.CompressionMethod.Zlib or Enum.CompressionMethod.Deflate
	local raw = E.DecodeBase64(body, Enum.Base64Variant.Standard)
	local json = raw and E.DecompressString(raw, method)
	local back = json and E.DeserializeJSON(json)
	local pass = type(back) == "table" and back.t == sample.t and back.n == 42
	return pass, text
end

local CHECKS = {
	-- Platform, version, restrictions ---------------------------------------------------------------
	{ id = "ver.build", kind = "func", name = "GetBuildInfo" },
	{ id = "ver.project", kind = "value", name = "WOW_PROJECT_ID" },
	{ id = "ver.camelot", kind = "value", name = "WOW_PROJECT_CAMELOT" },
	{ id = "ver.secretfn", kind = "exists", name = "issecretvalue" },
	{ id = "ver.secrets", kind = "func", name = "C_Secrets.HasSecretRestrictions" },
	{
		id = "ver.restrict",
		kind = "func",
		name = "C_RestrictedActions.IsAddOnRestrictionActive",
		args = function()
			return Enum.AddOnRestrictionType.Combat
		end,
	},
	{ id = "ver.locales", kind = "func", name = "GetAvailableLocales" },
	{ id = "ver.preset", kind = "func", name = "C_GameRules.GetForeverExperiencePreset" },
	{ id = "ver.hardcore", kind = "func", name = "C_GameRules.IsHardcoreActive" },
	{ id = "ver.selffound", kind = "func", name = "C_GameRules.IsSelfFoundAllowed" },
	{ id = "ver.rulesevent", kind = "event", name = "GAME_RULES_CHANGED" },
	{ id = "ver.throttle", kind = "func", name = "GetScriptBucketThrottleLimits" },
	{
		-- SavedVariables after a cold start: run, /reload, quit the client, start it, run again; the
		-- detail shows the marker of the previous run (Forever beta lost SavedVariables, chapter 15 §7).
		id = "sv.coldstart",
		kind = "test",
		name = "SavedVariables marker",
		run = function()
			local db = Probe.DB()
			local prev = db.marker
			db.marker = { at = GetServerTime(), build = select(2, GetBuildInfo()) }
			if type(prev) ~= "table" then
				return true, "no previous marker (first run or SavedVariables lost)"
			end
			return true, ("previous marker from %s, build %s"):format(tostring(prev.at), tostring(prev.build))
		end,
	},

	-- Step display (M1): quest log and events ---------------------------------------------------------
	{ id = "quest.count", kind = "func", name = "C_QuestLog.GetNumQuestLogEntries" },
	{
		id = "quest.info",
		kind = "func",
		name = "C_QuestLog.GetInfo",
		args = function()
			return select(2, FirstQuest())
		end,
	},
	{ id = "quest.objectives", kind = "func", name = "C_QuestLog.GetQuestObjectives", args = QuestID },
	{ id = "quest.flagged", kind = "func", name = "C_QuestLog.IsQuestFlaggedCompleted", args = QuestID },
	{ id = "quest.ready", kind = "func", name = "C_QuestLog.ReadyForTurnIn", args = QuestID },
	{ id = "quest.max", kind = "func", name = "C_QuestLog.GetMaxNumQuestsCanAccept" },
	{ id = "quest.trivial", kind = "func", name = "C_QuestLog.GetTrivialRange" },
	{ id = "quest.elite", kind = "func", name = "C_QuestLog.IsEliteQuest", args = QuestID },
	{ id = "quest.timers", kind = "func", name = "C_QuestLog.GetQuestTimers" },
	{ id = "quest.completed", kind = "func", name = "C_QuestLog.GetAllCompletedQuestIDs" },
	{ id = "quest.autocomplete", kind = "event", name = "QUEST_AUTOCOMPLETE" },
	{ id = "quest.progressev", kind = "event", name = "QUEST_PROGRESS" },
	{ id = "quest.finished", kind = "event", name = "QUEST_FINISHED" },

	-- Names from the client (M4) ----------------------------------------------------------------------
	{ id = "name.quest", kind = "func", name = "C_QuestLog.GetTitleForQuestID", args = QuestID },
	{ id = "name.loadquest", kind = "exists", name = "C_QuestLog.RequestLoadQuestByID" },
	{ id = "name.questload", kind = "event", name = "QUEST_DATA_LOAD_RESULT" },
	{
		id = "name.item",
		kind = "func",
		name = "C_Item.GetItemNameByID",
		args = function()
			return GetInventoryItemID("player", 16) or 0
		end,
	},
	{ id = "name.itemload", kind = "event", name = "ITEM_DATA_LOAD_RESULT" },
	{ id = "name.map", kind = "func", name = "C_Map.GetMapInfo", args = Map },
	{
		id = "name.npc",
		kind = "func",
		name = "UnitName",
		when = "QUEST_DETAIL",
		args = function()
			return "npc"
		end,
	},
	{
		id = "name.npctooltip",
		kind = "func",
		name = "C_TooltipInfo.GetHyperlink",
		when = "QUEST_DETAIL",
		args = function()
			return ("unit:Creature-0-0-0-0-%d-0000000000"):format(NpcID("npc"))
		end,
	},
	{
		id = "name.creatureid",
		kind = "func",
		name = "UnitCreatureID",
		when = "PLAYER_TARGET_CHANGED",
		args = function()
			return "target"
		end,
	},

	-- Navigation (M2) ---------------------------------------------------------------------------------
	{ id = "nav.map", kind = "func", name = "C_Map.GetBestMapForUnit", args = Player },
	{
		id = "nav.pos",
		kind = "func",
		name = "C_Map.GetPlayerMapPosition",
		args = function()
			return Map(), "player"
		end,
	},
	{ id = "nav.world", kind = "func", name = "UnitPosition", args = Player },
	{ id = "nav.facing", kind = "func", name = "GetPlayerFacing" },
	{ id = "nav.worldpos", kind = "exists", name = "C_Map.GetWorldPosFromMapPos" },
	{ id = "nav.canwaypoint", kind = "func", name = "C_Map.CanSetUserWaypointOnMap", args = Map },
	{ id = "nav.setwaypoint", kind = "exists", name = "C_Map.SetUserWaypoint" },
	{ id = "nav.mappoint", kind = "exists", name = "UiMapPoint.CreateFromCoordinates" },
	{ id = "nav.supertrack", kind = "exists", name = "C_SuperTrack.SetSuperTrackedUserWaypoint" },
	{ id = "nav.nextwaypoint", kind = "func", name = "C_QuestLog.GetNextWaypoint", args = QuestID },
	{ id = "nav.questsonmap", kind = "func", name = "C_QuestLog.GetQuestsOnMap", args = Map },
	{
		id = "nav.maprestrict",
		kind = "func",
		name = "C_RestrictedActions.IsAddOnRestrictionActive",
		args = function()
			return Enum.AddOnRestrictionType.Map
		end,
	},
	{ id = "nav.tomtom", kind = "value", name = "TomTom" },
	{ id = "nav.cvar", kind = "cvar", name = "showInGameNavigation" },
	{ id = "nav.range", kind = "value", name = "IN_GAME_NAVIGATION_RANGE" },
	{ id = "nav.reached", kind = "value", name = "NAVIGATION_DESTINATION_REACHED_MESSAGE" },
	{ id = "nav.supertrackev", kind = "event", name = "SUPER_TRACKING_CHANGED" },
	{ id = "nav.waypointev", kind = "event", name = "USER_WAYPOINT_UPDATED" },
	{ id = "nav.moving", kind = "event", name = "PLAYER_STARTED_MOVING" },

	-- Route choice (M3) -------------------------------------------------------------------------------
	{ id = "route.race", kind = "func", name = "UnitRace", args = Player },
	{ id = "route.class", kind = "func", name = "UnitClass", args = Player },
	{ id = "route.faction", kind = "func", name = "UnitFactionGroup", args = Player },
	{ id = "route.level", kind = "func", name = "UnitLevel", args = Player },
	{ id = "route.maxlevel", kind = "func", name = "GetMaxLevelForPlayerExpansion" },
	{ id = "route.xpoff", kind = "func", name = "IsXPUserDisabled" },

	-- Hints on the way (M5) ---------------------------------------------------------------------------
	{ id = "hint.bind", kind = "func", name = "GetBindLocation" },
	{ id = "hint.binder", kind = "exists", name = "C_PlayerInteractionManager.ConfirmationInteraction" },
	{ id = "hint.trainer", kind = "exists", name = "GetTrainerServiceInfo" },
	{ id = "hint.junk", kind = "exists", name = "C_MerchantFrame.SellAllJunkItems" },

	-- Discoveries for the collector (M7), context checks ---------------------------------------------
	{
		id = "find.giverguid",
		kind = "func",
		name = "UnitGUID",
		when = "QUEST_DETAIL",
		args = function()
			return "npc"
		end,
	},
	{ id = "find.giverquest", kind = "func", name = "GetQuestID", when = "QUEST_DETAIL" },
	{ id = "find.rewardxp", kind = "func", name = "GetRewardXP", when = "QUEST_DETAIL" },
	{ id = "find.questxp", kind = "func", name = "GetQuestLogRewardXP", args = QuestID },
	{
		id = "find.lootsource",
		kind = "func",
		name = "GetLootSourceInfo",
		when = "LOOT_OPENED",
		args = function()
			return 1
		end,
	},
	{ id = "find.lootcount", kind = "func", name = "GetNumLootItems", when = "LOOT_OPENED" },
	{ id = "find.fishing", kind = "func", name = "IsFishingLoot", when = "LOOT_OPENED" },
	{
		id = "find.lootnpc",
		kind = "func",
		name = "UnitGUID",
		when = "LOOT_OPENED",
		args = function()
			return "npc"
		end,
	},
	{
		id = "find.booknpc",
		kind = "func",
		name = "UnitGUID",
		when = "ITEM_TEXT_BEGIN",
		args = function()
			return "npc"
		end,
	},
	{ id = "find.booktitle", kind = "func", name = "ItemTextGetItem", when = "ITEM_TEXT_READY" },
	{ id = "find.taxiid", kind = "func", name = "GetTaxiMapID", when = "TAXIMAP_OPENED" },
	{
		id = "find.taxinodes",
		kind = "func",
		name = "C_TaxiMap.GetAllTaxiNodes",
		when = "TAXIMAP_OPENED",
		args = function()
			return GetTaxiMapID() or 0
		end,
	},
	{ id = "find.taxiworld", kind = "func", name = "C_TaxiMap.GetTaxiNodesForMap", args = Map },
	{ id = "find.flightstate", kind = "value", name = "Enum.FlightPathState" },
	{ id = "find.newtaxi", kind = "value", name = "ERR_NEWTAXIPATH" },
	{ id = "find.ontaxi", kind = "func", name = "UnitOnTaxi", args = Player },
	{
		id = "find.rareclass",
		kind = "func",
		name = "UnitClassification",
		when = "PLAYER_TARGET_CHANGED",
		args = function()
			return "target"
		end,
	},
	{
		id = "find.rarecombat",
		kind = "func",
		name = "UnitClassification",
		when = "PLAYER_REGEN_DISABLED",
		args = function()
			return "target"
		end,
	},
	{
		id = "find.targetguid",
		kind = "func",
		name = "UnitGUID",
		when = "PLAYER_REGEN_DISABLED",
		args = function()
			return "target"
		end,
	},
	{
		id = "find.targetname",
		kind = "func",
		name = "UnitName",
		when = "PLAYER_REGEN_DISABLED",
		args = function()
			return "target"
		end,
	},
	{
		id = "find.creatureid",
		kind = "func",
		name = "C_CreatureInfo.GetCreatureID",
		when = "PLAYER_TARGET_CHANGED",
		args = function()
			return UnitGUID("target")
		end,
	},
	{ id = "find.vignettes", kind = "func", name = "C_VignetteInfo.GetVignettes" },
	{ id = "find.vignetteev", kind = "event", name = "VIGNETTES_UPDATED" },
	{ id = "find.legacyconst", kind = "value", name = "Constants.LegacyConsts" },
	{
		id = "find.legacy1187",
		kind = "func",
		name = "C_Traits.GetConfigIDByTreeID",
		args = function()
			return 1187
		end,
	},
	{
		id = "find.legacy1188",
		kind = "func",
		name = "C_Traits.GetConfigIDByTreeID",
		args = function()
			return 1188
		end,
	},
	{
		id = "find.legacy1189",
		kind = "func",
		name = "C_Traits.GetConfigIDByTreeID",
		args = function()
			return 1189
		end,
	},
	-- Registering the combat log is a blocked action in Forever (JourneyTracker 0.6.5): validity only.
	{ id = "find.combatlog", kind = "event", name = "COMBAT_LOG_EVENT_UNFILTERED", noRegister = true },

	-- Quest item button (M8): the human clicks, the blocked watcher records ---------------------------
	{
		id = "qitem.info",
		kind = "func",
		name = "GetQuestLogSpecialItemInfo",
		args = function()
			return select(2, FirstQuest())
		end,
	},
	{ id = "qitem.use", kind = "exists", name = "UseQuestLogSpecialItem" },
	{ id = "qitem.cvar", kind = "cvar", name = "canUseQuestItemWithLeftClick" },
	{
		-- Creates a secure action button (type "item") out of combat for the first quest item in the log.
		-- Click it; an ADDON_ACTION_BLOCKED/FORBIDDEN line in the report means the call is not allowed.
		id = "qitem.button",
		kind = "test",
		name = "SecureActionButtonTemplate item",
		manual = true,
		run = function()
			if InCombatLockdown() then
				return false, "in combat"
			end
			local link
			for i = 1, U.Num((C_QuestLog.GetNumQuestLogEntries())) or 0 do
				link = U.Str((GetQuestLogSpecialItemInfo(i)))
				if link then
					break
				end
			end
			if not link then
				return false, "no quest item in the log"
			end
			local b = Probe.itemButton
				or CreateFrame("Button", "BraindeadForeverProbeItemButton", UIParent, "SecureActionButtonTemplate")
			Probe.itemButton = b
			b:SetSize(40, 40)
			b:SetPoint("CENTER", 0, -120)
			b:SetNormalTexture("Interface\\Icons\\INV_Misc_QuestionMark")
			b:RegisterForClicks("AnyUp", "AnyDown")
			b:SetAttribute("type", "item")
			b:SetAttribute("item", link)
			b:Show()
			return true, "button shown below the screen center: click it, then /bd4 probe report"
		end,
	},

	-- In-game exchange (M11) --------------------------------------------------------------------------
	{
		id = "comm.prefix",
		kind = "test",
		name = "RegisterAddonMessagePrefix",
		run = function()
			local r = C_ChatInfo.RegisterAddonMessagePrefix(Probe.PREFIX)
			local RR = Enum.RegisterAddonMessagePrefixResult
			return r == RR.Success or r == RR.DuplicatePrefix, "result " .. tostring(r)
		end,
	},
	{ id = "comm.lockdown", kind = "func", name = "C_ChatInfo.InChatMessagingLockdown" },
	{ id = "comm.outgoing", kind = "func", name = "C_ChatInfo.AreOutgoingAddonChatMessagesRestricted" },
	{ id = "comm.trial", kind = "func", name = "IsTrialAccount" },
	{ id = "comm.veteran", kind = "func", name = "IsVeteranTrialAccount" },
	{ id = "comm.join", kind = "exists", name = "JoinTemporaryChannel" },
	{ id = "comm.filter", kind = "exists", name = "ChatFrameUtil.AddMessageEventFilter" },
	{
		id = "comm.channel",
		kind = "test",
		name = "exchange channel",
		run = function()
			local X = ns.Exchange
			local c = X and X.channel
			if not c then
				return false, "exchange not loaded"
			end
			local id = U.Num((GetChannelName(X.CHANNELS[c.slot])))
			return c.state == "on", ("state %s, name %s, number %s"):format(c.state, X.CHANNELS[c.slot], tostring(id))
		end,
	},
	{
		-- Forever names are "Firstname Lastname"; only the format is reported, never the name.
		id = "comm.nameformat",
		kind = "test",
		name = "GetUnitName player",
		run = function()
			local n = U.Str((GetUnitName("player")))
			if not n then
				return false, "no name or secret"
			end
			return true, n:find(" ", 1, true) and "with surname separator" or "single name"
		end,
	},
	{
		id = "comm.stats",
		kind = "test",
		name = "exchange counters",
		run = function()
			local X = ns.Exchange
			if not X then
				return false, "exchange not loaded"
			end
			local s, results = X.stats, {}
			for k, v in pairs(s.results) do
				results[#results + 1] = k .. "=" .. v
			end
			table.sort(results)
			return true,
				("offered %d sent %d received %d confirmed %d dropped %d bad %d queue %d results %s"):format(
					s.offered,
					s.sent,
					s.received,
					s.confirmed,
					s.dropped,
					s.bad,
					#X.queue,
					table.concat(results, ",")
				)
		end,
	},
	{
		-- 12 messages in a row on the best target: the 11th should come back as AddonMessageThrottle (3)
		-- if Forever uses the default bucket. The loopback counter shows what came back.
		id = "comm.burst",
		kind = "test",
		name = "SendAddonMessage burst",
		manual = true,
		run = function()
			C_ChatInfo.RegisterAddonMessagePrefix(Probe.PREFIX)
			local dist, target
			if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
				dist = "INSTANCE_CHAT"
			elseif IsInGroup() then
				dist = "PARTY"
			elseif IsInGuild() then
				dist = "GUILD"
			elseif ns.Exchange and ns.Exchange.channel.state == "on" then
				dist = "CHANNEL"
				target = tostring(GetChannelName(ns.Exchange.CHANNELS[ns.Exchange.channel.slot]))
			end
			if not dist then
				return false, "no group, guild or channel"
			end
			local codes = {}
			for i = 1, 12 do
				codes[i] = tostring(C_ChatInfo.SendAddonMessage(Probe.PREFIX, "burst;" .. i, dist, target))
			end
			return true, ("%s: %s, loopback so far %d"):format(dist, table.concat(codes, ","), Probe.loopback or 0)
		end,
	},
	{ id = "comm.restrictev", kind = "event", name = "ADDON_RESTRICTION_STATE_CHANGED" },
	{ id = "comm.noticeev", kind = "event", name = "CHAT_MSG_CHANNEL_NOTICE" },

	-- Export (AP 4) -----------------------------------------------------------------------------------
	{
		id = "enc.json",
		kind = "test",
		name = "SerializeJSON umlauts",
		run = function()
			local E = C_EncodingUtil
			local s = E.SerializeJSON({ t = "äöüß", n = 1 })
			local back = s and E.DeserializeJSON(s)
			return type(back) == "table" and back.t == "äöüß", s
		end,
	},
	{
		id = "enc.deflate",
		kind = "test",
		name = "CompressString Deflate",
		run = function()
			return RoundTrip("d")
		end,
	},
	{
		id = "enc.zlib",
		kind = "test",
		name = "CompressString Zlib",
		run = function()
			return RoundTrip("z")
		end,
	},
	{
		-- DecodeBase64 with line breaks inside (pasted text): the docs say nothing about whitespace.
		id = "enc.base64space",
		kind = "test",
		name = "DecodeBase64 with whitespace",
		run = function()
			local E = C_EncodingUtil
			local b = E.EncodeBase64("Braindead 4ever export check")
			local spaced = b and (b:sub(1, 8) .. "\n" .. b:sub(9))
			local back = spaced and E.DecodeBase64(spaced)
			return back == "Braindead 4ever export check", back and "decoded" or "nil"
		end,
	},
	{
		-- Copy window with 50, 200 and 500 KB of text: milliseconds per size.
		id = "export.window",
		kind = "test",
		name = "copy window size",
		manual = true,
		run = function()
			local out = {}
			for _, kb in ipairs({ 50, 200, 500 }) do
				local text = ("0123456789abcdef"):rep(kb * 64)
				local t0 = debugprofilestop()
				ns.ShowCopy("Braindead 4ever probe", text)
				out[#out + 1] = ("%d KB %.0f ms"):format(kb, debugprofilestop() - t0)
			end
			return true, table.concat(out, ", ")
		end,
	},

	-- Safety measures (M14) ---------------------------------------------------------------------------
	{ id = "safe.eventvalid", kind = "exists", name = "C_EventUtils.IsEventValid" },
	{ id = "safe.errorhandler", kind = "exists", name = "geterrorhandler" },
	{ id = "safe.debugstack", kind = "exists", name = "debugstack" },
	{ id = "safe.blocked", kind = "event", name = "ADDON_ACTION_BLOCKED" },
	{ id = "safe.forbidden", kind = "event", name = "ADDON_ACTION_FORBIDDEN" },
	{ id = "safe.scripterrors", kind = "cvar", name = "scriptErrors" },

	-- Performance budget ------------------------------------------------------------------------------
	{ id = "perf.profiler", kind = "func", name = "C_AddOnProfiler.IsEnabled" },
	{
		id = "perf.average",
		kind = "func",
		name = "C_AddOnProfiler.GetAddOnMetric",
		args = function()
			return ADDON, Enum.AddOnProfilerMetric.SessionAverageTime
		end,
	},
	{
		-- Expensive (Blizzard calls it at most every 15 s): manual only.
		id = "perf.memory",
		kind = "test",
		name = "GetAddOnMemoryUsage",
		manual = true,
		run = function()
			UpdateAddOnMemoryUsage()
			return true, ("%.0f KB"):format(GetAddOnMemoryUsage(ADDON))
		end,
	},

	-- Interface (M12, M13; design concept 2.1 to 2.9) ------------------------------------------------
	{ id = "ui.settings", kind = "exists", name = "Settings.RegisterVerticalLayoutCategory" },
	{ id = "ui.opensettings", kind = "exists", name = "Settings.OpenToCategory" },
	{ id = "ui.editmode", kind = "value", name = "EditModeManagerFrame" },
	{ id = "ui.helptip", kind = "exists", name = "HelpTip.Show" },
	{ id = "ui.compartment", kind = "value", name = "AddonCompartmentFrame" },
	{ id = "ui.textsize", kind = "value", name = "TextSizeManager" },
	{ id = "ui.gamepad", kind = "func", name = "C_GamePad.IsEnabled" },
	{ id = "atlas.header", kind = "atlas", name = "UI-QuestTracker-Primary-Objective-Header" },
	{ id = "atlas.nub", kind = "atlas", name = "UI-QuestTracker-Objective-Nub" },
	{ id = "atlas.check", kind = "atlas", name = "UI-QuestTracker-Tracker-Check" },
	{ id = "atlas.glow", kind = "atlas", name = "OBJFX_LineGlow" },
	{ id = "atlas.collapse", kind = "atlas", name = "UI-QuestTrackerButton-Collapse-All" },
	{ id = "atlas.parchment", kind = "atlas", name = "QuestBG-Parchment" },
	{ id = "atlas.arrow", kind = "atlas", name = "Navigation-Tracked-Arrow" },
	{ id = "atlas.pin", kind = "atlas", name = "Waypoint-MapPin-Tracked" },
	{ id = "atlas.minipin", kind = "atlas", name = "Waypoint-MapPin-Minimap-Tracked" },
	{ id = "atlas.questnormal", kind = "atlas", name = "QuestNormal" },
	{ id = "atlas.questturnin", kind = "atlas", name = "QuestTurnin" },
	{ id = "atlas.barbg", kind = "atlas", name = "Legacy-Progressbar-BG" },
	{ id = "atlas.barfill", kind = "atlas", name = "Legacy-Progressbar-Fill" },
	{ id = "atlas.indicator", kind = "atlas", name = "ui-hud-minimap-addon-indicator" },
	-- Welle 5b: area of hint level 2, size grip and scroll list of the step window, quest tracker
	{ id = "atlas.area", kind = "atlas", name = "UI-prey-Scoutingmap-ring" },
	{ id = "atlas.areafill", kind = "atlas", name = "common-mask-circle" },
	{ id = "ui.resize", kind = "value", name = "PanelResizeButtonMixin" },
	{ id = "ui.scrollbox", kind = "exists", name = "ScrollUtil.InitScrollBoxWithScrollBar" },
	{ id = "ui.tracker", kind = "value", name = "ObjectiveTrackerFrame" },
	{ id = "font.header", kind = "value", name = "ObjectiveTrackerHeaderFont" },
	{ id = "font.line", kind = "value", name = "ObjectiveTrackerLineFont" },
	{ id = "font.small", kind = "value", name = "GameFontNormalSmall" },
	{ id = "font.med3", kind = "value", name = "GameFontNormalMed3" },
	{ id = "font.highlight", kind = "value", name = "GameFontHighlight" },
	-- Welle 5d: outline fonts of the arrow text, the arrow gives way to dialogs, the usage hint waits
	-- behind Blizzard's settings
	{ id = "font.outline", kind = "value", name = "GameFontHighlightOutline" },
	{ id = "font.normaloutline", kind = "value", name = "GameFontNormalOutline" },
	{ id = "ui.popupshown", kind = "exists", name = "StaticPopup_ForEachShownDialog" },
	{ id = "ui.helptiphide", kind = "exists", name = "HelpTip.Hide" },
	{ id = "ui.settingspanel", kind = "value", name = "SettingsPanel" },
	{ id = "color.normal", kind = "value", name = "NORMAL_FONT_COLOR" },
	{ id = "color.highlight", kind = "value", name = "HIGHLIGHT_FONT_COLOR" },
	{ id = "color.tracker", kind = "value", name = "OBJECTIVE_TRACKER_COLOR" },
	{ id = "color.dimred", kind = "value", name = "DIM_RED_FONT_COLOR" },
	{ id = "sound.complete", kind = "value", name = "SOUNDKIT.IG_QUEST_LIST_COMPLETE" },
	{ id = "sound.option", kind = "value", name = "SOUNDKIT.UI_EXPERIENCE_PRESET_OPTION_CLICK" },
	{ id = "sound.select", kind = "value", name = "SOUNDKIT.UI_EXPERIENCE_PRESET_SELECT_CLICK" },
	{ id = "cvar.contrast", kind = "cvar", name = "questTextContrast" },
	{ id = "cvar.colorblind", kind = "cvar", name = "colorblindMode" },
	{ id = "cvar.fontscale", kind = "cvar", name = "userFontScale" },
	{ id = "cvar.instant", kind = "cvar", name = "instantQuestText" },
	{ id = "cvar.gamepad", kind = "cvar", name = "GamePadEnable" },

	-- Version 1.0 features ----------------------------------------------------------------------------
	{ id = "auto.accept", kind = "exists", name = "AcceptQuest" },
	{ id = "auto.complete", kind = "exists", name = "CompleteQuest" },
	{ id = "auto.reward", kind = "exists", name = "GetQuestReward" },
	{ id = "auto.acknowledge", kind = "exists", name = "AcknowledgeAutoAcceptQuest" },
	{ id = "auto.autoaccept", kind = "exists", name = "QuestGetAutoAccept" },
	{ id = "auto.gossip", kind = "func", name = "C_GossipInfo.GetAvailableQuests", when = "GOSSIP_SHOW" },
	{ id = "auto.gossipselect", kind = "exists", name = "C_GossipInfo.SelectAvailableQuest" },
	{ id = "auto.greeting", kind = "func", name = "GetNumAvailableQuests", when = "QUEST_GREETING" },
	{ id = "group.ingroup", kind = "func", name = "IsInGroup" },
	{ id = "group.members", kind = "func", name = "GetNumGroupMembers" },
	{ id = "time.xp", kind = "func", name = "UnitXP", args = Player },
	{ id = "time.xpmax", kind = "func", name = "UnitXPMax", args = Player },
	{ id = "time.rested", kind = "func", name = "GetXPExhaustion" },
	{ id = "time.played", kind = "event", name = "TIME_PLAYED_MSG" },

	-- XP balance (owner wish 9): the Classic rules in Routes/XP.lua are assumptions for Forever ------
	{
		-- XP curve: the client's XP for the current level against the Classic table.
		id = "xp.curve",
		kind = "test",
		name = "UnitXPMax against the Classic level table",
		run = function()
			local level, max = U.Num(UnitLevel("player")), U.Num(UnitXPMax("player"))
			local classic = level and ns.XP.TO_LEVEL[level]
			if not (level and max and classic) then
				return false, ("level %s, client %s: no Classic value"):format(tostring(level), tostring(max))
			end
			return max == classic, ("level %d: client %d, Classic %d"):format(level, max, classic)
		end,
	},
	{
		-- Kill XP: kill a creature solo, keep its corpse targeted, then /bd4 probe check xp.kill.
		id = "xp.kill",
		kind = "test",
		manual = true,
		name = "last XP gain against the kill formula (Forever: creature level as base below the character)",
		run = function()
			local gain = ns.Route and ns.Route.LastGain()
			local level, mob = U.Num(UnitLevel("player")), U.Num(UnitLevel("target"))
			if not (gain and level and mob and mob > 0) then
				return false, "needs a kill with the creature still targeted"
			end
			local class = U.Str(UnitClassification("target")) or "?"
			local expect = ns.XP.KillXP(level, mob, class == "elite" or class == "rareelite")
			-- Rested kills give double (chapter 06 §8); both count as a match.
			local pass = math.abs(gain.xp - expect) <= 1 or math.abs(gain.xp - 2 * expect) <= 1
			return pass,
				("gain %d at level %d, target level %d %s: Classic %d, rested %d, rested pool %d"):format(
					gain.xp,
					level,
					mob,
					class,
					expect,
					2 * expect,
					U.Num(GetXPExhaustion()) or 0
				)
		end,
	},
	{
		-- Quest XP: the client's reward of the first quest in the log that the route knows, against
		-- the route data (Polestar) with the Classic level reduction.
		id = "xp.quest",
		kind = "test",
		name = "GetQuestLogRewardXP against the route data",
		run = function()
			local fn = Probe.Lookup("GetQuestLogRewardXP")
			local rt = ns.Route and ns.Route.Runtime()
			local level = U.Num(UnitLevel("player"))
			if type(fn) ~= "function" or not rt or not level then
				return false, "needs GetQuestLogRewardXP, an active route and the level"
			end
			local shown = U.Num((C_QuestLog.GetNumQuestLogEntries())) or 0
			for i = 1, shown do
				local info = C_QuestLog.GetInfo(i)
				local q = info and not info.isHeader and U.Num(info.questID)
				local data = q and rt.quests[q]
				if data and data[2] > 0 then
					local client = U.Num((fn(q)))
					local expect = ns.XP.QuestXP(data[2], data[1], level)
					return client == expect,
						("quest %d level %d at level %d: client %s, data %d"):format(
							q,
							data[1],
							level,
							tostring(client),
							expect
						)
				end
			end
			return false, "no quest of the route in the log"
		end,
	},
}

for _, c in ipairs(CHECKS) do
	Probe.CHECKS[#Probe.CHECKS + 1] = c
end

Probe.Subscribe()
