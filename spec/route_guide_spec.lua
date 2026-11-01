-- SPDX-License-Identifier: GPL-3.0-or-later
-- Routes/Guide.lua (module "route") with the real route data: a route for all 56 combinations, progress
-- that survives /reload, detection from simulated game events, quests done before the login, abandoned
-- quests, the chain rule on real prerequisites, callbacks and the XP balance event.
local wow = require("spec.helpers.wow")

-- 56 combinations from the client table CharBaseInfo (wowf 1.60.1.70707), brain chapter 14 §1.
local COMBOS = {
	Alliance = {
		[1] = { 1, 2, 3, 4, 5, 8, 9 },
		[3] = { 1, 2, 3, 4, 5, 7 },
		[7] = { 1, 4, 5, 8, 9 },
		[4] = { 1, 3, 4, 5, 11 },
		[95] = { 1, 3, 4, 8, 11 },
	},
	Horde = {
		[2] = { 1, 3, 4, 7, 8, 9 },
		[5] = { 1, 2, 4, 5, 8, 9 },
		[8] = { 1, 3, 4, 5, 7, 8, 9 },
		[6] = { 1, 3, 7, 11 },
		[96] = { 1, 3, 4, 7, 11 },
	},
}

local V = { ACCEPT = 1, COMPLETE = 2, TURNIN = 3, TRAVEL = 6 }

-- Plain copy, like SavedVariables written at logout and read at the next login: no shared tables.
local function deepcopy(t)
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in pairs(t) do
		c[deepcopy(k)] = deepcopy(v)
	end
	return c
end

-- A session for one character. opts: faction, race, class (IDs), level, completed (set), char, saved.
local function login(opts)
	opts = opts or {}
	wow.reset({ char = opts.char, saved = opts.saved, collect = opts.collect })
	local P = wow.world.player
	P.faction = { opts.faction or "Alliance", "" }
	P.race = { "-", "-", opts.race or 1 }
	P.class = { "-", "-", opts.class or 1 }
	P.level = opts.level or 1
	P.xp, P.xpMax = opts.xp or 0, opts.xpMax or 400
	for q in pairs(opts.completed or {}) do
		wow.world.completed[q] = true
	end
	local ns = wow.loadFiles(wow.addonFiles())
	wow.fire("ADDON_LOADED", "Pathmark")
	wow.fire("PLAYER_LOGIN")
	wow.fire("PLAYER_ENTERING_WORLD", true, false)
	return ns
end

-- /reload: logout writes the SavedVariables, the next session reads a copy of them.
local function reload(opts)
	wow.fire("PLAYER_LOGOUT")
	local o = deepcopy(opts or {})
	o.char = deepcopy(_G.PathmarkCharDB)
	o.saved = deepcopy(_G.PathmarkDB)
	o.collect = deepcopy(_G.PathmarkCollectDB)
	o.completed = deepcopy(wow.world.completed)
	local log = deepcopy(wow.world.questLog)
	local map = wow.world.player.map
	local ns = login(o)
	wow.world.questLog = log
	wow.world.player.map = map
	return ns
end

local function eachCombo(fn)
	for faction, races in pairs(COMBOS) do
		for race, classes in pairs(races) do
			for _, class in ipairs(classes) do
				fn(faction, race, class)
			end
		end
	end
end

local function logEntry(q)
	for _, e in ipairs(wow.world.questLog) do
		if e.questID == q then
			return e
		end
	end
end

-- The player does what the current step says, with the events the client sends.
local function play(step, opts)
	opts = opts or {}
	local W = wow.world
	for _, el in ipairs(step) do
		local v, q = el[1], el[2]
		if v == V.ACCEPT and not logEntry(q) and not W.completed[q] then
			W.questLog[#W.questLog + 1] = { questID = q, objectives = {} }
			wow.fire("QUEST_ACCEPTED", q)
		elseif v == V.COMPLETE and logEntry(q) then
			logEntry(q).complete = true
			wow.fire("QUEST_LOG_UPDATE")
		elseif v == V.TURNIN and logEntry(q) then
			for i, e in ipairs(W.questLog) do
				if e.questID == q then
					table.remove(W.questLog, i)
					break
				end
			end
			W.completed[q] = true
			wow.fire("QUEST_REMOVED", q, false)
			if not opts.noTurnedIn then -- Forever may send QUEST_TURNED_IN late or never
				wow.fire("QUEST_TURNED_IN", q, 100, 0)
			end
			wow.fire("QUEST_LOG_UPDATE")
		elseif v == V.TRAVEL then
			W.player.map = el[3]
			wow.fire("ZONE_CHANGED_NEW_AREA")
		end
	end
	wow.advance(1.5)
end

describe("Route module", function()
	it("gives all 56 combinations a route from their start module, in both modes", function()
		local n = 0
		eachCombo(function(faction, race, class)
			local ns = login({ faction = faction, race = race, class = class })
			local label = ("%s %d/%d"):format(faction, race, class)
			local R = ns.Route
			assert.are.equal("on", ns.Modules.state.route, label)
			local cur = R.Current()
			assert.is_table(cur, label)
			assert.are.equal(1, cur.index, label)
			assert.matches("%-speed%-start%-", cur.module, label)
			assert.is_true(R.SetMode("explorer"), label)
			assert.matches("%-explorer%-start%-", R.Current().module, label)
			n = n + 1
		end)
		assert.are.equal(56, n)
	end)

	it("keeps progress of every combination over /reload", function()
		eachCombo(function(faction, race, class)
			local opts = { faction = faction, race = race, class = class }
			local ns = login(opts)
			local R = ns.Route
			assert.is_true(R.Check())
			assert.is_true(R.Skip())
			local key = R.Current().key
			ns = reload(opts)
			assert.are.equal(key, ns.Route.Current().key, ("%s %d/%d"):format(faction, race, class))
			assert.is_true(ns.Route.Undo(), "undo list survives the reload")
		end)
	end)

	it("keeps marks, skipped quests, the mode and the undo list over /reload", function()
		local ns = login()
		local R = ns.Route
		R.Check()
		R.Skip()
		local key = R.Current().key
		local blocked = R.Runtime():Blocked()
		assert.is_true(next(blocked) ~= nil)
		ns = reload()
		R = ns.Route
		assert.are.equal(key, R.Current().key)
		assert.are.same(blocked, R.Runtime():Blocked())
		R.SetMode("explorer")
		ns = reload()
		assert.are.equal("explorer", ns.Route.Mode())
		ns.Route.SetMode("speed")
		assert.are.equal(key, ns.Route.Current().key, "the speed progress is kept apart from explorer")
	end)

	it("writes the progress back at logout when the client replaced the SavedVariables table", function()
		local ns = login()
		ns.Route.Check()
		local key = ns.Route.Current().key
		_G.PathmarkCharDB = { id = "replaced" } -- Forever beta trap (Polestar, brain chapter 15 §7)
		ns = reload()
		assert.are.equal(key, ns.Route.Current().key)
	end)

	it("follows accept, objectives, turn-in and travel through the whole Elwynn start module", function()
		local ns = login()
		local R = ns.Route
		local steps = 0
		local turnedInMissing = false
		while R.Current() and R.Current().module == "a-speed-start-elwynn" do
			local cur = R.Current()
			turnedInMissing = not turnedInMissing
			play(cur.step, { noTurnedIn = turnedInMissing })
			assert.are_not.equal(cur.key, R.Current() and R.Current().key, "stuck at " .. cur.key)
			assert.is_nil(R.Pending(), "a turn-in without QUEST_TURNED_IN is no abandon: " .. cur.key)
			steps = steps + 1
			assert.is_true(steps < 500)
		end
		assert.is_true(steps > 40, "only " .. steps .. " steps")
		assert.is_table(R.Current())
	end)

	it("moves on when the character outlevels steps (grinding instead of quests)", function()
		local ns = login()
		local R = ns.Route
		assert.are.equal(1, R.Current().lv)
		wow.world.player.level = 12
		wow.fire("PLAYER_LEVEL_UP", 12)
		wow.advance(0.5)
		assert.is_true(R.Current().lv >= 7, "at planned level " .. R.Current().lv)
	end)

	it("skips quests handed in before the login (entry at level 12 and 25 for each faction)", function()
		for _, who in ipairs({ { "Alliance", 1, 1 }, { "Horde", 2, 1 } }) do
			local base = login({ faction = who[1], race = who[2], class = who[3] })
			local done = {}
			for _, s in ipairs(base.Routes.Steps(who[1], "speed", who[2], who[3])) do
				if s.step.lv <= 10 then
					for _, el in ipairs(s.step) do
						if el[1] <= V.TURNIN then
							done[el[2]] = true
						end
					end
				end
			end
			local ns = login({ faction = who[1], race = who[2], class = who[3], level = 12, completed = done })
			local cur = ns.Route.Current()
			assert.is_true(cur.lv >= 10, who[1] .. " level 12 starts at planned level " .. cur.lv)
			local open = false
			for _, q in ipairs(cur.quests) do
				open = open or not done[q]
			end
			assert.is_true(open, "every quest of " .. cur.key .. " is done already")
			ns = login({ faction = who[1], race = who[2], class = who[3], level = 25 })
			assert.is_true(ns.Route.Current().lv >= 20, who[1] .. " level 25 at " .. ns.Route.Current().lv)
		end
	end)

	it("asks about an abandoned quest and offers to take it again or skip it", function()
		local ns = login()
		local R = ns.Route
		local asked = {}
		R.RegisterCallback("QuestAbandoned", "test", function(_, q)
			asked[#asked + 1] = q
		end)
		play(R.Current().step) -- accept 33
		play(R.Current().step) -- accept 783
		local cur = R.Current().key
		table.remove(wow.world.questLog, 1) -- abandon 33
		wow.fire("QUEST_REMOVED", 33, false)
		wow.advance(1.5)
		assert.are.same({ 33 }, asked)
		assert.are.equal(33, R.Pending())
		assert.are.equal(cur, R.Current().key, "nothing moves before the answer")
		assert.is_true(R.ResolveAbandon("reaccept"))
		assert.are.equal("a-speed-start-elwynn/a33", R.Current().key)
		assert.is_true(R.Undo())
		assert.is_true(R.ResolveAbandon("skip"))
		assert.are.equal("skipped", R.StepState("a-speed-start-elwynn/c33"))
	end)

	it("skips a chain of three quests from the real prerequisites", function()
		local ns = login()
		local rt = ns.Route.Runtime()
		-- Find q -> f -> g in this route (each one needs the one before).
		local chain
		for i, s in ipairs(rt.steps) do
			for _, q in ipairs(s.quests) do
				for _, f in ipairs(rt.dependents[q] or {}) do
					for _, g in ipairs(rt.dependents[f] or {}) do
						if rt.accepts[q] == i and rt.accepts[f] and rt.accepts[g] and not chain then
							chain = { q, f, g }
						end
					end
				end
			end
		end
		assert.is_table(chain, "no chain of three quests in the route")
		local key = rt.steps[rt.accepts[chain[1]]].key
		assert.is_true(ns.Route.Skip(key))
		for _, q in ipairs(chain) do
			assert.is_true(rt:Blocked()[q] == true, "not skipped: " .. q)
			assert.are.equal("skipped", ns.Route.StepState(rt.steps[rt.accepts[q]].key), "step of " .. q)
		end
	end)

	it("sends step changes, recalculations and the XP balance to listeners; a broken one stops none", function()
		local ns = login({ xp = 100, xpMax = 400 })
		local R = ns.Route
		local got = {}
		R.RegisterCallback("StepChanged", "broken", function()
			error("listener failed")
		end)
		R.RegisterCallback("StepChanged", "ui", function(owner, cur, prev)
			got[#got + 1] = { owner, cur.id, prev.id }
		end)
		R.RegisterCallback("RouteRecalculated", "ui", function(_, reason)
			got[#got + 1] = { "recalc", reason }
		end)
		R.RegisterCallback("XPBalance", "ui", function(_, b)
			got[#got + 1] = { "xp", b.toLevel }
		end)
		R.Check()
		assert.are.same({ "ui", "a783", "a33" }, got[1])
		R.Skip()
		assert.are.same({ "recalc", "skip" }, got[#got])
		wow.world.player.xp = 250
		wow.fire("PLAYER_XP_UPDATE", "player")
		wow.advance(0.5)
		assert.are.same({ "xp", 150 }, got[#got])
		assert.are.equal(150, R.LastGain().xp)
		assert.are.equal("on", ns.Modules.state.route)
		assert.matches("listener failed", ns.Guard:Report(), 1, true)
		R.UnregisterCallback("StepChanged", "ui")
		local n = #got
		R.Check()
		assert.are.equal(n, #got)
	end)

	it("reports a missing route instead of failing for an unknown race", function()
		local ns = login({ race = 99, class = 1 }) -- new races are announced (brain chapter 14 §1)
		assert.is_nil(ns.Route.Current())
		assert.matches("no route for Alliance 99/1", ns.CurrentStep(), 1, true)
		assert.are.equal("on", ns.Modules.state.route)
	end)
end)
