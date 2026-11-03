-- SPDX-License-Identifier: GPL-3.0-or-later
-- Collector/Collect.lua: records from game events, anonymity, fixed limit, export, mandatory module.
local wow = require("spec.helpers.wow")
local node = require("spec.helpers.node")
local json = require("spec.helpers.json")

local NPC = { guid = "Creature-0-1465-0-2105-823-0000ABC123", name = "Marshal McBride" }
local BOX = { guid = "GameObject-0-1465-0-2105-2843-0000ABC124", name = "Wanted Poster" }

local function split(line)
	local out, start = {}, 1
	while true do
		local i = line:find("\t", start, true)
		if not i then
			out[#out + 1] = line:sub(start)
			return out
		end
		out[#out + 1] = line:sub(start, i - 1)
		start = i + 1
	end
end

-- All records of a store in order, as field lists.
local function records(store)
	store:Flush()
	local out = {}
	for seq = store.db.first, store.db.seq do
		local text = store.db.chunks[seq]
		if text then
			for line in (text .. "\n"):gmatch("(.-)\n") do
				out[#out + 1] = split(line)
			end
		end
	end
	return out
end

local function ofKind(store, kind)
	local out = {}
	for _, r in ipairs(records(store)) do
		if r[1] == kind then
			out[#out + 1] = r
		end
	end
	return out
end

local function everything(store)
	store:Flush()
	local parts = {}
	for seq = store.db.first, store.db.seq do
		parts[#parts + 1] = store.db.chunks[seq] or ""
	end
	return table.concat(parts, "\n")
end

local function start(opts)
	local ns = wow.session(opts)
	return ns, ns.Collector.own
end

describe("Collector", function()
	it("starts at login with an anonymous session header", function()
		local ns, own = start()
		assert.are.equal("on", ns.Modules.state.collector)
		local s = ofKind(own, "session")[1]
		assert.are.same({
			"session",
			"0",
			BraindeadForeverCharDB.id,
			"Human",
			"WARRIOR",
			"Alliance",
			"5",
			"enUS",
			"70532",
			"dev",
			"1",
			"0",
			"",
		}, s)
		assert.matches("^[0-9a-z]+$", BraindeadForeverCharDB.id)
		assert.are.equal(10, #BraindeadForeverCharDB.id)
		assert.are.equal(12, #BraindeadForeverCollectDB.install)
		assert.are.equal(1, BraindeadForeverCollectDB.schema)
		local zone = ofKind(own, "zone")[1]
		assert.are.same({ "1429", "4231", "6512" }, { zone[3], zone[4], zone[5] })
	end)

	it("keeps the IDs across sessions", function()
		local _, _ = start()
		local char, collect = BraindeadForeverCharDB, BraindeadForeverCollectDB
		local id, install = char.id, collect.install
		start({ char = char, collect = collect })
		assert.are.equal(id, BraindeadForeverCharDB.id)
		assert.are.equal(install, BraindeadForeverCollectDB.install)
	end)

	it("records quest accept with giver, dialog position, name, level and quest XP", function()
		local ns, own = start()
		wow.world.npc, wow.world.questID = NPC, 783
		wow.fire("QUEST_DETAIL", 0)
		wow.world.npc = nil
		wow.world.player.x, wow.world.player.y = 0.5, 0.5 -- walked away before accepting
		wow.fire("QUEST_ACCEPTED", 783)
		local r = ofKind(own, "accept")[1]
		-- then the prerequisite observation: token, link, unlock, done, missing (Routes/Prereq.lua)
		local token = ns.Prereq.Token(BraindeadForeverCollectDB.install, 783)
		assert.are.same({
			"accept",
			"0",
			"1429",
			"4231",
			"6512",
			"783",
			"c",
			"823",
			"0",
			"Marshal McBride",
			"5",
			"40",
			token,
			"0",
			"0",
			"",
			"",
		}, r)
		-- the NPC name is also noted once
		assert.are.same({ "823", "Marshal McBride" }, { ofKind(own, "npc")[1][6], ofKind(own, "npc")[1][7] })
	end)

	it("records the turn-in once even when QUEST_REMOVED comes first or later", function()
		local _, own = start()
		wow.world.npc, wow.world.questID = NPC, 783
		wow.fire("QUEST_COMPLETE")
		wow.fire("QUEST_REMOVED", 783, false)
		wow.fire("QUEST_TURNED_IN", 783, 450, 75)
		wow.world.completed[783] = true
		wow.advance(2)
		local t = ofKind(own, "turnin")
		assert.are.equal(1, #t)
		assert.are.same(
			{ "783", "c", "823", "5", "450", "75" },
			{ t[1][6], t[1][7], t[1][8], t[1][9], t[1][10], t[1][11] }
		)
	end)

	it("tells a turn-in without QUEST_TURNED_IN from an abandoned quest by the completion flag", function()
		local _, own = start()
		wow.world.completed[900] = true
		wow.fire("QUEST_REMOVED", 900, false)
		wow.fire("QUEST_REMOVED", 901, false)
		wow.advance(1)
		assert.are.equal("900", ofKind(own, "turnin")[1][6])
		assert.are.equal("901", ofKind(own, "abandon")[1][6])
	end)

	it("records objective progress only when it changes, also from a collapsed log", function()
		local _, own = start()
		wow.world.questLog = { { questID = 783, objectives = { { numFulfilled = 3, numRequired = 8 } } } }
		wow.fire("QUEST_LOG_UPDATE")
		wow.advance(0.5)
		assert.are.equal(0, #ofKind(own, "progress")) -- first scan is the starting point
		wow.world.questLog[1].objectives[1].numFulfilled = 4
		wow.fire("QUEST_WATCH_UPDATE", 783)
		wow.fire("QUEST_LOG_UPDATE")
		wow.advance(0.5)
		wow.fire("QUEST_LOG_UPDATE")
		wow.advance(0.5)
		local p = ofKind(own, "progress")
		assert.are.equal(1, #p)
		assert.are.same({ "783", "4/8" }, { p[1][6], p[1][7] })
		-- quest hidden under a collapsed header: the ID from QUEST_WATCH_UPDATE keeps it in the scan
		local hidden = { questID = 783, objectives = { { numFulfilled = 5, numRequired = 8 } } }
		wow.world.questLog = {}
		local GetObjectives = C_QuestLog.GetQuestObjectives
		C_QuestLog.GetQuestObjectives = function(q)
			return q == 783 and hidden.objectives or GetObjectives(q)
		end
		wow.fire("QUEST_LOG_CRITERIA_UPDATE", 783, 1, "", 5, 8)
		wow.advance(0.5)
		assert.are.equal("5/8", ofKind(own, "progress")[2][7])
	end)

	it("records experience with rested XP and level-ups", function()
		local _, own = start()
		wow.world.player.rested = 300
		wow.fire("PLAYER_XP_UPDATE", "player")
		wow.fire("PLAYER_XP_UPDATE", "party1")
		wow.fire("PLAYER_LEVEL_UP", 6, 10, 10, 0, 0, 1, 1, 1, 1, 1)
		local xp = ofKind(own, "xp")
		assert.are.equal(1, #xp)
		assert.are.same(
			{ "", "", "", "120", "400", "300" },
			{ xp[1][3], xp[1][4], xp[1][5], xp[1][6], xp[1][7], xp[1][8] }
		)
		assert.are.equal("6", ofKind(own, "level")[1][6])
	end)

	it("records looted objects with their items and skips secret sources and fishing", function()
		local _, own = start()
		wow.world.loot = {
			{
				link = "|cff9d9d9d|Hitem:2589::::::::5:::::::|h[Linen Cloth]|h|r",
				sources = { BOX.guid, 1, wow.SECRET, 1 },
			},
			{ link = "|Hitem:117:::|h[Bread]|h", sources = { BOX.guid, 1 } },
		}
		wow.fire("LOOT_OPENED", false, false)
		local o = ofKind(own, "object")
		assert.are.equal(1, #o)
		assert.are.same({ "2843", "2589;117" }, { o[1][6], o[1][7] })
		wow.world.fishing = true
		wow.fire("LOOT_OPENED", false, false)
		assert.are.equal(1, #ofKind(own, "object"))
	end)

	it("records readable objects with their title", function()
		local _, own = start()
		wow.world.npc = BOX
		wow.fire("ITEM_TEXT_BEGIN")
		local b = ofKind(own, "book")[1]
		assert.are.same({ "2843", "Ein altes Buch" }, { b[6], b[7] })
		wow.world.npc = NPC -- a creature is not a book
		wow.fire("ITEM_TEXT_BEGIN")
		assert.are.equal(1, #ofKind(own, "book"))
	end)

	it("records rare enemies once per session and skips secret identities", function()
		local _, own = start()
		wow.world.units.target = {
			guid = "Creature-0-1465-0-2105-61-0000ABC125",
			name = "Thuros Lightfingers",
			classification = "rareelite",
			level = 8,
		}
		wow.fire("PLAYER_TARGET_CHANGED")
		wow.fire("PLAYER_TARGET_CHANGED")
		wow.world.units.mouseover = { guid = wow.SECRET, name = wow.SECRET, classification = "rare" }
		wow.fire("UPDATE_MOUSEOVER_UNIT")
		wow.world.units.nameplate1 = { guid = "Creature-0-1465-0-2105-99-0000ABC126", classification = "normal" }
		wow.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
		local r = ofKind(own, "rare")
		assert.are.equal(1, #r)
		assert.are.same(
			{ "61", "rareelite", "8", "Thuros Lightfingers", "t" },
			{ r[1][6], r[1][7], r[1][8], r[1][9], r[1][10] }
		)
	end)

	it("records vignettes with their own position once", function()
		local _, own = start()
		wow.world.vignettes["Vignette-1"] = { info = { vignetteID = 4711, objectGUID = BOX.guid }, x = 0.25, y = 0.75 }
		wow.fire("VIGNETTE_MINIMAP_UPDATED", "Vignette-1", true)
		wow.fire("VIGNETTE_MINIMAP_UPDATED", "Vignette-1", true)
		wow.fire("VIGNETTE_MINIMAP_UPDATED", "Vignette-2", false)
		local v = ofKind(own, "vignette")
		assert.are.equal(1, #v)
		assert.are.same({ "4711", "o", "2843", "2500", "7500" }, { v[1][6], v[1][7], v[1][8], v[1][9], v[1][10] })
	end)

	it("records flight masters with the known nodes, unreachable ones left out", function()
		local _, own = start()
		wow.world.npc = { guid = "Creature-0-1465-0-2105-352-0000ABC127", name = "Dungar Longdrink" }
		wow.world.taxi.nodes = {
			{ nodeID = 2, state = Enum.FlightPathState.Current },
			{ nodeID = 4, state = Enum.FlightPathState.Reachable },
			{ nodeID = 6, state = Enum.FlightPathState.Unreachable },
		}
		wow.fire("TAXIMAP_OPENED", 0)
		wow.fire("UI_INFO_MESSAGE", 0, "New flight path discovered!")
		wow.fire("UI_INFO_MESSAGE", 0, "Something else")
		local f = ofKind(own, "flightmaster")[1]
		assert.are.same({ "352", "2", "2;4" }, { f[6], f[7], f[8] })
		assert.are.equal(1, #ofKind(own, "newtaxi"))
	end)

	it("records the legs of the flight network, the chosen flight and its seconds", function()
		local ns, own = start()
		local FP = Enum.FlightPathState
		wow.world.npc = { guid = "Creature-0-1465-0-2105-352-0000ABC127", name = "Dungar Longdrink" }
		wow.world.taxi.nodes = {
			{ nodeID = 2, state = FP.Current, slotIndex = 1 },
			{ nodeID = 4, state = FP.Reachable, slotIndex = 2 },
			{ nodeID = 6, state = FP.Reachable, slotIndex = 3 },
			{ nodeID = 9, state = FP.Unreachable, slotIndex = 4 },
		}
		wow.world.taxi.routes = { [2] = { 1, 2 }, [3] = { 1, 2, 3 }, [4] = { 1, 4 } }
		wow.fire("TAXIMAP_OPENED", 0)
		wow.fire("TAXIMAP_OPENED", 0) -- the same known points: the legs are not read again
		local legs = ofKind(own, "taxilegs")
		assert.are.equal(1, #legs)
		assert.are.same({ "2", "2>4;4>6" }, { legs[1][6], legs[1][7] })
		assert.are.equal(2, wow.world.taxi.reads)
		-- A newly known point: the legs are read and recorded again.
		wow.world.taxi.nodes[4].state = FP.Reachable
		wow.world.taxi.routes[4] = { 1, 2, 4 }
		wow.fire("TAXIMAP_OPENED", 0)
		assert.are.equal(5, wow.world.taxi.reads)
		legs = ofKind(own, "taxilegs")
		assert.are.equal(2, #legs)
		assert.are.equal("2>4;4>6;4>9", legs[2][7])

		-- Own records only: the flight offers nothing to the exchange (the channel budget is untouched).
		local offered, offer = 0, ns.Exchange.Offer
		ns.Exchange.Offer = function(...)
			offered = offered + 1
			return offer(...)
		end
		_G.TakeTaxiNode(3)
		assert.are.equal(3, wow.world.taxi.taken) -- the hook does not replace the original
		local f = ofKind(own, "flight")
		assert.are.equal(1, #f)
		assert.are.same({ "2", "6", "2;4;6" }, { f[1][6], f[1][7], f[1][8] })
		wow.world.onTaxi = true
		wow.fire("PLAYER_CONTROL_LOST")
		wow.advance(120)
		wow.world.onTaxi = false
		wow.fire("PLAYER_CONTROL_GAINED")
		wow.advance(1)
		local land = ofKind(own, "land")
		assert.are.equal(1, #land)
		assert.are.same({ "6", "120" }, { land[1][6], land[1][7] })
		assert.are.equal(0, offered)
		ns.Exchange.Offer = offer
	end)

	it("leaves out flights and legs it cannot name", function()
		local _, own = start()
		local FP = Enum.FlightPathState
		wow.world.taxi.nodes = {
			{ nodeID = 2, state = FP.Current, slotIndex = 1 },
			{ nodeID = 4, state = FP.Reachable, slotIndex = 2 },
		}
		wow.world.taxi.routes = { [2] = { 1, 7 } } -- slot 7 is not on the map: broken answer
		wow.fire("TAXIMAP_OPENED", 0)
		assert.are.equal(0, #ofKind(own, "taxilegs"))
		_G.TakeTaxiNode(5) -- unknown slot
		assert.are.equal(0, #ofKind(own, "flight"))
		_G.TakeTaxiNode(2) -- known slot, broken path: the flight is kept without its points
		local f = ofKind(own, "flight")
		assert.are.equal(1, #f)
		assert.are.same({ "2", "4", "" }, { f[1][6], f[1][7], f[1][8] or "" })
		-- Landing without a chosen flight (a /reload in the air): position only.
		wow.world.onTaxi = true
		wow.fire("PLAYER_CONTROL_LOST")
		wow.advance(2)
		wow.world.onTaxi = false
		wow.fire("PLAYER_CONTROL_GAINED")
		wow.advance(1)
		wow.world.onTaxi = true
		wow.fire("PLAYER_CONTROL_LOST")
		wow.advance(2)
		wow.world.onTaxi = false
		wow.fire("PLAYER_CONTROL_GAINED")
		wow.advance(1)
		local land = ofKind(own, "land")
		assert.are.equal(2, #land)
		assert.are.equal("4", land[1][6])
		assert.is_nil(land[2][6])
	end)

	it("records taxi start and landing, deaths, own kills and group size", function()
		local _, own = start()
		wow.world.onTaxi = true
		wow.fire("PLAYER_CONTROL_LOST")
		wow.advance(1)
		wow.world.onTaxi = false
		wow.fire("PLAYER_CONTROL_GAINED")
		wow.advance(0.5)
		wow.fire("PLAYER_DEAD")
		wow.fire("PARTY_KILL", wow.world.player.guid, "Creature-0-1465-0-2105-299-0000ABC128")
		wow.fire("PARTY_KILL", "Player-1234-0FFFFFF0", "Creature-0-1465-0-2105-300-0000ABC129")
		wow.fire("PARTY_KILL", wow.SECRET, wow.SECRET)
		wow.world.group.members = 3
		wow.fire("GROUP_ROSTER_UPDATE")
		wow.fire("GROUP_ROSTER_UPDATE")
		wow.advance(3)
		assert.are.equal(1, #ofKind(own, "taxi"))
		assert.are.equal(1, #ofKind(own, "land"))
		assert.are.equal(1, #ofKind(own, "death"))
		local k = ofKind(own, "kill")
		assert.are.equal(1, #k)
		assert.are.equal("299", k[1][6])
		local g = ofKind(own, "group")
		assert.are.equal("3", g[#g][6])
	end)

	it("samples the position only after a real move", function()
		local _, own = start()
		wow.advance(2)
		local before = #ofKind(own, "pos")
		wow.world.player.x = 0.4235 -- 4 hundredths of a percent: standing still
		wow.advance(2)
		assert.are.equal(before, #ofKind(own, "pos"))
		wow.world.player.x = 0.4300
		wow.advance(2)
		assert.are.equal(before + 1, #ofKind(own, "pos"))
	end)

	it("writes a record without coordinates when the client withholds the position", function()
		local _, own = start()
		C_Map.GetPlayerMapPosition = function()
			return { x = wow.SECRET, y = wow.SECRET }
		end
		wow.fire("PLAYER_DEAD")
		local d = ofKind(own, "death")[1]
		assert.are.same({ "1429", "", "" }, { d[3], d[4], d[5] })
		assert.are.same({}, wow.errors)
	end)

	it("never registers the combat log", function()
		local ns = start()
		for _, f in ipairs(wow.frames) do
			assert.is_nil(f.events.COMBAT_LOG_EVENT_UNFILTERED)
		end
		assert.are.equal("on", ns.Modules.state.collector)
	end)

	it("rebinds to a replaced SavedVariables table at logout", function()
		local ns, own = start()
		wow.fire("PLAYER_DEAD")
		local install = BraindeadForeverCollectDB.install
		BraindeadForeverCollectDB = nil -- Forever beta: the global was lost
		wow.fire("PLAYER_LOGOUT")
		assert.is_table(BraindeadForeverCollectDB)
		assert.are.equal(install, BraindeadForeverCollectDB.install)
		assert.are.equal(own.db, BraindeadForeverCollectDB.own)
		assert.matches("death", BraindeadForeverCollectDB.own.chunks[BraindeadForeverCollectDB.own.seq])
		assert.are.equal("on", ns.Modules.state.collector)
	end)

	it("keeps data from a newer version untouched and stays off", function()
		local saved = { schema = 99, install = "zzzzzzzzzzzz", own = { seq = 3, chunks = { [3] = "keep" } } }
		local ns = start({ collect = saved })
		assert.are.equal("error", ns.Modules.state.collector)
		assert.are.equal(saved, BraindeadForeverCollectDB)
		assert.are.equal("keep", BraindeadForeverCollectDB.own.chunks[3])
		assert.matches("newer addon version", wow.errors[1], 1, true)
	end)

	it("saves a backup when it migrates older data", function()
		local saved = { own = { seq = 1, chunks = { "chunk\t0\t1\t1" } } }
		start({ collect = saved })
		assert.are.equal(1, BraindeadForeverCollectDB.schema)
		assert.are.same({ seq = 1, chunks = { "chunk\t0\t1\t1" } }, BraindeadForeverCollectDB.backup.data.own)
	end)
end)

describe("Mandatory data contribution", function()
	it("refuses /bdf flag for the collector and the exchange", function()
		start()
		SlashCmdList.BRAINDEADFOREVER("flag collector off")
		SlashCmdList.BRAINDEADFOREVER("flag exchange off")
		assert.is_nil(BraindeadForeverDB.flags.collector)
		assert.is_nil(BraindeadForeverDB.flags.exchange)
		assert.matches("collector is part of the addon and cannot be turned off", wow.output(), 1, true)
	end)

	it("ignores a flag written into the SavedVariables by hand", function()
		local ns = start({ saved = { flags = { collector = false, exchange = false, report = false } } })
		assert.are.equal("on", ns.Modules.state.collector)
		assert.are.equal("on", ns.Modules.state.exchange)
		assert.are.equal("off", ns.Modules.state.report)
	end)

	it("keeps sharing in a safe mode set by hand, but not in the automatic one", function()
		local ns = start({ saved = { safeMode = true, autoSafe = false } })
		assert.are.equal("on", ns.Modules.state.exchange)
		ns = start({ saved = { safeMode = true, autoSafe = true, boot = { version = "dev", fails = 2 } } })
		assert.are.equal("off", ns.Modules.state.exchange)
		assert.are.equal("on", ns.Modules.state.collector)
	end)
end)

describe("Export of collected data", function()
	local function useNodeCompression()
		C_EncodingUtil.SerializeJSON = json.encode
		C_EncodingUtil.CompressString = function(s, method)
			return node.compress(s, method)
		end
	end

	it("shows the copy window and acknowledges after Ctrl+C", function()
		local ns, own = start()
		wow.fire("PLAYER_DEAD")
		SlashCmdList.BRAINDEADFOREVER("export")
		local win = ns.CopyWindow()
		assert.is_true(win:IsShown())
		assert.matches("^PM1:d:%d+:%x+:", win.box:GetText())
		assert.are.equal(0, own.db.acked)
		wow.world.ctrl = true
		win.box.scripts.OnKeyUp(win.box, "C")
		assert.is_true(own.db.acked > 0)
		SlashCmdList.BRAINDEADFOREVER("export")
		assert.matches("no new data to share yet", wow.output(), 1, true)
		SlashCmdList.BRAINDEADFOREVER("export all")
		assert.matches("^PM1:", win.box:GetText())
	end)

	it("refuses in combat", function()
		local ns = start()
		wow.world.combat = true
		SlashCmdList.BRAINDEADFOREVER("export")
		assert.is_nil(ns.CopyWindow())
		assert.matches("try again after combat", wow.output(), 1, true)
	end)

	it("decodes on the website to anonymous data with install ID and chunks", function()
		local ns = start()
		useNodeCompression()
		wow.world.npc, wow.world.questID = NPC, 783
		wow.fire("QUEST_DETAIL", 0)
		wow.fire("QUEST_ACCEPTED", 783)
		local text = assert(ns.Collector.BuildExport(false))
		local out = assert(node.decode(text))
		local payload = node.parseJSON(out)
		assert.are.equal("braindead-forever", payload.format)
		assert.are.equal(BraindeadForeverCollectDB.install, payload.install)
		assert.is_true(#payload.own >= 1)
		local all = table.concat(payload.own, "\n")
		assert.matches("accept\t%d+\t1429\t4231\t6512\t783\tc\t823", all)
		for _, secret in ipairs({ "Testchar", "Brightwood", "Testrealm", "Player-" }) do
			assert.is_nil(out:find(secret, 1, true), secret .. " in the export")
		end
	end)
end)

describe("Two hours of play", function()
	it("runs without a Lua error, stays under the limit and keeps the data anonymous", function()
		local ns, own = start()
		ns.Collector.OWN_BYTES = 2 * 1024 * 1024
		local W = wow.world
		W.questLog = {}
		local q = 1000
		for minute = 1, 120 do
			-- a quest per minute: dialog, accept, progress, XP, loot, rare, turn-in
			q = q + 1
			W.npc, W.questID = NPC, q
			wow.fire("QUEST_DETAIL", 0)
			W.npc = nil
			wow.fire("QUEST_ACCEPTED", q)
			W.questLog[#W.questLog + 1] = { questID = q, objectives = { { numFulfilled = 0, numRequired = 5 } } }
			for step = 1, 5 do
				W.player.x = (W.player.x + 0.003) % 1
				W.questLog[#W.questLog].objectives[1].numFulfilled = step
				wow.fire("QUEST_WATCH_UPDATE", q)
				wow.fire("QUEST_LOG_UPDATE")
				W.player.xp = W.player.xp + 10
				wow.fire("PLAYER_XP_UPDATE", "player")
				wow.fire("PARTY_KILL", W.player.guid, "Creature-0-1465-0-2105-" .. (300 + step) .. "-0000ABC130")
				wow.advance(8)
			end
			W.loot = { { link = "|Hitem:" .. minute .. ":::|h[x]|h", sources = { BOX.guid, 1 } } }
			wow.fire("LOOT_OPENED", false, false)
			W.units.target =
				{ guid = "Creature-0-1465-0-2105-" .. (5000 + minute) .. "-0000ABC131", classification = "rare" }
			wow.fire("PLAYER_TARGET_CHANGED")
			W.npc = NPC
			wow.fire("QUEST_COMPLETE")
			W.npc = nil
			table.remove(W.questLog)
			W.completed[q] = true
			wow.fire("QUEST_TURNED_IN", q, 500, 10)
			wow.fire("QUEST_REMOVED", q, false)
			wow.fire("ZONE_CHANGED_NEW_AREA")
			wow.advance(20)
		end
		wow.fire("PLAYER_LOGOUT")
		assert.are.same({}, wow.errors)
		assert.are.same({}, ns.Guard.list)
		assert.are.equal("on", ns.Modules.state.collector)
		assert.are.equal(120, #ofKind(own, "accept"))
		assert.are.equal(120, #ofKind(own, "turnin"))
		assert.is_true(own:Stats().bytes <= ns.Collector.OWN_BYTES)
		local all = everything(own)
		for _, secret in ipairs({ "Testchar", "Brightwood", "Testrealm", "Player-" }) do
			assert.is_nil(all:find(secret, 1, true), secret .. " in the records")
		end
		-- no wall-clock time: every chunk header carries the day number only
		for header in all:gmatch("chunk\t0\t%d+\t(%d+)") do
			assert.are.equal(math.floor(W.serverTime / 86400), tonumber(header))
		end
	end)
end)
