-- SPDX-License-Identifier: GPL-3.0-or-later
-- Hint levels 1 and 2 in the interface (Welle 5b task 11; design v2 view 4) against the real discovery
-- logic of Welle 4 and the real catalog (ATT finds of Elwynn Forest): the riddle of the zone as its own
-- line in the step window in the look of the rumor line, and the area of a find as a circle of
-- Blizzard's atlases on the world map with the tooltip "Area".
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

local function riddle(ns)
	local W = ns.StepFrame.frame
	return rawget(W.riddle, "shown") and W.riddle.text or nil
end

local function areas()
	local out = {}
	for _, p in ipairs(_G.WorldMapFrame.pins) do
		if p.kind == "area" then
			out[#out + 1] = p
		end
	end
	return out
end

describe("Hint levels in the interface", function()
	describe("level 1: riddle line", function()
		it("shows the first riddle of the player's zone in gold above the current step", function()
			local ns = S.login({ style = "hints" })
			local W = ns.StepFrame.frame
			assert.are.equal(1, ns.Explore.Level())
			assert.are.equal("Hint: A book waits to be read in the south of Elwynn Forest.", riddle(ns))
			assert.are.same({ 1, 0.82, 0 }, W.riddle.textColor)
			assert.are.same(W.banner.font, W.riddle.font) -- same look as the rumor line
			local _, _, _, _, ry = W.riddle:GetPoint(1)
			local _, _, _, _, sy = W.step:GetPoint(1)
			assert.is_true(-ry < -sy, "riddle above the current step")
		end)

		it("goes after the next completed step and the next riddle of the zone follows", function()
			local ns = S.login({ style = "hints" })
			local first = riddle(ns)
			ns.StepFrame.frame.box:Click()
			wow.advance(1)
			assert.is_string(riddle(ns))
			assert.are_not.equal(first, riddle(ns))
			assert.matches("^Hint: A rare creature roams in the south%-west of Elwynn Forest%.$", riddle(ns))
		end)

		it("stands next to a rumor, as its own line", function()
			local ns = S.login({ style = "hints" })
			ns.Explore.Heard({ kind = "r", n = 5, 62, "r", 1429, 4231, 6512 }, false)
			wow.advance(0.3)
			local W = ns.StepFrame.frame
			assert.matches("^Rumor: ", W.banner.text)
			assert.is_string(riddle(ns))
		end)

		it("speaks German", function()
			local ns = S.login({ style = "hints", locale = "deDE" })
			assert.matches("^Hinweis: ", riddle(ns))
			assert.matches("Wald von Elwynn", riddle(ns), 1, true)
		end)

		it(
			"is not there with “just follow the arrow”, at level 0 or 2, in the mini view or with an open question",
			function()
				local ns = S.login({ style = "arrow" })
				assert.is_nil(riddle(ns))
				ns = S.login({ saved = { ui = { style = "self", hint = 0 } } })
				assert.are.equal(0, ns.Explore.Level())
				assert.is_nil(riddle(ns))
				ns = S.login({ style = "hints" })
				_G.Settings.SetValue("PATHMARK_HINT", 2)
				ns.StepFrame.View().riddleShown = nil
				ns.StepFrame.Refresh()
				assert.is_nil(riddle(ns))
				_G.Settings.SetValue("PATHMARK_HINT", 1)
				ns.StepFrame.SetMini(true)
				assert.are.equal(0, ns.StepFrame.frame.riddle.alpha)
				ns.StepFrame.SetMini(false)
				ns.Route.Pending = function()
					return 33
				end
				ns.StepFrame.Refresh()
				assert.is_nil(riddle(ns))
			end
		)

		it("brings no new riddle in a fight", function()
			local ns = S.login({ saved = { ui = { style = "self", hint = 0 } } })
			S.combat(true)
			_G.Settings.SetValue("PATHMARK_HINT", 1)
			assert.is_nil(riddle(ns))
			S.combat(false)
			ns.StepFrame.Refresh()
			assert.is_string(riddle(ns))
		end)
	end)

	describe("level 2: area on the world map", function()
		it("draws the area of every find as a circle of Blizzard's atlases, sized in map units", function()
			local ns = S.login({ style = "hints" })
			_G.Settings.SetValue("PATHMARK_HINT", 2)
			wow.advance(0.3)
			local list = areas()
			assert.are.equal(9, #list)
			local items = {}
			for _, item in ipairs(ns.Connect.MapItems(1429)) do
				if item.kind == "area" then
					items[#items + 1] = item
				end
			end
			local p, item = list[1], items[1]
			assert.are.equal("UI-prey-Scoutingmap-ring", p.Icon.atlas)
			assert.are.equal("common-mask-circle", p.Fill.atlas)
			assert.are.same({ 1, 0.82, 0 }, { p.Fill.vertex[1], p.Fill.vertex[2], p.Fill.vertex[3] })
			assert.are.equal(0.18, p.Fill.alpha)
			assert.is_true(p.ignoreGlobalPinScale) -- the circle scales with the terrain
			assert.are.equal(1, p.scale)
			assert.are.same({ item.x, item.y }, { p.x, p.y })
			assert.is_true(math.abs(p.w - 1002 * item.rx * 2) < 0.01)
			assert.is_true(math.abs(p.h - 668 * item.ry * 2) < 0.01)
			assert.is_true(p.w > 10 and p.w < 200, "a circle of about 100 yards, not the whole map")
		end)

		it("names the find in the tooltip like design v2 and lets clicks through to the map", function()
			local ns = S.login({ style = "hints" })
			_G.Settings.SetValue("PATHMARK_HINT", 2)
			wow.advance(0.3)
			local p = areas()[1]
			assert.is_true(p.motion)
			assert.is_false(p.clicks)
			p.scripts.OnEnter(p)
			assert.are.same({ "Area", "A book lies within the marked circle." }, wow.world.tooltip.lines)
			assert.is_truthy(ns)
		end)

		it("speaks German", function()
			S.login({ style = "hints", locale = "deDE" })
			_G.Settings.SetValue("PATHMARK_HINT", 2)
			wow.advance(0.3)
			local p = areas()[1]
			p.scripts.OnEnter(p)
			assert.are.same({ "Bereich", "Ein Buch liegt im markierten Kreis." }, wow.world.tooltip.lines)
		end)

		it("is gone at level 1 and 3; level 3 shows points instead", function()
			S.login({ style = "hints" })
			assert.are.equal(0, #areas())
			_G.Settings.SetValue("PATHMARK_HINT", 3)
			wow.advance(0.3)
			assert.are.equal(0, #areas())
			local points = 0
			for _, p in ipairs(_G.WorldMapFrame.pins) do
				points = points + (p.kind == "pin" and 1 or 0)
			end
			assert.is_true(points >= 9)
		end)
	end)

	it("developer preview: riddle and area", function()
		local ns = S.login({ style = "hints", probe = true })
		SlashCmdList.PATHMARK("preview riddle")
		assert.are.equal("Hint: A book waits to be read in the south of Elwynn Forest.", riddle(ns))
		SlashCmdList.PATHMARK("preview area")
		local list = areas()
		assert.are.equal(1, #list)
		list[1].scripts.OnEnter(list[1])
		assert.are.same({ "Area", "A book lies within the marked circle." }, wow.world.tooltip.lines)
		SlashCmdList.PATHMARK("preview off")
		assert.are.same({}, wow.errors)
	end)
end)
