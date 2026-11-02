-- SPDX-License-Identifier: GPL-3.0-or-later
-- Explorer mode (Welle 4, task 1): hint levels 0 to 3 per player, own finds against finds of other
-- players (rumor per zone, the point only on request), confirmation by a second player, the three play
-- styles of the first start, and riddle sentences that come only from templates filled with data.
local wow = require("spec.helpers.wow")

-- Catalog entry of the Alliance data: rare 100 in Elwynn Forest (1429) at 27.60 / 88.40 (ATT).
local CAT = { key = "rare:100", map = 1429, x = 2760, y = 8840 }
-- A rare another player reports, not in the catalog.
local HEARD = { key = "rare:62", map = 1429, x = 4231, y = 6512, msg = "r;1;62;r;1429;4231;6512" }

local function session(opts)
	opts = opts or {}
	local ns = wow.session(opts)
	if opts.locale == "deDE" then
		wow.loadFile("Pathmark/Locales/deDE.lua", "Pathmark", ns) -- the TOC loads it on German clients
	end
	wow.advance(10) -- a clean start, so the start guard keeps every module on
	wow.world.mapInfo[1429] = { mapID = 1429, name = opts.locale == "deDE" and "Wald von Elwynn" or "Elwynn Forest" }
	wow.world.mapInfo[1436] = { mapID = 1436, name = "Westfall" }
	return ns
end

local function hear(msg, sender)
	wow.fire("CHAT_MSG_ADDON", "Pathmark", msg, "PARTY", sender or "Anna Sommer")
	wow.readInbox()
end

-- The player targets a rare himself.
local function meetRare(id, x, y)
	local P = wow.world.player
	P.x, P.y = x / 10000, y / 10000
	wow.world.units.target = {
		guid = ("Creature-0-1465-0-2105-%d-0000ABC%03d"):format(id, id % 1000),
		name = "Rare " .. id,
		classification = "rare",
		level = 10,
	}
	wow.fire("PLAYER_TARGET_CHANGED")
end

local function byKey(list)
	local out = {}
	for _, e in ipairs(list) do
		out[e.key] = e
	end
	return out
end

local function inside(area, x, y)
	local dx, dy = (x - area.x) / area.rx, (y - area.y) / area.ry
	return dx * dx + dy * dy <= 1
end

describe("Discovery rules (pure)", function()
	wow.reset({})
	local D = wow.loadFiles({ "Pathmark/Routes/Discover.lua" }).Discover

	it("shows a foreign find never at level 0, also not on request", function()
		for _, source in ipairs({ "data", "players" }) do
			assert.is_nil(D.View(0, nil, false, source))
			assert.is_nil(D.View(0, 3, false, source))
		end
		assert.are.equal("point", D.View(0, nil, true, "players"), "own finds at every level")
	end)

	it("shows a sentence at level 1, the area at 2, the point at 3 or on request", function()
		assert.are.equal("riddle", D.View(1, nil, false, "data"))
		assert.are.equal("rumor", D.View(1, nil, false, "players"))
		assert.are.equal("area", D.View(1, 2, false, "players"))
		assert.are.equal("point", D.View(1, 3, false, "data"))
		assert.are.equal("area", D.View(2, nil, false, "data"))
		assert.are.equal("point", D.View(2, 3, false, "data"))
		assert.are.equal("point", D.View(3, nil, false, "players"))
	end)

	it("splits a zone into thirds", function()
		assert.are.equal("nw", D.Part(0, 0))
		assert.are.equal("c", D.Part(5000, 5000))
		assert.are.equal("sw", D.Part(2760, 8840))
		assert.are.equal("e", D.Part(10000, 5000))
		assert.are.equal("s", D.Part(5000, 10000))
	end)

	it("puts the area around the point without centring it there", function()
		for _, key in ipairs({ "rare:100", "treasure:3642", "book:386691", "flightpath:12" }) do
			local a = D.Area(key, 4000, 6000, 3470.84, 2314.62) -- Elwynn Forest in yards (chapter 07)
			assert.is_true(inside(a, 4000, 6000), key)
			assert.is_false(a.x == 4000 and a.y == 6000, key)
			assert.are.equal(math.floor(100 / 3470.84 * 10000 + 0.5), a.rx)
			assert.are.same(a, D.Area(key, 4000, 6000, 3470.84, 2314.62), "stable per find")
		end
		local a = D.Area("rare:1", 50, 50)
		assert.are.equal(D.AREA_MAP, a.rx, "without map size: fixed share of the map")
	end)

	it("never returns half a sentence", function()
		assert.is_nil(D.Fill("in {zone}", {}))
		assert.is_nil(D.Fill(nil, { zone = "x" }))
		assert.are.equal("in Westfall", D.Fill("in {zone}", { zone = "Westfall" }))
	end)
end)

describe("Explorer mode", function()
	it("level 0: only own finds; the find of another player and the catalog stay hidden", function()
		local ns = session()
		assert.is_true(ns.Explore.SetLevel(0))
		hear(HEARD.msg)
		local list = ns.Explore.List()
		assert.are.same({}, list, "nothing found yet, nothing shown, no count")
		assert.is_false(ns.Explore.Ask(HEARD.key, 3), "a hidden find cannot be asked for")
		assert.are.same({}, ns.Explore.List())
		meetRare(100, 2700, 8800)
		list = ns.Explore.List()
		assert.are.equal(1, #list)
		assert.are.equal("rare:100", list[1].key)
		assert.are.equal("own", list[1].status)
		assert.are.same({ { 2700, 8800 } }, list[1].points, "own position, not the catalog's")
	end)

	it("level 1: catalog as riddle, other players as rumor, no position in either", function()
		local ns = session()
		ns.Explore.SetLevel(1)
		hear(HEARD.msg)
		local f = byKey(ns.Explore.List(1429))
		local cat, heard = f[CAT.key], f[HEARD.key]
		assert.are.equal("riddle", cat.show)
		assert.are.equal("sw", cat.part)
		assert.are.equal("A rare creature roams in the south-west of Elwynn Forest.", cat.text)
		assert.are.equal("data", cat.source)
		assert.are.equal("unconfirmed", cat.status)
		assert.are.equal("rumor", heard.show)
		assert.are.equal("Other players saw a rare creature in Elwynn Forest.", heard.text)
		assert.are.equal("unconfirmed", heard.status)
		for _, e in ipairs(ns.Explore.List()) do
			assert.is_nil(e.points, e.key)
			assert.is_nil(e.area, e.key)
			assert.is_nil(e.part and e.source == "players" or nil, "a rumor names no part of the zone")
		end
	end)

	it("gives the exact point only on request, for that one find", function()
		local ns = session()
		ns.Explore.SetLevel(1)
		hear(HEARD.msg)
		assert.is_true(ns.Explore.Ask(HEARD.key, 3))
		local f = byKey(ns.Explore.List(1429))
		assert.are.same({ { HEARD.x, HEARD.y } }, f[HEARD.key].points)
		assert.are.equal("riddle", f[CAT.key].show, "the other finds stay riddles")
		assert.is_true(ns.Explore.Ask(CAT.key, 2))
		f = byKey(ns.Explore.List(1429))
		assert.are.equal("area", f[CAT.key].show)
		assert.is_true(inside(f[CAT.key].area, CAT.x, CAT.y))
	end)

	it("level 2: areas that hold the point; level 3: points", function()
		local ns = session()
		ns.Explore.SetLevel(2)
		hear(HEARD.msg)
		for _, e in ipairs(ns.Explore.List()) do
			assert.are.equal("area", e.show, e.key)
			assert.is_nil(e.points, e.key)
		end
		local a = byKey(ns.Explore.List(1429))[HEARD.key].area
		assert.is_true(inside(a, HEARD.x, HEARD.y))
		ns.Explore.SetLevel(3)
		local f = byKey(ns.Explore.List(1429))
		assert.are.same({ { HEARD.x, HEARD.y } }, f[HEARD.key].points)
		assert.are.same({ { CAT.x, CAT.y } }, f[CAT.key].points)
	end)

	it("confirms a find when a second player reports it", function()
		local ns = session()
		ns.Explore.SetLevel(3)
		hear(HEARD.msg, "Anna Sommer")
		assert.are.equal("unconfirmed", byKey(ns.Explore.List())[HEARD.key].status)
		hear(HEARD.msg, "Anna Sommer")
		assert.are.equal("unconfirmed", byKey(ns.Explore.List())[HEARD.key].status, "same player twice")
		hear(HEARD.msg, "Bert Winter")
		assert.are.equal("confirmed", byKey(ns.Explore.List())[HEARD.key].status)
	end)

	it("replaces the catalog position by a player's report and counts it as confirmation", function()
		local ns = session()
		ns.Explore.SetLevel(3)
		hear("r;1;100;r;1429;2700;8810")
		local e = byKey(ns.Explore.List())[CAT.key]
		assert.are.equal("players", e.source)
		assert.are.equal("confirmed", e.status)
		assert.are.same({ { 2700, 8810 } }, e.points)
	end)

	it("counts a quest outside the data as discovery, a known quest not", function()
		local ns = session()
		ns.Explore.SetLevel(0)
		local W = wow.world
		W.npc = { guid = "Creature-0-1465-0-2105-823-0000ABC123", name = "Marshal McBride" }
		for _, q in ipairs({ 783, 2, 990001 }) do -- route quest, Classic quest outside the route, unknown quest
			W.questID = q
			wow.fire("QUEST_DETAIL", 0)
			W.questLog[#W.questLog + 1] = { questID = q, objectives = {} }
			wow.fire("QUEST_ACCEPTED", q)
		end
		local keys = {}
		for _, e in ipairs(ns.Explore.List()) do
			keys[#keys + 1] = e.key
		end
		assert.are.same({ "quest:990001" }, keys)
	end)

	it("counts a looted object only when the catalog knows it as treasure or book", function()
		local ns = session()
		ns.Explore.SetLevel(0)
		hear("o;1;3642;1413;4300;2350") -- catalog treasure in the Barrens; heard, hidden at level 0
		wow.world.loot = { { link = "item:2770", sources = { "GameObject-0-1-0-1-1731-0000000001", 1 } } }
		wow.fire("LOOT_OPENED") -- copper vein: no discovery
		assert.are.same({}, ns.Explore.List())
		wow.world.loot = { { link = "item:2770", sources = { "GameObject-0-1-0-1-3642-0000000002", 1 } } }
		wow.fire("LOOT_OPENED")
		local list = ns.Explore.List()
		assert.are.equal(1, #list)
		assert.are.equal("treasure:3642", list[1].key)
	end)

	it("keeps own finds per character and reports of others for the account over /reload", function()
		local ns = session()
		ns.Explore.SetLevel(1)
		hear(HEARD.msg)
		meetRare(100, 2700, 8800)
		wow.fire("PLAYER_LOGOUT")
		local char, saved = _G.PathmarkCharDB, _G.PathmarkDB
		ns = session({ char = char, saved = saved })
		local f = byKey(ns.Explore.List(1429))
		assert.are.equal(1, ns.Explore.Level())
		assert.are.equal("own", f[CAT.key].status)
		assert.are.equal("rumor", f[HEARD.key].show)
		-- another character of the account: hears the rumor, has not found the rare
		ns = session({ saved = saved })
		ns.Explore.SetLevel(1)
		f = byKey(ns.Explore.List(1429))
		assert.are.equal("riddle", f[CAT.key].show)
		assert.are.equal("rumor", f[HEARD.key].show)
	end)
end)

describe("Play styles", function()
	it("sets route mode and hint level; the level stays a slider of its own", function()
		local ns = session()
		assert.is_nil(ns.Explore.Style(), "first start: not asked yet")
		assert.are.equal(3, ns.Explore.Level(), "speed mode default")
		assert.are.same({ "arrow", "hints", "self" }, {
			ns.Explore.Styles()[1].key,
			ns.Explore.Styles()[2].key,
			ns.Explore.Styles()[3].key,
		})
		assert.is_true(ns.Explore.SetStyle("self"))
		assert.are.equal("explorer", ns.Route.Mode())
		assert.are.equal(0, ns.Explore.Level())
		assert.is_true(ns.Explore.SetStyle("hints"))
		assert.are.equal("explorer", ns.Route.Mode())
		assert.are.equal(1, ns.Explore.Level())
		assert.is_true(ns.Explore.SetLevel(2))
		assert.are.equal("hints", ns.Explore.Style())
		assert.are.equal(2, ns.Explore.Level())
		assert.is_true(ns.Explore.SetStyle("arrow"))
		assert.are.equal("speed", ns.Route.Mode())
		assert.are.equal(3, ns.Explore.Level())
		assert.is_false(ns.Explore.SetStyle("other"))
		assert.is_false(ns.Explore.SetLevel(4))
	end)

	it("defaults to level 0 in explorer mode when the player chose no level", function()
		local ns = session()
		ns.Route.SetMode("explorer")
		assert.are.equal(0, ns.Explore.Level())
	end)
end)

describe("Riddle sentences", function()
	-- Every sentence must be a template of the locale with the zone name and part filled in: no other
	-- word may come from anywhere else.
	local function check(locale, zone)
		local ns = session({ locale = locale })
		local L, D = ns.L, ns.Discover
		ns.Explore.SetLevel(1)
		local n = 0
		for _, e in ipairs(ns.Explore.List(1429)) do
			local want = D.Fill(L["RIDDLE_" .. e.kind], { where = D.Fill(L["WHERE_" .. e.part], { zone = zone }) })
			assert.are.equal(want, e.text, e.key)
			assert.is_truthy(e.text:find(zone, 1, true))
			n = n + 1
		end
		assert.is_true(n > 0, "the Elwynn catalog has finds")
	end

	it("are built only from templates and data (English)", function()
		check("enUS", "Elwynn Forest")
	end)

	it("are built only from templates and data (German)", function()
		check("deDE", "Wald von Elwynn")
		local ns = session({ locale = "deDE" })
		ns.Explore.SetLevel(1)
		local e = byKey(ns.Explore.List(1429))[CAT.key]
		assert.are.equal("Ein seltenes Wesen streift im Südwesten des Gebiets Wald von Elwynn umher.", e.text)
	end)

	it("give no sentence without a zone name from the client", function()
		local ns = session()
		wow.world.mapInfo[1429] = nil
		ns.Explore.SetLevel(1)
		local e = byKey(ns.Explore.List(1429))[CAT.key]
		assert.are.equal("riddle", e.show)
		assert.is_nil(e.text)
	end)

	it("have a template for every type and part in both languages", function()
		local ns = session()
		for _, kind in ipairs(ns.Discover.TYPES) do
			assert.is_string(ns.L["RIDDLE_" .. kind])
			assert.is_string(ns.L["RUMOR_" .. kind])
		end
		for _, part in ipairs({ "n", "ne", "e", "se", "s", "sw", "w", "nw", "c" }) do
			assert.are_not.equal("WHERE_" .. part, ns.L["WHERE_" .. part])
		end
	end)
end)
