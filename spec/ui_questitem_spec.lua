-- SPDX-License-Identifier: GPL-3.0-or-later
-- Quest item button (M8, UI/QuestItem.lua): when a quest of the current step has a quest item, the step
-- window shows a secure button (type "item") with icon, charges, cooldown and range dot like Blizzard's
-- quest tracker. Its attribute, place and visibility change only out of combat; in a fight the item set
-- last stays usable. The stand-ins (spec/helpers/ui.lua) treat a secure frame, its parents and every
-- frame it is anchored to as protected and record changes in a fight like ADDON_ACTION_BLOCKED.
-- Counter-checks: without the combat guard, and with the button left anchored to the window, the same
-- fight records blocked calls, so the main tests can see the fault they guard against.
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

local ITEM = 2875 -- test value: a quest item of quest 33 in the stand-in quest log
local LINKED = "item:" .. ITEM

-- Quest 33 ("Wolves Across the Border") is in the log with an item; the route's current step is then
-- a783, and c33 (complete 33) comes eleven steps later for the human warrior, right behind c3100. t33
-- (turn in 33) comes eight steps after c33 and stays the current step when the quest completes.
local function login(opts)
	opts = opts or {}
	local before = opts.before
	opts.before = function(W)
		W.questLog[#W.questLog + 1] = {
			questID = 33,
			objectives = { { numFulfilled = 0, numRequired = 8, finished = false, text = "Tough Wolf Meat: 0/8" } },
			item = opts.item or { id = ITEM, name = "Wolf Bait", icon = 133972, charges = 0 },
		}
		if before then
			before(W)
		end
	end
	return S.login(opts)
end

local function button()
	return _G.BraindeadForeverQuestItemButton
end

local function shown(f)
	return rawget(f, "shown") == true
end

-- Checks off steps until the current step has this id.
local function toStep(ns, id)
	for _ = 1, 30 do
		local cur = ns.Route.Current()
		if cur and cur.id == id then
			return cur
		end
		ns.Connect.Check()
		wow.advance(1)
	end
	error("step " .. id .. " not reached")
end

local function protectedBlocked()
	local out = {}
	for _, name in ipairs(wow.blocked) do
		if name:find("^Protected:") or name == "IsQuestLogSpecialItemInRange" then
			out[#out + 1] = name
		end
	end
	return out
end

describe("Quest item button (M8)", function()
	it("appears with the step whose quest has an item and goes with the step", function()
		local ns = login()
		local B, W = button(), ns.StepFrame.frame
		assert.are.equal("on", ns.Modules.state.questitem)
		assert.is_true(B.secure)
		assert.are.equal("item", B:GetAttribute("type"))
		assert.are.same({ "AnyUp", "AnyDown" }, B.clicksFor) -- a binding fires on key down
		assert.are.equal("a783", ns.Route.Current().id)
		assert.is_false(shown(B)) -- quest 783 is not in the log
		assert.is_nil(B:GetAttribute("item"))

		toStep(ns, "c33")
		assert.is_true(shown(B))
		assert.are.equal(LINKED, B:GetAttribute("item"))
		assert.are.equal(133972, B.icon.file)
		local point, rel, relPoint, x, y = B:GetPoint(1)
		assert.are.same({ "TOPRIGHT", W, "TOPRIGHT", -ns.StepFrame.RIGHT }, { point, rel, relPoint, x })
		assert.is_true(y < -ns.StepFrame.HEADER) -- at the current step, below the header band
		-- the step text leaves room for the button
		local full = ns.StepFrame.Width() - (ns.StepFrame.LEFT + ns.StepFrame.ICON + ns.StepFrame.GAP_ICON)
		assert.are.equal(full - ns.StepFrame.RIGHT - ns.QuestItem.ROOM, W.step:GetWidth())

		ns.Connect.Back() -- c3100: quest 3100 has no item
		wow.advance(1)
		assert.are.equal("c3100", ns.Route.Current().id)
		assert.is_false(shown(B))
		assert.is_nil(B:GetAttribute("item")) -- no click uses an old item
		assert.are.equal(full - ns.StepFrame.RIGHT, W.step:GetWidth())
		assert.is_nil(B:GetPoint(1)) -- hidden, it is anchored to nothing

		toStep(ns, "t33")
		assert.is_true(shown(B))
		-- the quest completes: Blizzard's tracker keeps no item of a complete quest
		wow.world.questLog[1].complete = true
		wow.world.questLog[1].objectives[1].finished = true
		wow.fire("QUEST_LOG_UPDATE")
		wow.advance(1)
		assert.are.equal("t33", ns.Route.Current().id) -- the step stays, only the quest changed
		assert.is_false(shown(B))
		assert.are.same({}, wow.errors)
	end)

	it("keeps an item marked for complete quests (showItemWhenComplete)", function()
		local ns = login({ item = { id = ITEM, icon = 133972, always = true } })
		toStep(ns, "t33")
		wow.world.questLog[1].complete = true
		wow.fire("QUEST_LOG_UPDATE")
		wow.advance(1)
		assert.are.equal("t33", ns.Route.Current().id)
		assert.is_true(shown(button()))
	end)

	it("changes nothing protected in a fight; the item set last stays usable until the fight ends", function()
		local ns = login()
		local B, W = button(), ns.StepFrame.frame
		toStep(ns, "c33")
		S.combat(true)
		-- pinned to UIParent at the start of the fight, so the window stays free
		local _, rel = B:GetPoint(1)
		assert.are.equal(_G.UIParent, rel)
		assert.is_false(wow.restricted(W))
		ns.Connect.Back() -- the step changes in the fight: c3100 has no item
		wow.advance(1)
		ns.UI.SetPaused(true) -- the guidance pauses in the fight
		ns.UI.SetPaused(false)
		ns.UI.Set("scale", 120)
		wow.fire("QUEST_LOG_UPDATE")
		wow.advance(1)
		assert.are.same({}, protectedBlocked())
		assert.is_true(shown(B))
		assert.are.equal(LINKED, B:GetAttribute("item"))
		assert.is_true(ns.UI.Waiting() > 0)
		S.combat(false)
		assert.are.same({}, protectedBlocked())
		assert.is_false(shown(B))
		assert.is_nil(B:GetAttribute("item"))
		-- back at the item step after the fight: anchored to the window again, at the new scale
		toStep(ns, "c33")
		local _, rel2 = B:GetPoint(1)
		assert.are.equal(W, rel2)
		assert.are.equal(1.2, B:GetScale())
	end)

	it("counter-check: without the combat guard the same fight records blocked calls", function()
		local ns = login()
		toStep(ns, "c33")
		ns.UI.OutOfCombat = function(_, fn, ...)
			fn(...)
			return true
		end
		S.combat(true)
		ns.Connect.Back()
		wow.advance(1)
		local blocked = protectedBlocked()
		assert.is_true(#blocked > 0)
		local kinds = {}
		for _, name in ipairs(blocked) do
			kinds[name] = true
		end
		assert.is_true(kinds["Protected:SetAttribute"])
		assert.is_true(kinds["Protected:Hide"])
	end)

	it("counter-check: left anchored to the window, the window's layout is blocked in a fight", function()
		local ns = login({
			loaded = function(ns)
				ns.QuestItem.Detach = function() end
			end,
		})
		toStep(ns, "c33")
		S.combat(true)
		assert.is_true(wow.restricted(ns.StepFrame.frame))
		ns.Connect.Back()
		wow.advance(1)
		local kinds = {}
		for _, name in ipairs(protectedBlocked()) do
			kinds[name] = true
		end
		assert.is_true(kinds["Protected:SetHeight"] or kinds["Protected:SetWidth"])
	end)

	it("charges, cooldown, key and range dot like Blizzard's tracker; no range question in a fight", function()
		local ns = login({
			item = { id = ITEM, icon = 133972, charges = 3, cooldown = { 990, 30, 0 }, range = 0 },
		})
		local B = button()
		toStep(ns, "c33")
		assert.are.equal(3, B.count.text)
		assert.is_true(shown(B.count))
		assert.are.same({ 990, 30, 0 }, B.cooldown.cooldownSet)
		assert.are.same({ 0.4, 0.4, 0.4 }, { B.icon.vertex[1], B.icon.vertex[2], B.icon.vertex[3] })
		-- range: 0 too far (red dot), 1 in range (gray), nil no range (no dot)
		B.scripts.OnUpdate(B, 0.25)
		assert.are.equal("●", B.hotkey.text)
		assert.is_true(shown(B.hotkey))
		assert.are.same({ 1, 0.125, 0.125 }, { B.hotkey.vertex[1], B.hotkey.vertex[2], B.hotkey.vertex[3] })
		assert.is_false(B.icon.desaturated == true) -- color alone, as in Blizzard's tracker
		wow.world.questLog[1].item.range = 1
		B.scripts.OnUpdate(B, 0.25)
		assert.are.same({ 0.6, 0.6, 0.6 }, { B.hotkey.vertex[1], B.hotkey.vertex[2], B.hotkey.vertex[3] })
		wow.world.questLog[1].item.range = nil
		B.scripts.OnUpdate(B, 0.25)
		assert.is_false(shown(B.hotkey))
		-- colorblind mode: too far also turns the icon gray (design rule B3)
		wow.world.cvars.colorblindMode = "1"
		wow.world.questLog[1].item.range = 0
		B.scripts.OnUpdate(B, 0.25)
		assert.is_true(B.icon.desaturated)
		-- a bound key shows its text and turns red when too far
		wow.world.bindings[ns.QuestItem.BINDING] = "Q"
		wow.fire("UPDATE_BINDINGS")
		assert.are.equal("Q", B.hotkey.text)
		assert.are.same({ 1, 0.125, 0.125 }, { B.hotkey.vertex[1], B.hotkey.vertex[2], B.hotkey.vertex[3] })
		-- cooldown over
		wow.world.questLog[1].item.cooldown = { 0, 0, 1 }
		wow.fire("BAG_UPDATE_COOLDOWN")
		assert.are.same({ 1, 1, 1 }, { B.icon.vertex[1], B.icon.vertex[2], B.icon.vertex[3] })
		-- in a fight the range is not asked
		local calls = wow.world.rangeCalls
		S.combat(true)
		for _ = 1, 20 do
			B.scripts.OnUpdate(B, 0.25)
		end
		assert.are.equal(calls, wow.world.rangeCalls)
		assert.are.same({}, protectedBlocked())
		S.combat(false)
	end)

	it("pause and the window key take the button along, out of a fight", function()
		local ns = login()
		local B = button()
		toStep(ns, "c33")
		ns.UI.SetPaused(true)
		assert.is_false(shown(B))
		ns.UI.SetPaused(false)
		assert.is_true(shown(B))
		_G.BraindeadForeverBinding("WINDOW")
		assert.is_false(shown(B))
		_G.BraindeadForeverBinding("WINDOW")
		assert.is_true(shown(B))
	end)

	it("a login in a fight sets the button up after the fight", function()
		local ns = login({ combat = true })
		local B = button()
		assert.is_table(B)
		assert.is_nil(B:GetAttribute("type"))
		assert.are.same({}, protectedBlocked())
		S.combat(false)
		assert.are.equal("item", B:GetAttribute("type"))
		assert.are.same({ "AnyUp", "AnyDown" }, B.clicksFor)
		assert.are.equal("on", ns.Modules.state.questitem)
	end)

	it("turns off without the quest item API; the window runs without it", function()
		local ns = login({
			before = function()
				_G.GetQuestLogSpecialItemInfo = nil
			end,
		})
		assert.are.equal("off", ns.Modules.state.questitem)
		assert.matches("GetQuestLogSpecialItemInfo", ns.Modules.why.questitem, 1, true)
		assert.is_nil(button())
		assert.are.equal("on", ns.Modules.state.window)
		toStep(ns, "c33")
		local full = ns.StepFrame.Width() - (ns.StepFrame.LEFT + ns.StepFrame.ICON + ns.StepFrame.GAP_ICON)
		assert.are.equal(full - ns.StepFrame.RIGHT, ns.StepFrame.frame.step:GetWidth())
		assert.are.same({}, wow.errors)
	end)

	it("the probe lists the module's functions and checks cooldown, range and the frame atlas", function()
		local ns = S.login({ probe = true })
		local ids = {}
		for _, c in ipairs(ns.Probe.All()) do
			ids[c.id] = c
		end
		for _, id in ipairs({ "qitem.info", "qitem.cooldown", "qitem.range", "qitem.button", "atlas.questitem" }) do
			assert.is_table(ids[id], id)
		end
		assert.is_table(ids["mod.questitem.GetBindingKey"])
		assert.is_table(ids["mod.questitem.BAG_UPDATE_COOLDOWN"])
		-- M4: functions with an explicit check (name.npc UnitName, name.npctooltip C_TooltipInfo.GetHyperlink)
		-- are not repeated as mod.npcnames.*
		for _, id in ipairs({ "mod.npcnames.GetLocale", "mod.npcnames.QUEST_DETAIL", "name.npc", "name.npctooltip" }) do
			assert.is_table(ids[id], id)
		end
	end)
end)
