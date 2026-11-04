-- SPDX-License-Identifier: GPL-3.0-or-later
-- Design v2, view 2 "Pfeil und Karte": arrow colors along the course deviation (green up to 20 degrees,
-- yellow at 90, red from 135 with "behind you"; blue, white, orange in Blizzard's colorblind mode,
-- decision PF-1101), black outline, distance text at most five times per second, arrival at 12 yd,
-- no arrow in instances or on another continent, Blizzard navigation, world map and minimap pins,
-- positioning in Edit Mode.
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

local function arrow(ns)
	return ns.Arrow.frame
end

local function goal(ns)
	return ns.Nav.Target(ns.Route.Current())
end

-- Runs n frames of the arrow (60 per second).
local function frames(ns, n)
	for _ = 1, n do
		ns.Arrow.Update(1 / 60)
	end
end

local function near(a, b)
	return math.abs(a - b) < 1e-6
end

describe("Arrow", function()
	it("points to the current goal with its own sharp arrow in a 64x64 square and a black outline", function()
		local ns = S.login()
		local F = arrow(ns)
		assert.is_true(rawget(F, "shown"))
		assert.are.same({ "TOP", -140 }, { F.points[1][1], F.points[1][5] })
		-- Blizzard's atlas was 22x18 drawn at 44x36 and stepped at the edges (screenshot round 3)
		assert.are.equal("Interface\\AddOns\\Braindead4Ever\\Media\\arrow", F.tex.file)
		assert.is_nil(rawget(F.tex, "atlas"))
		assert.are.same({ 64, 64 }, { F.w, F.h }) -- square: turning does not stretch it
		assert.are.equal("Interface\\AddOns\\Braindead4Ever\\Media\\arrow-outline", F.outline.file)
		assert.are.same({ 0, 0, 0, 1 }, F.outline.vertex)
		assert.is_false(F.mouse) -- not clickable outside Edit Mode
		assert.are.equal("Accept “Wolves Across the Border”", F.title.text)
		assert.are.equal(1, F.title.maxLines)
		assert.are.equal(220, F.title.w)
	end)

	it("colors by course deviation like TomTom: green, yellow, red with “behind you”", function()
		local ns = S.login()
		local F = arrow(ns)
		local t = goal(ns)
		local cases = {
			{ 0, { 0, 1, 0 }, "" },
			{ 20, { 0, 1, 0 }, "" },
			{ 90, { 1, 1, 0 }, "" },
			{ 134, nil, "" },
			{ 135, { 1, 0, 0 }, "behind you" },
			{ 160, { 1, 0, 0 }, "behind you" },
			{ -160, { 1, 0, 0 }, "behind you" },
		}
		for _, c in ipairs(cases) do
			S.face(ns, t, c[1])
			frames(ns, 15)
			if c[2] then
				for i = 1, 3 do
					assert.is_true(near(F.tex.vertex[i], c[2][i]), ("deviation %d channel %d"):format(c[1], i))
				end
			end
			assert.are.equal(c[3], F.hint.text, "hint at " .. c[1])
		end
		-- halfway between 20 and 90 degrees: halfway from green to yellow
		S.face(ns, t, 55)
		frames(ns, 15)
		assert.is_true(near(F.tex.vertex[1], 0.5) and near(F.tex.vertex[2], 1) and near(F.tex.vertex[3], 0))
		-- rotation is the relative angle (counterclockwise)
		assert.is_true(near(F.tex.rotation, math.rad(55)))
	end)

	it("uses blue, white and orange in Blizzard's colorblind mode", function()
		local ns = S.login({
			before = function(W)
				W.cvars.colorblindMode = "1"
			end,
		})
		local F = arrow(ns)
		local t = goal(ns)
		for _, c in ipairs({ { 5, { 0.2, 0.6, 1 } }, { 90, { 1, 1, 1 } }, { 170, { 1, 0.5, 0 } } }) do
			S.face(ns, t, c[1])
			frames(ns, 15)
			for i = 1, 3 do
				assert.is_true(near(F.tex.vertex[i], c[2][i]))
			end
		end
	end)

	-- Welle 5d, M10: on screen the colorblind arrow was dark green at 5 degrees and gold at 90, because
	-- the gold atlas multiplied the vertex color. What the client draws must be the palette itself.
	it("draws blue, white and orange on screen, not the gold atlas tinted (M10)", function()
		local ns = S.login({
			before = function(W)
				W.cvars.colorblindMode = "1"
			end,
		})
		local F = arrow(ns)
		local t = goal(ns)
		assert.is_nil(rawget(F, "lift")) -- the white texture needs no additive copy (0.9.1)
		local function drawn(deg)
			S.face(ns, t, deg)
			frames(ns, 15)
			assert.are.equal(F.tex.rotation, F.outline.rotation)
			return S.drawnArrow(F)
		end
		local blue = drawn(5)
		assert.is_true(blue[3] >= 0.9 and blue[3] > blue[2] + 0.2 and blue[3] > blue[1] + 0.5, "blue")
		local white = drawn(90)
		assert.is_true(white[1] >= 0.9 and white[2] >= 0.9 and white[3] >= 0.9, "white")
		local orange = drawn(170)
		assert.is_true(orange[1] >= 0.9 and orange[2] > 0.35 and orange[2] < 0.7 and orange[3] < 0.1, "orange")
		-- the normal palette too: green, yellow, red at full strength
		ns.Arrow.colorblind = false
		local green, yellow, red = drawn(0), drawn(90), drawn(160)
		assert.is_true(green[2] >= 0.9 and green[1] < 0.1, "green")
		assert.is_true(yellow[1] >= 0.9 and yellow[2] >= 0.9 and yellow[3] < 0.1, "yellow")
		assert.is_true(red[1] >= 0.9 and red[2] < 0.1, "red")
		-- arrival: Blizzard's check in its own colors and at its old size, without the outline
		S.place(t.wx + 8, t.wy)
		frames(ns, 4)
		assert.are.equal("UI-QuestTracker-Tracker-Check", F.tex.atlas)
		assert.are.same({ 36, 36 }, { F.tex.w, F.tex.h })
		assert.is_false(rawget(F.outline, "shown"))
		-- away again: back to the arrow
		S.place(t.wx + 200, t.wy)
		frames(ns, 4)
		assert.are.equal("Interface\\AddOns\\Braindead4Ever\\Media\\arrow", F.tex.file)
	end)

	-- Welle 5d, M3: the goal and the distance stood at 1.6:1 to 1.8:1 against a bright sky with a 1 px
	-- shadow. Blizzard's outline fonts put a black edge around every glyph.
	it("writes goal, distance and “behind you” in Blizzard's outline fonts (M3)", function()
		local ns = S.login()
		local F = arrow(ns)
		assert.are.equal("GameFontHighlightOutline", F.title.template)
		assert.are.equal("GameFontNormalOutline", F.dist.template)
		assert.are.equal("GameFontNormalOutline", F.hint.template)
	end)

	-- Welle 5d, M12: Blizzard's dialogs stand at the top center like the arrow; its text showed through.
	it("hides while one of Blizzard's dialogs is open (M12)", function()
		local ns = S.login()
		local F = arrow(ns)
		frames(ns, 4)
		assert.are.equal(1, F.alpha)
		ns.StepFrame.AskSkip()
		assert.is_truthy(wow.popup)
		frames(ns, 4)
		assert.are.equal(0, F.alpha)
		_G.StaticPopup_Hide(wow.popup.which)
		frames(ns, 4)
		assert.are.equal(1, F.alpha)
	end)

	it("shows the distance with Blizzard's format, at most five times per second", function()
		local ns = S.login()
		local F = arrow(ns)
		frames(ns, 1)
		assert.are.equal("70 |4yd:yds", F.dist.text)
		local sets = 0
		local set = F.SetText
		F.dist.SetText = function(self, v)
			sets = sets + 1
			set(self, v)
		end
		for i = 1, 60 do -- one second while walking: the number changes every frame
			S.place(-136.5, -8933.5 + i * 0.5)
			ns.Arrow.Update(1 / 60)
		end
		assert.is_true(sets <= 5, "distance text set " .. sets .. " times in one second")
		assert.is_true(sets >= 4)
	end)

	it("arrives at 12 yd: check, “Reached destination”, gone after one second", function()
		local ns = S.login()
		local F = arrow(ns)
		local t = goal(ns)
		S.place(t.wx + 8, t.wy)
		frames(ns, 4)
		assert.are.equal("UI-QuestTracker-Tracker-Check", F.tex.atlas)
		assert.are.equal("Reached destination", F.dist.text)
		assert.is_false(rawget(F.outline, "shown"))
		wow.advance(1)
		frames(ns, 1)
		assert.are.equal(0, F.tex.alpha)
	end)

	it("shows goal and distance again for the next goal after an arrival (screenshot round 3)", function()
		local ns = S.login()
		local F = arrow(ns)
		local t = goal(ns)
		S.place(t.wx + 8, t.wy)
		frames(ns, 4)
		wow.advance(1)
		frames(ns, 1)
		assert.are.equal(0, F.title:GetAlpha())
		ns.Arrow.SetExtra({ map = t.map, wx = t.wx + 200, wy = t.wy, inst = t.inst, title = "Next goal" })
		frames(ns, 30)
		assert.are.equal("Next goal", F.title.text)
		assert.are.equal(1, F.title:GetAlpha())
		assert.are.equal(1, F.dist:GetAlpha())
		assert.are.equal(1, F.tex:GetAlpha())
		assert.matches("%d", F.dist.text)
	end)

	it("arrival distance follows the setting (5 to 30 yd)", function()
		local ns = S.login()
		ns.UI.Set("arrival", 5)
		local t = goal(ns)
		S.place(t.wx + 8, t.wy)
		frames(ns, 4)
		assert.are.equal("Interface\\AddOns\\Braindead4Ever\\Media\\arrow", arrow(ns).tex.file)
	end)

	it("has no arrow in instances or on another continent; the step window says why", function()
		local ns = S.login()
		local F = arrow(ns)
		wow.world.player.north = nil -- UnitPosition is nil in instances
		frames(ns, 4)
		ns.StepFrame.Tick(1)
		assert.are.equal(0, F.tex.alpha)
		assert.are.equal("No arrow inside instances", ns.StepFrame.frame.status.text)
		S.place(-136.5, -8933.5, 1)
		frames(ns, 4)
		ns.StepFrame.Tick(1)
		assert.are.equal(0, F.tex.alpha)
		assert.are.equal("No arrow: the goal is on another continent", ns.StepFrame.frame.status.text)
	end)

	it("hides for “show arrow” off, a paused guidance and Blizzard navigation", function()
		local ns = S.login()
		local F = arrow(ns)
		ns.UI.Set("arrow", false)
		assert.is_false(rawget(F, "shown"))
		ns.UI.Set("arrow", true)
		assert.is_true(rawget(F, "shown"))
		ns.UI.SetPaused(true)
		assert.is_false(rawget(F, "shown"))
		ns.UI.SetPaused(false)
		-- Blizzard navigation: Forever's default of showInGameNavigation is "0" (chapter 18 §1.2)
		ns.UI.Set("blizzNav", true)
		assert.is_true(rawget(F, "shown"))
		assert.is_table(wow.world.waypoint) -- Blizzard's marker gets the goal
		assert.are.equal(1429, wow.world.waypoint.uiMapID)
		assert.is_true(wow.world.supertrack)
		wow.world.cvars.showInGameNavigation = "1"
		wow.fire("CVAR_UPDATE", "showInGameNavigation", "1")
		assert.is_false(rawget(F, "shown"))
		ns.UI.Set("blizzNav", false)
		assert.is_nil(wow.world.waypoint) -- our waypoint is removed again
	end)

	it("never touches the player's own waypoint without Blizzard navigation", function()
		S.login()
		assert.is_nil(wow.world.waypoint)
		assert.is_nil(wow.world.supertrack)
	end)
end)

describe("Map pins", function()
	local function pins()
		local out = {}
		for _, p in ipairs(_G.WorldMapFrame.pins) do
			out[#out + 1] = p
		end
		return out
	end

	it("marks the goal with Blizzard's waypoint pin, givers and turn-ins with the quest symbols", function()
		S.login()
		local list = pins()
		assert.is_true(#list >= 2)
		local goalPin = list[1]
		assert.are.equal("pin", goalPin.kind)
		assert.are.equal("Waypoint-MapPin-Tracked", goalPin.Icon.atlas)
		assert.is_true(goalPin.x > 0 and goalPin.x < 1 and goalPin.y > 0 and goalPin.y < 1)
		local atlases = {}
		for _, p in ipairs(list) do
			atlases[p.Icon.atlas] = true
		end
		assert.is_true(atlases.QuestNormal)
		assert.is_true(atlases.QuestTurnin)
		-- only Blizzard's own symbols (owner reading point 7)
		for name in pairs(atlases) do
			assert.is_truthy(({ ["Waypoint-MapPin-Tracked"] = 1, QuestNormal = 1, QuestTurnin = 1 })[name], name)
		end
	end)

	it("follows the setting and the pause", function()
		local ns = S.login()
		ns.UI.Set("pins", false)
		assert.are.equal(0, #pins())
		ns.UI.Set("pins", true)
		assert.is_true(#pins() > 0)
		ns.UI.SetPaused(true)
		assert.are.equal(0, #pins())
	end)

	it("shows the minimap pin only on request and only with map pins on", function()
		local ns = S.login()
		local mini = ns.MapPins.mini
		assert.is_false(rawget(mini, "shown")) -- off by default (scope "Standard")
		ns.UI.Set("minipins", true)
		assert.is_true(rawget(mini, "shown"))
		assert.are.equal("Waypoint-MapPin-Minimap-Tracked", mini.tex.atlas)
		mini.scripts.OnUpdate(mini, 1)
		local _, _, _, x, y = mini:GetPoint(1)
		-- goal lies north-east of the player: right and up on a north-up minimap
		assert.is_true(x > 0 and y > 0)
		ns.UI.Set("pins", false)
		assert.is_false(rawget(mini, "shown"))
	end)
end)

describe("Positions in Edit Mode", function()
	it("makes window and arrow movable while Blizzard's Edit Mode is open and saves the place", function()
		local ns = S.login()
		local W, F = ns.StepFrame.frame, arrow(ns)
		_G.EventRegistry:TriggerEvent("EditMode.Enter")
		assert.is_true(W.movable and F.movable)
		assert.is_true(F.mouse)
		assert.is_true(rawget(ns.UI.movers.window.overlay, "shown"))
		W.scripts.OnDragStart(W)
		assert.is_true(W.moving)
		S.drop(W, 100, 1030)
		W.scripts.OnDragStop(W)
		assert.are.same({ "TOPLEFT", "TOPLEFT", 100, -50 }, ns.UI.DB().pos.window)
		_G.EventRegistry:TriggerEvent("EditMode.Exit")
		assert.is_false(F.mouse) -- click-free again (P7)
		F.scripts.OnDragStart(F)
		assert.is_falsy(rawget(F, "moving")) -- without Shift the arrow stays where it is
		assert.is_false(rawget(ns.UI.movers.window.overlay, "shown"))
		ns.UI.ResetPositions()
		assert.are.equal("TOPRIGHT", W.points[1][1])
	end)

	it("cannot be dragged by its body outside Edit Mode (the header band: spec/ui_place_spec.lua)", function()
		local ns = S.login()
		local W = ns.StepFrame.frame
		W.scripts.OnDragStart(W)
		assert.is_nil(rawget(W, "moving"))
	end)
end)
