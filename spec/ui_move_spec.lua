-- SPDX-License-Identifier: GPL-3.0-or-later
-- Moving the windows (owner reading 16, Welle 5c task 14): the step window by dragging its header band
-- with the left mouse button outside a fight, "Lock window" (Display page, off by default) stops that,
-- Blizzard's Edit Mode moves both windows as well. The arrow stays click-free (rule P7) and moves with
-- Shift held or in Edit Mode. The place is saved; right-click menu and check box keep working.
-- Counter-checks: spec/ui_combat_spec.lua records Frame:StartMoving in a fight once the guard is out.
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

local HEADER_Y, BODY_Y = 690, 600 -- cursor heights: the stand-in window's top is 700, the band 36 high

-- Drags a window like the client: press (OnDragStart), the frame follows the mouse, release. `to` is
-- either an anchor { point, relPoint, x, y } or a screen spot { left = x, top = y } where the client
-- anchors the frame at the nearest point (S.drop).
local function drag(f, cursorY, to)
	wow.world.cursor = { 500, cursorY or HEADER_Y }
	f.scripts.OnDragStart(f)
	local moving = rawget(f, "moving") == true
	if moving and to and to.left then
		S.drop(f, to.left, to.top)
	elseif moving and to then
		f:ClearAllPoints()
		f:SetPoint(to[1], _G.UIParent, to[2], to[3], to[4])
	end
	f.scripts.OnDragStop(f)
	return moving
end

local function shift(down)
	wow.world.shift = down
	wow.fire("MODIFIER_STATE_CHANGED", "LSHIFT", down and 1 or 0)
end

local function kinds(page)
	for _, c in ipairs(wow.world.settings.categories) do
		if c.name == page then
			local out = {}
			for _, i in ipairs(c.inits) do
				out[#out + 1] = i.kind .. ":" .. (i.setting and i.setting.key or i.name)
			end
			return out
		end
	end
end

describe("Step window, free drag", function()
	it("moves by its header band and saves the place", function()
		local ns = S.login()
		local W = ns.StepFrame.frame
		assert.is_true(W.mouse and W.movable)
		assert.is_true(drag(W, HEADER_Y, { left = 300, top = 650 }))
		-- held at its top edge: 650 is 430 below the top of the 1080 high screen
		assert.are.same({ "TOPLEFT", "TOPLEFT", 300, -430 }, ns.UI.DB().pos.window)
		assert.is_false(W.moving)
		-- the next login puts it there
		local db = { ui = ns.UI.DB() }
		ns = S.login({ saved = db })
		assert.are.same({ "TOPLEFT", _G.UIParent, "TOPLEFT", 300, -430 }, ns.StepFrame.frame.points[1])
	end)

	-- Welle 5d, M4: the client anchored the dropped window at RIGHT (middle of the screen height), so it
	-- grew up and down and ran into the minimap buttons, the coordinates and the buff bar.
	it("holds the top edge after a drop in the middle of the screen, so it grows only downwards (M4)", function()
		local ns = S.login()
		local W = ns.StepFrame.frame
		W.h = 200
		wow.world.cursor = { 500, HEADER_Y }
		W.scripts.OnDragStart(W)
		assert.is_true(W.moving)
		assert.are.equal("RIGHT", S.drop(W, 1500, 640)) -- what the client picks there
		W.scripts.OnDragStop(W)
		local point, rel, relPoint, x, y = W:GetPoint(1)
		assert.are.same({ "TOPRIGHT", _G.UIParent, "TOPRIGHT", -120, -440 }, { point, rel, relPoint, x, y })
		assert.are.same({ "TOPRIGHT", "TOPRIGHT", -120, -440 }, ns.UI.DB().pos.window)
		-- a line more: the top edge stays, only the bottom moves
		W.top, W.bottom = nil, nil
		ns.StepFrame.SetMessage("New version available")
		assert.are.equal("TOPRIGHT", (W:GetPoint(1)))
		assert.are.equal(-440, select(5, W:GetPoint(1)))
	end)

	it("moves a place saved before Welle 5d (RIGHT, CENTER) to the top edge at login (M4)", function()
		local saved = { ui = { pos = { window = { "RIGHT", "RIGHT", -120, 20 } } } }
		local ns = S.login({ saved = saved })
		local W = ns.StepFrame.frame
		local point = W:GetPoint(1)
		assert.matches("^TOP", point)
		assert.matches("^TOP", ns.UI.DB().pos.window[1])
	end)

	it("does not move by its body, and a refused drag saves nothing", function()
		local ns = S.login()
		local W = ns.StepFrame.frame
		assert.is_false(drag(W, BODY_Y, { "TOPLEFT", "BOTTOMLEFT", 300, 650 }))
		assert.is_nil(ns.UI.DB().pos)
	end)

	it("counts the header band in the window's scale", function()
		local ns = S.login({ saved = { ui = { scale = 200 } } })
		local W = ns.StepFrame.frame
		assert.are.equal(2, W:GetEffectiveScale())
		-- the cursor counts in screen pixels: header band 700 - 36 = 664 window units = 1328 pixels
		assert.is_true(drag(W, 1340))
		assert.is_false(drag(W, 1320))
	end)

	it("'Lock window' stops the header drag; Edit Mode still moves it", function()
		local ns = S.login()
		local W = ns.StepFrame.frame
		assert.is_false(ns.UI.Get("lock"))
		ns.UI.Set("lock", true)
		assert.is_false(drag(W, HEADER_Y, { "TOPLEFT", "BOTTOMLEFT", 300, 650 }))
		assert.is_nil(ns.UI.DB().pos)
		_G.EventRegistry:TriggerEvent("EditMode.Enter")
		assert.is_true(drag(W, BODY_Y, { left = 200, top = 600 }))
		assert.are.same({ "TOPLEFT", "TOPLEFT", 200, -480 }, ns.UI.DB().pos.window)
		_G.EventRegistry:TriggerEvent("EditMode.Exit")
		assert.is_false(drag(W, HEADER_Y))
	end)

	it("never moves in a fight; a fight ends a running drag and keeps the place", function()
		local ns = S.login()
		local W = ns.StepFrame.frame
		S.combat(true)
		assert.is_false(drag(W, HEADER_Y))
		_G.EventRegistry:TriggerEvent("EditMode.Enter")
		assert.is_false(drag(W, HEADER_Y))
		_G.EventRegistry:TriggerEvent("EditMode.Exit")
		assert.are.same({}, wow.blocked)
		S.combat(false)
		-- drag running when the fight starts
		wow.world.cursor = { 500, HEADER_Y }
		W.scripts.OnDragStart(W)
		assert.is_true(W.moving)
		S.drop(W, 250, 640)
		S.combat(true)
		assert.is_false(W.moving)
		assert.are.same({ "TOPLEFT", "TOPLEFT", 250, -440 }, ns.UI.DB().pos.window)
		W.scripts.OnDragStop(W) -- the release after the fight start changes nothing
		assert.are.same({}, wow.blocked)
		assert.are.same({ "TOPLEFT", "TOPLEFT", 250, -440 }, ns.UI.DB().pos.window)
	end)

	it("does not move while the grip sizes it", function()
		local ns = S.login()
		local SF, W = ns.StepFrame, ns.StepFrame.frame
		SF.grip.scripts.OnMouseDown(SF.grip, "LeftButton")
		assert.is_true(SF.sizing)
		wow.world.cursor = { 500, HEADER_Y }
		W.scripts.OnDragStart(W)
		assert.is_falsy(rawget(W, "moving"))
		SF.grip.scripts.OnMouseUp(SF.grip, "LeftButton")
	end)

	it("keeps the right-click menu and the check box working, also after a drag", function()
		local ns = S.login()
		local W = ns.StepFrame.frame
		drag(W, HEADER_Y, { left = 300, top = 650 })
		assert.is_table(S.menu(ns))
		assert.is_table(S.item(S.menu(ns), "Settings"))
		W.box:Click()
		assert.are.equal("UI-QuestTracker-Tracker-Check", W.icon.atlas)
		assert.are.same({ 878 }, wow.world.sounds)
		-- the header band itself opens the menu with the right button
		wow.menu = nil
		W.scripts.OnMouseUp(W, "RightButton")
		assert.is_table(wow.menu)
	end)

	it("has the option 'Lock window' on the Display page, after Blizzard's quest tracker", function()
		S.login()
		local list = kinds("Display")
		local at = {}
		for i, k in ipairs(list) do
			at[k] = i
		end
		assert.is_number(at["checkbox:lock"], table.concat(list, ", "))
		assert.is_true(at["checkbox:lock"] == at["dropdown:tracker"] + 1, table.concat(list, ", "))
		assert.is_false(wow.world.settings.settings.BRAINDEADFOREVER_LOCK:GetValue())
	end)
end)

describe("Arrow, free drag", function()
	local function arrow(ns)
		return ns.Arrow.frame
	end

	it("is click-free and moves with Shift held, outside a fight", function()
		local ns = S.login()
		local F = arrow(ns)
		assert.is_false(F.mouse) -- rule P7
		assert.is_false(drag(F, 0))
		shift(true)
		assert.is_true(F.mouse)
		assert.is_true(drag(F, 0, { "CENTER", "CENTER", 40, 180 }))
		assert.are.same({ "CENTER", "CENTER", 40, 180 }, ns.UI.DB().pos.arrow)
		shift(false)
		assert.is_false(F.mouse)
	end)

	it("lets go of the mouse in a fight even with Shift held, and takes it again after", function()
		local ns = S.login()
		local F = arrow(ns)
		shift(true)
		S.combat(true)
		assert.is_false(F.mouse)
		assert.is_false(drag(F, 0))
		assert.are.same({}, wow.blocked)
		S.combat(false)
		assert.is_true(F.mouse)
		shift(false)
		assert.is_false(F.mouse)
	end)

	it("ignores other modifier keys", function()
		local ns = S.login()
		local F = arrow(ns)
		wow.world.shift = true -- held, but the event is for Ctrl
		wow.fire("MODIFIER_STATE_CHANGED", "LCTRL", 1)
		assert.is_false(F.mouse)
	end)

	it("moves in Edit Mode without Shift, and 'Lock window' does not hold it there", function()
		local ns = S.login()
		local F = arrow(ns)
		ns.UI.Set("lock", true)
		_G.EventRegistry:TriggerEvent("EditMode.Enter")
		assert.is_true(F.mouse)
		assert.is_true(drag(F, 0, { "CENTER", "CENTER", -60, 200 }))
		assert.are.same({ "CENTER", "CENTER", -60, 200 }, ns.UI.DB().pos.arrow)
		_G.EventRegistry:TriggerEvent("EditMode.Exit")
		assert.is_false(F.mouse)
	end)
end)
