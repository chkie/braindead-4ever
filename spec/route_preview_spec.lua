-- SPDX-License-Identifier: GPL-3.0-or-later
-- Routes/Runtime.lua, additions for the step window (Welle 5): which follow-up quests a skip takes
-- with it (shown in the confirmation dialog before anything moves) and which action "undo" takes
-- back (named in the right-click menu). Made-up route as in route_runtime_spec.lua.
local wow = require("spec.helpers.wow")

local A, B, C, D, E, F = 900001, 900002, 900003, 900004, 900005, 900006
-- A -> B -> C chain; E needs A or D (one group); F needs B and D (two groups).
local QUESTS = {
	[A] = { 2, 100 },
	[B] = { 3, 200, { { A } } },
	[C] = { 4, 300, { { B } } },
	[D] = { 2, 150 },
	[E] = { 4, 250, { { A, D } } },
	[F] = { 5, 400, { { B }, { D } } },
}

local function q(code, quest)
	return { code, quest, 1, 0 }
end
local function step(id, lv, ...)
	return { module = "m-test", step = { id = id, lv = lv, ... } }
end

local function route()
	return {
		step("aA", 1, q(1, A)),
		step("aD", 1, q(1, D)),
		step("cA", 2, q(2, A)),
		step("tA", 2, q(3, A), q(1, B)),
		step("cB", 3, q(2, B)),
		step("tB", 3, q(3, B), q(1, C)),
		step("tD", 3, q(3, D), q(1, E), q(1, F)),
		step("tC", 4, q(3, C)),
		step("tE", 5, q(3, E)),
		step("tF", 5, q(3, F)),
	}
end

local function newWorld()
	local w = { flagged = {}, log = {} }
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
			return 1
		end,
		Map = function()
			return 1429
		end,
		XP = function()
			return 0, 400, nil
		end,
	}
	return w
end

local function copy(t)
	local c = {}
	for k, v in pairs(t) do
		c[k] = type(v) == "table" and copy(v) or v
	end
	return c
end

describe("Route runtime previews for the step window", function()
	wow.reset({})
	local ns = wow.loadFiles({
		"Braindead4Ever/Routes/Routes.lua",
		"Braindead4Ever/Routes/XP.lua",
		"Braindead4Ever/Routes/Runtime.lua",
	})
	local RT = ns.Runtime

	local function fresh(w)
		w = w or newWorld()
		local saved = {}
		local rt = RT.New(route(), QUESTS, w.api, saved, { race = 1, class = 1 })
		rt:Evaluate()
		return rt, w, saved
	end

	it("lists the follow-up quests a skip takes with it, without changing anything", function()
		local rt, _, saved = fresh()
		local before = copy(saved)
		-- skipping A blocks B (needs A), C (needs B) and F (group {B} empty); E keeps D
		assert.are.same({ B, C, F }, rt:SkipPreview("m-test/aA"))
		assert.are.same(before, saved)
		assert.are.equal("aA", rt:Current().id)
		-- D alone: E still has A, F loses its group {D}
		assert.are.same({ F }, rt:SkipPreview("m-test/aD"))
		-- default is the current step
		assert.are.same({ B, C, F }, rt:SkipPreview())
		assert.is_nil(rt:SkipPreview("m-test/nope"))
	end)

	it("matches what the skip really does", function()
		local rt = fresh()
		local preview = rt:SkipPreview("m-test/aA")
		rt:Skip("m-test/aA")
		local blocked = rt:Blocked()
		for _, quest in ipairs(preview) do
			assert.is_true(blocked[quest] == true, "preview names " .. quest .. " but the skip did not block it")
		end
		assert.is_nil(blocked[E])
	end)

	it("leaves quests already handed in out of the preview", function()
		local w = newWorld()
		w.flagged[B] = true
		local rt = fresh(w)
		assert.are.same({}, rt:SkipPreview("m-test/aA"))
	end)

	it("lists the follow-up quests of an abandoned quest", function()
		local w = newWorld()
		w.log[A] = { complete = false }
		w.log[D] = { complete = false }
		local rt = fresh(w)
		assert.are.equal("cA", rt:Current().id)
		w.log[A] = nil
		assert.is_true(rt:OnAbandoned(A))
		assert.are.same({ B, C, F }, rt:AbandonPreview())
		rt:ResolveAbandon("reaccept")
		assert.is_nil(rt:AbandonPreview())
	end)

	it("names the last action for undo", function()
		local w = newWorld()
		w.log[A] = { complete = false }
		w.log[D] = { complete = false }
		local rt = fresh(w)
		assert.is_nil(rt:LastAction())
		rt:Check()
		assert.are.same({ kind = "check", key = "m-test/cA", quest = A }, rt:LastAction())
		rt:Skip("m-test/tD")
		assert.are.same({ kind = "skip", key = "m-test/tD", quest = D }, rt:LastAction())
		rt:Back()
		assert.are.equal("back", rt:LastAction().kind)
		rt:Undo()
		assert.are.equal("skip", rt:LastAction().kind)
		w.log[A] = nil
		rt:Undo()
		rt:Undo()
		assert.is_nil(rt:LastAction())
	end)

	it("names abandon answers for undo", function()
		local w = newWorld()
		w.log[A] = { complete = false }
		w.log[D] = { complete = false }
		local rt = fresh(w)
		w.log[A] = nil
		rt:OnAbandoned(A)
		rt:ResolveAbandon("skip")
		assert.are.same({ kind = "skipquest", key = "m-test/aA", quest = A }, rt:LastAction())
		rt:Undo()
		rt:OnAbandoned(A)
		rt:ResolveAbandon("reaccept")
		assert.are.same({ kind = "reaccept", key = "m-test/aA", quest = A }, rt:LastAction())
	end)

	it("reads undo lists saved before the action names existed", function()
		local w = newWorld()
		local saved = { undo = { { marks = {}, roots = {}, anchor = "m-test/aA" } } }
		local rt = RT.New(route(), QUESTS, w.api, saved, { race = 1, class = 1 })
		rt:Evaluate()
		assert.are.same({ kind = "unknown" }, rt:LastAction())
		assert.is_true(rt:Undo())
	end)
end)
