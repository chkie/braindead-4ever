-- SPDX-License-Identifier: GPL-3.0-or-later
-- Probe/Preview.lua (developer build only): "/bd4 preview <state>" puts the real windows into each
-- state of design v2 for the screenshots of design stage 2 (docs/TESTING-RETAIL.md). Every state runs
-- without a Lua error and shows what the design shows; "off" goes back to the live route.
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

local function preview(state, opts)
	opts = opts or {}
	opts.probe = true
	local ns = S.login(opts)
	SlashCmdList.BRAINDEADFOREVER("preview " .. state)
	return ns, ns.StepFrame.frame
end

describe("Developer preview", function()
	it("normal: the design's example step with counter, next steps and XP line", function()
		local _, W = preview("normal")
		assert.matches("“Wolves Across the Border”: collect Tough Wolf Meat", W.step.text, 1, true)
		assert.matches("3/8", W.step.text, 1, true)
		assert.matches("• 4/48$", W.title.text)
		assert.matches(
			"Level |cffffffff3|r • |cffffffff620|r XP to go • this step +|cffffffff260|r XP",
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
		assert.matches("Source: open game data%.$", wow.world.tooltip.lines[2])
		SlashCmdList.BRAINDEADFOREVER("preview done")
		assert.are.equal("UI-QuestTracker-Tracker-Check", W.icon.atlas)
		wow.advance(1)
		SlashCmdList.BRAINDEADFOREVER("preview mini")
		assert.are.equal(0, W.detail.alpha)
		SlashCmdList.BRAINDEADFOREVER("preview combat")
		assert.are.equal(0.6, W.alpha)
		-- Welle 5d, M5: after the mini state the button shows "−" again
		assert.are.equal("UI-QuestTrackerButton-Collapse-All", W.toggle.tex.atlas)
		SlashCmdList.BRAINDEADFOREVER("preview help")
		assert.are.equal(1, #wow.world.helptips)
		SlashCmdList.BRAINDEADFOREVER("preview menu")
		assert.matches("^Undo: checked off", wow.menu.items[2].text)
		SlashCmdList.BRAINDEADFOREVER("preview status")
		assert.are.equal("New version 0.9.1 available", W.status.text)
		assert.is_true(ns.UI.DB().hintsSeen.rightclick) -- the preview does not use up the real hint
		assert.are.same({}, wow.errors)
	end)

	it("reach, skip, abandon, dungeon, rumor", function()
		local ns, W = preview("reach")
		assert.are.equal(
			"The route falls short of Westfall. About 640 XP missing, roughly 9 level 9 enemies.",
			W.reach.text
		)
		SlashCmdList.BRAINDEADFOREVER("preview skip")
		assert.matches("^Skip “Wolves Across the Border”%?", wow.popup.text)
		assert.matches("Grape Manifest", wow.popup.text, 1, true)
		SlashCmdList.BRAINDEADFOREVER("preview abandon")
		assert.are.equal(
			"“Kobold Camp Cleanup” was abandoned in the quest log. 3 follow-up quests depend on it.",
			W.banner.text
		)
		assert.are.equal("UI-QuestTracker-Objective-Fail", W.icon.atlas)
		-- Welle 5d, M9: the note and the marked step name the same quest; the symbol stands at the step
		assert.matches("^“Kobold Camp Cleanup”: kill Kobold Vermin", W.step.text)
		assert.are.equal("step", ns.StepFrame.View().failAt)
		assert.are.same({ "CENTER", W.box }, { W.icon.points[1][1], W.icon.points[1][2] })
		SlashCmdList.BRAINDEADFOREVER("preview dungeon")
		assert.are.equal("Optional • Dungeon • Level 18–24", W.next[2].tag.text)
		assert.are.equal(
			"The Deadmines: accept “The Defias Brotherhood” and “Red Silk Bandanas”",
			W.next[2].text.text
		)
		ns = S.login({ probe = true, style = "hints" })
		SlashCmdList.BRAINDEADFOREVER("preview rumor")
		assert.are.equal("Rumor: Someone found something in the Riverglades.", ns.StepFrame.frame.banner.text)
		SlashCmdList.BRAINDEADFOREVER("preview off")
		assert.is_false(rawget(ns.StepFrame.frame.banner, "shown"))
		assert.matches("A Threat Within", ns.StepFrame.frame.step.text, 1, true) -- the live route's first step
		assert.are.same({}, wow.errors)
	end)

	it("arrow colors, arrival and colorblind mode at a chosen angle", function()
		local ns = preview("arrow 90")
		local F = ns.Arrow.frame
		ns.Arrow.Update(0.25)
		assert.are.same({ 1, 1, 0 }, { F.tex.vertex[1], F.tex.vertex[2], F.tex.vertex[3] })
		SlashCmdList.BRAINDEADFOREVER("preview arrow 160")
		ns.Arrow.Update(0.25)
		assert.are.equal("behind you", F.hint.text)
		SlashCmdList.BRAINDEADFOREVER("preview colorblind 170")
		ns.Arrow.Update(0.25)
		assert.are.same({ 1, 0.5, 0 }, { F.tex.vertex[1], F.tex.vertex[2], F.tex.vertex[3] })
		SlashCmdList.BRAINDEADFOREVER("preview arrival")
		ns.Arrow.Update(0.25)
		assert.are.equal("Reached destination", F.dist.text)
		assert.are.same({}, wow.errors)
	end)

	it("narrow and wide: smallest width and ten steps with the rest scrolling, off restores the size", function()
		local ns, W = preview("narrow", { locale = "deDE" })
		assert.are.equal(260, W.w)
		assert.are.equal(3, #ns.StepFrame.VisibleRows())
		SlashCmdList.BRAINDEADFOREVER("preview wide")
		assert.are.equal(500, W.w)
		assert.are.equal(10, #ns.StepFrame.VisibleRows())
		assert.is_true(W.listBox.scrollable)
		SlashCmdList.BRAINDEADFOREVER("preview off")
		assert.are.same({ 300, 3 }, { ns.UI.Get("width"), ns.UI.Get("ahead") })
		assert.are.same({}, wow.errors)
	end)

	it("over the plan, switch point and quests skipped earlier (Welle 7)", function()
		local ns, W = preview("over")
		assert.are.equal("You are 3 levels above the plan. Adjust the route?", W.banner.text)
		assert.are.equal("Adjust", W.btnYes.text)
		W.btnYes:Click()
		assert.are.equal("2 quests left out: their turn-in would give less than 80 % XP.", W.status.text)
		assert.is_false(rawget(W.btnYes, "shown"))
		SlashCmdList.BRAINDEADFOREVER("preview switch")
		assert.are.equal(
			"Westfall fits your level better (planned from level 9). Go there next? About 25 min faster.",
			W.banner.text
		)
		assert.are.equal("Go there", W.btnYes.text)
		SlashCmdList.BRAINDEADFOREVER("preview earlier")
		local lines = wow.world.tooltip.lines
		local at
		for i, line in ipairs(lines) do
			if line == "7 quests skipped earlier:" then
				at = i
			end
		end
		assert.is_not_nil(at, "the list of quests skipped earlier")
		assert.are.equal("“Kobold Camp Cleanup”", lines[at + 1])
		assert.are.equal("and 2 more", lines[at + 6])
		assert.are.same({}, wow.errors)
		SlashCmdList.BRAINDEADFOREVER("preview off")
		assert.are.same({}, ns.Connect.Earlier())
	end)

	-- Welle 5d, S8: the preview's area had radii in map units and came out as an oval of 1.5:1.
	-- M4 and M8 (0.9.1): the NPC name in the step text and the quest item button, for the screenshots.
	it("npc and questitem: NPC names in the steps and the quest item button, cleared by the next state", function()
		local ns, W = preview("npc")
		assert.are.equal("Accept “Wolves Across the Border” from Eagan Peltskinner", W.step.text)
		assert.matches("Turn in “Kobold Camp Cleanup” to Marshal McBride", W.next[1].text.text, 1, true)
		SlashCmdList.BRAINDEADFOREVER("preview questitem")
		local B = _G.BraindeadForeverQuestItemButton
		assert.is_true(rawget(B, "shown"))
		assert.is_nil(B:GetAttribute("item")) -- a click in the preview uses nothing
		assert.are.equal("Interface\\Icons\\INV_Misc_QuestionMark", B.icon.file)
		assert.are.equal(3, B.count.text)
		assert.is_true(rawget(B.hotkey, "shown"))
		assert.is_nil(W.step.text:find("Eagan", 1, true)) -- the names of the state before are gone
		SlashCmdList.BRAINDEADFOREVER("preview off")
		assert.is_false(rawget(B, "shown"))
		assert.is_nil(ns.NpcNames.Giver(9000001))
		assert.are.same({}, wow.errors)
		-- German client: the German word order
		local _, WD = preview("npc", { locale = "deDE" })
		assert.are.equal("„Wölfe an der Grenze“ bei Eagan Peltskinner annehmen", WD.step.text)
	end)

	-- A35: the hint steps of the routes (trainer, inn, flight point, flight) for the screenshots. Each demo
	-- step carries an element the route data really has, so its words come from the step text code.
	it("hints: trainer, inn, flight point and flight steps with the route's elements and words", function()
		local ns, W = preview("hints")
		local V = ns.Routes.VERB
		-- the compiled data of both factions as text (the session releases the other faction's builder)
		local data = ""
		for _, faction in ipairs({ "Alliance", "Horde" }) do
			local f = assert(io.open("Braindead4Ever/Routes/Data_" .. faction .. ".lua"))
			data = data .. f:read("*a")
			f:close()
		end
		local function has(el) -- the element as the data writes it; a flight may lead to any map
			local parts = {}
			for i, v in ipairs(el) do
				parts[i] = (el[1] == V.TRAVEL and i == 3) and "%d+" or tostring(v)
			end
			return data:find("{ " .. table.concat(parts, ", ") .. " }") ~= nil
		end
		local steps = { ns.Connect.Current() }
		for _, s in ipairs(ns.Connect.Upcoming(3)) do
			steps[#steps + 1] = s
		end
		local verbs = {}
		for i, s in ipairs(steps) do
			verbs[i] = s.step[1][1]
			assert.is_true(has(s.step[1]), "element of step " .. i .. " is not in the route data")
		end
		assert.are.same({ V.TRAIN, V.SETHOME, V.FP, V.TRAVEL }, verbs)
		assert.are.equal(2, steps[4].step[1][2]) -- travel how 2: fly
		assert.are.equal("Learn new skills at your trainer", W.step.text)
		assert.are.equal("Set your hearthstone at the inn", W.next[1].text.text)
		assert.are.equal("Get the flight path", W.next[2].text.text)
		assert.are.equal("Fly to Westfall", W.next[3].text.text)
		-- world map: the tracking symbols of the three services, no service symbol for the flight
		local kinds = {}
		for _, p in ipairs(ns.MapPins.Collect()) do
			kinds[#kinds + 1] = p.kind
		end
		assert.are.same({ "pin", "trainer", "innkeeper", "flightmaster" }, kinds)
		assert.are.same({}, wow.errors)
		local _, WD = preview("hints", { locale = "deDE" })
		assert.are.equal("Beim Lehrer neue Fähigkeiten lernen", WD.step.text)
		assert.are.equal("Ruhestein im Gasthaus setzen", WD.next[1].text.text)
		assert.are.equal("Flugpunkt holen", WD.next[2].text.text)
		assert.are.equal("Nach Westfall fliegen", WD.next[3].text.text)
		assert.are.same({}, wow.errors)
	end)

	it("area: a round circle, sized from the map's world size (S8)", function()
		local ns = preview("area", { style = "hints" })
		ns.MapPins.Refresh()
		local pin
		for _, p in ipairs(_G.WorldMapFrame.pins) do
			if p.kind == "area" then
				pin = p
			end
		end
		assert.is_table(pin, "no area pin")
		assert.is_true(math.abs(pin.w / pin.h - 1) < 0.02, ("circle %.1f x %.1f"):format(pin.w, pin.h))
	end)

	-- Welle 5d, K2 and task 19: every state starts from a clean window.
	it("clears the state before: hint, dialog, rumor, demo arrow, size, mini (K2)", function()
		local ns, W = preview("help", { style = "hints" })
		assert.is_true(_G.HelpTip:IsShowing(W))
		SlashCmdList.BRAINDEADFOREVER("preview normal")
		assert.is_false(_G.HelpTip:IsShowing(W))
		assert.is_true(ns.UI.DB().hintsSeen.rightclick) -- the real hint stays as it was
		SlashCmdList.BRAINDEADFOREVER("preview skip")
		assert.is_table(wow.popup)
		SlashCmdList.BRAINDEADFOREVER("preview abandon")
		assert.is_nil(wow.popup)
		SlashCmdList.BRAINDEADFOREVER("preview rumor")
		assert.is_true(rawget(W.banner, "shown"))
		SlashCmdList.BRAINDEADFOREVER("preview normal")
		assert.is_false(rawget(W.banner, "shown"))
		SlashCmdList.BRAINDEADFOREVER("preview arrow 90")
		assert.is_table(ns.Arrow.extra)
		SlashCmdList.BRAINDEADFOREVER("preview normal")
		assert.is_nil(ns.Arrow.extra)
		SlashCmdList.BRAINDEADFOREVER("preview wide")
		assert.are.equal(500, W.w)
		SlashCmdList.BRAINDEADFOREVER("preview normal")
		assert.are.same({ 300, 3 }, { ns.UI.Get("width"), ns.UI.Get("ahead") })
		SlashCmdList.BRAINDEADFOREVER("preview setup")
		assert.is_true(rawget(_G.BraindeadForeverSetupFrame, "shown"))
		SlashCmdList.BRAINDEADFOREVER("preview normal")
		assert.is_false(rawget(_G.BraindeadForeverSetupFrame, "shown"))
		SlashCmdList.BRAINDEADFOREVER("preview mini")
		SlashCmdList.BRAINDEADFOREVER("preview normal")
		assert.are.equal("UI-QuestTrackerButton-Collapse-All", W.toggle.tex.atlas)
		assert.are.equal(1, W.alpha)
		assert.are.same({}, wow.errors)
	end)

	it("dungeon: the player's level fits the dungeon's band (K2)", function()
		local _, W = preview("dungeon")
		assert.are.equal("Optional • Dungeon • Level 18–24", W.next[2].tag.text)
		assert.matches("^Level |cffffffff18|r", W.xp.text)
	end)

	it("arrival holds the check ten seconds for the picture, then fades (task 19)", function()
		local ns = preview("arrival")
		local F = ns.Arrow.frame
		ns.Arrow.Update(0.25)
		assert.are.equal("UI-QuestTracker-Tracker-Check", F.tex.atlas)
		assert.are.equal("Reached destination", F.dist.text)
		wow.advance(5)
		ns.StepFrame.Refresh()
		ns.Arrow.Update(0.25)
		assert.are.equal("UI-QuestTracker-Tracker-Check", F.tex.atlas)
		assert.are_not.equal(0, rawget(F.tex, "alpha"))
		wow.advance(6)
		ns.Arrow.Update(0.25)
		assert.are.equal(0, rawget(F.tex, "alpha"))
	end)

	it("riddle: the line of hint level 1 with a riddle for the player's zone (task 19)", function()
		local _, W = preview("riddle", { style = "hints" })
		assert.is_true(rawget(W.riddle, "shown"))
		assert.matches("^Hint: ", W.riddle.text)
	end)

	it("setup and settings windows; unknown states list the choices", function()
		local ns = preview("setup")
		assert.is_true(rawget(_G.BraindeadForeverSetupFrame, "shown"))
		-- Welle 5d, S6: the first start's footer, with what closing picks
		assert.matches("Closing picks “With hints”%.$", _G.BraindeadForeverSetupFrame.foot.text)
		_G.BraindeadForeverSetupFrame:Hide()
		assert.are.equal("arrow", ns.UI.Get("style")) -- closing the preview changes nothing
		SlashCmdList.BRAINDEADFOREVER("preview settings")
		assert.are.same({ ns.settingsCategoryID }, wow.world.settings.opened)
		-- the automation switch (A74): main page, scrolled to its label
		SlashCmdList.BRAINDEADFOREVER("preview auto")
		assert.are.same({ ns.settingsCategoryID, ns.settingsCategoryID }, wow.world.settings.opened)
		assert.are.equal("Automate route quests", wow.world.settings.scrolledTo)
		SlashCmdList.BRAINDEADFOREVER("preview nonsense")
		assert.matches("normal | tooltip | done", wow.output(), 1, true)
	end)

	it("your run: page with and without comparison data, review card at 10 and 30 (Welle 8)", function()
		local ns = preview("stats")
		local SP = ns.StatsPage
		local P = _G.BraindeadForeverStatsFrame
		assert.is_true(rawget(P, "shown"))
		assert.are.equal("Level 12 • Mensch • Krieger", P.head.text)
		assert.matches("running$", SP.rendered[1].cells[2]) -- level 12, on top
		assert.matches("%d+ min$", SP.rendered[2].cells[3]) -- median of the class
		assert.matches("%d+ %%$", SP.rendered[2].cells[4])
		assert.are.equal("9,850", P.sum[3].value.text)
		SlashCmdList.BRAINDEADFOREVER("preview stats0")
		assert.are.equal("collecting", SP.rendered[2].cells[3])
		assert.are.equal("collecting data", P.sum[3].value.text)
		SlashCmdList.BRAINDEADFOREVER("preview recap10")
		assert.is_false(rawget(P, "shown")) -- the state before is gone
		local R = _G.BraindeadForeverRecapFrame
		assert.is_true(rawget(R, "shown"))
		assert.are.equal("Level 10 reached", R.head.text)
		assert.matches("%(57 runs%)$", R.facts[1].value.text)
		assert.matches("new, this character$", R.facts[3].value.text)
		SlashCmdList.BRAINDEADFOREVER("preview recap30")
		assert.are.equal("Level 30 reached", R.head.text)
		assert.are.equal("collecting data (6 of 10 runs)", R.facts[1].value.text)
		assert.is_nil(ns.RunStats.Char().recap[10]) -- the preview does not use up the real card
		SlashCmdList.BRAINDEADFOREVER("preview off")
		assert.is_false(rawget(R, "shown"))
		assert.are.same({}, wow.errors)
	end)
end)
