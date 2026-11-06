-- SPDX-License-Identifier: GPL-3.0-or-later
-- Design v2, view 1 "Schrittanzeige": every state of the approved design has a test here (normal,
-- origin tooltip, done, mini, combat, usage hint, right-click menu, status line, route falls short,
-- skip with follow-ups, quest abandoned, optional dungeon step, rumor line), plus check box and XP line.
-- Real route data (human warrior, Elwynn Forest), UI stand-ins from spec/helpers/ui.lua.
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

local function frame(ns)
	return ns.StepFrame.frame
end

local function shown(region)
	return rawget(region, "shown") == true
end

-- Next steps in the visible part of the scroll list.
local function nextRows(ns)
	return ns.StepFrame.VisibleRows()
end

-- First step key (from the current one on) whose skip takes follow-up quests with it.
-- First step with follow-up quests; postpone = true: one whose skip postpones a class chain (KQ-1105),
-- else one whose skip leaves the quests out.
local function chainStep(ns, postpone)
	local list = { ns.Route.Current() }
	for _, n in ipairs(ns.Route.Upcoming(80)) do
		list[#list + 1] = n
	end
	for _, info in ipairs(list) do
		local follow = ns.Route.SkipPreview(info.key)
		if follow and #follow > 0 and ns.Route.SkipPostpones(info.key) == (postpone == true) then
			return info, follow
		end
	end
end

describe("Step window", function()
	describe("normal state", function()
		local ns = S.login({ before = S.away }) -- the first goal 70 yd away (spec/helpers/uisession.lua)
		local W = frame(ns)

		it("shows the current step, the next three dimmed, and the XP line", function()
			assert.is_true(shown(W))
			local cur = ns.Route.Current()
			assert.are.equal("a-speed-start-elwynn/a783", cur.key)
			assert.matches("^Elwynn Forest • 1/%d+$", W.title.text)
			assert.matches("^Accept “A Threat Within”", W.step.text)
			-- the target lies in the zone the header names: only the distance (Welle 5d, Q3)
			assert.are.equal("70 |4yd:yds away", W.detail.text)
			local rows = nextRows(ns)
			assert.are.equal(3, #rows)
			for _, row in ipairs(rows) do
				assert.are.equal(0.7, row.text.alpha) -- Welle 5d, M1: 5.2:1 on white ground behind 70 %
				assert.are.equal(2, row.text.maxLines) -- at most two lines (release gate T19)
			end
			assert.matches("Level |cffffffff1|r • |cffffffff400|r XP to go", W.xp.text, 1, true)
			assert.is_false(shown(W.status))
		end)

		it("uses one background and a header band on exactly the window width", function()
			assert.are.same({ 0, 0, 0, 0.7 }, W.bg.colorTexture)
			assert.are.equal(300, W.w)
			assert.are.equal("UI-QuestTracker-Primary-Objective-Header", W.header.atlas)
			-- Welle 5d, Q1: the atlas draws from 3.0 % to 94.1 % of its width; stretched past the window by
			-- those parts, its drawn band starts and ends exactly at the window edges
			local l, r = W.header.points[1], W.header.points[2]
			assert.are.same({ "TOPLEFT", W, "TOPLEFT" }, { l[1], l[2], l[3] })
			assert.are.same({ "TOPRIGHT", W, "TOPRIGHT" }, { r[1], r[2], r[3] })
			local band = 300 - l[4] + r[4]
			local trim = ns.StepFrame.HEADER_TRIM
			assert.is_true(math.abs(l[4] + band * trim[1]) < 1e-6, "left edge of the drawn band")
			assert.is_true(math.abs(l[4] + band * (1 - trim[2]) - 300) < 1e-6, "right edge of the drawn band")
			assert.is_true(l[4] < -5 and r[4] > 10)
			assert.are.equal("TOPRIGHT", W.points[1][1])
			-- the place of Blizzard's quest tracker, hidden by default (spec/ui_place_spec.lua)
			assert.are.same({ -115, -266 }, { W.points[1][4], W.points[1][5] })
		end)

		it("writes in copies of Blizzard's tracker fonts at 15, 13 and 12", function()
			assert.are.equal(_G.BraindeadForeverFontStep, W.step.font)
			assert.are.equal(_G.ObjectiveTrackerFont15, _G.BraindeadForeverFontStep.copyOf)
			assert.are.equal(15, _G.BraindeadForeverFontStep.size)
			assert.are.equal(13, _G.BraindeadForeverFontLine.size)
			assert.are.equal(12, _G.BraindeadForeverFontSmall.size)
			assert.are.equal(_G.ObjectiveTrackerHeaderFont, _G.BraindeadForeverFontHeader.copyOf)
			assert.are.same({ 1, 0.82, 0 }, W.title.textColor)
			assert.are.same({ 1, 1, 1 }, W.step.textColor)
			assert.are.same({ 0.8, 0.8, 0.8 }, W.detail.textColor)
		end)

		it("has the check box in place of the nub and the provisional clock in the header", function()
			assert.are.equal("checkbox-minimal", W.box.tex.atlas)
			assert.is_true(shown(W.box))
			assert.are.same({ 19, 19 }, { W.box.w, W.box.h })
			assert.are.equal("auctionhouse-icon-clock", W.clock.tex.atlas)
			assert.is_true(shown(W.clock))
			assert.are.equal("UI-QuestTrackerButton-Collapse-All", W.toggle.tex.atlas)
		end)

		it("counts the objective in gold behind the goal", function()
			local cur = ns.Route.Current()
			local q = cur.quests[1]
			wow.world.questLog[#wow.world.questLog + 1] = {
				questID = q,
				objectives = { { text = "Diseased Young Wolf slain: 3/8", numFulfilled = 3, numRequired = 8 } },
			}
			local text = ns.StepText.Step({ step = { { 2, q, 1, 0 } } }, true)
			assert.are.equal("“A Threat Within”: Diseased Young Wolf slain", text)
			wow.world.questLog = {}
		end)
	end)

	it("tooltip names the origin of every value, the clock explains provisional", function()
		local ns = S.login()
		local W = frame(ns)
		W.cur.scripts.OnEnter(W.cur)
		local lines = wow.world.tooltip.lines
		assert.are.equal("“A Threat Within”", lines[1])
		assert.matches("^Step 1 of %d+$", lines[2])
		assert.are.equal("Where the data comes from", lines[3])
		-- no other addon by name (owner 04.11.2026): the game data projects show as "open game data"
		assert.are.equal("Quest giver: open game data, unconfirmed", lines[4])
		assert.are.equal("Location: open game data, unconfirmed", lines[5])
		W.clock.scripts.OnEnter(W.clock)
		lines = wow.world.tooltip.lines
		assert.are.equal("Provisional", lines[1])
		-- the module's hint steps (train, sethome, hs) come from the route plan (src=plan)
		assert.matches(
			"^Too few own runs for this section so far %(0%)%. Source: open game data and route plan%.$",
			lines[2]
		)
	end)

	describe("done", function()
		it("turns the box into the check, glows, plays one sound, then the next step moves up", function()
			local ns = S.login()
			local W = frame(ns)
			local first = ns.Route.Current().key
			W.box:Click()
			assert.are.equal("UI-QuestTracker-Tracker-Check", W.icon.atlas)
			assert.is_true(shown(W.icon))
			assert.is_false(shown(W.box))
			assert.are.same({ 0.6, 0.6, 0.6 }, W.step.textColor)
			assert.matches("A Threat Within", W.step.text, 1, true)
			assert.are.equal(1, W.glowAnim.played)
			assert.are.same({ 878 }, wow.world.sounds)
			-- glow inside the window edges
			assert.are.same({ "LEFT", "TOPLEFT", 0 }, { W.glow.points[1][1], W.glow.points[1][3], W.glow.points[1][4] })
			assert.are.same(
				{ "RIGHT", "TOPRIGHT", 0 },
				{ W.glow.points[2][1], W.glow.points[2][3], W.glow.points[2][4] }
			)
			wow.advance(0.9)
			assert.are_not.equal(first, ns.Route.Current().key)
			assert.is_true(shown(W.box))
			assert.matches("Kobold Camp Cleanup", W.step.text, 1, true) -- t783 hands in 783 and accepts 7
		end)

		it("comes from the game as well: an accepted quest checks the step", function()
			local ns = S.login()
			local W = frame(ns)
			wow.world.questLog[#wow.world.questLog + 1] = { questID = 783, objectives = {} }
			wow.fire("QUEST_ACCEPTED", 783)
			wow.advance(0.15)
			assert.are.equal("UI-QuestTracker-Tracker-Check", W.icon.atlas)
			wow.advance(1)
			assert.matches("Kobold Camp Cleanup", W.step.text, 1, true)
		end)

		it("adds “(done)” in Blizzard's colorblind mode and stays silent with the sound option off", function()
			local ns = S.login({
				before = function(W)
					W.cvars.colorblindMode = "1"
				end,
			})
			ns.UI.Set("sound", false)
			frame(ns).box:Click()
			assert.matches("%(done%)", frame(ns).step.text)
			assert.are.same({}, wow.world.sounds)
		end)
	end)

	it("mini view shows only the current step and switches the collapse atlas", function()
		local ns = S.login()
		local W = frame(ns)
		W.toggle:Click()
		assert.is_true(ns.UI.DB().mini)
		assert.are.equal("UI-QuestTrackerButton-Expand-All", W.toggle.tex.atlas)
		assert.are.equal(0, W.detail.alpha)
		assert.are.equal(0, W.xp.alpha)
		for _, row in ipairs(W.next) do
			assert.are.equal(0, row.text.alpha)
		end
		assert.is_nil(rawget(W.step, "alpha"))
		W.toggle:Click()
		assert.is_nil(ns.UI.DB().mini)
		assert.are.equal(1, W.detail.alpha)
	end)

	describe("in combat", function()
		it("dims to 60 %, checks without glow and sound", function()
			local ns = S.login()
			local W = frame(ns)
			S.combat(true)
			assert.are.equal(0.6, W.alpha)
			W.box:Click()
			assert.are.equal(0, W.glowAnim.played)
			assert.are.same({}, wow.world.sounds)
			assert.matches("Kobold Camp Cleanup", W.step.text, 1, true)
			S.combat(false)
			assert.are.equal(1, W.alpha)
		end)

		it("stays bright with “dim in combat” off", function()
			local ns = S.login()
			ns.UI.Set("dim", false)
			S.combat(true)
			assert.are.equal(1, frame(ns).alpha)
		end)
	end)

	describe("usage hint", function()
		it("comes once per account as a HelpTip with “Got It”, never in combat", function()
			local ns = S.login({ hint = false, combat = true })
			ns.StepFrame.ShowHintOnce()
			assert.are.same({}, wow.world.helptips)
			S.combat(false)
			assert.are.equal(1, #wow.world.helptips)
			local info = wow.world.helptips[1].info
			assert.are.equal("Right-click the window for skip, arrow, mini view and settings.", info.text)
			assert.are.equal(4, info.buttonStyle) -- HelpTip.ButtonStyle.GotIt
			info.onAcknowledgeCallback()
			ns.StepFrame.ShowHintOnce()
			assert.are.equal(1, #wow.world.helptips)
		end)

		-- Welle 5d, M13: the hint lay over Blizzard's settings (slider "Size") and on the first start.
		it("waits while settings or the first start are open and comes back after (M13)", function()
			local ns = S.login({ hint = false })
			local W = frame(ns)
			ns.StepFrame.ShowHintOnce()
			assert.is_true(_G.HelpTip:IsShowing(W))
			ns.Menu.OpenSettings()
			assert.is_true(rawget(_G.SettingsPanel, "shown"))
			assert.is_false(_G.HelpTip:IsShowing(W))
			assert.is_nil(ns.UI.DB().hintsSeen.rightclick) -- hidden, not seen
			_G.SettingsPanel:Hide()
			assert.is_true(_G.HelpTip:IsShowing(W))
			SlashCmdList.BRAINDEADFOREVER("setup")
			assert.is_false(_G.HelpTip:IsShowing(W))
			_G.BraindeadForeverSetupFrame:Hide()
			assert.is_true(_G.HelpTip:IsShowing(W))
			-- only "Got It" uses it up
			local tip = wow.world.helptips[#wow.world.helptips]
			assert.is_nil(tip.info.acknowledgeOnHide)
			tip.info.onAcknowledgeCallback()
			assert.is_true(ns.UI.DB().hintsSeen.rightclick)
		end)

		it("goes once into the status line when HelpTip is off (gamepad, help tips hidden)", function()
			local ns = S.login({ hint = false })
			wow.world.helptipResult = false
			ns.StepFrame.ShowHintOnce()
			assert.are.equal("Right-click the window for skip, arrow, mini view and settings.", frame(ns).status.text)
			assert.is_true(ns.UI.DB().hintsSeen.rightclick)
		end)
	end)

	describe("right-click menu", function()
		it("lists the work steps with undo on top, disabled without an action", function()
			local ns = S.login()
			local menu = S.menu(ns)
			local texts = {}
			for i, item in ipairs(menu.items) do
				texts[i] = item.text or item.kind
			end
			assert.are.same({
				"Braindead 4ever",
				"Undo",
				"Skip step",
				"Previous step",
				"Show arrow",
				"Mini view",
				"divider",
				"Report a problem",
				"Share data",
				"Your run",
				"Settings",
				"Pause guidance",
			}, texts)
			assert.is_false(menu.items[2].enabled)
		end)

		it("names the last action and takes it back", function()
			local ns = S.login()
			local first = ns.Route.Current().key
			frame(ns).box:Click()
			wow.advance(1)
			local menu = S.menu(ns)
			local undo = menu.items[2]
			assert.are.equal("Undo: checked off “A Threat Within”", undo.text)
			assert.is_true(undo.enabled)
			undo.fn()
			assert.are.equal(first, ns.Route.Current().key)
		end)

		it("switches arrow, mini view and the guidance from the menu", function()
			local ns = S.login()
			local menu = S.menu(ns)
			assert.is_true(S.item(menu, "Show arrow").get())
			S.item(menu, "Show arrow").set()
			assert.is_false(ns.UI.Get("arrow"))
			S.item(menu, "Mini view").set()
			assert.is_true(ns.UI.DB().mini)
			S.item(menu, "Pause guidance").fn()
			assert.is_true(ns.UI.Paused())
			assert.is_false(shown(frame(ns)))
			assert.is_truthy(S.item(S.menu(ns), "Resume guidance"))
		end)

		it("reports a problem and opens the settings out of combat", function()
			local ns = S.login()
			S.item(S.menu(ns), "Report a problem").fn()
			assert.is_true(_G.BraindeadForeverCopyFrame.shown)
			S.item(S.menu(ns), "Settings").fn()
			assert.are.same({ ns.settingsCategoryID }, wow.world.settings.opened)
		end)
	end)

	describe("status line", function()
		it("names safe mode", function()
			local ns = S.login({ saved = { safeMode = true } })
			assert.are.equal("Safe mode: only the core is running", frame(ns).status.text)
		end)

		it("names a newer version", function()
			local ns = S.login()
			ns.newerVersion = "1.1.0"
			ns.StepFrame.Refresh()
			assert.are.equal("New version 1.1.0 available", frame(ns).status.text)
		end)

		it("names a module that turned off", function()
			local ns = S.login()
			ns.Modules.state.mappins = "disabled"
			ns.StepFrame.Refresh()
			assert.are.equal("Module mappins turned off, see /bd4 status", frame(ns).status.text)
		end)

		it("says when there is no route for the race and class", function()
			local ns = S.login({
				before = function(W)
					W.player.race = { "-", "-", 99 }
				end,
			})
			assert.are.equal("No route for this race and class yet", frame(ns).status.text)
			assert.is_false(shown(frame(ns).step))
		end)

		it("says when the route is finished", function()
			local ns = S.login()
			local rt = ns.Route.Runtime()
			rt.saved.anchor = "_end"
			rt:Evaluate()
			assert.are.equal(
				"End of the route reached. Routes from level 30 on follow with updates.",
				frame(ns).status.text
			)
		end)
	end)

	it("route falls short: names the gap and about how many enemies fill it", function()
		local ns = S.login()
		ns.Route.Balance = function()
			return {
				level = 8,
				toLevel = 1600,
				step = { xp = 480, source = "log" },
				zone = { nextMap = 1436, shortfall = 640, enough = false, kills = 9, stepsLeft = 3 },
			}
		end
		ns.StepFrame.Invalidate()
		ns.StepFrame.Refresh()
		local W = frame(ns)
		assert.are.equal(
			"The route falls short of Westfall. About 640 XP missing, roughly 9 level 8 enemies.",
			W.reach.text
		)
		assert.matches("this step +|cffffffff480|r XP", W.xp.text, 1, true)
		assert.are.same({ 1, 0.82, 0 }, W.reach.textColor)
	end)

	-- Owner 2026-11-05 (first game test, wrong prerequisite in the open data): the giver of the current
	-- accept lists its quests without it; the route goes on and comes back once it is offered.
	it("sets aside an accept its giver does not offer and takes it back when offered", function()
		local ns = S.login()
		local W = wow.world
		assert.are.equal("a783", ns.Route.Current().id)
		W.npc = { guid = "Creature-0-1-0-0-823-0000000000", name = "Deputy Willem" }
		W.offers = { 7 }
		wow.fire("GOSSIP_SHOW")
		wow.advance(1)
		assert.are_not.equal("a783", ns.Route.Current().id)
		assert.matches("is not offered here yet", frame(ns).status.text, 1, true)
		W.offers = { 783, 7 }
		wow.fire("GOSSIP_SHOW")
		wow.advance(1)
		assert.are.equal("a783", ns.Route.Current().id)
	end)

	it("leaves the route alone when another NPC lists its quests", function()
		local ns = S.login()
		local W = wow.world
		W.npc = { guid = "Creature-0-1-0-0-197-0000000000", name = "Marshal McBride" }
		W.offers = { 7 }
		wow.fire("GOSSIP_SHOW")
		wow.advance(1)
		assert.are.equal("a783", ns.Route.Current().id)
	end)

	-- Owner 2026-11-05: a level 1 orc saw "falls short of Silverpine Forest … 209 level 1 enemies" at the
	-- first step; far from the zone end the line stays empty.
	it("names no shortfall far from the zone end (level 1, 30 steps, next zone level 11)", function()
		local ns = S.login()
		ns.Route.Balance = function()
			return {
				level = 1,
				toLevel = 400,
				zone = {
					nextMap = 1421,
					shortfall = 10430,
					enough = false,
					kills = 209,
					nextLevel = 11,
					stepsLeft = 30,
				},
			}
		end
		ns.StepFrame.Invalidate()
		ns.StepFrame.Refresh()
		local W = frame(ns)
		assert.is_falsy(W.reach:IsShown() and W.reach.text ~= "" and W.reach.text)
		assert.is_nil(ns.StepText.Reach(ns.Route.Balance()))
	end)

	-- Welle 5d, M8: a zone the client cannot name showed as "bis ?".
	it("route falls short of a zone the client cannot name: the sentence names no zone (M8)", function()
		local ns = S.login({ locale = "deDE" })
		ns.Route.Balance = function()
			return {
				level = 9,
				toLevel = 1600,
				zone = { nextMap = 99999, shortfall = 640, enough = false, kills = 9, nextLevel = 10, stepsLeft = 20 },
			}
		end
		ns.StepFrame.Invalidate()
		ns.StepFrame.Refresh()
		local text = frame(ns).reach.text
		assert.are.equal(
			"Route reicht nicht bis zum nächsten Gebiet. Es fehlen ca. 640 EP, das sind ca. 9 Gegner der Stufe 9.",
			text
		)
		assert.is_nil(text:find("?", 1, true))
	end)

	-- Welle 5d, Q3: another zone than the header's keeps its name in the detail line.
	it("names the target's zone in the detail line only when the header names another (Q3)", function()
		local ns = S.login()
		local ST = ns.StepText
		assert.are.equal("Westfall • 42 |4yd:yds", ST.Detail({ map = 1436 }, 42, "Elwynn Forest"))
		assert.are.equal("42 |4yd:yds away", ST.Detail({ map = 1429 }, 42, "Elwynn Forest"))
		assert.are.equal("", ST.Detail({ map = 1429 }, nil, "Elwynn Forest"))
	end)

	-- Welle 5d, K1 and S5: the counter stays with the last word; an abandoned step's counter takes the
	-- step's color instead of gold (the abandoned quest's progress no longer counts).
	it("keeps the counter on the line of the last word, and plain on an abandoned step (K1, S5)", function()
		local ns = S.login({ locale = "deDE" })
		local W = frame(ns)
		wow.world.questLog[#wow.world.questLog + 1] = {
			questID = 33,
			objectives = { { text = "Zähes Wolfsfleisch: 3/8", numFulfilled = 3, numRequired = 8, finished = false } },
		}
		local V = ns.Routes.VERB
		local info = { key = "test/c33", index = 2, total = 9, quests = { 33 }, step = { { V.COMPLETE, 33 } } }
		ns.StepFrame.Render(info)
		assert.matches("Zähes Wolfsfleisch\194\160|cff%x+3/8|r$", W.step.text)
		ns.Connect.Pending = function()
			return 33
		end
		ns.StepFrame.Render(info)
		assert.matches("Zähes Wolfsfleisch\194\1603/8$", W.step.text)
		assert.are.same({ 1, 1, 1 }, W.step.textColor)
		assert.are.equal("step", ns.StepFrame.View().failAt)
	end)

	-- Welle 5d, M5: the developer preview cleared the mini flag without the look, and "+" stayed.
	it("draws the collapse button from the mini flag on every refresh (M5)", function()
		local ns = S.login()
		local W = frame(ns)
		ns.UI.DB().mini = true
		ns.StepFrame.Refresh()
		assert.are.equal("UI-QuestTrackerButton-Expand-All", W.toggle.tex.atlas)
		ns.UI.DB().mini = nil
		ns.StepFrame.Refresh()
		assert.are.equal("UI-QuestTrackerButton-Collapse-All", W.toggle.tex.atlas)
	end)

	describe("skip with follow-up quests", function()
		it("asks in a dialog that names every follow-up quest, then skips", function()
			local ns = S.login()
			local info, follow = chainStep(ns)
			assert.is_table(info, "no step with follow-up quests in the Elwynn route")
			ns.StepFrame.AskSkip(info.key)
			local popup = wow.popup
			assert.are.equal("BRAINDEADFOREVER_SKIP_CHAIN", popup.which)
			local d = popup.dialog
			assert.are.same({ "Skip", "Cancel", 0, 1, 1, 1 }, {
				d.button1,
				d.button2,
				d.timeout,
				d.whileDead,
				d.exclusive,
				d.hideOnEscape,
			})
			assert.matches("^Skip .*%? These follow%-up quests are skipped too:", popup.text)
			for _, q in ipairs(follow) do
				assert.matches(ns.StepText.Quest(q), popup.text, 1, true)
			end
			assert.are.equal("open", ns.Route.StepState(info.key)) -- nothing moved yet
			d.OnAccept(nil, popup.data)
			assert.are.equal("skipped", ns.Route.StepState(info.key))
			assert.matches("Route recalculated%.$", frame(ns).status.text)
		end)

		it("a class chain is postponed: the dialog says so and the quests come back (KQ-1105)", function()
			local ns = S.login()
			local info, follow = chainStep(ns, true)
			assert.is_table(info, "no step of a class chain with follow-up quests in the Elwynn route")
			ns.StepFrame.AskSkip(info.key)
			local popup = wow.popup
			assert.matches("^Postpone .*%? It belongs to your class quest", popup.text)
			popup.dialog.OnAccept(nil, popup.data)
			assert.are.equal("skipped", ns.Route.StepState(info.key))
			assert.matches("postponed%. They come back at the next zone change%.$", frame(ns).status.text)
			local later = {}
			for _, q in ipairs(ns.Route.Runtime():Later()) do
				later[q] = true
			end
			-- the list holds the class chain; a follow-up without class bond waits with it and opens
			-- again once the postponed quest is handed in (Runtime.lua RT:Later)
			local rt, chain = ns.Route.Runtime(), 0
			for _, q in ipairs(follow) do
				if rt:ClassChain(q) then
					chain = chain + 1
					assert.is_true(later[q] == true, "class chain not on the list later: " .. q)
				else
					assert.is_true(rt:Blocked()[q] == true, "follow-up not waiting: " .. q)
					assert.is_nil(rt:Blocked(true)[q], "follow-up skipped for good: " .. q)
				end
			end
			assert.is_true(chain > 0 or #rt:Later() > 0, "nothing postponed")
		end)

		it("cancel leaves the route as it was; a step without follow-ups skips at once", function()
			local ns = S.login()
			local info = chainStep(ns)
			ns.StepFrame.AskSkip(info.key)
			assert.are.equal("open", ns.Route.StepState(info.key))
			wow.popup = nil
			local plain
			for _, n in ipairs(ns.Route.Upcoming(20)) do
				if #ns.Route.SkipPreview(n.key) == 0 and not ns.Route.SkipPostpones(n.key) then
					plain = n
					break
				end
			end
			ns.StepFrame.AskSkip(plain.key)
			assert.is_nil(wow.popup)
			assert.are.equal("skipped", ns.Route.StepState(plain.key))
			assert.matches("skipped%. Route recalculated%.$", frame(ns).status.text)
		end)
	end)

	describe("quest abandoned", function()
		-- Plays a783, t783 (783 handed in, 7 taken) and a33; the route stands at c7. Then 33 is abandoned.
		local function abandoned()
			local ns = S.login()
			local W = wow.world
			W.questLog[#W.questLog + 1] = { questID = 783, objectives = {} }
			wow.fire("QUEST_ACCEPTED", 783)
			wow.advance(2)
			W.questLog = {}
			W.completed[783] = true
			wow.fire("QUEST_TURNED_IN", 783, 40, 0)
			wow.fire("QUEST_REMOVED", 783)
			for _, q in ipairs({ 7, 33 }) do
				W.questLog[#W.questLog + 1] = { questID = q, objectives = {} }
				wow.fire("QUEST_ACCEPTED", q)
				wow.advance(2)
			end
			assert.are.equal("a-speed-start-elwynn/c7", ns.Route.Current().key)
			table.remove(W.questLog) -- 33
			wow.fire("QUEST_REMOVED", 33)
			wow.advance(1.5)
			return ns
		end

		it("shows the fail symbol and two ways; nothing moves without a click", function()
			local ns = abandoned()
			local W = frame(ns)
			assert.are.equal(33, ns.Route.Pending())
			assert.matches("^“Wolves Across the Border” was abandoned in the quest log%.", W.banner.text)
			assert.is_true(shown(W.btnReaccept))
			assert.is_true(shown(W.btnSkipChain))
			assert.are.equal("Accept again", W.btnReaccept.text)
			assert.are.equal("UI-QuestTracker-Objective-Fail", W.icon.atlas)
			assert.is_false(shown(W.box))
			W.box:Click()
			assert.are.equal(33, ns.Route.Pending())
		end)

		-- Welle 5d, M9: the note named one quest and the window marked the step of another. The runtime
		-- asks about a quest taken earlier; here the current step is c7 (“Kobold Camp Cleanup”).
		it("marks only the step of the abandoned quest; another current step stays as it is (M9)", function()
			local ns = abandoned()
			local W = frame(ns)
			local cur = ns.Route.Current()
			assert.is_false(ns.StepFrame.StepHasQuest(cur, 33))
			assert.matches("Kobold Camp Cleanup", W.step.text, 1, true)
			-- the fail symbol stands in front of the note that names the quest, not at the step
			assert.are.same(
				{ "TOPLEFT", W, "TOPLEFT" },
				{ W.icon.points[1][1], W.icon.points[1][2], W.icon.points[1][3] }
			)
			assert.are.equal("banner", ns.StepFrame.View().failAt)
		end)

		-- Welle 5d, M2: DIM_RED on the window measured 1.3:1 over a bright sky and stays under 2.5:1
		-- behind any opacity; the step text stays white, the symbol and the note carry the state.
		it("keeps the step text white and readable while a quest is abandoned (M2)", function()
			local ns = abandoned()
			assert.are.same({ 1, 1, 1 }, frame(ns).step.textColor)
		end)

		it("“Accept again” leads back to the quest giver", function()
			local ns = abandoned()
			frame(ns).btnReaccept:Click()
			assert.is_nil(ns.Route.Pending())
			assert.are.equal("a-speed-start-elwynn/a33", ns.Route.Current().key)
			assert.is_false(shown(frame(ns).banner))
			assert.are.equal("Undo: accepted “Wolves Across the Border” again", S.menu(ns).items[2].text)
		end)

		it("“Skip” answers the question with the follow-up quests", function()
			local ns = abandoned()
			local follow = ns.Route.AbandonPreview()
			frame(ns).btnSkipChain:Click()
			if #follow > 0 then
				wow.popup.dialog.OnAccept(nil, wow.popup.data)
			end
			assert.is_nil(ns.Route.Pending())
			assert.matches("skipped", frame(ns).status.text)
		end)
	end)

	it("optional dungeon step carries the gold tag, the givers' quests, and skips like a step", function()
		local ns = S.login()
		local skipped
		local first = ns.Route.Upcoming(1)[1].index
		ns.Route.DungeonHint = function()
			if skipped then
				return {}
			end
			return {
				{ id = 63, area = 1581, lo = 18, hi = 24, first = first, quests = { { q = 7, state = "take" } } },
			}
		end
		ns.Route.SkipDungeon = function(id)
			skipped = id
			return true
		end
		ns.StepFrame.Invalidate()
		ns.StepFrame.Refresh()
		local W = frame(ns)
		local row = W.next[2] -- behind the step where its giver is passed
		assert.is_true(shown(row.tag))
		assert.are.equal("Optional • Dungeon • Level 18–24", row.tag.text)
		assert.are.equal("The Deadmines: accept “Kobold Camp Cleanup”", row.text.text)
		assert.are.same({ 1, 0.82, 0 }, row.tag.textColor)
		assert.are.equal(4, row.text.maxLines)
		assert.are.equal(0.78, row.text.alpha)
		assert.is_false(shown(W.next[1].tag))
		assert.are.equal(3, #nextRows(ns)) -- it takes one of the three places
		row.hit.scripts.OnMouseUp(row.hit, "RightButton")
		assert.are.equal("Skip step", wow.menu.items[2].text)
		wow.menu.items[2].fn()
		assert.are.equal(63, skipped)
		assert.is_false(shown(W.next[2].tag))
	end)

	it("origin tooltip says when the prerequisites of a step are still being collected", function()
		local ns = S.login()
		local current = ns.Route.Current
		ns.Route.Current = function()
			local c = current()
			c.chain = "incomplete"
			return c
		end
		ns.StepFrame.Refresh()
		local W = frame(ns)
		W.cur.scripts.OnEnter(W.cur)
		local lines = wow.world.tooltip.lines
		assert.are.equal("Follow-up quests: collecting data", lines[#lines])
	end)

	it("missing atlas: neutral surface and a line in the problem report", function()
		local ns = S.login({
			before = function(W)
				W.missingAtlas["checkbox-minimal"] = true
			end,
		})
		local box = frame(ns).box.tex
		assert.is_nil(rawget(box, "atlas"))
		assert.are.same({ 1, 1, 1, 0.15 }, box.colorTexture)
		assert.matches("Missing atlases: checkbox%-minimal", ns.Report.Build())
	end)

	it("German client: German texts, German quotes and “m” for yards", function()
		local ns = S.login({ locale = "deDE", before = S.away })
		local W = frame(ns)
		assert.are.equal("„Eine Bedrohung von innen“ annehmen", W.step.text)
		-- Welle 5d, Q2: "|4m" without a colon lost the "m" in the client; Q3: no zone repeated
		assert.are.equal("70 m entfernt", W.detail.text)
		-- Welle 5d, Q5: number and "EP" joined by a no-break space, so "EP" never stands alone
		assert.matches("^Stufe |cffffffff1|r • noch |cffffffff400|r\194\160EP", W.xp.text)
		assert.matches("^Wald von Elwynn • 1/", W.title.text)
		assert.are.equal(1, W.title.maxLines)
	end)
end)
