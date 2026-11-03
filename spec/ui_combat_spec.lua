-- SPDX-License-Identifier: GPL-3.0-or-later
-- Combat rule (release gate T15/T21, brain chapter 05 §3, chapter 18 R1/R3/N7): no protected or
-- restricted call and nothing the design forbids happens while the lockdown is on. The stand-ins in
-- spec/helpers/ui.lua record such calls in wow.blocked like the client's ADDON_ACTION_BLOCKED.
-- Counter-check: with the guard taken out, the same actions fill wow.blocked, so the main test would
-- fail (the test can see the fault it guards against). Received addon messages are only queued in a
-- fight and read after it (Collector/Exchange.lua), with the same kind of counter-check.
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

-- Everything a player can trigger in a fight, through the real entry points.
local function everything(ns)
	local W = ns.StepFrame.frame
	W.box:Click() -- step done: sound and glow must wait
	wow.advance(1)
	ns.StepFrame.ShowHintOnce() -- HelpTip (before the windows it waits behind, Welle 5d M13)
	S.item(S.menu(ns), "Settings").fn() -- Settings.OpenToCategory
	SlashCmdList.PATHMARK("setup") -- setup window
	ns.UI.Set("blizzNav", true) -- user waypoint and super tracking
	ns.UI.Set("blizzNav", false)
	ns.UI.Set("blizzNav", true)
	_G.EventRegistry:TriggerEvent("EditMode.Enter")
	W.scripts.OnDragStart(W)
	W.scripts.OnDragStop(W)
	_G.EventRegistry:TriggerEvent("EditMode.Exit")
	ns.StepFrame.AskSkip()
	SlashCmdList.PATHMARK("stats") -- the page "Your run" (Welle 8)
	ns.MinimapButton.Click("LeftButton")
	ns.MinimapButton.Click("LeftButton")
	-- every key binding (Welle 9, K2): the same entry points as the window
	for _, action in ipairs(ns.Bindings.ACTIONS) do
		_G.PathmarkBinding(action)
		_G.PathmarkBinding(action)
	end
	ns.Arrow.Update(1)
	local grip = ns.StepFrame.grip -- size grip (owner reading 14)
	grip.scripts.OnMouseDown(grip, "LeftButton")
	grip.scripts.OnMouseUp(grip, "LeftButton")
	-- Blizzard's quest tracker (owner reading 15): a quest off the route with Blizzard's own mark, then
	-- the option from "only quests of the route" (see Login) to hidden: both want RemoveQuestWatch and
	-- the tracker's alpha
	wow.world.questLog[#wow.world.questLog + 1] = { questID = 90001 }
	wow.fire("QUEST_ACCEPTED", 90001)
	wow.world.watch(90001, true)
	ns.UI.Set("tracker", "hide")
	wow.advance(1)
end

-- The player chose "only quests of the route" (owner reading 16 made "hidden" the default), so the
-- switch to hidden happens in the fight.
local function Login()
	return S.login({ hint = false, saved = { ui = { tracker = "route", rev = 1 } } })
end

describe("Combat lockdown", function()
	it("lets no restricted call through in a fight and runs them after it", function()
		local ns = Login()
		S.combat(true)
		everything(ns)
		assert.are.same({}, wow.blocked)
		assert.are.same({}, wow.world.sounds)
		assert.are.same({}, wow.world.helptips)
		assert.are.same({}, wow.world.settings.opened)
		assert.is_nil(_G.PathmarkSetupFrame)
		assert.is_nil(wow.world.waypoint)
		assert.is_true(ns.UI.Waiting() > 0)
		S.combat(false)
		assert.are.same({}, wow.blocked)
		assert.are.same({ ns.settingsCategoryID }, wow.world.settings.opened)
		assert.is_true(rawget(_G.PathmarkSetupFrame, "shown"))
		assert.is_true(rawget(_G.PathmarkStatsFrame, "shown")) -- Welle 8: the page opened after the fight
		-- the usage hint came after the fight and waits behind settings and first start (M13)
		assert.is_false(_G.HelpTip:IsShowing(ns.StepFrame.frame))
		_G.PathmarkSetupFrame:Hide()
		_G.SettingsPanel:Hide()
		assert.is_true(_G.HelpTip:IsShowing(ns.StepFrame.frame))
		assert.is_table(wow.world.waypoint)
		assert.are.same({}, wow.world.watches) -- the tracker pass ran after the fight
		assert.are.equal(0, ns.UI.Waiting())
	end)

	it("first start at a login in combat opens only after the fight", function()
		S.login({ setup = false, combat = true })
		wow.advance(3)
		assert.are.same({}, wow.blocked)
		assert.is_nil(_G.PathmarkSetupFrame)
		S.combat(false)
		assert.is_true(rawget(_G.PathmarkSetupFrame, "shown"))
	end)

	-- Received addon messages wait in the exchange's inbox in a fight (owner 2026-11-02: receiving
	-- costs next to nothing, reading happens outside fights; Collector/Exchange.lua).
	local function hearInFight(ns)
		S.combat(true)
		for i = 1, 5 do
			wow.fire(
				"CHAT_MSG_ADDON",
				"Pathmark",
				("o;1;%d;1429;4231;6512"):format(2840 + i),
				"CHANNEL",
				"Anna Sommer" .. i,
				"",
				0,
				5,
				"PathmarkShare",
				0
			)
		end
		wow.fire("CHAT_MSG_ADDON", "Pathmark", "o;1;2850;1429;4231;6512", "PARTY", "Ben Winter")
		wow.advance(30)
		return ns.Exchange
	end

	it("reads no received addon message in a fight and reads them after it", function()
		local X = hearInFight(Login())
		assert.are.equal(0, X.stats.received)
		assert.are.equal(5, X.Waiting(X.inbox.channel))
		assert.are.equal(1, X.Waiting(X.inbox.other))
		S.combat(false)
		wow.advance(1)
		assert.are.equal(6, X.stats.received)
	end)

	it("counter-check: reading without the guard happens in the fight", function()
		local ns = Login()
		ns.Exchange.CanRead = function()
			return true
		end
		local X = hearInFight(ns)
		assert.are.equal(6, X.stats.received)
	end)

	it("counter-check: without the guard the same fight records blocked calls", function()
		local ns = Login()
		-- take the guard out: everything runs at once and the fight is not noticed for the looks
		ns.UI.OutOfCombat = function(_, fn, ...)
			fn(...)
			return true
		end
		ns.UI.Fighting = function()
			return false
		end
		S.combat(true)
		everything(ns)
		local seen = {}
		for _, name in ipairs(wow.blocked) do
			seen[name] = true
		end
		assert.is_true(seen["Settings.OpenToCategory"], "OpenToCategory not caught")
		assert.is_true(seen["HelpTip.Show"], "HelpTip not caught")
		assert.is_true(seen["PathmarkSetupFrame:Show"], "setup window not caught")
		assert.is_true(seen["C_Map.SetUserWaypoint"], "waypoint not caught")
		assert.is_true(seen.PlaySound, "sound not caught")
		assert.is_true(seen["Frame:StartSizing"], "sizing not caught")
		assert.is_true(seen["C_QuestLog.RemoveQuestWatch"], "RemoveQuestWatch not caught")
		assert.is_true(seen["ObjectiveTrackerFrame:SetAlpha"], "tracker alpha not caught")
		assert.is_true(seen["Frame:StartMoving"], "window drag not caught") -- owner reading 16
		assert.is_true(seen["PathmarkStatsFrame:Show"], "page Your run not caught") -- Welle 8
		local kinds = 0
		for _ in pairs(seen) do
			kinds = kinds + 1
		end
		io.stdout:write(("\n[combat] counter-check: %d blocked calls of %d kinds"):format(#wow.blocked, kinds))
	end)
end)
