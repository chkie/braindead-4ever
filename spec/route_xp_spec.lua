-- SPDX-License-Identifier: GPL-3.0-or-later
-- Routes/XP.lua: Classic experience rules as estimates for the XP balance (owner wish 9, 2026-11-01).
-- Expected values are hand-computed from the sources named in XP.lua (warcraft.wiki.gg, cmangos).
local wow = require("spec.helpers.wow")

local function load()
	wow.reset({})
	return wow.loadFiles({ "Pathmark/Routes/XP.lua" }, "Pathmark", {}).XP
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

	it("computes kill XP with the character level as base", function()
		-- base = 20 * 5 + 45 = 145
		assert.are.equal(145, XP.KillXP(20, 20))
		assert.are.equal(152, XP.KillXP(20, 21)) -- 145 * 1.05 = 152.25
		assert.are.equal(174, XP.KillXP(20, 24)) -- 145 * 1.20
		assert.are.equal(174, XP.KillXP(20, 30)) -- capped at +4 levels
		assert.are.equal(119, XP.KillXP(20, 18)) -- 145 * (1 - 2/11) = 118.6
		assert.are.equal(66, XP.KillXP(20, 14)) -- 145 * (1 - 6/11) = 65.9
		assert.are.equal(0, XP.KillXP(20, 13)) -- 7 below: trivial (gray)
		assert.are.equal(290, XP.KillXP(20, 20, true)) -- elite doubles
		assert.are.equal(50, XP.KillXP(1, 1))
	end)

	it("reduces quest XP when the character outlevels the quest", function()
		assert.are.equal(450, XP.QuestXP(450, 10, 15)) -- up to quest level + 5: full
		assert.are.equal(360, XP.QuestXP(450, 10, 16)) -- 80 %
		assert.are.equal(270, XP.QuestXP(450, 10, 17)) -- 60 %
		assert.are.equal(180, XP.QuestXP(450, 10, 18)) -- 40 %
		assert.are.equal(90, XP.QuestXP(450, 10, 19)) -- 20 %
		assert.are.equal(45, XP.QuestXP(450, 10, 20)) -- 10 %
		assert.are.equal(45, XP.QuestXP(450, 10, 35))
		assert.are.equal(35, XP.QuestXP(340, 5, 20)) -- 34 rounded to a multiple of 5
		assert.are.equal(0, XP.QuestXP(0, 5, 5))
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
