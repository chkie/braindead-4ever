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

-- Collector/Collect.lua: the data collector. Records quests, experience, positions and discoveries
-- (objects, books, rare enemies, vignettes, flight masters) as text records in a ring buffer
-- (Store.lua) and offers discoveries to the in-game exchange (Exchange.lua).
-- Patterns after Polestar Recorder (GPL-3.0), QuestieTrace (GPL-3.0) and JourneyTracker (MIT); own code.
-- Anonymity: never the player's, realm, guild or chat names; player GUIDs are dropped; time inside a
-- chunk is relative, the date only as a day number. The combat log is never registered (in Forever it
-- is a blocked action at every login, JourneyTracker 0.6.5).
-- Contributing data is part of the addon: the module is core and mandatory (no flag turns it off).
local _, ns = ...
local L = ns.L
local U, Store, Migrate, Export = ns.Util, ns.Store, ns.Migrate, ns.Export
local M, Guard = ns.Modules, ns.Guard
local Num, Str, Ref, Pos, ParseGUID = U.Num, U.Str, U.Ref, U.Pos, U.ParseGUID

local C = {
	SCHEMA = 1, -- PathmarkCollectDB layout
	CONTEXT_TTL = 600, -- seconds a quest dialog context stays valid (Polestar)
	POS_EVERY = 2, -- position sample interval in seconds
	POS_STEP = 50, -- minimum move between samples, hundredths of a percent of the map (about 15 yd)
	SAVE_EVERY = 60, -- refresh of the open chunk: a /reload or crash loses at most a minute
	OWN_BYTES = 2 * 1024 * 1024, -- own records
	NET_BYTES = 1024 * 1024, -- finds received from other players (own data is never pushed out by them)
	EXPORT_RAW_MAX = 1024 * 1024, -- raw bytes per export text; the rest comes with the next export
	CODEC = "d", -- Deflate; "z" only after the probe check enc.zlib passed in the client
}
ns.Collector = C

-- Versioned layout of PathmarkCollectDB. Step v lifts version v-1 to v.
C.STEPS = {
	[1] = function(d)
		d.install = d.install or U.NewId(12)
	end,
}

local own, net -- Store instances: own records, received finds
local api = {} -- optional client functions, resolved at init
local tickers = {}
local detail, completion -- quest dialog contexts
local turnedIn, active, lastObj = {}, {}, {}
local npcSeen, rareSeen, vignetteSeen = {}, {}, {}
local scanQueued, lastMap, lastX, lastY, onTaxi, rosterTimer = false, nil, nil, nil, false, nil

local function Rec(kind, map, x, y, ...)
	if own then
		own:Write(nil, kind, map, x, y, ...)
	end
end

-- Record at the player's current position. Returns the position for offers.
local function Here(kind, ...)
	local map, x, y = Pos()
	Rec(kind, map, x, y, ...)
	return map, x, y
end

local function Offer(kind, ...)
	local X = ns.Exchange
	if X and X.Offer then
		X.Offer(kind, ...)
	end
end

local function Call(fn, ...)
	if not fn then
		return
	end
	local ok, a, b = pcall(fn, ...)
	if ok then
		return a, b
	end
end

-- Received finds from the exchange go into their own buffer.
function C.RecordNet(kind, ...)
	if net and net:IsOpen() then
		return net:Write(nil, kind, ...)
	end
	return false
end

-- NPC name in the client language, once per NPC and session (Plan: NPC names come from the collectors).
local function NoteNpc(k, id, name, map, x, y)
	if k ~= "c" or not id or npcSeen[id] then
		return
	end
	npcSeen[id] = true
	Rec("npc", map, x, y, id, name)
end

-- Remember quest giver and position when the dialog opens; at QUEST_ACCEPTED or QUEST_TURNED_IN the
-- window is often closed already (Polestar: context from QUEST_DETAIL or QUEST_COMPLETE, 600 s).
local function Context(questStartItemID)
	local k, id = Ref("npc")
	local map, x, y = Pos()
	local name = (k == "c") and Str((UnitName("npc"))) or nil
	NoteNpc(k, id, name, map, x, y)
	return {
		q = Num((Call(api.GetQuestID))),
		k = k,
		id = id,
		item = Num(questStartItemID),
		name = name,
		map = map,
		x = x,
		y = y,
		at = GetTime(),
	}
end

local function Take(ctx, q)
	if ctx and ctx.q == q and GetTime() - ctx.at < C.CONTEXT_TTL then
		return ctx
	end
end

-- Objectives: events are only markers; the quest log is read in one batch (Polestar queueScan).
local function Scan()
	scanQueued = false
	if not own then
		return
	end
	local ids = {}
	local shown, count = C_QuestLog.GetNumQuestLogEntries()
	for i = 1, math.max(Num(shown) or 0, Num(count) or 0) do
		local info = C_QuestLog.GetInfo(i)
		local q = info and not info.isHeader and Num(info.questID)
		if q and q > 0 then
			ids[q] = true
		end
	end
	for q in pairs(active) do
		ids[q] = true
	end
	local map, x, y
	for q in pairs(ids) do
		local parts = {}
		for j, o in ipairs(C_QuestLog.GetQuestObjectives(q) or {}) do
			parts[j] = ("%d/%d"):format(Num(o.numFulfilled) or 0, Num(o.numRequired) or 0)
		end
		local s = table.concat(parts, ";")
		if lastObj[q] and lastObj[q] ~= s then
			if not map then
				map, x, y = Pos()
			end
			Rec("progress", map, x, y, q, s)
		end
		lastObj[q] = s
	end
end
local ScanSafe = Guard.Wrap("collector", Scan)

local function QueueScan()
	if scanQueued then
		return
	end
	scanQueued = true
	C_Timer.After(0.2, ScanSafe)
end

-- Rare enemies from name plates, target and mouseover; once per NPC and session.
local RARE = { rare = true, rareelite = true, worldboss = true }
local function SeeRare(unit, src)
	local cls = Str(Call(UnitClassification, unit))
	if not (cls and RARE[cls]) then
		return
	end
	local k, id = Ref(unit)
	if k ~= "c" or rareSeen[id] then
		return
	end
	rareSeen[id] = true
	local map, x, y = Here("rare", id, cls, Num((Call(UnitLevel, unit))), Str((Call(UnitName, unit))), src)
	if map and x and y then
		Offer("r", id, ns.Proto.CLASS_OF[cls], map, x, y)
	end
end

-- Vermaechtnis (legacy) ranks of the adventure tree 1188, the way Blizzard_LegacySystemUtil.lua reads
-- them (chapter 14 pattern 4). "nodeID:rank;..." or nil when the client does not offer the system.
local function Legacy()
	local LC = type(Constants) == "table" and Constants.LegacyConsts
	if not (LC and api.GetConfigIDByTreeID and api.GetTreeNodes and api.GetNodeInfo) then
		return nil
	end
	local tree = LC.LEGACY_TREE_ADVENTURE_ID
	local config = Num((Call(api.GetConfigIDByTreeID, tree)))
	if not config then
		return nil
	end
	local parts = {}
	for _, node in ipairs(Call(api.GetTreeNodes, tree) or {}) do
		local info = Call(api.GetNodeInfo, config, node)
		local rank = info and Num(info.currentRank)
		if rank and rank > 0 then
			parts[#parts + 1] = ("%d:%d"):format(node, rank)
		end
	end
	return table.concat(parts, ";")
end

local function Header()
	local _, race = UnitRace("player")
	local _, class = UnitClass("player")
	local _, build = GetBuildInfo()
	local preset = Call(api.GetForeverExperiencePreset)
	local hardcore = Call(api.IsHardcoreActive)
	return U.Pack(
		PathmarkCharDB.id,
		Str(race),
		Str(class),
		Str((UnitFactionGroup("player"))),
		Num(UnitLevel("player")),
		GetLocale(),
		tonumber(build),
		ns.version,
		Num(preset),
		hardcore == true,
		Legacy()
	)
end

-- Write the live state back into whatever table the globals hold now (Polestar trap).
local function Save()
	if not own then
		return
	end
	local root = PathmarkCollectDB
	if type(root) ~= "table" then
		root = {}
	end
	if root ~= C.root then
		for k, v in pairs(C.root) do
			if root[k] == nil and k ~= "own" and k ~= "net" then
				root[k] = v
			end
		end
	end
	root.own = own:Rebind(root.own)
	root.net = net:Rebind(root.net)
	own:Flush()
	net:Flush()
	PathmarkCollectDB, C.root = root, root
	if type(PathmarkCharDB) ~= "table" then
		PathmarkCharDB = { id = C.charId }
	end
end
C.Save = Save

local function SamplePosition()
	local map, x, y = Pos()
	if not (map and x and y) then
		return
	end
	if map == lastMap and math.abs(x - lastX) + math.abs(y - lastY) < C.POS_STEP then
		return
	end
	lastMap, lastX, lastY = map, x, y
	Rec("pos", map, x, y)
end

local function Start()
	if not own or own:IsOpen() then
		return
	end
	local header = Header()
	own:Open(header)
	net:Open(header)
	Here("zone")
	Rec("group", nil, nil, nil, Num(GetNumGroupMembers()) or 0)
	QueueScan()
	tickers[#tickers + 1] = C_Timer.NewTicker(
		C.SAVE_EVERY,
		Guard.Wrap("collector", function()
			if not InCombatLockdown() then
				Save()
			end
		end)
	)
	tickers[#tickers + 1] = C_Timer.NewTicker(C.POS_EVERY, Guard.Wrap("collector", SamplePosition))
end

local function Init()
	-- No math.randomseed: the client seeds math.random itself (JourneyTracker: some clients ignore it).
	for name, path in pairs({
		GetQuestID = "GetQuestID",
		GetQuestLogRewardXP = "GetQuestLogRewardXP",
		GetLootSourceInfo = "GetLootSourceInfo",
		IsFishingLoot = "IsFishingLoot",
		ItemTextGetItem = "ItemTextGetItem",
		GetTaxiMapID = "GetTaxiMapID",
		GetAllTaxiNodes = "C_TaxiMap.GetAllTaxiNodes",
		UnitOnTaxi = "UnitOnTaxi",
		GetVignetteInfo = "C_VignetteInfo.GetVignetteInfo",
		GetVignettePosition = "C_VignetteInfo.GetVignettePosition",
		GetConfigIDByTreeID = "C_Traits.GetConfigIDByTreeID",
		GetTreeNodes = "C_Traits.GetTreeNodes",
		GetNodeInfo = "C_Traits.GetNodeInfo",
		GetForeverExperiencePreset = "C_GameRules.GetForeverExperiencePreset",
		IsHardcoreActive = "C_GameRules.IsHardcoreActive",
	}) do
		api[name] = M.Optional(path)
	end

	local saved = type(PathmarkCollectDB) == "table" and PathmarkCollectDB or {}
	local root, why = Migrate.Upgrade(saved, C.SCHEMA, C.STEPS)
	if not root then
		-- Data stays untouched; the module shows "error" in /pathmark status.
		error(why == "newer" and L.ERR_COLLECT_NEWER or why, 0)
	end
	if root ~= saved and next(saved) then
		local copy = U.Copy(saved)
		copy.backup = nil
		root.backup = { from = saved.schema, data = copy }
	end
	root.own = type(root.own) == "table" and root.own or {}
	root.net = type(root.net) == "table" and root.net or {}
	PathmarkCollectDB, C.root = root, root

	PathmarkCharDB = type(PathmarkCharDB) == "table" and PathmarkCharDB or {}
	PathmarkCharDB.id = Str(PathmarkCharDB.id) or U.NewId(10)
	C.charId = PathmarkCharDB.id

	own = Store.New(root.own, GetTime, GetServerTime, { STORE_BYTES = C.OWN_BYTES })
	net = Store.New(root.net, GetTime, GetServerTime, { STORE_BYTES = C.NET_BYTES })
	C.own, C.net = own, net
end

local function Stop()
	for i = #tickers, 1, -1 do
		tickers[i]:Cancel()
		tickers[i] = nil
	end
	Save()
end

local events = {
	PLAYER_LOGIN = function()
		Start()
	end,
	PLAYER_LOGOUT = function()
		Save()
	end,

	QUEST_DETAIL = function(_, _, questStartItemID)
		detail = Context(questStartItemID)
	end,
	QUEST_COMPLETE = function()
		completion = Context()
	end,
	QUEST_ACCEPTED = function(_, _, questID) -- Forever/Retail: (questID); Classic Era: (index, questID)
		local q = Num(questID)
		if not q then
			return
		end
		local ctx = Take(detail, q) or {}
		detail = nil
		local map, x, y = ctx.map, ctx.x, ctx.y
		if not ctx.at then
			map, x, y = Pos()
		end
		-- GetQuestLogRewardXP is not in the API documentation and may vanish (Polestar): optional.
		local xp = Num((Call(api.GetQuestLogRewardXP, q)))
		Rec("accept", map, x, y, q, ctx.k, ctx.id, ctx.item, ctx.name, Num(UnitLevel("player")), xp)
		active[q] = true
		if map and x and y then
			Offer("q", q, ctx.k or "n", ctx.id or 0, map, x, y)
		end
		QueueScan()
	end,
	-- Forever trap: XP and level-up partly arrive BEFORE QUEST_TURNED_IN (JourneyTracker #21), and
	-- QUEST_TURNED_IN can come late or not at all (chapter 06). The addon writes raw events with time;
	-- the pipeline assigns XP (up to 3 s before the turn-in belongs to the quest).
	QUEST_TURNED_IN = function(_, _, questID, xp, money)
		local q = Num(questID)
		if not q then
			return
		end
		turnedIn[q] = GetTime()
		local ctx = Take(completion, q) or {}
		completion = nil
		local map, x, y = ctx.map, ctx.x, ctx.y
		if not ctx.at then
			map, x, y = Pos()
		end
		Rec("turnin", map, x, y, q, ctx.k, ctx.id, Num(UnitLevel("player")), Num(xp), Num(money))
		if map and x and y then
			Offer("t", q, ctx.k or "n", ctx.id or 0, map, x, y)
		end
	end,
	-- QUEST_REMOVED comes for turn-ins too. After 1 s the completion flag decides (chapter 06 §3).
	QUEST_REMOVED = function(_, _, questID)
		local q = Num(questID)
		if not q then
			return
		end
		active[q], lastObj[q] = nil, nil
		C_Timer.After(
			1,
			Guard.Wrap("collector", function()
				if turnedIn[q] then
					turnedIn[q] = nil
					return
				end
				local flagged = C_QuestLog.IsQuestFlaggedCompleted(q) == true
				Here(flagged and "turnin" or "abandon", q) -- "turnin" without XP: no QUEST_TURNED_IN came
			end)
		)
	end,
	QUEST_LOG_UPDATE = function()
		QueueScan()
	end,
	QUEST_WATCH_UPDATE = function(_, _, questID)
		local q = Num(questID)
		if q then
			active[q] = true
		end
		QueueScan()
	end,
	-- Forever duel and emote quests progress only with this event and QUEST_LOG_UPDATE (Questie).
	QUEST_LOG_CRITERIA_UPDATE = function()
		QueueScan()
	end,
	UNIT_QUEST_LOG_CHANGED = function(_, _, unit)
		if unit == "player" then
			QueueScan()
		end
	end,

	PLAYER_XP_UPDATE = function(_, _, unit)
		if unit ~= "player" then
			return
		end
		Rec("xp", nil, nil, nil, Num(UnitXP("player")), Num(UnitXPMax("player")), Num(GetXPExhaustion()))
	end,
	PLAYER_LEVEL_UP = function(_, _, level)
		Here("level", Num(level))
	end,

	-- Chests, objects, ore, herbs and glittering book objects: loot source with GameObject GUID plus the
	-- item IDs in the window. GetLootSourceInfo(slot) -> guid1, count1, guid2, count2, ...
	LOOT_OPENED = function()
		if Call(api.IsFishingLoot) then
			return
		end
		local objs, items = {}, {}
		for slot = 1, Num(GetNumLootItems()) or 0 do
			local link = Str(GetLootSlotLink(slot))
			local item = link and tonumber(link:match("item:(%d+)"))
			if item then
				items[#items + 1] = item
			end
			if api.GetLootSourceInfo then
				local src = U.Pack(pcall(api.GetLootSourceInfo, slot))
				if src[1] then
					for i = 2, src.n, 2 do
						local kind, id = ParseGUID(src[i])
						if kind == "GameObject" and id then
							objs[id] = true
						end
					end
				end
			end
		end
		local list = table.concat(items, ";")
		local map, x, y = Pos()
		for id in pairs(objs) do
			Rec("object", map, x, y, id, list)
			if map and x and y then
				Offer("o", id, map, x, y)
			end
		end
	end,

	-- Readable objects: read the GUID at BEGIN, after CLOSED it is gone (Lorekeeper pattern, Retail).
	ITEM_TEXT_BEGIN = function()
		local k, id = Ref("npc")
		if k ~= "o" then
			return
		end
		local map, x, y = Here("book", id, Str((Call(api.ItemTextGetItem))))
		if map and x and y then
			Offer("b", id, map, x, y)
		end
	end,

	NAME_PLATE_UNIT_ADDED = function(_, _, unit)
		if Str(unit) then
			SeeRare(unit, "p")
		end
	end,
	PLAYER_TARGET_CHANGED = function()
		SeeRare("target", "t")
	end,
	UPDATE_MOUSEOVER_UNIT = function()
		SeeRare("mouseover", "m")
	end,

	-- Vignettes (treasure and rare markers on the minimap); whether Forever zones have them is unconfirmed.
	VIGNETTE_MINIMAP_UPDATED = function(_, _, guid, onMinimap)
		if not onMinimap or not api.GetVignetteInfo then
			return
		end
		local info = Call(api.GetVignetteInfo, guid)
		local vid = info and Num(info.vignetteID)
		if not vid or vignetteSeen[vid] then
			return
		end
		vignetteSeen[vid] = true
		local kind, oid = ParseGUID(info and info.objectGUID)
		local k = kind and U.KIND[kind]
		local map = Num(C_Map.GetBestMapForUnit("player"))
		local v = map and Call(api.GetVignettePosition, guid, map)
		local vx = v and Num(v.x) and math.floor(v.x * 10000 + 0.5)
		local vy = v and Num(v.y) and math.floor(v.y * 10000 + 0.5)
		local pmap, px, py = Pos()
		Rec("vignette", pmap, px, py, vid, k ~= "p" and k or nil, k ~= "p" and oid or nil, vx, vy)
		if map and vx and vy then
			Offer("v", vid, map, vx, vy)
		end
	end,

	-- Flight master: Current/Reachable = surely discovered; Unreachable means "not discovered OR not
	-- connected" (Mapzeroth) and therefore does not count as unknown.
	TAXIMAP_OPENED = function()
		local FP = Enum.FlightPathState
		local mapID = Num((Call(api.GetTaxiMapID)))
		local nodes = mapID and Call(api.GetAllTaxiNodes, mapID) or {}
		local here, known = nil, {}
		for _, n in ipairs(nodes) do
			local node, state = Num(n.nodeID), Num(n.state)
			if node and state then
				if FP and state == FP.Current then
					here = node
				end
				if not FP or state ~= FP.Unreachable then
					known[#known + 1] = node
				end
			end
		end
		table.sort(known)
		local k, npc = Ref("npc")
		local map, x, y = Here("flightmaster", k == "c" and npc or nil, here, table.concat(known, ";"))
		if k == "c" and here and map and x and y then
			Offer("f", npc, here, map, x, y)
		end
	end,
	UI_INFO_MESSAGE = function(_, _, _, message) -- says "new", not which flight path
		if ERR_NEWTAXIPATH and Str(message) == ERR_NEWTAXIPATH then
			Here("newtaxi")
		end
	end,

	-- Other NPC interactions only note the NPC name.
	GOSSIP_SHOW = function()
		local k, id = Ref("npc")
		local map, x, y = Pos()
		NoteNpc(k, id, k == "c" and Str((UnitName("npc"))) or nil, map, x, y)
	end,
	PLAYER_INTERACTION_MANAGER_FRAME_SHOW = function()
		local k, id = Ref("npc")
		local map, x, y = Pos()
		NoteNpc(k, id, k == "c" and Str((UnitName("npc"))) or nil, map, x, y)
	end,

	ZONE_CHANGED_NEW_AREA = function()
		Here("zone")
	end,
	PLAYER_CONTROL_LOST = function()
		if not api.UnitOnTaxi then
			return
		end
		C_Timer.After(
			1,
			Guard.Wrap("collector", function()
				if Call(api.UnitOnTaxi, "player") then
					onTaxi = true
					Here("taxi")
				end
			end)
		)
	end,
	PLAYER_CONTROL_GAINED = function()
		if onTaxi then
			onTaxi = false
			C_Timer.After(
				0.2,
				Guard.Wrap("collector", function()
					Here("land")
				end)
			)
		end
	end,
	PLAYER_DEAD = function()
		Here("death")
	end,
	-- Kills by the player (XP per kill comes from the xp records). Both GUIDs can be secret.
	PARTY_KILL = function(_, _, attackerGUID, targetGUID)
		local me, attacker = Str((Call(UnitGUID, "player"))), Str(attackerGUID)
		if not (me and attacker == me) then
			return
		end
		local kind, id = ParseGUID(targetGUID)
		if kind and U.KIND[kind] == "c" and id then
			Here("kill", id)
		end
	end,
	GROUP_ROSTER_UPDATE = function()
		if rosterTimer then
			return
		end
		rosterTimer = true
		C_Timer.After(
			2,
			Guard.Wrap("collector", function()
				rosterTimer = nil
				Rec("group", nil, nil, nil, Num(GetNumGroupMembers()) or 0)
			end)
		)
	end,
	HEARTHSTONE_BOUND = function()
		Here("bind")
	end,
}

-- Export text of the chunks not exported yet (all = everything still in the buffer).
-- Returns text, ownLast, netLast, more | nil, reason.
function C.BuildExport(all)
	if not own then
		return nil, L.EXPORT_OFF
	end
	own:Rotate()
	net:Rotate()
	local ownChunks, ownLast = own:Chunks(all and 0 or own.db.acked, C.EXPORT_RAW_MAX)
	local netChunks, netLast = net:Chunks(all and 0 or net.db.acked, C.EXPORT_RAW_MAX / 2)
	if #ownChunks == 0 and #netChunks == 0 then
		return nil, L.EXPORT_NOTHING
	end
	local payload = {
		format = "pathmark",
		v = 1,
		install = C.root.install,
		addon = ns.version,
		own = ownChunks,
		net = netChunks,
	}
	local text, err = Export.Build(payload, Export.GameCodec(C.CODEC))
	if not text then
		return nil, L.EXPORT_FAILED:format(err)
	end
	local more = #(own:Chunks(ownLast, 1)) > 0 or #(net:Chunks(netLast, 1)) > 0
	return text, ownLast, netLast, more
end

function C.ShowExport(all)
	if not M.IsActive("collector") then
		print(L.EXPORT_OFF)
		return
	end
	if InCombatLockdown() then
		print(L.MSG_AFTER_COMBAT)
		return
	end
	local text, ownLast, netLast, more = C.BuildExport(all)
	if not text then
		print(ownLast)
		return
	end
	ns.ShowCopy(L.EXPORT_TITLE, text, {
		hint = more and L.EXPORT_MORE or nil,
		onCopy = function()
			own:Ack(ownLast)
			net:Ack(netLast)
		end,
	})
end

ns.Commands.export = function(rest)
	C.ShowExport(rest == "all")
end

M.Define("collector", {
	core = true,
	mandatory = true,
	requires = {
		funcs = {
			"C_Map.GetBestMapForUnit",
			"C_Map.GetPlayerMapPosition",
			"C_QuestLog.GetNumQuestLogEntries",
			"C_QuestLog.GetInfo",
			"C_QuestLog.GetQuestObjectives",
			"C_QuestLog.IsQuestFlaggedCompleted",
			"C_EncodingUtil.SerializeJSON",
			"C_EncodingUtil.CompressString",
			"C_EncodingUtil.EncodeBase64",
			"UnitXP",
			"UnitGUID",
			"GetServerTime",
		},
		events = { "PLAYER_LOGIN", "PLAYER_LOGOUT", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_XP_UPDATE" },
	},
	optional = {
		funcs = {
			"GetQuestID",
			"GetQuestLogRewardXP",
			"GetLootSourceInfo",
			"IsFishingLoot",
			"ItemTextGetItem",
			"GetTaxiMapID",
			"C_TaxiMap.GetAllTaxiNodes",
			"UnitOnTaxi",
			"C_VignetteInfo.GetVignetteInfo",
			"C_VignetteInfo.GetVignettePosition",
			"C_Traits.GetConfigIDByTreeID",
			"C_Traits.GetTreeNodes",
			"C_Traits.GetNodeInfo",
			"C_GameRules.GetForeverExperiencePreset",
			"C_GameRules.IsHardcoreActive",
		},
		events = {
			"QUEST_DETAIL",
			"QUEST_COMPLETE",
			"QUEST_TURNED_IN",
			"QUEST_LOG_UPDATE",
			"QUEST_WATCH_UPDATE",
			"QUEST_LOG_CRITERIA_UPDATE",
			"UNIT_QUEST_LOG_CHANGED",
			"PLAYER_LEVEL_UP",
			"LOOT_OPENED",
			"ITEM_TEXT_BEGIN",
			"NAME_PLATE_UNIT_ADDED",
			"PLAYER_TARGET_CHANGED",
			"UPDATE_MOUSEOVER_UNIT",
			"VIGNETTE_MINIMAP_UPDATED",
			"TAXIMAP_OPENED",
			"UI_INFO_MESSAGE",
			"GOSSIP_SHOW",
			"PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
			"ZONE_CHANGED_NEW_AREA",
			"PLAYER_CONTROL_LOST",
			"PLAYER_CONTROL_GAINED",
			"PLAYER_DEAD",
			"PARTY_KILL",
			"GROUP_ROSTER_UPDATE",
			"HEARTHSTONE_BOUND",
		},
	},
	init = Init,
	disable = Stop,
	events = events,
})
