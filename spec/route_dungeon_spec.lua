-- SPDX-License-Identifier: GPL-3.0-or-later
-- Dungeon hint (owner wish 11, Welle 4 task 2): level band, givers on the way, prerequisites, the XP
-- balance in speed mode (Forever rules, brain chapter 14 §4.3) and skipping without effect on the
-- route. Real route data for the Deadmines (Alliance) and Ragefire Chasm (Horde), made-up data for
-- the balance rule.
local wow = require("spec.helpers.wow")

-- XP from level n to n + 1 (Routes/XP.lua), for a character with no XP in hand.
local TO_LEVEL = { [13] = 11400, [16] = 16000, [21] = 25200 }

-- A session. opts: faction, race, class, level, mode, anchor (step key), completed (list), log (list).
local function login(opts)
	local mode = opts.mode or "explorer"
	local char = nil
	if opts.anchor then
		char = {
			route = { mode = mode, [mode] = { v = 1, race = opts.race, class = opts.class or 1, anchor = opts.anchor } },
		}
	end
	wow.reset({ char = char })
	local P = wow.world.player
	P.faction = { opts.faction, "" }
	P.race = { "-", "-", opts.race }
	P.class = { "-", "-", opts.class or 1 }
	P.level, P.xp, P.xpMax = opts.level, 0, TO_LEVEL[opts.level] or 10000
	for _, q in ipairs(opts.completed or {}) do
		wow.world.completed[q] = true
	end
	for _, q in ipairs(opts.log or {}) do
		wow.world.questLog[#wow.world.questLog + 1] = { questID = q, objectives = {} }
	end
	local ns = wow.loadFiles(wow.addonFiles())
	wow.fire("ADDON_LOADED", "Braindead4Ever")
	wow.fire("PLAYER_LOGIN")
	wow.fire("PLAYER_ENTERING_WORLD", true, false)
	if ns.Route.Mode() ~= mode then
		ns.Route.SetMode(mode)
	end
	return ns
end

local function hint(ns, id)
	for _, h in ipairs(ns.Route.DungeonHint()) do
		if h.id == id then
			return h
		end
	end
end

local function questSet(h)
	local out = {}
	for _, e in ipairs(h.quests) do
		out[e.q] = e
	end
	return out
end

describe("Dungeon hint: Deadmines (Alliance)", function()
	-- Human warrior at level 16 in Westfall (the route plans Westfall for levels 10 to 14).
	local HUMAN = { faction = "Alliance", race = 1, class = 1, level = 16 }

	it("names the Sentinel Hill quests once the Defias chain is done, not the Stormwind ones", function()
		local opts = { completed = { 155 } }
		for k, v in pairs(HUMAN) do
			opts[k] = v
		end
		local ns = login(opts)
		local h = hint(ns, 63)
		assert.is_table(h, "Deadmines hint")
		assert.are.equal(1581, h.area)
		assert.is_true(h.lo <= 16 and 16 <= h.hi)
		local qs = questSet(h)
		assert.is_table(qs[166], "The Defias Brotherhood finale at Sentinel Hill")
		assert.is_table(qs[214], "Red Silk Bandanas: after the route hands in 153")
		for q, e in pairs(qs) do
			assert.are_not.equal(1453, e.map, "Stormwind is no giver on the way from Westfall: " .. q)
			assert.is_true(e.yards <= ns.Dungeon.ON_WAY_YARDS, q)
			assert.are.equal("take", e.state)
			assert.is_string(e.step)
		end
		assert.is_true(qs[166].yards <= 50)
	end)

	it("leaves the Deadmines out while the prerequisites are not on the way", function()
		local ns = login(HUMAN)
		assert.is_nil(hint(ns, 63), "166 and 214 need 155, the route does not take the Defias chain")
	end)

	it("leaves quests out of other races and classes", function()
		local ns = login({ faction = "Alliance", race = 1, class = 1, level = 22, mode = "explorer" })
		for _, h in ipairs(ns.Route.DungeonHint()) do
			assert.is_nil(questSet(h)[1740], "1740 is a warlock quest")
		end
	end)
end)

describe("Dungeon hint: Ragefire Chasm (Horde)", function()
	it("names the Thunder Bluff givers for a tauren at level 16", function()
		local ns = login({ faction = "Horde", race = 6, class = 1, level = 16 })
		local h = hint(ns, 226)
		assert.is_table(h, "Ragefire Chasm hint")
		assert.are.equal(2437, h.area)
		local qs = questSet(h)
		assert.are.equal(1456, qs[5722].map)
		assert.are.equal(1456, qs[5723].map)
		assert.is_true(qs[5722].yards < 400 and qs[5723].yards < 400)
		assert.is_nil(qs[5728], "Orgrimmar quests need 5727, which no route takes")
	end)

	it("speed mode: shows the dungeon when the route lacks XP and the dungeon covers part of it", function()
		-- Orc warrior entering Silverpine at level 16 without XP in hand: the route up to the next zone
		-- does not reach the planned level; the Undercity giver of Ragefire Chasm is on the way.
		local ns = login({
			faction = "Horde",
			race = 2,
			class = 1,
			level = 16,
			mode = "speed",
			anchor = "h-speed-core-02-1421/r1421",
		})
		local b = ns.Route.Balance()
		assert.is_true(b.zone.shortfall > 0)
		local h = hint(ns, 226)
		assert.is_table(h, "Ragefire Chasm in speed mode")
		assert.is_true(h.justified)
		assert.are.equal(b.zone.shortfall, h.need)
		assert.is_true(h.balance > 0)
		assert.are.equal(1458, questSet(h)[5725].map)
	end)

	it("speed mode: no dungeon when the balance is negative (the route has enough XP)", function()
		local explorer = login({ faction = "Horde", race = 6, class = 1, level = 16, mode = "explorer" })
		local h = hint(explorer, 226)
		assert.is_table(h, "explorer mode shows it")
		assert.are.equal(0, h.need)
		assert.is_true(h.balance < 0)
		assert.is_false(h.justified)
		local speed = login({ faction = "Horde", race = 6, class = 1, level = 16, mode = "speed" })
		assert.are.equal(0, speed.Route.Balance().zone.shortfall)
		for _, d in ipairs(speed.Route.DungeonHint()) do
			assert.is_true(d.balance > 0, "speed mode shows dungeon " .. d.id .. " despite a negative balance")
		end
		assert.is_nil(hint(speed, 226))
	end)

	it("can be skipped without any change of the route, and shown again", function()
		local ns = login({ faction = "Horde", race = 6, class = 1, level = 16 })
		local rt = ns.Route.Runtime()
		local before = { key = ns.Route.Current().key, upcoming = #ns.Route.Upcoming(5) }
		local roots, marks = 0, 0
		assert.is_true(ns.Route.SkipDungeon(226))
		assert.is_nil(hint(ns, 226))
		assert.are.equal(before.key, ns.Route.Current().key)
		assert.are.equal(before.upcoming, #ns.Route.Upcoming(5))
		for _ in pairs(rt.saved.roots) do
			roots = roots + 1
		end
		for _ in pairs(rt.saved.marks) do
			marks = marks + 1
		end
		assert.are.equal(0, roots)
		assert.are.equal(0, marks)
		assert.is_true(ns.Route.SkipDungeon(226, true))
		assert.is_table(hint(ns, 226))
		assert.is_false(ns.Route.SkipDungeon(999999), "unknown dungeon")
	end)

	it("counts a dungeon quest in the log, leaves out handed-in ones", function()
		local ns = login({ faction = "Horde", race = 6, class = 1, level = 16, log = { 5722 }, completed = { 5723 } })
		local qs = questSet(hint(ns, 226))
		assert.are.equal("log", qs[5722].state)
		assert.is_nil(qs[5723])
	end)
end)

describe("Dungeon hint: balance rule (made-up data)", function()
	-- One step with a goto point next to the giver, one dungeon with one quest worth 2000 XP.
	local function setup()
		wow.reset({})
		local ns = wow.loadFiles({
			"Braindead4Ever/Routes/Routes.lua",
			"Braindead4Ever/Routes/XP.lua",
			"Braindead4Ever/Routes/Prereq.lua",
			"Braindead4Ever/Routes/Dungeon.lua",
			"Braindead4Ever/Routes/Runtime.lua",
		})
		local world = {
			IsFlagged = function()
				return false
			end,
			InLog = function()
				return false
			end,
			IsComplete = function()
				return false
			end,
			Level = function()
				return 20
			end,
			Map = function()
				return 100
			end,
		}
		local steps = { { module = "m", step = { id = "g1", lv = 20, { 5, 100, 10, 10, 10, 1, 0, 1 } } } }
		local rt = ns.Runtime.New(steps, {}, world, {})
		rt:Evaluate()
		local data = {
			maps = { [100] = 1 },
			dungeons = { [7] = { area = 70, min = 15, lo = 18, hi = 24, quests = { 900001 } } },
			dquests = { [900001] = { 20, 15, 2000, 100, 20, 20 } },
		}
		return ns.Dungeon, rt, data
	end

	local function run(mode, need)
		local DG, rt, data = setup()
		return DG.Hints(rt, data, { mode = mode, level = 20, balance = { zone = { shortfall = need } } })[1]
	end

	it("balance = covered need minus XP the route does not need", function()
		assert.are.equal(-2000, run("explorer", 0).balance)
		assert.are.equal(2000, run("explorer", 5000).balance)
		assert.are.equal(500, run("explorer", 1250).balance, "1250 covered, 750 surplus")
		assert.are.equal(-1000, run("explorer", 500).balance, "500 covered, 1500 surplus")
	end)

	it("speed mode shows the dungeon only with a positive balance", function()
		assert.is_nil(run("speed", 0))
		assert.is_nil(run("speed", 500))
		assert.is_nil(run("speed", 1000), "balance 0: no gain over the route")
		assert.is_table(run("speed", 1250))
		assert.is_table(run("speed", 5000))
		assert.is_table(run("explorer", 0), "explorer mode does not ask the balance")
	end)

	it("uses the Classic level reduction on top of the Forever value", function()
		local DG, rt, data = setup()
		data.dungeons[7].hi = 30
		local h = DG.Hints(rt, data, { mode = "explorer", level = 26 })[1]
		assert.are.equal(1600, h.gain, "quest level 20 at character level 26: 80 %")
	end)

	it("needs the giver within the on-the-way distance", function()
		local DG, rt, data = setup()
		data.dquests[900001][5] = 10 + DG.ON_WAY_YARDS + 1
		assert.is_nil(DG.Hints(rt, data, { mode = "explorer", level = 20 })[1])
	end)
end)
