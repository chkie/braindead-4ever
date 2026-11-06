-- SPDX-License-Identifier: GPL-3.0-or-later
-- Class quests are never lost (owner 2026-11-05, KQ-1105): skipping, abandoning or passing a quest of a
-- class chain puts it on the list "later"; the travel step of a class insert asks "now or later"; the
-- list comes back at the next zone change and is played as a side trip. Made-up route (quest IDs
-- 900501 and up) and a fake world, as in route_runtime_spec.lua.
local wow = require("spec.helpers.wow")

local A, K, K2, X, X2, Z, N = 900501, 900502, 900503, 900504, 900505, 900506, 900507
-- K is a class quest of the core (element class filter), K2 needs K; X and X2 are the class insert
-- (module kind "class"), X2 needs X; A and Z are quests for everyone.
local QUESTS = {
	[A] = { 2, 100 },
	[K] = { 3, 200 },
	[K2] = { 4, 300, { { K } } },
	[X] = { 4, 300 },
	[X2] = { 5, 300, { { X } } },
	[Z] = { 6, 400 },
	[N] = { 4, 100, { { K } } }, -- for everyone, needs the class quest K
}

local function q(code, quest, class)
	return { code, quest, 1, 0, c = class }
end
local function go(map)
	return { 5, map, 0, 0, 10, 1, 0, 1 }
end
local function st(module, id, lv, ...)
	return { module = module, step = { id = id, lv = lv, ... } }
end

local MODULES = {
	["m-core"] = { kind = "core" },
	["m-class"] = { kind = "class" },
	["m-next"] = { kind = "core" },
}

local function route()
	local detour = { id = "r1454", lv = 4, ret = "Klassenquest", { 6, 1, 1454, 16, 0 } }
	return {
		st("m-core", "aA", 1, q(1, A), go(1429)),
		st("m-core", "tA", 2, q(3, A), go(1429)),
		st("m-core", "aK", 3, q(1, K, 1), go(1429)),
		st("m-core", "tK", 3, q(3, K, 1), q(1, K2, 1), go(1429)),
		st("m-core", "tK2", 4, q(3, K2, 1), q(1, N), go(1429)),
		st("m-core", "tN", 4, q(3, N), go(1429)),
		{ module = "m-class", step = detour },
		st("m-class", "aX", 4, q(1, X), go(1454)),
		st("m-class", "tX", 4, q(3, X), q(1, X2), go(1454)),
		st("m-class", "tX2", 5, q(3, X2), go(1454)),
		st("m-next", "r1436", 6, { 6, 1, 1436, 16, 0 }),
		st("m-next", "aZ", 6, q(1, Z), go(1436)),
		st("m-next", "tZ", 6, q(3, Z), go(1436)),
	}
end

local function newWorld()
	local w = { flagged = {}, log = {}, level = 1, map = 1429 }
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

describe("Class quests are never lost (KQ-1105)", function()
	wow.reset({})
	local ns = wow.loadFiles({
		"Braindead4Ever/Routes/Routes.lua",
		"Braindead4Ever/Routes/XP.lua",
		"Braindead4Ever/Routes/Runtime.lua",
		"Braindead4Ever/Routes/Replan.lua",
	})
	local RT = ns.Runtime

	local function new(w, saved)
		local rt = RT.New(route(), QUESTS, w.api, saved or {}, { modules = MODULES })
		rt:Evaluate()
		return rt
	end

	local function contains(list, x)
		for _, v in ipairs(list) do
			if v == x then
				return true
			end
		end
		return false
	end

	it("knows class quests by the element filter and by the class insert", function()
		local rt = new(newWorld())
		assert.is_true(rt:ClassChain(K))
		assert.is_true(rt:ClassChain(X2))
		assert.is_false(rt:ClassChain(A))
		assert.is_false(rt:ClassChain(Z))
	end)

	it("skipping a class quest postpones it: nothing is blocked, the follow-up stays", function()
		local w = newWorld()
		w:hand(A)
		local rt = new(w)
		assert.are.equal("aK", rt:Current().id)
		assert.are.same({ K2, N }, rt:SkipPreview(), "the follow-ups go along")
		assert.is_true(rt:Skip())
		assert.are.equal("r1454", rt:Current().id, "the route moves on")
		assert.is_nil(rt:Blocked(true)[K], "not skipped for good")
		assert.is_true(contains(rt:Later(), K))
		assert.is_true(contains(rt:Later(), K2), "the follow-up waits with it")
		assert.is_true(rt:Blocked()[N], "a quest without class bond that needs K waits too")
		assert.is_false(contains(rt:Later(), N), "but it is no class quest to bring back")
		-- counter-check: a quest for everyone is skipped as before
		local w2 = newWorld()
		local rt2 = new(w2)
		assert.are.equal("aA", rt2:Current().id)
		rt2:Skip()
		assert.is_true(rt2:Blocked()[A])
		assert.are.same({}, rt2:Later())
	end)

	it("abandoning a class quest and answering skip postpones it", function()
		local w = newWorld()
		w:hand(A)
		w.log[K] = { complete = false }
		local rt = new(w)
		assert.are.equal("tK", rt:Current().id)
		w.log[K] = nil
		assert.is_true(rt:OnAbandoned(K))
		assert.is_true(rt:ResolveAbandon("skip"))
		assert.is_nil(rt:Blocked(true)[K])
		assert.is_true(contains(rt:Later(), K))
	end)

	it("the class insert asks now or later; later comes back at the next zone change", function()
		local w = newWorld()
		for _, id in ipairs({ A, K, K2, N }) do
			w:hand(id)
		end
		w.level = 4
		local rt = new(w)
		assert.are.equal("r1454", rt:Current().id)
		local o = rt:Offer()
		assert.are.equal("class", o.kind)
		assert.are.equal(1454, o.map)
		assert.is_true(rt:AnswerOffer(o.id, false))
		assert.are.equal("r1436", rt:Current().id, "later: the route goes on with the next zone")
		assert.is_true(contains(rt:Later(), X))
		assert.is_true(contains(rt:Later(), X2))
		local o2 = rt:Offer()
		assert.are.equal("later", o2.kind)
		assert.are.equal(2, #o2.quests)
		assert.is_true(rt:AnswerOffer(o2.id, true))
		assert.are.equal("r1454", rt:Current().id, "now: the side trip starts at the detour")
		assert.is_nil(rt:Offer(), "no new question during the side trip")
		w.map = 1454
		rt:Evaluate()
		assert.are.equal("aX", rt:Current().id)
		w:hand(X)
		w:hand(X2)
		rt:Evaluate()
		assert.are.equal("r1436", rt:Current().id, "after the side trip the route goes on where it was")
		assert.are.same({}, rt:Later())
	end)

	it("no keeps the list for the next zone change", function()
		local w = newWorld()
		for _, id in ipairs({ A, K, K2, N }) do
			w:hand(id)
		end
		w.level = 4
		local rt = new(w)
		rt:AnswerOffer(rt:Offer().id, false)
		local o = rt:Offer()
		assert.are.equal("later", o.kind)
		assert.is_true(rt:AnswerOffer(o.id, false))
		assert.is_nil(rt:Offer())
		assert.are.equal(2, #rt:Later(), "still on the list")
	end)

	it("a class chain the route passes by level waits on the list", function()
		local w = newWorld()
		w:hand(A)
		w.level = 12 -- more than five levels above aK, tK, tK2 and the insert
		local rt = new(w)
		assert.is_true(contains(rt:Later(), K))
		assert.is_true(contains(rt:Later(), X))
		assert.is_false(contains(rt:Later(), Z))
	end)

	it("undo takes a postponement back", function()
		local w = newWorld()
		w:hand(A)
		local rt = new(w)
		rt:Skip()
		assert.is_true(contains(rt:Later(), K))
		assert.is_true(rt:Undo())
		assert.is_false(contains(rt:Later(), K))
		assert.are.equal("aK", rt:Current().id)
	end)
end)

describe("Level hint for class quests (ME-1106)", function()
	wow.reset({})
	local ns = wow.loadFiles({
		"Braindead4Ever/Routes/Routes.lua",
		"Braindead4Ever/Routes/XP.lua",
		"Braindead4Ever/Routes/Runtime.lua",
		"Braindead4Ever/Routes/Replan.lua",
	})
	local RT = ns.Runtime
	-- the class insert's first quest X has minimum level 4
	local mods = {
		["m-core"] = { kind = "core" },
		["m-class"] = { kind = "class", ready = 4 },
		["m-next"] = { kind = "core" },
	}
	local function new(w, saved)
		local rt = RT.New(route(), QUESTS, w.api, saved or {}, { modules = mods })
		rt:Evaluate()
		return rt
	end

	it("reaching the level asks now or later while the insert is still far ahead", function()
		local w = newWorld()
		w:hand(A)
		w.level = 4
		local rt = new(w)
		assert.are.equal("aK", rt:Current().id)
		local o = rt:Offer()
		assert.are.equal("ready", o.kind)
		assert.are.equal(X, o.quest)
		assert.are.equal(1454, o.map)
		assert.is_true(rt:AnswerOffer(o.id, true))
		assert.are.equal("r1454", rt:Current().id, "now: the side trip starts at the detour")
		assert.is_nil(rt:Offer(), "the travel step asks no more")
		w.map = 1454
		rt:Evaluate()
		assert.are.equal("aX", rt:Current().id)
		w:hand(X)
		w:hand(X2)
		rt:Evaluate()
		assert.are.equal("aK", rt:Current().id, "after the side trip the route goes on where it was")
		assert.is_true(rt:Undo() ~= false)
	end)

	it("below the level there is no hint", function()
		local w = newWorld()
		w:hand(A)
		w.level = 3
		local rt = new(w)
		assert.are.equal("aK", rt:Current().id)
		assert.is_nil(rt:Offer())
	end)

	it("later keeps the insert at its planned place, where the travel step asks again", function()
		local w = newWorld()
		w:hand(A)
		w.level = 4
		local rt = new(w)
		local o = rt:Offer()
		assert.are.equal("ready", o.kind)
		assert.is_true(rt:AnswerOffer(o.id, false))
		assert.is_nil(rt:Offer(), "the hint does not come again")
		for _, id in ipairs({ K, K2, N }) do
			w:hand(id)
		end
		rt:Evaluate()
		assert.are.equal("r1454", rt:Current().id)
		assert.are.equal("class", rt:Offer().kind)
	end)

	it("an insert due within the next steps gets no extra hint", function()
		local w = newWorld()
		for _, id in ipairs({ A, K, K2 }) do
			w:hand(id)
		end
		w.level = 4
		local rt = new(w)
		assert.are.equal("tK2", rt:Current().id, "two steps before the detour")
		assert.is_nil(rt:Offer())
	end)
end)
