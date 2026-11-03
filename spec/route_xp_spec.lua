-- SPDX-License-Identifier: GPL-3.0-or-later
-- Routes/XP.lua: experience rules as estimates for the XP balance (owner wish 9, 2026-11-01).
-- Expected values are hand-computed from the sources named in XP.lua (warcraft.wiki.gg, cmangos,
-- forever-bugs #138). The kill and quest cases live in tools/tests/fixtures/xp_cases.json, which
-- tools/routekit/xp.py must pass as well (tools/tests/test_xp.py).
local wow = require("spec.helpers.wow")
local json = require("spec.helpers.json")

local function cases()
	local fh = assert(io.open("tools/tests/fixtures/xp_cases.json", "rb"))
	local t = json.decode(fh:read("*a"))
	fh:close()
	return t
end

local function load()
	wow.reset({})
	return wow.loadFiles({ "Braindead4Ever/Routes/XP.lua" }, "Braindead4Ever", {}).XP
end

describe("XP rules", function()
	local XP = load()

	it("knows the Classic level table and its total of 4,084,700 XP from 1 to 60", function()
		assert.are.equal(400, XP.TO_LEVEL[1])
		assert.are.equal(7600, XP.TO_LEVEL[10])
		assert.are.equal(47400, XP.TO_LEVEL[30])
		assert.are.equal(209800, XP.TO_LEVEL[59])
		local sum = 0
		for level = 1, 59 do
			sum = sum + XP.TO_LEVEL[level]
		end
		assert.are.equal(4084700, sum)
		assert.is_nil(XP.TO_LEVEL[60])
	end)

	it("computes kill XP of the shared cases, creatures below with their own level as base (Forever)", function()
		local t = cases()
		assert.is_true(#t.kill >= 10)
		for _, c in ipairs(t.kill) do
			assert.are.equal(c.xp, XP.KillXP(c.level, c.mob, c.elite), c.name)
		end
	end)

	it("matches forever-bugs #138: level 10 against level 5 gives 40 XP rested, 20 without", function()
		-- Measured in the Forever beta: 40 XP rested (Classic Era: 54). Rested kills give double.
		assert.are.equal(20, XP.KillXP(10, 5))
		assert.are.equal(40, 2 * XP.KillXP(10, 5))
	end)

	it("reduces quest XP of the shared cases when the character outlevels the quest", function()
		for _, c in ipairs(cases().quest) do
			assert.are.equal(c.xp, XP.QuestXP(c.full, c.ql, c.level), ("%d %d %d"):format(c.full, c.ql, c.level))
		end
	end)

	it("adds up the XP needed to reach a level", function()
		-- level 5 with 120 of 2800: 2680 left, then 3600 (6), 4500 (7) to reach 8
		assert.are.equal(2680 + 3600 + 4500, XP.Needed(5, 120, 2800, 8))
		assert.are.equal(2680, XP.Needed(5, 120, 2800, 6))
		assert.are.equal(0, XP.Needed(5, 120, 2800, 5))
		assert.are.equal(0, XP.Needed(9, 0, 6500, 3))
	end)

	it("counts kills for a shortfall, rested kills give double and use up the pool", function()
		-- level 10: 95 per kill
		assert.are.equal(11, (XP.Kills(1000, 10, 0))) -- 1000 / 95 = 10.5
		assert.are.equal(6, (XP.Kills(1000, 10, 2000))) -- all rested: 1000 / 190 = 5.3
		-- 380 rested (2 kills at 190), then 620 normal (7 kills at 95)
		assert.are.equal(9, (XP.Kills(1000, 10, 380)))
		local n, per = XP.Kills(0, 10, 0)
		assert.are.equal(0, n)
		assert.are.equal(95, per)
	end)
end)
