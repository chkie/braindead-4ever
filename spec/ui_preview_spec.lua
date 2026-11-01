-- SPDX-License-Identifier: GPL-3.0-or-later
-- Probe/Preview.lua (developer build only): "/pathmark preview <state>" puts the real windows into each
-- state of design v2 for the screenshots of design stage 2 (docs/TESTING-RETAIL.md). Every state runs
-- without a Lua error and shows what the design shows; "off" goes back to the live route.
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

local function preview(state, opts)
	opts = opts or {}
	opts.probe = true
	local ns = S.login(opts)
	SlashCmdList.PATHMARK("preview " .. state)
	return ns, ns.StepFrame.frame
end

describe("Developer preview", function()
	it("normal: the design's example step with counter, next steps and XP line", function()
		local _, W = preview("normal")
		assert.matches("“Wolves Across the Border”: collect Tough Wolf Meat", W.step.text, 1, true)
		assert.matches("3/8", W.step.text, 1, true)
		assert.matches("· 4/48$", W.title.text)
		assert.matches(
			"Level |cffffffff3|r · |cffffffff620|r XP to go · this step +|cffffffff260|r XP",
			W.xp.text,
			1,
			true
		)
		assert.are.same({}, wow.errors)
	end)

	it("tooltip, done, mini, combat, help, menu, status", function()
		local ns, W = preview("tooltip")
		assert.are.equal("Where the data comes from", wow.world.tooltip.lines[3])
		W.clock.scripts.OnEnter(W.clock)
		assert.matches("ATT, EG Link and Polestar forever%-db", wow.world.tooltip.lines[2])
		SlashCmdList.PATHMARK("preview done")
		assert.are.equal("UI-QuestTracker-Tracker-Check", W.icon.atlas)
		wow.advance(1)
		SlashCmdList.PATHMARK("preview mini")
		assert.are.equal(0, W.detail.alpha)
		SlashCmdList.PATHMARK("preview combat")
		assert.are.equal(0.6, W.alpha)
		SlashCmdList.PATHMARK("preview help")
		assert.are.equal(1, #wow.world.helptips)
		SlashCmdList.PATHMARK("preview menu")
		assert.matches("^Undo: checked off", wow.menu.items[2].text)
		SlashCmdList.PATHMARK("preview status")
		assert.are.equal("New version available", W.status.text)
		assert.is_true(ns.UI.DB().hintsSeen.rightclick) -- the preview does not use up the real hint
		assert.are.same({}, wow.errors)
	end)

	it("reach, skip, abandon, dungeon, rumor", function()
		local _, W = preview("reach")
		assert.are.equal(
			"The route falls short of Westfall. About 640 XP missing, roughly 9 level 9 enemies.",
			W.reach.text
		)
		SlashCmdList.PATHMARK("preview skip")
		assert.matches("^Skip “Wolves Across the Border”%?", wow.popup.text)
		assert.matches("Grape Manifest", wow.popup.text, 1, true)
		SlashCmdList.PATHMARK("preview abandon")
		assert.are.equal(
			"“Kobold Camp Cleanup” was abandoned in the quest log. 3 follow-up quests depend on it.",
			W.banner.text
		)
		assert.are.equal("UI-QuestTracker-Objective-Fail", W.icon.atlas)
		SlashCmdList.PATHMARK("preview dungeon")
		assert.are.equal("Optional · Dungeon · Level 18–24", W.next[2].tag.text)
		assert.are.equal(
			"The Deadmines: accept “The Defias Brotherhood” and “Red Silk Bandanas”",
			W.next[2].text.text
		)
		local ns = S.login({ probe = true, style = "hints" })
		SlashCmdList.PATHMARK("preview rumor")
		assert.are.equal("Rumor: Someone found something in the Riverglades.", ns.StepFrame.frame.banner.text)
		SlashCmdList.PATHMARK("preview off")
		assert.is_false(rawget(ns.StepFrame.frame.banner, "shown"))
		assert.matches("Wolves Across the Border", ns.StepFrame.frame.step.text, 1, true)
		assert.are.same({}, wow.errors)
	end)

	it("arrow colors, arrival and colorblind mode at a chosen angle", function()
		local ns = preview("arrow 90")
		local F = ns.Arrow.frame
		ns.Arrow.Update(0.25)
		assert.are.same({ 1, 1, 0 }, { F.tex.vertex[1], F.tex.vertex[2], F.tex.vertex[3] })
		SlashCmdList.PATHMARK("preview arrow 160")
		ns.Arrow.Update(0.25)
		assert.are.equal("behind you", F.hint.text)
		SlashCmdList.PATHMARK("preview colorblind 170")
		ns.Arrow.Update(0.25)
		assert.are.same({ 1, 0.5, 0 }, { F.tex.vertex[1], F.tex.vertex[2], F.tex.vertex[3] })
		SlashCmdList.PATHMARK("preview arrival")
		ns.Arrow.Update(0.25)
		assert.are.equal("Reached destination", F.dist.text)
		assert.are.same({}, wow.errors)
	end)

	it("setup and settings windows; unknown states list the choices", function()
		local ns = preview("setup")
		assert.is_true(rawget(_G.PathmarkSetupFrame, "shown"))
		SlashCmdList.PATHMARK("preview settings")
		assert.are.same({ ns.settingsCategoryID }, wow.world.settings.opened)
		SlashCmdList.PATHMARK("preview nonsense")
		assert.matches("normal | tooltip | done", wow.output(), 1, true)
	end)
end)
