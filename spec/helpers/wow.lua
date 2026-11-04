-- SPDX-License-Identifier: GPL-3.0-or-later
-- WoW API stand-ins for offline tests on stock Lua 5.1.
-- Unknown global names stay nil, so a missing stand-in cannot silently change a test.
-- Values follow the Forever docs (Gethe/wow-ui-source branch forever, build 70532);
-- they describe what the code expects, not measurements from a live client.
-- M.world holds the game state a test can change (player, quest log, loot, chat, ...).
local json = require("spec.helpers.json")

local M = {}

local stock_xpcall = xpcall
M.stock_xpcall = stock_xpcall

-- WoW's xpcall passes extra arguments to f (stock Lua 5.1 does not).
local function wow_xpcall(f, handler, ...)
	local n = select("#", ...)
	if n == 0 then
		return stock_xpcall(f, handler)
	end
	local args = { ... }
	return stock_xpcall(function()
		return f(unpack(args, 1, n))
	end, handler)
end

-- Opaque value that issecretvalue() reports as secret.
M.SECRET = setmetatable({}, {
	__tostring = function()
		return "SECRET-VALUE"
	end,
})

local BASE_EVENTS = {
	"ADDON_LOADED",
	"PLAYER_LOGIN",
	"PLAYER_ENTERING_WORLD",
	"PLAYER_LOGOUT",
	"QUEST_ACCEPTED",
	"QUEST_DETAIL",
	"QUEST_COMPLETE",
	"QUEST_TURNED_IN",
	"QUEST_REMOVED",
	"QUEST_LOG_UPDATE",
	"QUEST_WATCH_UPDATE",
	"QUEST_LOG_CRITERIA_UPDATE",
	"QUEST_AUTOCOMPLETE",
	"QUEST_PROGRESS",
	"QUEST_FINISHED",
	"QUEST_GREETING",
	"QUEST_DATA_LOAD_RESULT",
	"ITEM_DATA_LOAD_RESULT",
	"UNIT_QUEST_LOG_CHANGED",
	"PLAYER_XP_UPDATE",
	"PLAYER_LEVEL_UP",
	"PLAYER_STARTED_MOVING",
	"PLAYER_STOPPED_MOVING",
	"LOOT_OPENED",
	"ITEM_TEXT_BEGIN",
	"ITEM_TEXT_READY",
	"NAME_PLATE_UNIT_ADDED",
	"PLAYER_TARGET_CHANGED",
	"UPDATE_MOUSEOVER_UNIT",
	"VIGNETTE_MINIMAP_UPDATED",
	"VIGNETTES_UPDATED",
	"TAXIMAP_OPENED",
	"UI_INFO_MESSAGE",
	"GOSSIP_SHOW",
	"GOSSIP_CLOSED",
	"LOADING_SCREEN_ENABLED",
	"LOADING_SCREEN_DISABLED",
	"PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
	"ZONE_CHANGED_NEW_AREA",
	"PLAYER_CONTROL_LOST",
	"PLAYER_CONTROL_GAINED",
	"PLAYER_DEAD",
	"PARTY_KILL",
	"GROUP_ROSTER_UPDATE",
	"HEARTHSTONE_BOUND",
	"TRAINER_SHOW",
	"UNIT_SPELLCAST_SUCCEEDED",
	"PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED",
	"CHAT_MSG_ADDON",
	"CHAT_MSG_CHANNEL_NOTICE",
	"UPDATE_CHAT_WINDOWS",
	"ADDON_RESTRICTION_STATE_CHANGED",
	"ADDON_ACTION_BLOCKED",
	"ADDON_ACTION_FORBIDDEN",
	"SUPER_TRACKING_CHANGED",
	"USER_WAYPOINT_UPDATED",
	"TIME_PLAYED_MSG",
	-- valid, but registering it is a blocked action in Forever: the addon must never register it
	"COMBAT_LOG_EVENT_UNFILTERED",
}

local FLAVORS = {
	forever = {
		build = { "1.60.1", "70532", "Oct 20 2026", 16001 },
		project = 18,
		extraEvents = { "GAME_RULES_CHANGED", "INPUT_DEVICE_INTERFACE_TRANSITION" },
	},
	retail = {
		build = { "12.1.5", "70448", "Oct 14 2026", 120105 },
		project = 1,
		extraEvents = {},
	},
}

-- Widgets: the methods tests look at behave, every other widget method does nothing.
local Frame = {}
local noop = function() end
local FrameMeta = {
	__index = function(_, k)
		local m = rawget(Frame, k)
		if m ~= nil then
			return m
		end
		return noop
	end,
}

function Frame:RegisterEvent(event)
	-- Since 8.0.1 the client throws for unknown event names.
	if not M.knownEvents[event] then
		error(('Attempt to register unknown event "%s"'):format(tostring(event)), 2)
	end
	self.events[event] = true
end

function Frame:UnregisterEvent(event)
	self.events[event] = nil
end

function Frame:SetScript(name, fn)
	self.scripts[name] = fn
end

function Frame:GetScript(name)
	return self.scripts[name]
end

function Frame:SetText(text)
	self.text = text
end

function Frame:GetText()
	return self.text
end

function Frame:Show()
	self.shown = true
end

function Frame:Hide()
	self.shown = false
end

function Frame:IsShown()
	return self.shown == true
end

function Frame:SetAttribute(k, v)
	self.attributes[k] = v
end

function Frame:GetAttribute(k)
	return self.attributes[k]
end

local function NewWidget(kind, name, template, parent)
	local f = setmetatable(
		{ type = kind, name = name, template = template, parent = parent, events = {}, scripts = {}, attributes = {} },
		FrameMeta
	)
	M.frames[#M.frames + 1] = f
	if name then
		_G[name] = f
	end
	return f
end

function Frame:CreateFontString(_, layer, template)
	local fs = NewWidget("FontString", nil, template, self)
	fs.layer = layer
	return fs
end

function Frame:CreateTexture(_, layer, _, sublevel)
	local t = NewWidget("Texture", nil, nil, self)
	t.layer, t.sublevel = layer, sublevel
	return t
end

-- For the UI stand-ins in spec/helpers/ui.lua.
M.Frame = Frame
M.NewWidget = NewWidget

local function join(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	return table.concat(parts, " ")
end

-- Default game state; tests change fields of M.world after reset.
local function NewWorld(flavor)
	return {
		player = {
			name = "Testchar",
			surname = "Brightwood",
			realm = "Testrealm",
			guid = "Player-1234-0ABCDEF0",
			race = { "Mensch", "Human", 1 }, -- UnitRace: localized, raceFile, raceID
			class = { "Krieger", "WARRIOR", 1 }, -- UnitClass: localized, classFile, classID
			faction = { "Alliance", "Allianz" },
			level = 5,
			xp = 120,
			xpMax = 400,
			rested = nil,
			map = 1429,
			x = 0.4231,
			y = 0.6512,
		},
		npc = nil, -- { guid = "Creature-...", name = "..." } while a dialog is open
		units = {}, -- token -> { guid, name, classification, level }
		questID = nil, -- GetQuestID() in an open quest dialog
		offers = {}, -- quest IDs the open NPC dialog lists (GOSSIP_SHOW, QUEST_GREETING)
		-- { { questID = n, objectives = { { numFulfilled, numRequired, finished } }, complete = bool,
		--    rewardXP = n } }
		questLog = {},
		completed = {}, -- questID -> true
		mapInfo = {}, -- uiMapID -> { mapID, name, parentMapID } (C_Map.GetMapInfo)
		loot = {}, -- { { link = "...", sources = { guid, count, ... } } }
		fishing = false,
		itemText = "Ein altes Buch",
		taxi = { mapID = 1429, nodes = {} },
		vignettes = {}, -- guid -> { info = {...}, x = 0.1, y = 0.2 }
		onTaxi = false,
		combat = false,
		instance = false, -- IsInInstance (a dungeon, raid, battleground or arena)
		fps = 60, -- GetFramerate
		group = { instance = false, raid = false, party = false, members = 0 },
		guild = false,
		trial = false,
		veteran = false,
		lockdown = false,
		prefixes = {},
		sent = {}, -- { prefix, msg, dist, target }
		sendResult = function()
			return 0
		end,
		channels = {}, -- joined channel name -> number
		refuse = {}, -- channel name -> notice kind sent on join
		removedFromChat = {},
		chatFilters = {},
		cvars = { questTextContrast = "0", showInGameNavigation = "0" },
		serverTime = 1793836800, -- 2026-11-05 00:00 UTC
		ctrl = false,
		inputStyle = 0, -- C_InputInterfaceStyle.GetCurrentStyle in Forever: 0 mouse and keyboard, 1 gamepad
		flavor = flavor,
	}
end

-- Fresh client state. opts: flavor ("forever" | "retail"), locale, version, saved (BraindeadForeverDB),
-- collect (BraindeadForeverCollectDB), char (BraindeadForeverCharDB), player (fields of world.player to change).
function M.reset(opts)
	opts = opts or {}
	local flavor = FLAVORS[opts.flavor or "forever"]
	M.flavor = opts.flavor or "forever"
	M.clock = 1000
	M.timers = {}
	M.timerSeq = 0
	M.frames = {}
	M.errors = {}
	M.printed = {}
	M.knownEvents = {}
	for _, e in ipairs(BASE_EVENTS) do
		M.knownEvents[e] = true
	end
	for _, e in ipairs(flavor.extraEvents) do
		M.knownEvents[e] = true
	end
	local W = NewWorld(M.flavor)
	for k, v in pairs(opts.player or {}) do -- e.g. a new character: { level = 1, xp = 0 }
		W.player[k] = v
	end
	M.world = W
	local forever = M.flavor == "forever"

	_G.xpcall = wow_xpcall
	_G.GetTime = function()
		return M.clock
	end
	_G.GetServerTime = function()
		return W.serverTime + math.floor(M.clock - 1000)
	end
	_G.debugprofilestop = function()
		return M.clock * 1000
	end
	_G.issecretvalue = function(v)
		return v == M.SECRET
	end
	_G.geterrorhandler = function()
		return function(msg)
			M.errors[#M.errors + 1] = msg
		end
	end
	_G.debugstack = function()
		return "stack"
	end
	_G.print = function(...)
		M.printed[#M.printed + 1] = join(...)
	end
	_G.CreateFrame = function(frameType, name, parent, template)
		return NewWidget(frameType, name, template, parent)
	end
	_G.UIParent = NewWidget("Frame")
	_G.UISpecialFrames = {}
	_G.tinsert = table.insert
	_G.CLOSE = "Close"
	_G.ChatFontNormal = {}
	_G.IsControlKeyDown = function()
		return W.ctrl
	end
	_G.IsMetaKeyDown = function()
		return false
	end
	_G.InCombatLockdown = function()
		return W.combat
	end
	_G.IsInInstance = function()
		return W.instance, W.instance and "party" or "none"
	end
	_G.GetFramerate = function()
		return W.fps
	end
	_G.C_EventUtils = {
		IsEventValid = function(event)
			return M.knownEvents[event] == true
		end,
	}
	_G.C_Timer = {
		After = function(seconds, callback)
			M.schedule(seconds, callback)
		end,
		NewTimer = function(seconds, callback)
			local t = M.schedule(seconds, callback)
			t.passHandle = true
			return t
		end,
		NewTicker = function(seconds, callback)
			return M.schedule(seconds, callback, seconds)
		end,
	}
	_G.C_AddOns = {
		GetAddOnMetadata = function(_, field)
			if field == "Version" then
				return opts.version or "@project-version@"
			end
		end,
	}
	_G.GetLocale = function()
		return opts.locale or "enUS"
	end
	_G.date = os.date -- the client's date() is Lua's os.date
	-- Race and class names (Forever CreatureInfoDocumentation.lua: GetRaceInfo -> raceName, GetClassInfo
	-- -> className); a few IDs in the client language of the test.
	local RACES = { [1] = { "Human", "Mensch" }, [2] = { "Orc", "Orc" }, [3] = { "Dwarf", "Zwerg" } }
	local CLASSES = { [1] = { "Warrior", "Krieger" }, [3] = { "Hunter", "Jäger" }, [8] = { "Mage", "Magier" } }
	local lang = opts.locale == "deDE" and 2 or 1
	_G.C_CreatureInfo = {
		GetRaceInfo = function(id)
			local r = RACES[id]
			return r and { raceName = r[lang], raceID = id }
		end,
		GetClassInfo = function(id)
			local c = CLASSES[id]
			return c and { className = c[lang], classID = id }
		end,
	}
	_G.GetBuildInfo = function()
		return unpack(flavor.build)
	end
	_G.WOW_PROJECT_MAINLINE = 1
	_G.WOW_PROJECT_CLASSIC = 2
	_G.WOW_PROJECT_ID = flavor.project

	_G.Enum = {
		SendAddonMessageResult = {
			Success = 0,
			InvalidPrefix = 1,
			InvalidMessage = 2,
			AddonMessageThrottle = 3,
			InvalidChatType = 4,
			NotInGroup = 5,
			TargetRequired = 6,
			InvalidChannel = 7,
			ChannelThrottle = 8,
			GeneralError = 9,
			NotInGuild = 10,
			AddOnMessageLockdown = 11,
			TargetOffline = 12,
		},
		RegisterAddonMessagePrefixResult = { Success = 0, DuplicatePrefix = 1, InvalidPrefix = 2, MaxPrefixes = 3 },
		FlightPathState = { Current = 0, Reachable = 1, Unreachable = 2 },
		CompressionMethod = { Deflate = 0, Zlib = 1, Gzip = 2 },
		CompressionLevel = { Default = 0, OptimizeForSpeed = 1, OptimizeForSize = 2 },
		Base64Variant = { Standard = 0, StandardUrlSafe = 1 },
		AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
		AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 },
		AddOnProfilerMetric = { SessionAverageTime = 0, RecentAverageTime = 1 },
		InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 },
	}

	-- Player and units
	local P = W.player
	local function unit(u)
		if u == "npc" then
			return W.npc
		end
		return W.units[u]
	end
	_G.UnitGUID = function(u)
		if u == "player" then
			return P.guid
		end
		local x = unit(u)
		return x and x.guid
	end
	_G.UnitName = function(u)
		if u == "player" then
			return P.name, forever and P.surname or nil
		end
		local x = unit(u)
		return x and x.name
	end
	_G.GetUnitName = function(u)
		if u == "player" then
			return forever and (P.name .. " " .. P.surname) or P.name
		end
		local x = unit(u)
		return x and x.name
	end
	_G.Ambiguate = function(name)
		return name
	end
	_G.GetRealmName = function()
		return P.realm
	end
	_G.UnitLevel = function(u)
		if u == "player" then
			return P.level
		end
		local x = unit(u)
		return x and x.level or 0
	end
	_G.UnitClassification = function(u)
		local x = unit(u)
		return x and x.classification or "normal"
	end
	_G.UnitRace = function()
		return P.race[1], P.race[2], P.race[3]
	end
	_G.UnitClass = function()
		return P.class[1], P.class[2], P.class[3]
	end
	_G.UnitFactionGroup = function()
		return P.faction[1], P.faction[2]
	end
	_G.UnitXP = function()
		return P.xp
	end
	_G.UnitXPMax = function()
		return P.xpMax
	end
	_G.GetXPExhaustion = function()
		return P.rested
	end
	_G.UnitOnTaxi = function()
		return W.onTaxi
	end
	_G.GetNumGroupMembers = function()
		return W.group.members
	end
	_G.LE_PARTY_CATEGORY_HOME = 1
	_G.LE_PARTY_CATEGORY_INSTANCE = 2
	_G.IsInGroup = function(category)
		if category == 2 then
			return W.group.instance
		end
		return W.group.party or W.group.raid or W.group.instance
	end
	_G.IsInRaid = function()
		return W.group.raid
	end
	_G.IsInGuild = function()
		return W.guild
	end

	-- Map
	_G.C_Map = {
		GetBestMapForUnit = function(u)
			if u == "player" then
				return P.map
			end
		end,
		GetPlayerMapPosition = function(_, u)
			if u == "player" and P.x ~= nil then
				return { x = P.x, y = P.y }
			end
		end,
		GetMapInfo = function(id)
			return W.mapInfo[id]
		end,
	}

	-- Quests
	local log = function()
		return W.questLog
	end
	_G.C_QuestLog = {
		GetNumQuestLogEntries = function()
			return #log(), #log()
		end,
		GetInfo = function(i)
			local e = log()[i]
			return e and { questID = e.questID, isHeader = e.isHeader == true }
		end,
		GetQuestObjectives = function(q)
			for _, e in ipairs(log()) do
				if e.questID == q then
					return e.objectives or {}
				end
			end
		end,
		GetLogIndexForQuestID = function(q)
			for i, e in ipairs(log()) do
				if e.questID == q and not e.isHeader then
					return i
				end
			end
		end,
		IsQuestFlaggedCompleted = function(q)
			return W.completed[q] == true
		end,
		IsComplete = function(q)
			for _, e in ipairs(log()) do
				if e.questID == q then
					return e.complete == true
				end
			end
			return false
		end,
		IsFailed = function()
			return false
		end,
	}
	if forever then
		_G.C_QuestLog.GetTrivialRange = function()
			return 5
		end
	end
	_G.GetQuestID = function()
		return W.questID
	end
	-- NPC offers: gossip list (C_GossipInfo) and greeting list (indexed globals), quest IDs only.
	_G.C_GossipInfo = {
		GetAvailableQuests = function()
			local out = {}
			for i, q in ipairs(W.offers) do
				out[i] = { questID = q, title = "Quest " .. q }
			end
			return out
		end,
	}
	_G.GetNumAvailableQuests = function()
		return #W.offers
	end
	_G.GetAvailableQuestInfo = function(i)
		return false, 0, false, false, W.offers[i]
	end
	-- Quest dialog (Mainline/QuestFrame.lua, Forever): W.dialog holds what the open dialog shows; every
	-- call is recorded in W.dialog.calls and changes nothing, like a call the server ignores. A test plays
	-- the server's answer by firing the next event.
	W.dialog = {
		calls = {}, -- { "AcceptQuest" }, { "SelectAvailableQuest", i }, ...
		active = {}, -- gossip and greeting: quests to hand in, { { questID = n, isComplete = bool } }
		choices = 0, -- GetNumQuestChoices
		completable = true,
		money = 0, -- GetQuestMoneyToGet
		autoAccept = false,
		areaTrigger = false,
		pvp = false,
	}
	local D = W.dialog
	local function record(name)
		return function(...)
			D.calls[#D.calls + 1] = { name, ... }
		end
	end
	for _, name in ipairs({
		"AcceptQuest",
		"AcknowledgeAutoAcceptQuest",
		"ConfirmAcceptQuest",
		"CompleteQuest",
		"GetQuestReward",
		"SelectActiveQuest",
		"SelectAvailableQuest",
		"DeclineQuest",
		"CloseQuest",
	}) do
		_G[name] = record(name)
	end
	_G.C_GossipInfo.SelectActiveQuest = record("C_GossipInfo.SelectActiveQuest")
	_G.C_GossipInfo.SelectAvailableQuest = record("C_GossipInfo.SelectAvailableQuest")
	_G.C_GossipInfo.SelectOption = record("C_GossipInfo.SelectOption")
	_G.C_GossipInfo.CloseGossip = record("C_GossipInfo.CloseGossip")
	_G.C_GossipInfo.GetActiveQuests = function()
		local out = {}
		for i, a in ipairs(D.active) do
			out[i] = { questID = a.questID, title = "Quest " .. a.questID, isComplete = a.isComplete }
		end
		return out
	end
	_G.GetNumActiveQuests = function()
		return #D.active
	end
	_G.GetActiveTitle = function(i)
		local a = D.active[i]
		if a then
			return "Quest " .. a.questID, a.isComplete == true
		end
	end
	_G.GetActiveQuestID = function(i)
		return D.active[i] and D.active[i].questID
	end
	_G.GetNumQuestChoices = function()
		return D.choices
	end
	_G.IsQuestCompletable = function()
		return D.completable
	end
	_G.GetQuestMoneyToGet = function()
		return D.money
	end
	_G.QuestGetAutoAccept = function()
		return D.autoAccept
	end
	_G.QuestIsFromAreaTrigger = function()
		return D.areaTrigger
	end
	_G.QuestFlagsPVP = function()
		return D.pvp
	end
	_G.GetQuestLogRewardXP = function(q)
		for _, e in ipairs(log()) do
			if e.questID == q and e.rewardXP then
				return e.rewardXP, e.rewardXP
			end
		end
		return 40, 40
	end

	-- Loot, books, flight masters, vignettes
	_G.GetNumLootItems = function()
		return #W.loot
	end
	_G.GetLootSlotLink = function(i)
		return W.loot[i] and W.loot[i].link
	end
	_G.GetLootSourceInfo = function(i)
		local s = W.loot[i] and W.loot[i].sources
		if s then
			return unpack(s)
		end
	end
	_G.IsFishingLoot = function()
		return W.fishing
	end
	_G.ItemTextGetItem = function()
		return W.itemText
	end
	_G.GetTaxiMapID = function()
		return W.taxi.mapID
	end
	_G.C_TaxiMap = {
		GetAllTaxiNodes = function()
			return W.taxi.nodes
		end,
	}
	-- W.taxi.routes[slot] = { slot, slot, ... }: the slots of the trip to `slot`, start first.
	_G.GetNumRoutes = function(slot)
		W.taxi.reads = (W.taxi.reads or 0) + 1
		local r = W.taxi.routes and W.taxi.routes[slot]
		return r and #r - 1 or 0
	end
	_G.TaxiGetNodeSlot = function(slot, leg, isSource)
		local r = W.taxi.routes and W.taxi.routes[slot]
		return r and r[isSource and leg or leg + 1]
	end
	_G.TakeTaxiNode = function(slot)
		W.taxi.taken = slot
	end
	-- Post-hook as in the client: the original runs first, then the hook with the same arguments.
	_G.hooksecurefunc = function(a, b, c)
		local t, name, fn = _G, a, b
		if type(a) == "table" then
			t, name, fn = a, b, c
		end
		local original = t[name]
		t[name] = function(...)
			local r = { original(...) }
			fn(...)
			return unpack(r)
		end
	end
	_G.ERR_NEWTAXIPATH = "New flight path discovered!"
	_G.C_VignetteInfo = {
		GetVignetteInfo = function(guid)
			return W.vignettes[guid] and W.vignettes[guid].info
		end,
		GetVignettePosition = function(guid)
			local v = W.vignettes[guid]
			return v and { x = v.x, y = v.y }
		end,
	}

	-- Chat and addon messages
	_G.C_ChatInfo = {
		RegisterAddonMessagePrefix = function(prefix)
			if W.prefixes[prefix] then
				return 1
			end
			W.prefixes[prefix] = true
			return 0
		end,
		SendAddonMessage = function(prefix, msg, dist, target)
			local r = W.sendResult(prefix, msg, dist, target)
			W.sent[#W.sent + 1] = { prefix = prefix, msg = msg, dist = dist, target = target, result = r, at = M.clock }
			return r
		end,
		InChatMessagingLockdown = function()
			return W.lockdown
		end,
		AreOutgoingAddonChatMessagesRestricted = function()
			return false
		end,
	}
	_G.IsTrialAccount = function()
		return W.trial
	end
	_G.IsVeteranTrialAccount = function()
		return W.veteran
	end
	_G.JoinTemporaryChannel = function(name)
		local refused = W.refuse[name]
		if refused then
			M.fire("CHAT_MSG_CHANNEL_NOTICE", refused, "", "", "", "", "", 0, 0, name)
			return
		end
		W.channels[name] = 5
	end
	_G.GetChannelName = function(name)
		return W.channels[name] or 0
	end
	_G.LeaveChannelByName = function(name)
		W.channels[name] = nil
	end
	_G.NUM_CHAT_WINDOWS = 1
	_G.ChatFrame1 = {
		RemoveChannel = function(_, name)
			W.removedFromChat[name] = true
		end,
	}
	_G.ChatFrameUtil = {
		AddMessageEventFilter = function(event, fn)
			W.chatFilters[event] = fn
		end,
	}

	-- Encoding: JSON and Base64 real, "compression" reversible and tagged with the method.
	local decoded = {}
	_G.C_EncodingUtil = {
		SerializeJSON = function(t)
			local s = json.encode(t)
			decoded[s] = t
			return s
		end,
		DeserializeJSON = function(s)
			return decoded[s]
		end,
		CompressString = function(s, method)
			return ("Z%d:%s"):format(method or 0, s)
		end,
		DecompressString = function(s, method)
			local m, body = s:match("^Z(%d+):(.*)$")
			if tonumber(m) == (method or 0) then
				return body
			end
		end,
		EncodeBase64 = function(s)
			return json.b64encode(s)
		end,
		DecodeBase64 = function(s)
			return json.b64decode(s)
		end,
	}
	_G.C_CVar = {
		GetCVar = function(name)
			return W.cvars[name]
		end,
	}

	if forever then
		_G.C_InputInterfaceStyle = {
			GetCurrentStyle = function()
				return W.inputStyle
			end,
		}
	else
		_G.C_InputInterfaceStyle = nil -- Retail 12.1.5 has no gamepad UI style
	end
	if forever then
		_G.WOW_PROJECT_CAMELOT = 18
		_G.C_SkillInfo = { AbandonSkill = function() end }
		_G.C_GameRules = {
			GetForeverExperiencePreset = function()
				return 1
			end,
			IsHardcoreActive = function()
				return false
			end,
		}
	else
		_G.WOW_PROJECT_CAMELOT = nil
		-- Retail 12.1.5 documents C_SkillInfo with no functions: a namespace without the call.
		_G.C_SkillInfo = {}
		_G.C_GameRules = {}
	end
	_G.SlashCmdList = {}
	_G.SLASH_BRAINDEADFOREVER1 = nil
	_G.SLASH_BRAINDEADFOREVER2 = nil
	_G.SLASH_BRAINDEADFOREVER3 = nil
	-- the key binding handler holds the last session's namespace (UI/Bindings.lua): a fresh client has none
	_G.BraindeadForeverBinding = nil
	_G.BraindeadForeverDB = opts.saved
	_G.BraindeadForeverCollectDB = opts.collect
	_G.BraindeadForeverCharDB = opts.char
	_G.BraindeadForeverCopyFrame = nil
	-- Interface stand-ins (settings, menus, fonts, atlases, map, minimap): spec/helpers/ui.lua.
	require("spec.helpers.ui").install(M, W, opts)
end

-- Schedule a callback on the fake clock. interval makes it a ticker. Returns a handle with Cancel.
function M.schedule(seconds, fn, interval)
	M.timerSeq = M.timerSeq + 1
	local t = { at = M.clock + seconds, fn = fn, interval = interval, seq = M.timerSeq }
	function t.Cancel()
		t.cancelled = true
	end
	function t.IsCancelled()
		return t.cancelled == true
	end
	M.timers[#M.timers + 1] = t
	return t
end

-- Fire an event at every frame that registered it (like the client).
function M.fire(event, ...)
	for _, f in ipairs(M.frames) do
		local handler = f.scripts.OnEvent
		if f.events[event] and handler then
			handler(f, event, ...)
		end
	end
end

-- Advance the clock and run due timers in time order; tickers run again every interval.
function M.advance(seconds)
	local target = M.clock + seconds
	while true do
		local best, bi
		for i, t in ipairs(M.timers) do
			if
				not t.cancelled
				and t.at <= target
				and (not best or t.at < best.at or (t.at == best.at and t.seq < best.seq))
			then
				best, bi = t, i
			end
		end
		if not best then
			break
		end
		table.remove(M.timers, bi)
		M.clock = math.max(M.clock, best.at)
		if best.passHandle or best.interval then
			best.fn(best) -- timers and tickers get their handle, C_Timer.After callbacks nothing
		else
			best.fn()
		end
		if best.interval and not best.cancelled then
			M.timerSeq = M.timerSeq + 1
			best.at, best.seq = best.at + best.interval, M.timerSeq
			M.timers[#M.timers + 1] = best
		end
	end
	M.clock = target
	for i = #M.timers, 1, -1 do
		if M.timers[i].cancelled then
			table.remove(M.timers, i)
		end
	end
end

-- Load one addon file like the client: with (addonName, ns) as varargs.
function M.loadFile(path, addonName, ns)
	local chunk = assert(loadfile(path))
	chunk(addonName, ns)
	return ns
end

-- Load several addon files into one namespace.
function M.loadFiles(paths, addonName, ns)
	ns = ns or {}
	for _, p in ipairs(paths) do
		M.loadFile(p, addonName or "Braindead4Ever", ns)
	end
	return ns
end

-- Every file of the addon in TOC order (without the developer probe unless asked).
function M.addonFiles(withProbe)
	local files = {
		"Braindead4Ever/Locales/enUS.lua",
		"Braindead4Ever/Core/Util.lua",
		"Braindead4Ever/Core/Guard.lua",
		"Braindead4Ever/Core/Modules.lua",
		"Braindead4Ever/Core/CopyWindow.lua",
		"Braindead4Ever/Collector/Migrate.lua",
		"Braindead4Ever/Collector/Store.lua",
		"Braindead4Ever/Collector/Export.lua",
		"Braindead4Ever/Collector/Proto.lua",
		"Braindead4Ever/Collector/Runs.lua",
		"Braindead4Ever/Collector/Flights.lua",
		"Braindead4Ever/Collector/Budget.lua",
		"Braindead4Ever/Collector/Version.lua",
		"Braindead4Ever/Collector/Collect.lua",
		"Braindead4Ever/Collector/Exchange.lua",
		"Braindead4Ever/Core/Report.lua",
		"Braindead4Ever/Routes/Routes.lua",
		"Braindead4Ever/Routes/Data_Alliance.lua",
		"Braindead4Ever/Routes/Data_Horde.lua",
		"Braindead4Ever/Routes/Data_Flights.lua",
		"Braindead4Ever/Routes/Data_Npcs.lua",
		"Braindead4Ever/Routes/XP.lua",
		"Braindead4Ever/Routes/Prereq.lua",
		"Braindead4Ever/Routes/Discover.lua",
		"Braindead4Ever/Routes/Dungeon.lua",
		"Braindead4Ever/Routes/Hardcore.lua",
		"Braindead4Ever/Routes/Forecast.lua",
		"Braindead4Ever/Routes/Stats.lua",
		"Braindead4Ever/Routes/Runtime.lua",
		"Braindead4Ever/Routes/Replan.lua",
		"Braindead4Ever/Routes/Guide.lua",
		"Braindead4Ever/Routes/Explore.lua",
		"Braindead4Ever/Routes/RunStats.lua",
		"Braindead4Ever/UI/Core.lua",
		"Braindead4Ever/UI/Theme.lua",
		"Braindead4Ever/UI/Nav.lua",
		"Braindead4Ever/UI/Connect.lua",
		"Braindead4Ever/UI/NpcNames.lua",
		"Braindead4Ever/UI/StepText.lua",
		"Braindead4Ever/UI/Menu.lua",
		"Braindead4Ever/UI/StepFrame.lua",
		"Braindead4Ever/UI/QuestItem.lua",
		"Braindead4Ever/UI/Arrow.lua",
		"Braindead4Ever/UI/TomTom.lua",
		"Braindead4Ever/UI/MapPins.lua",
		"Braindead4Ever/UI/QuestWatch.lua",
		"Braindead4Ever/UI/Auto.lua",
		"Braindead4Ever/UI/Minimap.lua",
		"Braindead4Ever/UI/Setup.lua",
		"Braindead4Ever/UI/Settings.lua",
		"Braindead4Ever/UI/StatsPage.lua",
		"Braindead4Ever/UI/Bindings.lua",
	}
	if withProbe then
		files[#files + 1] = "Braindead4Ever/Probe/Probe.lua"
		files[#files + 1] = "Braindead4Ever/Probe/Checks.lua"
		files[#files + 1] = "Braindead4Ever/Probe/Preview.lua"
	end
	files[#files + 1] = "Braindead4Ever/Core/Boot.lua"
	return files
end

-- A full session: load every file, ADDON_LOADED, PLAYER_LOGIN, PLAYER_ENTERING_WORLD.
-- opts as in reset, plus probe = true to load the developer probe.
function M.session(opts)
	opts = opts or {}
	M.reset(opts)
	local ns = M.loadFiles(M.addonFiles(opts.probe))
	M.fire("ADDON_LOADED", "Braindead4Ever")
	M.fire("PLAYER_LOGIN")
	M.fire("PLAYER_ENTERING_WORLD", true, false)
	M.ns = ns
	return ns
end

-- Received addon messages wait in the exchange's inbox (Collector/Exchange.lua) until its ticker reads
-- a slice; this reads all of them now, under the same rules (nothing in a fight or an instance).
function M.readInbox(ns)
	local X = (ns or M.ns).Exchange
	while X.Drain() > 0 do
	end
end

-- Lets the exchange send on the hidden channel whenever the rest of its rules allow: the channel
-- budget (Collector/Budget.lua) grants every credit. For tests of delays, gaps and order.
function M.freeChannel(ns)
	local X = (ns or M.ns).Exchange
	X.budget = {
		Has = function()
			return true
		end,
		Spend = function() end,
		Heard = function() end,
	}
end

-- Lines printed so far, as one string.
function M.output()
	return table.concat(M.printed, "\n")
end

return M
