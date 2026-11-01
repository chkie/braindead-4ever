-- SPDX-License-Identifier: GPL-3.0-or-later
-- Combat rule (release gate T15/T21, brain chapter 05 §3, chapter 18 R1/R3/N7): no protected or
-- restricted call and nothing the design forbids happens while the lockdown is on. The stand-ins in
-- spec/helpers/ui.lua record such calls in wow.blocked like the client's ADDON_ACTION_BLOCKED.
-- Counter-check: with the guard taken out, the same actions fill wow.blocked, so the main test would
-- fail (the test can see the fault it guards against).
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

-- Everything a player can trigger in a fight, through the real entry points.
local function everything(ns)
	local W = ns.StepFrame.frame
	W.box:Click() -- step done: sound and glow must wait
	wow.advance(1)
	S.item(S.menu(ns), "Settings").fn() -- Settings.OpenToCategory
	SlashCmdList.PATHMARK("setup") -- setup window
	ns.StepFrame.ShowHintOnce() -- HelpTip
	ns.UI.Set("blizzNav", true) -- user waypoint and super tracking
	ns.UI.Set("blizzNav", false)
	ns.UI.Set("blizzNav", true)
	_G.EventRegistry:TriggerEvent("EditMode.Enter")
	W.scripts.OnDragStart(W)
	W.scripts.OnDragStop(W)
	_G.EventRegistry:TriggerEvent("EditMode.Exit")
	ns.StepFrame.AskSkip()
	ns.MinimapButton.Click("LeftButton")
	ns.MinimapButton.Click("LeftButton")
	ns.Arrow.Update(1)
end

describe("Combat lockdown", function()
	it("lets no restricted call through in a fight and runs them after it", function()
		local ns = S.login({ hint = false })
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
		assert.are.equal(1, #wow.world.helptips)
		assert.is_table(wow.world.waypoint)
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

	it("counter-check: without the guard the same fight records blocked calls", function()
		local ns = S.login({ hint = false })
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
	end)
end)
