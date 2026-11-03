-- SPDX-License-Identifier: GPL-3.0-or-later
-- Gamepad (Welle 9, K8; requirement A40, concept §2.9): Forever saves Edit Mode layouts per UI type,
-- mouse and keyboard apart from gamepad (patch 1.60.1 beta 4). The windows follow: one set of places per
-- UI type, switched with INPUT_DEVICE_INTERFACE_TRANSITION, never in a fight. Retail has no gamepad UI.
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

local HEADER_Y = 690

local function drag(f, left, top)
	wow.world.cursor = { 500, HEADER_Y }
	f.scripts.OnDragStart(f)
	S.drop(f, left, top)
	f.scripts.OnDragStop(f)
end

-- The player switches the UI type (Blizzard: INPUT_DEVICE_INTERFACE_TRANSITION newMode, oldMode).
local function switch(pad)
	local old = wow.world.inputStyle
	wow.world.inputStyle = pad and 1 or 0
	wow.fire("INPUT_DEVICE_INTERFACE_TRANSITION", wow.world.inputStyle, old)
end

local function point(f)
	local p = f.points[1]
	return { p[1], p[3], p[4], p[5] }
end

describe("Places per UI type (gamepad)", function()
	it("keeps the places of mouse and keyboard and of the gamepad apart", function()
		local ns = S.login()
		local W = ns.StepFrame.frame
		local default = point(W)
		drag(W, 300, 650)
		assert.are.same({ "TOPLEFT", "TOPLEFT", 300, -430 }, ns.UI.DB().pos.window)
		switch(true)
		assert.is_true(ns.UI.Pad())
		assert.are.same(default, point(W), "the gamepad layout has no place yet: the default")
		drag(W, 600, 500)
		assert.are.same({ "TOPLEFT", "TOPLEFT", 600, -580 }, ns.UI.DB().posPad.window)
		assert.are.same({ "TOPLEFT", "TOPLEFT", 300, -430 }, ns.UI.DB().pos.window, "mouse place untouched")
		switch(false)
		assert.are.same({ "TOPLEFT", "TOPLEFT", 300, -430 }, point(W))
		switch(true)
		assert.are.same({ "TOPLEFT", "TOPLEFT", 600, -580 }, point(W))
	end)

	it("starts with the places of the UI type the player logs in with", function()
		local ns = S.login({
			saved = { ui = { pos = { window = { "TOPLEFT", "TOPLEFT", 300, -430 } } } },
			before = function(W)
				W.inputStyle = 1
			end,
		})
		assert.is_true(ns.UI.Pad())
		assert.are_not.same({ "TOPLEFT", "TOPLEFT", 300, -430 }, point(ns.StepFrame.frame))
	end)

	it("moves nothing in a fight: the switch waits for its end", function()
		local ns = S.login()
		local W = ns.StepFrame.frame
		drag(W, 300, 650)
		switch(true)
		drag(W, 600, 500)
		S.combat(true)
		switch(false)
		assert.are.same({ "TOPLEFT", "TOPLEFT", 600, -580 }, point(W))
		assert.are.same({}, wow.blocked)
		S.combat(false)
		assert.are.same({ "TOPLEFT", "TOPLEFT", 300, -430 }, point(W))
	end)

	it("Reset puts back only the places of the current UI type", function()
		local ns = S.login()
		local W = ns.StepFrame.frame
		drag(W, 300, 650)
		switch(true)
		drag(W, 600, 500)
		ns.UI.ResetPositions()
		assert.is_nil(ns.UI.DB().posPad)
		assert.are.same({ "TOPLEFT", "TOPLEFT", 300, -430 }, ns.UI.DB().pos.window)
	end)

	it("Retail has no gamepad UI: always the places of mouse and keyboard", function()
		wow.reset({ flavor = "retail" })
		assert.is_nil(_G.C_InputInterfaceStyle)
		local ns = wow.loadFiles({
			"Braindead4Ever/Locales/enUS.lua",
			"Braindead4Ever/Core/Util.lua",
			"Braindead4Ever/Core/Guard.lua",
		})
		ns = wow.loadFiles({ "Braindead4Ever/Core/Modules.lua", "Braindead4Ever/UI/Core.lua" }, "Braindead4Ever", ns)
		assert.is_false(ns.UI.Pad())
		assert.are.equal("pos", ns.UI.PosKey())
	end)
end)
