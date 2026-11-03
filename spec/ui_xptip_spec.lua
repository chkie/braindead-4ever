-- SPDX-License-Identifier: GPL-3.0-or-later
-- Tooltip of the XP line (Welle 5b tasks 10 and 12): planned level at this step against the character's
-- level (owner guideline 7, requirement A16) and the time forecast of Route.Forecast() (owner reading
-- point 13: "collecting data" until enough real runs exist, never an invented number).
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

local function hover(ns)
	local hit = ns.StepFrame.frame.xpHit
	hit.scripts.OnEnter(hit)
	return wow.world.tooltip.lines
end

local READY = {
	state = "ready",
	seconds = 41200,
	level = 30,
	runs = 7,
	plan = { module = "m", delta = 240 },
	nextLevel = { state = "ready", seconds = 1800, perHour = 12000 },
}

describe("XP line tooltip", function()
	it("names the planned level here, the own level and says collecting data without runs", function()
		local ns = S.login()
		local info = ns.Route.Current()
		assert.is_number(info.lv)
		assert.are.equal("collecting", ns.Route.Forecast().state) -- no module times measured yet
		local lines = hover(ns)
		assert.are.equal("Level and time", lines[1])
		assert.are.equal("Planned level at this step: " .. info.lv, lines[2])
		assert.matches("^Your level: 1, ", lines[3])
		assert.are.equal("Time forecast", lines[4])
		assert.are.equal("End of the route: collecting data", lines[5])
		assert.are.equal("Level 2: collecting data", lines[6])
		assert.are.equal(6, #lines)
		assert.are.equal(ns.StepFrame.frame, wow.world.tooltip.owner.parent)
	end)

	it("tells the deviation from the plan in levels", function()
		local ns = S.login()
		local ST = ns.StepText
		local cases = {
			{ 12, 12, "as planned" },
			{ 13, 12, "1 level above the plan" },
			{ 15, 12, "3 levels above the plan" },
			{ 11, 12, "1 level below the plan" },
			{ 8, 12, "4 levels below the plan" },
		}
		for _, c in ipairs(cases) do
			local _, lines = ST.XPTip({ lv = c[2] }, { level = c[1] }, nil)
			assert.are.equal("Your level: " .. c[1] .. ", " .. c[3], lines[2].text)
		end
		local _, none = ST.XPTip({}, { level = 5 }, nil) -- a step without a planned level
		assert.are.same({}, none)
	end)

	it("shows the forecast with numbers once enough runs exist", function()
		local ns = S.login()
		ns.Route.Forecast = function()
			return READY
		end
		local lines = hover(ns)
		assert.are.equal("End of the route at level 30: 11 h 27 min", lines[5])
		assert.are.equal("4 min faster than the median in this section", lines[6])
		assert.are.equal("Level 2: 30 min (12,000 XP per hour)", lines[7])
		READY.plan.delta = -900
		lines = hover(ns)
		assert.are.equal("15 min slower than the median in this section", lines[6])
		READY.plan.delta = 30 -- under a minute: no line
		lines = hover(ns)
		assert.are.equal("Level 2: 30 min (12,000 XP per hour)", lines[6])
	end)

	it("leaves out the next level at the maximum level and the forecast at the end of the route", function()
		local ns = S.login()
		local ST = ns.StepText
		local _, lines = ST.XPTip({ lv = 60 }, { level = 60, stopped = true }, READY)
		for _, l in ipairs(lines) do
			assert.is_nil(l.text:find("^Level 61"))
		end
		_, lines = ST.XPTip({ lv = 60 }, { level = 60 }, { state = "done" })
		assert.are.equal(2, #lines)
	end)

	it("lists the quests skipped earlier (Welle 7): the number, five names, the rest as a number", function()
		local ns = S.login()
		local ST = ns.StepText
		local _, lines = ST.XPTip({ lv = 3 }, { level = 3 }, nil, { 33, 783, 7, 900001, 900002, 900003, 900004 })
		assert.are.equal("7 quests skipped earlier:", lines[3].text)
		assert.is_true(lines[3].gold)
		assert.matches("Wolves Across the Border", lines[4].text)
		assert.matches("A Threat Within", lines[5].text)
		assert.are.equal("and 2 more", lines[9].text)
		assert.are.equal(9, #lines)
		ns.Route.Earlier = function()
			return { 33 }
		end
		local shown = hover(ns)
		assert.are.equal("1 quest skipped earlier:", shown[4])
		assert.matches("Wolves Across the Border", shown[5])
		assert.are.equal("Time forecast", shown[6])
		ns.Route.Earlier = function()
			return {}
		end
		assert.are.equal("Time forecast", hover(ns)[4], "no line without skipped quests")
		local de = S.login({ locale = "deDE" })
		_, lines = de.StepText.XPTip({ lv = 3 }, { level = 3 }, nil, { 33, 783, 7, 1, 2, 3 })
		assert.are.equal("6 Quests früher übersprungen:", lines[3].text)
		assert.are.equal("und 1 weitere", lines[9].text)
	end)

	it("speaks German", function()
		local ns = S.login({ locale = "deDE" })
		local lines = hover(ns)
		assert.are.equal("Stufe und Zeit", lines[1])
		assert.matches("^Geplante Stufe an dieser Stelle: %d+$", lines[2])
		assert.are.equal("Zeitprognose", lines[4])
		assert.are.equal("Ende der Route: sammelt noch Daten", lines[5])
		assert.are.equal("1 Std. 5 Min.", ns.StepText.Duration(3900))
		assert.are.equal("unter 1 Min.", ns.StepText.Duration(20))
	end)

	it("right-click on the XP line opens the menu; the mini view hides the hover area", function()
		local ns = S.login()
		local W = ns.StepFrame.frame
		assert.is_true(rawget(W.xpHit, "shown"))
		W.xpHit.scripts.OnMouseUp(W.xpHit, "RightButton")
		assert.are.equal("Braindead 4ever", wow.menu.items[1].text)
		ns.StepFrame.SetMini(true)
		assert.is_false(rawget(W.xpHit, "shown"))
	end)

	it("developer preview: forecast and collecting", function()
		local ns = S.login({ probe = true })
		SlashCmdList.BRAINDEADFOREVER("preview forecast")
		local lines = wow.world.tooltip.lines
		assert.are.equal("Planned level at this step: 3", lines[2])
		assert.are.equal("Your level: 5, 2 levels above the plan", lines[3])
		assert.are.equal("End of the route at level 30: 11 h 27 min", lines[5])
		SlashCmdList.BRAINDEADFOREVER("preview collecting")
		lines = wow.world.tooltip.lines
		assert.are.equal("End of the route: collecting data", lines[5])
		assert.are.same({}, wow.errors)
		SlashCmdList.BRAINDEADFOREVER("preview off")
		assert.is_nil(ns.Connect.Forecast().seconds)
	end)
end)
