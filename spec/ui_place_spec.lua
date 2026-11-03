-- SPDX-License-Identifier: GPL-3.0-or-later
-- Default place of the step window (owner readings 16 and 17, Welle 5c tasks 13 and 16): top right,
-- where Blizzard's quest tracker stands while Braindead 4ever hides it, with a gap to the right action bars
-- (shown or not, bars 6 to 8 when they stand at the right edge) and to the minimap; left of the tracker
-- while the tracker shows. Measured from Blizzard's frames at login and after layout changes, fixed
-- values when nothing can be measured. A saved place is never overwritten.
-- The stand-ins of spec/helpers/ui.lua (U.layout) hold Blizzard's frames in Retail measures
-- (wow-ui-source live 12.1.5 and forever 1.60.1, sources there).
-- Counter-checks: the old place TOPRIGHT -80/-260 is fed to the same checks and must fail them.
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

local GAP = 10 -- the gap the window keeps (StepFrame.lua SF.GAP)
local OLD = { -80, -260 } -- the place before Welle 5c

-- Login with a screen and bars (U.layout options) and saved options.
local function login(o)
	o = o or {}
	return S.login({
		saved = o.saved,
		before = function()
			wow.layout({ screen = o.screen, bars = o.bars })
			if o.layout then
				o.layout()
			end
		end,
	})
end

local function saved(ui)
	return { ui = ui }
end

-- Rectangle in UIParent units of a frame of the layout.
local function rect(ns, name)
	local l, r, t, b = ns.UI.Rect(_G[name])
	assert.is_number(l, name)
	return { l = l, r = r, t = t, b = b, name = name }
end

-- Rectangle of the step window from its anchor (TOPRIGHT against UIParent's TOPRIGHT) and its size;
-- x, y replace the anchor's offsets (counter-checks with the old place).
local function window(ns, x, y)
	local W = ns.StepFrame.frame
	local p = W.points[1]
	assert.are.equal("TOPRIGHT", p[1])
	assert.are.equal(_G.UIParent, p[2])
	assert.are.equal("TOPRIGHT", p[3])
	local s = W:GetEffectiveScale() / _G.UIParent:GetEffectiveScale()
	local scr = wow.world.screen
	local right, top = scr.w + (x or p[4]) * s, scr.h + (y or p[5]) * s
	return { l = right - W:GetWidth() * s, r = right, t = top, b = top - W:GetHeight() * s, name = "window" }
end

local function overlaps(a, b)
	return a.l < b.r and b.l < a.r and a.b < b.t and b.b < a.t
end

-- Everything the window must stay clear of, with the gap: nil when clear, else the reason.
local function clash(ns, win, o)
	o = o or {}
	local names = { "MultiBarRight", "MultiBarLeft", "MinimapCluster" }
	for _, extra in ipairs(o.also or {}) do
		names[#names + 1] = extra
	end
	for _, name in ipairs(names) do
		local f = rect(ns, name)
		local grown = { l = f.l - GAP, r = f.r + GAP, t = f.t + GAP, b = f.b - GAP }
		if overlaps(win, grown) then
			return ("window %.0f..%.0f / %.0f..%.0f within %d of %s %.0f..%.0f / %.0f..%.0f"):format(
				win.l,
				win.r,
				win.b,
				win.t,
				GAP,
				name,
				f.l,
				f.r,
				f.b,
				f.t
			)
		end
	end
	if win.l < 0 or win.b < 0 then
		return "window leaves the screen"
	end
end

describe("Default place of the step window", function()
	for _, screen in ipairs({ "1080", "768" }) do
		for _, bars in ipairs({ 2, 1, 0 }) do
			it(
				("takes the hidden tracker's place, clear of bars and minimap (%s, %d bars shown)"):format(screen, bars),
				function()
					local ns = login({ screen = screen, bars = bars })
					assert.are.equal("hide", ns.UI.Get("tracker"))
					local win = window(ns)
					assert.is_nil(clash(ns, win))
					-- where the tracker stands with both right bars shown: its right edge, its column
					local scr = wow.world.screen
					assert.is_true(win.r <= scr.w - 105 - GAP, "room for both right bars, shown or not")
					assert.is_true(win.r >= scr.w - 105 - 260, "in the tracker's column")
					assert.is_true(win.t <= rect(ns, "MinimapCluster").b - GAP, "below the minimap")
					assert.is_true(win.t >= scr.h - 300, "at the top")
				end
			)
		end

		it(("moves left of Blizzard's tracker while the tracker shows (%s)"):format(screen), function()
			for _, mode in ipairs({ "route", "keep" }) do
				local ns = login({ screen = screen, saved = saved({ tracker = mode, rev = 1 }) })
				local win = window(ns)
				assert.is_nil(clash(ns, win, { also = { "ObjectiveTrackerFrame" } }), mode)
				local tracker = rect(ns, "ObjectiveTrackerFrame")
				assert.are.equal(tracker.l - GAP, win.r, mode)
			end
		end)

		it(("counter-check: the old place lies on Blizzard's tracker (%s)"):format(screen), function()
			local ns = login({ screen = screen, saved = saved({ tracker = "route", rev = 1 }) })
			local old = window(ns, OLD[1], OLD[2])
			assert.is_true(overlaps(old, rect(ns, "ObjectiveTrackerFrame")))
			assert.is_not_nil(clash(ns, old, { also = { "ObjectiveTrackerFrame" } }))
		end)
	end

	-- On the 768 screen the scaled bars end 0.2 units right of the old place; the owner saw the clash
	-- on a larger screen, the 1080 one shows it.
	it("counter-check: the old place reaches into the right bars (1080)", function()
		local ns = login()
		assert.matches("MultiBarLeft", clash(ns, window(ns, OLD[1], OLD[2])) or "")
	end)

	it("follows the option: hidden, then shown, then hidden again", function()
		local ns = login()
		local hidden = window(ns)
		ns.UI.Set("tracker", "route")
		local shown = window(ns)
		assert.is_true(shown.r <= rect(ns, "ObjectiveTrackerFrame").l - GAP)
		ns.UI.Set("tracker", "hide")
		assert.are.same(hidden, window(ns))
	end)

	it("stands beside the tracker while the first start is open, then takes its place", function()
		local ns = S.login({
			setup = false,
			before = function()
				wow.layout({})
			end,
		})
		wow.advance(2)
		assert.is_true(rawget(_G.BraindeadForeverSetupFrame, "shown"))
		assert.are.equal(1, _G.ObjectiveTrackerFrame:GetAlpha()) -- the option starts after the first start
		assert.is_nil(clash(ns, window(ns), { also = { "ObjectiveTrackerFrame" } }))
		_G.BraindeadForeverSetupFrame.CloseButton:Click()
		wow.advance(1)
		assert.are.equal(0, _G.ObjectiveTrackerFrame.alpha)
		local win = window(ns)
		assert.is_true(win.r > rect(ns, "ObjectiveTrackerFrame").l, "in the tracker's place")
		assert.is_nil(clash(ns, win))
	end)

	it("moves left of the tracker when the module that hides it turns off", function()
		local ns = login()
		ns.Modules.Disable("questwatch", "test")
		wow.advance(1)
		assert.are.equal(1, _G.ObjectiveTrackerFrame.alpha)
		assert.is_nil(clash(ns, window(ns), { also = { "ObjectiveTrackerFrame" } }))
	end)

	it("stays clear at window scale 150 % and width 400, also beside the tracker", function()
		for _, screen in ipairs({ "1080", "768" }) do
			for _, mode in ipairs({ "hide", "route" }) do
				local ns =
					login({ screen = screen, saved = saved({ tracker = mode, rev = 1, scale = 150, width = 400 }) })
				local W = ns.StepFrame.frame
				assert.are.equal(1.5, W:GetEffectiveScale())
				local also = mode == "route" and { "ObjectiveTrackerFrame" } or nil
				assert.is_nil(clash(ns, window(ns), { also = also }), screen .. " " .. mode)
			end
		end
	end)

	it("keeps clear of a bar 6 to 8 that stands at the right edge, not of one in the middle", function()
		local ns = login({
			layout = function()
				local f = _G.MultiBar5 -- one vertical column left of MultiBarLeft (1820)
				f.left, f.right, f.top, f.bottom = 1770, 1815, 700, 200
			end,
		})
		local win = window(ns)
		assert.is_nil(clash(ns, win, { also = { "MultiBar5" } }))
		assert.are.equal(1770 - GAP, win.r)
		-- bars 6 and 7 stand in the middle of the screen (Blizzard's default): no effect
		assert.is_true(rect(ns, "MultiBar6").r < win.l)
	end)

	it("stays below a minimap that stands lower, and at Blizzard's top line when the minimap moved away", function()
		local ns = login({
			layout = function()
				local m = _G.MinimapCluster
				m.top, m.bottom = 1080, 760 -- taller header
			end,
		})
		assert.are.equal(760 - GAP, window(ns).t)
		ns = login({
			layout = function()
				local m = _G.MinimapCluster
				m.left, m.right, m.top, m.bottom = 0, 256, 256, 0 -- bottom left
			end,
		})
		assert.are.equal(1080 - 260, window(ns).t) -- RIGHT_CONTAINER_OFFSET_Y
	end)

	it("falls back to fixed values when Blizzard's frames cannot be measured", function()
		local ns = login({
			layout = function()
				for _, name in ipairs({ "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7" }) do
					_G[name] = nil
				end
				_G.MinimapCluster = nil
			end,
		})
		local p = ns.StepFrame.frame.points[1]
		assert.are.same({ -115, -266 }, { p[4], p[5] })
		-- UIParent without a size yet (or secret): the same fixed place
		_G.UIParent.right = wow.SECRET
		assert.are.same({ "TOPRIGHT", -115, -266 }, ns.StepFrame.DefaultPoint())
		_G.UIParent.right = nil
		_G.UIParent.GetRight = function()
			return nil
		end
		assert.are.same({ "TOPRIGHT", -115, -266 }, ns.StepFrame.DefaultPoint())
		_G.UIParent.GetRight = nil
	end)

	it("the fixed values clear the bars and the minimap of a 1080 screen", function()
		local ns = login()
		local fixed = window(ns, -115, -266)
		assert.is_nil(clash(ns, fixed))
	end)

	it("is computed again at login and after Blizzard's layout changes, one frame later", function()
		local ns = login()
		local W = ns.StepFrame.frame
		local function anchor()
			return { W.points[1][4], W.points[1][5] }
		end
		-- the player drags bar 6 to the right edge in Edit Mode, and back
		local function edge(on)
			local f = _G.MultiBar5
			if on then
				f.left, f.right, f.top, f.bottom = 1770, 1815, 700, 200
			else
				wow.layout({})
			end
		end
		local before = anchor()
		edge(true)
		wow.fire("EDIT_MODE_LAYOUTS_UPDATED", {}, false)
		assert.are.same(before, anchor()) -- Blizzard lays out its bars in its handler of the same event
		wow.advance(0)
		local after = anchor()
		assert.are.same({ 1760 - 1920, before[2] }, after)
		assert.is_nil(clash(ns, window(ns), { also = { "MultiBar5" } }))
		for _, event in ipairs({ "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED", "PLAYER_ENTERING_WORLD" }) do
			edge(false)
			wow.fire(event)
			wow.advance(0)
			assert.are.same(before, anchor(), event)
			edge(true)
			wow.fire(event)
			wow.advance(0)
			assert.are.same(after, anchor(), event)
		end
	end)

	it("waits for the end of a fight to move", function()
		local ns = login()
		local before = window(ns)
		S.combat(true)
		ns.UI.Set("tracker", "route")
		assert.are.same(before, window(ns))
		S.combat(false)
		assert.is_true(window(ns).r <= rect(ns, "ObjectiveTrackerFrame").l - GAP)
	end)

	it("never overwrites a saved place", function()
		local pos = { "TOPLEFT", "BOTTOMLEFT", 40, 600 }
		local ns = login({ saved = saved({ pos = { window = { pos[1], pos[2], pos[3], pos[4] } } }) })
		local W = ns.StepFrame.frame
		local function at()
			assert.are.same({ "TOPLEFT", _G.UIParent, "BOTTOMLEFT", 40, 600 }, W.points[1])
			assert.are.same(pos, ns.UI.DB().pos.window)
		end
		at()
		for _, mode in ipairs({ "route", "keep", "hide" }) do
			ns.UI.Set("tracker", mode)
			at()
		end
		ns.UI.Set("scale", 150)
		ns.UI.Set("width", 400)
		for _, event in ipairs({
			"EDIT_MODE_LAYOUTS_UPDATED",
			"DISPLAY_SIZE_CHANGED",
			"UI_SCALE_CHANGED",
			"PLAYER_ENTERING_WORLD",
		}) do
			wow.fire(event)
			wow.advance(0)
			at()
		end
		_G.EventRegistry:TriggerEvent("EditMode.Enter")
		_G.EventRegistry:TriggerEvent("EditMode.Exit")
		at()
		-- "Reset" is the player's own choice: back to the default
		ns.UI.ResetPositions()
		assert.is_nil(ns.UI.DB().pos)
		assert.are.equal("TOPRIGHT", W.points[1][1])
	end)
end)

describe("Default of Blizzard's quest tracker (migration)", function()
	it("gives the new default to whoever kept the old one, and keeps every choice", function()
		local cases = {
			{ saved = nil, want = "hide" }, -- new player
			{ saved = { tracker = "route" }, want = "hide" }, -- old default, filled in by UI.DB before Welle 5c
			{ saved = { tracker = "keep" }, want = "keep" }, -- chosen
			{ saved = { tracker = "hide" }, want = "hide" }, -- chosen
			{ saved = { tracker = "route", rev = 1 }, want = "route" }, -- chosen after Welle 5c
		}
		for i, c in ipairs(cases) do
			local ns = login({ saved = c.saved and saved(c.saved) })
			assert.are.equal(c.want, ns.UI.Get("tracker"), "case " .. i)
			assert.are.equal(ns.UI.REV, ns.UI.DB().rev, "case " .. i)
		end
	end)

	-- Welle 5d, M1: background opacity 35 % left the text at about 3:1 over a bright sky; 70 % is the new
	-- default. Who kept 35 gets it, any other value is a choice and stays.
	it("lifts the old background opacity 35 % to 70 % and keeps a chosen one", function()
		for i, c in ipairs({
			{ saved = nil, want = 70 },
			{ saved = { bgAlpha = 35 }, want = 70 },
			{ saved = { bgAlpha = 35, rev = 1 }, want = 70 },
			{ saved = { bgAlpha = 50, rev = 1 }, want = 50 },
			{ saved = { bgAlpha = 35, rev = 2 }, want = 35 }, -- chosen after Welle 5d
		}) do
			local ns = login({ saved = c.saved and saved(c.saved) })
			assert.are.equal(c.want, ns.UI.Get("bgAlpha"), "case " .. i)
			assert.are.equal(2, ns.UI.DB().rev, "case " .. i)
		end
	end)

	it("leaves positions, size and every other option alone", function()
		local ui = {
			tracker = "route",
			pos = { window = { "TOPLEFT", "BOTTOMLEFT", 40, 600 }, arrow = { "CENTER", "CENTER", 0, 120 } },
			width = 420,
			ahead = 5,
			scale = 125,
			sound = false,
		}
		local ns = login({ saved = saved(ui) })
		local db = ns.UI.DB()
		assert.are.same({ "TOPLEFT", "BOTTOMLEFT", 40, 600 }, db.pos.window)
		assert.are.same({ "CENTER", "CENTER", 0, 120 }, db.pos.arrow)
		assert.are.same({ 420, 5, 125, false }, { db.width, db.ahead, db.scale, db.sound })
		assert.are.equal("hide", db.tracker)
	end)

	it("runs once: a later choice of the old default stays", function()
		local db = { ui = { tracker = "route" } }
		local ns = login({ saved = db })
		assert.are.equal("hide", ns.UI.Get("tracker"))
		ns.UI.Set("tracker", "route")
		ns = login({ saved = db })
		assert.are.equal("route", ns.UI.Get("tracker"))
	end)

	it("counter-check: without the revision a chosen 'only quests of the route' would be lost", function()
		local ns = login({ saved = saved({ tracker = "route", rev = 1 }) })
		local t = { tracker = "route" } -- the same choice without the revision mark
		ns.UI.Migrate(t)
		assert.is_nil(t.tracker)
		t = { tracker = "route", rev = 1 }
		ns.UI.Migrate(t)
		assert.are.equal("route", t.tracker)
	end)
end)
