-- SPDX-License-Identifier: GPL-3.0-or-later
-- Size of the step window (owner reading point 14, Welle 5b task 7): grip at the bottom right, width
-- 260 to 500 (default 300), the height sets how many next steps are visible (0 to 10, "steps ahead"
-- follows both ways), the next steps sit in a scroll list and the rest scrolls; size per account,
-- "Reset" resets it; never while fighting; mini view and scaling stay.
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

local function shown(region)
	return rawget(region, "shown") == true
end

-- Drags the grip like the client: press, size changes (OnSizeChanged), release.
local function drag(ns, width, height)
	local SF, W = ns.StepFrame, ns.StepFrame.frame
	SF.grip.scripts.OnMouseDown(SF.grip, "LeftButton")
	W:SetSize(width, height)
	W.scripts.OnSizeChanged(W, width, height)
end

local function release(ns)
	local SF = ns.StepFrame
	SF.grip.scripts.OnMouseUp(SF.grip, "LeftButton")
end

-- Window height that shows exactly n next steps (list top, rows, what lies below).
local function heightFor(ns, n)
	local SF = ns.StepFrame
	return SF.listTop + SF.rowBottoms[n] + SF.below
end

describe("Step window size", function()
	it("has Blizzard's resize grip, width 260 to 500 and the default size 300 with three steps", function()
		local ns = S.login()
		local SF, W = ns.StepFrame, ns.StepFrame.frame
		assert.are.equal("PanelResizeButtonTemplate", SF.grip.template)
		assert.are.same({ "BOTTOMRIGHT", W, "BOTTOMRIGHT", -2, 2 }, SF.grip.points[1])
		assert.is_true(shown(SF.grip))
		assert.is_true(W.resizable)
		assert.are.equal(260, W.bounds[1])
		assert.are.equal(500, W.bounds[3])
		assert.are.equal(300, W.w)
		assert.are.equal(3, ns.UI.Get("ahead"))
		assert.are.equal(3, #SF.VisibleRows())
	end)

	it("keeps the next 20 steps in a Blizzard scroll box; what the height does not show scrolls", function()
		local ns = S.login()
		local SF, W = ns.StepFrame, ns.StepFrame.frame
		assert.are.equal("WowScrollBox", W.listBox.template)
		assert.are.equal("MinimalScrollBar", SF.bar.template)
		assert.are.equal(W.list, W.listBox.child)
		assert.is_true(W.list.scrollable)
		assert.is_true(SF.bar.hideIfUnscrollable)
		assert.are.equal(20, #SF.rowBottoms)
		assert.are.equal(SF.rowBottoms[20], W.list.h)
		assert.are.equal(SF.rowBottoms[3], W.listBox.h)
		assert.is_true(W.listBox.scrollable)
		assert.is_true(shown(SF.bar))
		assert.are.equal(20, W.listBox.view.pan)
	end)

	it("steps ahead 0 to 10 on the settings page and the window height follow each other", function()
		local ns = S.login()
		local SF, W = ns.StepFrame, ns.StepFrame.frame
		local slider
		for _, cat in ipairs(wow.world.settings.categories) do
			for _, i in ipairs(cat.inits) do
				if i.setting and i.setting.variable == "PATHMARK_AHEAD" then
					slider = i
				end
			end
		end
		assert.are.same({ 0, 10, 1 }, { slider.options.min, slider.options.max, slider.options.step })
		local heights = {}
		for _, n in ipairs({ 0, 1, 3, 7, 10 }) do
			_G.Settings.SetValue("PATHMARK_AHEAD", n)
			assert.are.equal(n, #SF.VisibleRows(), "steps ahead " .. n)
			heights[#heights + 1] = W.h
		end
		for i = 2, #heights do
			assert.is_true(heights[i] > heights[i - 1], "window grows with the steps ahead")
		end
	end)

	it("dragging the height shows as many steps as fit and sets steps ahead (live, then snaps)", function()
		local ns = S.login()
		local SF, W = ns.StepFrame, ns.StepFrame.frame
		for _, n in ipairs({ 1, 4, 6, 9, 10 }) do
			drag(ns, 300, heightFor(ns, n))
			assert.are.equal(n, ns.UI.Get("ahead"), "height for " .. n .. " steps")
			assert.are.equal(n, _G.Settings.GetValue("PATHMARK_AHEAD"))
			release(ns)
			assert.are.equal(n, #SF.VisibleRows())
			assert.are.equal(SF.height, W.h) -- snapped to the content
		end
		-- a few units less than a row's middle do not count it; more than ten never show
		drag(ns, 300, heightFor(ns, 5) - (SF.rowBottoms[5] - SF.rowTops[5]))
		assert.are.equal(4, ns.UI.Get("ahead"))
		drag(ns, 300, heightFor(ns, 10) + 400)
		assert.are.equal(10, ns.UI.Get("ahead"))
		release(ns)
		assert.are.equal(10, #SF.VisibleRows())
		assert.is_true(W.listBox.scrollable) -- steps 11 to 20 scroll
		-- dragged to the top: no next step
		drag(ns, 300, 10)
		release(ns)
		assert.are.equal(0, ns.UI.Get("ahead"))
		assert.is_false(shown(W.listBox))
	end)

	it("dragging from 0 steps ahead can show steps again", function()
		local ns = S.login()
		_G.Settings.SetValue("PATHMARK_AHEAD", 0)
		drag(ns, 300, 600)
		assert.are.equal(20, #ns.StepFrame.rowBottoms)
		assert.is_true(ns.UI.Get("ahead") > 0)
		release(ns)
	end)

	it("dragging the width lays the texts out at once and keeps it between 260 and 500", function()
		local ns = S.login()
		local W = ns.StepFrame.frame
		drag(ns, 420, W.h)
		assert.are.equal(420 - 33 - 12, W.step.w) -- text column follows while dragging
		release(ns)
		assert.are.equal(420, ns.UI.Get("width"))
		assert.are.equal(420, W.w)
		drag(ns, 640, W.h)
		release(ns)
		assert.are.equal(500, ns.UI.Get("width"))
		drag(ns, 120, W.h)
		release(ns)
		assert.are.equal(260, ns.UI.Get("width"))
	end)

	it("keeps the top left corner where it was and saves the position after a drag", function()
		local ns = S.login()
		local W = ns.StepFrame.frame
		W.left, W.top = 812, 640
		drag(ns, 360, W.h)
		release(ns)
		assert.are.same({ "TOPLEFT", _G.UIParent, "BOTTOMLEFT", 812, 640 }, W.points[1])
		assert.are.same({ "TOPLEFT", "BOTTOMLEFT", 812, 640 }, ns.UI.DB().pos.window)
		assert.is_nil(rawget(W, "sizingPoint"))
	end)

	it("keeps the size per account and resets it with the positions", function()
		local saved = {}
		local ns = S.login({ saved = saved })
		drag(ns, 380, heightFor(ns, 6))
		release(ns)
		assert.are.same({ 380, 6 }, { saved.ui.width, saved.ui.ahead })
		ns = S.login({ saved = saved, char = {} }) -- another character of the account
		local W = ns.StepFrame.frame
		assert.are.equal(380, W.w)
		assert.are.equal(6, #ns.StepFrame.VisibleRows())
		ns.UI.ResetPositions()
		assert.are.same({ 300, 3 }, { saved.ui.width, saved.ui.ahead })
		assert.are.equal(300, W.w)
		assert.are.equal(3, #ns.StepFrame.VisibleRows())
		assert.are.same({ -115, -266 }, { W.points[1][4], W.points[1][5] }) -- default place (ui_place_spec)
	end)

	it("cannot be sized in a fight; a fight ends a drag", function()
		local ns = S.login()
		local SF, W = ns.StepFrame, ns.StepFrame.frame
		S.combat(true)
		assert.is_false(SF.grip:IsEnabled())
		SF.grip.scripts.OnMouseDown(SF.grip, "LeftButton")
		assert.is_false(SF.StartSizing())
		assert.is_false(SF.sizing == true)
		assert.is_nil(rawget(W, "sizingPoint"))
		assert.are.same({}, wow.blocked)
		S.combat(false)
		assert.is_true(SF.grip:IsEnabled())
		assert.is_true(SF.StartSizing())
		assert.are.equal("BOTTOMRIGHT", W.sizingPoint)
		S.combat(true)
		assert.is_false(SF.sizing == true)
		assert.is_nil(rawget(W, "sizingPoint"))
		assert.are.same({}, wow.blocked)
	end)

	it("mini view hides the list and the grip; scaling stays", function()
		local ns = S.login()
		local SF, W = ns.StepFrame, ns.StepFrame.frame
		_G.Settings.SetValue("PATHMARK_SCALE", 200)
		SF.SetMini(true)
		assert.is_false(shown(SF.grip))
		assert.is_false(shown(W.listBox))
		assert.is_false(SF.StartSizing())
		SF.SetMini(false)
		assert.is_true(shown(SF.grip))
		assert.are.equal(2, W.scale)
		assert.are.equal(3, #SF.VisibleRows())
	end)

	it("a new current step scrolls the list back to its start", function()
		local ns = S.login()
		local W = ns.StepFrame.frame
		W.listBox.offset = 80
		ns.Route.Check()
		wow.advance(2)
		assert.are.equal(0, W.listBox.offset)
	end)

	it("German texts keep their umlauts at the narrowest width (T19)", function()
		local ns = S.login({ locale = "deDE", saved = { ui = { width = 260 } } })
		local SF, W = ns.StepFrame, ns.StepFrame.frame
		assert.are.equal(260, W.w)
		assert.matches("^„Wölfe an der Grenze“ annehmen", W.step.text)
		assert.matches("^Wald von Elwynn • 1/", W.title.text)
		for _, fs in ipairs({ W.step, W.detail, W.xp }) do
			assert.is_true(fs.w > 0 and fs.w <= 260 - 33, "text inside the window")
		end
		for _, row in ipairs(SF.VisibleRows()) do
			assert.are.equal(2, row.text.maxLines) -- wraps to two lines, never cut in the code
			assert.are.equal(260 - 33 - 11 - 12, row.text.w)
		end
		-- no text was cut by the code in the middle of a character: every string is valid UTF-8
		for _, fs in ipairs({ W.step, W.title, W.detail, W.xp }) do
			local t = fs.text or ""
			assert.is_nil(t:find("[\194-\244]%f[^\128-\191]"), "cut character in " .. t)
		end
	end)

	it("without Blizzard's scroll box the steps ahead still show, clipped", function()
		local ns = S.login({
			before = function()
				_G.ScrollUtil = nil
			end,
		})
		local SF, W = ns.StepFrame, ns.StepFrame.frame
		assert.is_nil(SF.bar)
		assert.are.equal(3, #SF.VisibleRows())
		assert.are.equal(SF.rowBottoms[3], W.listBox.h)
	end)
end)
