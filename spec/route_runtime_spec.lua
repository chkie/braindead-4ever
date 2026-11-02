-- SPDX-License-Identifier: GPL-3.0-or-later
-- Routes/Runtime.lua: current step, automatic detection, check, skip with follow-up quests, back,
-- undo, abandoned quests and the XP balance. Pure Lua with a made-up route (quest IDs 900001 and up)
-- and a fake world, so every rule is visible in the test.
local wow = require("spec.helpers.wow")

local function load()
	wow.reset({})
	return wow.loadFiles({ "Pathmark/Routes/Routes.lua", "Pathmark/Routes/XP.lua", "Pathmark/Routes/Runtime.lua" })
end

local A, B, C, D, E, F = 900001, 900002, 900003, 900004, 900005, 900006
-- A -> B -> C is a chain; D is independent; E needs A or D (one group, either is enough);
-- F needs B and D (two groups).
local QUESTS = {
	[A] = { 2, 100 },
	[B] = { 3, 200, { { A } } },
	[C] = { 4, 300, { { B } } },
	[D] = { 2, 150 },
	[E] = { 4, 250, { { A, D } } },
	[F] = { 5, 400, { { B }, { D } } },
}

-- Element codes: 1 accept, 2 complete, 3 turnin, 5 goto, 6 travel (docs/ROUTE-FORMAT.md).
local function q(code, quest)
	return { code, quest, 1, 0 }
end
local function go(map)
	return { 5, map, 0, 0, 10, 1, 0, 1 }
end
local function step(id, lv, ...)
	return { module = "m-test", step = { id = id, lv = lv, ... } }
end

local function route()
	return {
		step("aA", 1, q(1, A), go(1429)),
		step("aD", 1, q(1, D), go(1429)),
		step("cA", 2, q(2, A)),
		step("tA", 2, q(3, A), q(1, B), go(1429)),
		step("cB", 3, q(2, B)),
		step("tB", 3, q(3, B), q(1, C), go(1429)),
		step("cD", 3, q(2, D)),
		step("tD", 3, q(3, D), q(1, E), q(1, F), go(1429)),
		step("cC", 4, q(2, C)),
		step("tC", 4, q(3, C), go(1429)),
		step("cE", 4, q(2, E)),
		step("tE", 5, q(3, E), go(1429)),
		step("cF", 5, q(2, F)),
		step("tF", 5, q(3, F), go(1429)),
		step("r1436", 6, { 6, 1, 1436, 16, 0 }),
		step("aZ", 7, q(1, 900010), go(1436)),
	}
end

local function newWorld()
	local w = { flagged = {}, log = {}, level = 1, map = 1429, xp = 0, xpMax = 400, rested = nil, reward = {} }
	w.api = {
		IsFlagged = function(id)
			return w.flagged[id] == true
		end,
		InLog = function(id)
			return w.log[id] ~= nil
		end,
		IsComplete = function(id)
			return w.log[id] ~= nil and w.log[id].complete == true
		end,
		Level = function()
			return w.level
		end,
		Map = function()
			return w.map
		end,
		XP = function()
			return w.xp, w.xpMax, w.rested
		end,
		RewardXP = function(id)
			return w.reward[id]
		end,
	}
	function w:accept(id)
		self.log[id] = { complete = false }
	end
	function w:complete(id)
		self.log[id].complete = true
	end
	function w:turnin(id)
		self.log[id] = nil
		self.flagged[id] = true
	end
	return w
end

local function ids(list)
	local out = {}
	for i, s in ipairs(list) do
		out[i] = s.id
	end
	return out
end

describe("Route runtime", function()
	local ns = load()
	local RT = ns.Runtime

	local function fresh(saved, w)
		w = w or newWorld()
		local rt = RT.New(route(), QUESTS, w.api, saved or {}, { race = 1, class = 1 })
		rt:Evaluate()
		return rt, w
	end

	it("starts at the first step and follows the quest log", function()
		local rt, w = fresh()
		assert.are.equal("aA", rt:Current().id)
		assert.are.equal("m-test/aA", rt:Current().key)
		w:accept(A)
		rt:Evaluate()
		assert.are.equal("aD", rt:Current().id)
		w:accept(D)
		rt:Evaluate()
		assert.are.equal("cA", rt:Current().id)
		w:complete(A)
		rt:Evaluate()
		assert.are.equal("tA", rt:Current().id)
		w:turnin(A)
		rt:Evaluate()
		assert.are.equal("tA", rt:Current().id, "B is not accepted yet")
		w:accept(B)
		rt:Evaluate()
		assert.are.equal("cB", rt:Current().id)
		assert.are.same({ "tB", "cD", "tD" }, ids(rt:Upcoming(3)))
	end)

	it("reports step changes through the notify function", function()
		local rt, w = fresh()
		local seen = {}
		rt.notify = function(event, cur, prev)
			seen[#seen + 1] = { event, cur and cur.id, prev and prev.id }
		end
		w:accept(A)
		rt:Evaluate()
		assert.are.same({ "StepChanged", "aD", "aA" }, seen[1])
		rt:Evaluate()
		assert.are.equal(1, #seen, "no event without a change")
	end)

	it("marks a step as done by hand (check)", function()
		local rt = fresh()
		assert.is_true(rt:Check())
		assert.are.equal("aD", rt:Current().id)
		assert.are.equal("c", rt.saved.marks["m-test/aA"])
	end)

	it("skips a quest together with every quest that needs it, over three quests", function()
		local rt, w = fresh()
		local recalculated
		rt.notify = function(event, reason)
			if event == "RouteRecalculated" then
				recalculated = reason
			end
		end
		w:accept(D)
		rt:Skip("m-test/aA")
		assert.are.equal("skip", recalculated)
		local blocked = rt:Blocked()
		assert.is_true(blocked[A])
		assert.is_true(blocked[B], "B needs A")
		assert.is_true(blocked[C], "C needs B (third quest of the chain)")
		assert.is_true(blocked[F], "F needs B in one of its groups")
		assert.is_nil(blocked[D])
		assert.is_nil(blocked[E], "E needs A or D; D is still possible")
		-- Steps that only hold quests of the chain are skipped; tD stays (D, E remain).
		for _, id in ipairs({ "aA", "cA", "tA", "cB", "tB", "cC", "tC", "cF", "tF" }) do
			assert.are.equal("skipped", rt:StepState(rt.index["m-test/" .. id]), id)
		end
		assert.are.equal("open", rt:StepState(rt.index["m-test/tD"]), "tD also accepts E")
		assert.are.equal("cD", rt:Current().id)
		assert.are.same({ "tD", "cE", "tE" }, ids(rt:Upcoming(3)))
	end)

	it("never blocks a quest that is already handed in", function()
		local rt, w = fresh()
		w:accept(A)
		w:complete(A)
		w:turnin(A)
		w:accept(B)
		rt:Evaluate()
		rt:Skip("m-test/aA") -- A is done: nothing to skip in the chain
		assert.is_nil(rt:Blocked()[B])
	end)

	it("goes back to the last step the player marked and restores the chain", function()
		local rt = fresh()
		rt:Skip("m-test/aA")
		assert.are.equal("aD", rt:Current().id)
		assert.is_true(rt:Back())
		assert.are.equal("aA", rt:Current().id)
		assert.is_nil(next(rt:Blocked()))
		assert.is_nil(rt.saved.marks["m-test/aA"])
	end)

	it("does not go back over steps the server state has done", function()
		local rt, w = fresh()
		w:accept(A)
		rt:Evaluate()
		assert.are.equal("aD", rt:Current().id)
		assert.is_false(rt:Back(), "aA is done by the quest log, not by the player")
		assert.are.equal("aD", rt:Current().id)
	end)

	it("undoes the last action", function()
		local rt = fresh()
		rt:Check()
		rt:Skip()
		assert.are.equal("cA", rt:Current().id)
		assert.is_true(rt:Undo())
		assert.are.equal("aD", rt:Current().id)
		assert.is_nil(rt.saved.marks["m-test/aD"])
		assert.is_true(rt:Undo())
		assert.are.equal("aA", rt:Current().id)
		assert.is_false(rt:Undo())
	end)

	it("holds the step after an abandoned quest until the player decides", function()
		local rt, w = fresh()
		w:accept(A)
		w:accept(D)
		rt:Evaluate()
		assert.are.equal("cA", rt:Current().id)
		local asked
		rt.notify = function(event, quest)
			if event == "QuestAbandoned" then
				asked = quest
			end
		end
		w.log[A] = nil -- abandoned in the quest log
		rt:OnAbandoned(A)
		assert.are.equal(A, asked)
		assert.are.equal(A, rt:Pending())
		rt:Evaluate()
		assert.are.equal("cA", rt:Current().id, "nothing moves without a decision")
		-- Way 1: take it again -> back to the quest giver.
		rt:ResolveAbandon("reaccept")
		assert.is_nil(rt:Pending())
		assert.are.equal("aA", rt:Current().id)
		w:accept(A)
		rt:OnAccepted(A)
		assert.are.equal("cA", rt:Current().id)
		-- Way 2: skip it with its follow-up quests.
		w.log[A] = nil
		rt:OnAbandoned(A)
		rt:ResolveAbandon("skip")
		assert.is_true(rt:Blocked()[C])
		assert.are.equal("cD", rt:Current().id)
		-- Taking the quest again in the game also answers the question.
		rt:Undo()
		assert.are.equal(A, rt:Pending())
		w:accept(A)
		rt:OnAccepted(A)
		assert.is_nil(rt:Pending())
	end)

	it("passes a travel step when the zone is reached or the next quest is done", function()
		local rt, w = fresh()
		for _, id in ipairs({ A, D, B, C, E, F }) do
			w.flagged[id] = true
		end
		rt:Evaluate()
		assert.are.equal("r1436", rt:Current().id)
		w.map = 1436
		rt:Evaluate()
		assert.are.equal("aZ", rt:Current().id)
		local rt2, w2 = fresh()
		for _, id in ipairs({ A, D, B, C, E, F }) do
			w2.flagged[id] = true
		end
		w2:accept(900010) -- already took the first quest there (hearthed in, map not reported)
		rt2:Evaluate()
		assert.is_nil(rt2:Current(), "route finished")
	end)

	it("passes steps far below the character level on a fresh start, but keeps quests in the log", function()
		local w = newWorld()
		w.level = 9
		w:accept(D)
		local rt = fresh({}, w)
		-- levels 1-3 are more than 5 below 9; D is in the log, so its steps stay
		assert.are.equal("cD", rt:Current().id)
	end)

	it("marks the plan steps train, hs, sethome and fp done by their game event", function()
		-- Element codes 7 hs, 8 sethome, 9 fp, 10 train (docs/ROUTE-FORMAT.md).
		local steps = {
			step("aA", 1, q(1, A), go(1429)),
			step("p1", 1, { 10, 16, 0 }, go(1429)),
			step("p2", 1, { 8, 16, 0 }, go(1429)),
			step("p3", 1, { 9, 16, 0 }, go(1429)),
			step("p4", 2, { 7, 16, 0 }),
			step("cA", 2, q(2, A)),
		}
		local w = newWorld()
		local rt = RT.New(steps, QUESTS, w.api, {}, { race = 1, class = 1 })
		rt:Evaluate()
		w:accept(A)
		rt:Evaluate()
		assert.are.equal("p1", rt:Current().id, "a train step waits for the trainer window")
		assert.are.equal("open", rt:StepState(rt.index["m-test/p1"]))
		-- a hearthstone cast marks p4: it lies within the current and the next three steps
		assert.is_true(rt:MarkEvent(ns.Routes.VERB.HS))
		assert.are.equal("p1", rt:Current().id)
		assert.are.equal("done", rt:StepState(rt.index["m-test/p4"]))
		assert.is_true(rt:MarkEvent(ns.Routes.VERB.TRAIN))
		assert.are.equal("p2", rt:Current().id)
		assert.is_true(rt:MarkEvent(ns.Routes.VERB.SETHOME))
		assert.are.equal("p3", rt:Current().id)
		assert.is_true(rt:MarkEvent(ns.Routes.VERB.FP))
		assert.are.equal("cA", rt:Current().id, "p4 was done by its event before")
		assert.is_false(rt:MarkEvent(ns.Routes.VERB.TRAIN), "no train step ahead")
	end)

	it("skips a travel step whose zone block is entirely skipped", function()
		local steps = route()
		table.insert(steps, 15, step("r1433", 5, { 6, 1, 1433, 16, 0 }))
		table.insert(steps, 16, step("aC2", 5, q(1, 900011), go(1433)))
		local w = newWorld()
		local rt = RT.New(steps, QUESTS, w.api, {}, {})
		rt:Evaluate()
		rt:Skip("m-test/aC2")
		assert.are.equal("skipped", rt:StepState(rt.index["m-test/r1433"]))
		assert.are.equal("open", rt:StepState(rt.index["m-test/r1436"]))
	end)

	it("computes the XP balance up to the next zone", function()
		local w = newWorld()
		w.level, w.xp, w.xpMax = 4, 1000, 2100
		w:accept(A)
		w:complete(A)
		w:accept(D)
		w.reward[A] = 110 -- the client value wins over the data
		local rt = fresh({}, w)
		assert.are.equal("tA", rt:Current().id)
		local b = rt:Balance()
		assert.are.equal(1100, b.toLevel)
		assert.are.equal(110, b.step.xp)
		assert.are.equal("log", b.step.source)
		-- turn-ins up to the travel step r1436: A 110 (log), B 200, D 150, C 300, E 250, F 400 = 1410
		assert.are.equal(1410, b.zone.routeXP)
		-- planned level after the travel is 7: 1100 (to 5) + 2800 (5) + 3600 (6) = 7500
		assert.are.equal(7, b.zone.nextLevel)
		assert.are.equal(1436, b.zone.nextMap)
		assert.are.equal(7500, b.zone.needed)
		assert.is_false(b.zone.enough)
		assert.are.equal(6090, b.zone.shortfall)
		-- level 4: 65 XP per kill -> 6090 / 65 = 93.7
		assert.are.equal(94, b.zone.kills)
		assert.are.equal(65, b.zone.killXP)
		assert.is_true(b.estimate)
	end)

	it("reports enough XP when the route reaches the next zone's level", function()
		local w = newWorld()
		w.level, w.xp, w.xpMax = 6, 3500, 3600
		local rt = fresh({}, w)
		local b = rt:Balance()
		assert.are.equal(100, b.toLevel)
		assert.is_true(b.zone.enough)
		assert.are.equal(0, b.zone.shortfall)
		assert.are.equal(0, b.zone.kills)
	end)
end)
