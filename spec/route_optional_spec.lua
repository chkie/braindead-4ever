-- SPDX-License-Identifier: GPL-3.0-or-later
-- Optional quests (owner 2026-11-10, Camping 101): a module lists quests the route offers with a choice
-- instead of requiring them (module field optional). At the first step that accepts one of them the
-- route asks once "fit them in now or do them on your own"; no leaves them out with their follow-ups.
-- Made-up route (quest IDs 900601 and up) and a fake world, as in route_classquest_spec.lua.
local wow = require("spec.helpers.wow")

local G, P1, P2, P3, F, Z = 900601, 900602, 900603, 900604, 900605, 900606
-- G hands in, then the step accepts the optional P1, P2 and P3; F needs P1; Z is for everyone.
local QUESTS = {
	[G] = { 2, 100 },
	[P1] = { 4, 270, { { G } } },
	[P2] = { 4, 270, { { G } } },
	[P3] = { 4, 270, { { G } } },
	[F] = { 5, 300, { { P1 } } },
	[Z] = { 5, 400 },
}

local function q(code, quest)
	return { code, quest, 1, 0 }
end
local function go(map)
	return { 5, map, 0, 0, 10, 1, 0, 1 }
end
local function st(module, id, lv, ...)
	return { module = module, step = { id = id, lv = lv, ... } }
end

local function route()
	return {
		st("m-start", "aG", 1, q(1, G), go(2521)),
		st("m-start", "tG", 2, q(3, G), q(1, P1), q(1, P2), q(1, P3), go(2521)),
		st("m-start", "cP1", 3, q(2, P1), go(2521)),
		st("m-start", "tP1", 3, q(3, P1), q(1, F), go(2521)),
		st("m-start", "tP2", 3, q(2, P2), q(3, P2), go(2521)),
		st("m-start", "tP3", 3, q(2, P3), q(3, P3), go(2521)),
		st("m-start", "tF", 4, q(3, F), go(2521)),
		st("m-start", "aZ", 4, q(1, Z), go(2521)),
		st("m-start", "tZ", 5, q(3, Z), go(2521)),
	}
end

local function newWorld()
	local w = { flagged = {}, log = {}, level = 2, map = 2521 }
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
			return 0, 400, 0
		end,
	}
	function w:hand(id)
		self.log[id] = nil
		self.flagged[id] = true
	end
	return w
end

describe("Optional quests are an offer with a choice (Camping 101)", function()
	wow.reset({})
	local ns = wow.loadFiles({
		"Braindead4Ever/Routes/Routes.lua",
		"Braindead4Ever/Routes/XP.lua",
		"Braindead4Ever/Routes/Runtime.lua",
		"Braindead4Ever/Routes/Replan.lua",
	})
	local RT = ns.Runtime
	local MODULES = { ["m-start"] = { kind = "start", optional = { beruf = { P1, P2, P3 } } } }

	local function new(w, saved, modules)
		local rt = RT.New(route(), QUESTS, w.api, saved or {}, { modules = modules or MODULES })
		rt:Evaluate()
		return rt
	end

	it("asks at the step that accepts them, with every open optional quest of the module", function()
		local w = newWorld()
		local rt = new(w)
		assert.are.equal("aG", rt:Current().id)
		assert.is_nil(rt:Offer(), "no question before the step")
		w:hand(G)
		rt:Evaluate()
		assert.are.equal("tG", rt:Current().id)
		local o = rt:Offer()
		assert.are.equal("opt", o.kind)
		assert.are.same({ P1, P2, P3 }, o.quests)
		assert.is_true(rt:OptPending(P1), "unanswered: the automation leaves them alone")
		assert.is_false(rt:OptPending(Z))
	end)

	it("now keeps the steps and asks no more", function()
		local w = newWorld()
		w:hand(G)
		local rt = new(w)
		local o = rt:Offer()
		assert.is_true(rt:AnswerOffer(o.id, true))
		assert.is_nil(rt:Offer())
		assert.is_false(rt:OptPending(P1))
		assert.is_nil(rt:Blocked()[P1])
		w.log[P1], w.log[P2], w.log[P3] = {}, {}, {}
		rt:Evaluate()
		assert.are.equal("cP1", rt:Current().id)
	end)

	it("on my own leaves them out with their follow-up quests, and undo brings them back", function()
		local w = newWorld()
		w:hand(G)
		local rt = new(w)
		local o = rt:Offer()
		assert.is_true(rt:AnswerOffer(o.id, false))
		local blocked = rt:Blocked()
		assert.is_true(blocked[P1] and blocked[P2] and blocked[P3])
		assert.is_true(blocked[F], "the follow-up of P1 goes with it")
		assert.is_nil(blocked[Z])
		assert.is_nil(rt:Offer(), "the question does not come again")
		assert.are.equal("aZ", rt:Current().id, "the route goes on with the next quest for everyone")
		assert.are.equal("optional", rt:LastAction().kind)
		assert.is_true(rt:Undo())
		assert.is_nil(rt:Blocked()[P1])
		assert.are.equal("tG", rt:Current().id)
	end)

	it("a quest already in the log does not ask again, the others still do", function()
		local w = newWorld()
		w:hand(G)
		w.log[P1] = {}
		local rt = new(w)
		local o = rt:Offer()
		assert.are.equal("opt", o.kind)
		w.log[P2], w.log[P3] = {}, {}
		rt:Evaluate()
		assert.is_nil(rt:Offer(), "all taken in the game: nothing left to ask")
	end)

	it("a module without the list asks nothing", function()
		local w = newWorld()
		w:hand(G)
		local rt = new(w, nil, { ["m-start"] = { kind = "start" } })
		assert.are.equal("tG", rt:Current().id)
		assert.is_nil(rt:Offer())
		assert.is_false(rt:OptPending(P1))
	end)
end)
