-- SPDX-License-Identifier: GPL-3.0-or-later
-- Design v2, view 5 "Einstellungen" and the rules of brain chapter 18 §7.3 (E1 to E7): Blizzard's
-- settings panel with vertical lists, main page with four options and two buttons, sub pages Play
-- style, Display, Arrow and Map, Accessibility and Credits; one-sentence tooltips, positive labels,
-- greyed-out dependent options, immediate effect. Also view 6 (fonts: Blizzard's Friz Quadrata through
-- font object copies, no font of our own) and task 5 (size 75 to 200 %, Blizzard's text size).
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

local function categories()
	return wow.world.settings.categories
end

local function byName(name)
	for _, c in ipairs(categories()) do
		if c.name == name then
			return c
		end
	end
end

local function init(cat, variable)
	for _, i in ipairs(cat.inits) do
		if i.setting and i.setting.variable == variable then
			return i
		end
	end
end

-- Every option and button of every page, with its label and tooltip.
local function options()
	local out = {}
	for _, c in ipairs(categories()) do
		for _, i in ipairs(c.inits) do
			if i.kind ~= "header" then
				out[#out + 1] = { label = i.setting and i.setting.name or i.name, tip = i.tooltip, kind = i.kind }
			end
		end
	end
	return out
end

-- One sentence: no sentence end before the last character (abbreviations like "bzw." excepted).
local function sentences(text)
	local t = text:gsub("bzw%.", "bzw"):gsub("z%. B%.", "zB")
	local n = 0
	for _ in t:gmatch("[%.!?]%s") do
		n = n + 1
	end
	return n + 1
end

describe("Settings", function()
	it("register one category with five sub pages as vertical lists, Credits as canvas", function()
		S.login()
		local main = byName("Pathmark")
		assert.is_true(main.registered)
		local subs = {}
		for _, c in ipairs(categories()) do
			if c.parent == main then
				subs[#subs + 1] = c.name .. (c.canvas and " (canvas)" or "")
			end
		end
		assert.are.same({ "Play style", "Display", "Arrow and Map", "Accessibility", "Credits (canvas)" }, subs)
	end)

	it("main page: four options and two buttons (rule E1)", function()
		S.login()
		local kinds = {}
		for _, i in ipairs(byName("Pathmark").inits) do
			kinds[#kinds + 1] = i.kind .. ":" .. (i.setting and i.setting.key or i.name)
		end
		assert.are.same({
			"header:Basics",
			"dropdown:scope",
			"checkbox:arrow",
			"slider:scale",
			"checkbox:sound",
			"header:Setup",
			"button:Setup",
			"button:Windows",
		}, kinds)
	end)

	it("start with the design's defaults", function()
		local ns = S.login({ setup = false })
		local expect = {
			scope = "standard",
			arrow = true,
			scale = 100,
			sound = true,
			ahead = 3,
			bgAlpha = 70,
			dim = true,
			arrival = 12,
			pins = true,
			minipins = false,
			blizzNav = false,
			mmButton = true,
			textSize = true,
			style = "hints",
			hint = 1,
			tracker = "hide", -- owner reading 16
			lock = false,
		}
		for key, value in pairs(expect) do
			assert.are.equal(value, ns.UI.Get(key), key)
			assert.are.equal(value, wow.world.settings.settings["PATHMARK_" .. key:upper()]:GetValue(), key)
		end
	end)

	for _, locale in ipairs({ "enUS", "deDE" }) do
		it("have one-sentence tooltips up to 140 characters and positive labels (E2, E3, " .. locale .. ")", function()
			S.login({ locale = locale })
			for _, o in ipairs(options()) do
				assert.is_string(o.tip, "no tooltip: " .. tostring(o.label))
				assert.is_true(#o.tip <= 140 + 10, "tooltip too long: " .. o.label) -- bytes: umlauts count twice
				assert.are.equal(1, sentences(o.tip), "more than one sentence: " .. o.tip)
				local low = o.label:lower()
				for _, word in ipairs({ "nicht", "deaktivieren", "ausblenden", "verbergen", "hide", "disable", " not " }) do
					assert.is_nil(low:find(word, 1, true), "negative label: " .. o.label)
				end
			end
		end)
	end

	it("apply at once: size, background, steps ahead, combat dim", function()
		local ns = S.login()
		local W, F = ns.StepFrame.frame, ns.Arrow.frame
		_G.Settings.SetValue("PATHMARK_SCALE", 150)
		assert.are.equal(1.5, W.scale)
		assert.are.equal(1.5, F.scale)
		_G.Settings.SetValue("PATHMARK_BGALPHA", 60)
		assert.are.same({ 0, 0, 0, 0.6 }, W.bg.colorTexture)
		_G.Settings.SetValue("PATHMARK_AHEAD", 1)
		assert.are.equal(1, #ns.StepFrame.VisibleRows())
	end)

	it("size slider runs from 75 to 200 % in steps of 5 and shows percent", function()
		S.login()
		local slider = init(byName("Pathmark"), "PATHMARK_SCALE")
		assert.are.same({ 75, 200, 5 }, { slider.options.min, slider.options.max, slider.options.step })
		assert.are.equal("150 %", slider.options.formatter(150))
		local alpha = init(byName("Display"), "PATHMARK_BGALPHA")
		assert.are.same({ 0, 80, 5 }, { alpha.options.min, alpha.options.max, alpha.options.step })
		local arrival = init(byName("Arrow and Map"), "PATHMARK_ARRIVAL")
		assert.are.same({ 5, 30, 1 }, { arrival.options.min, arrival.options.max, arrival.options.step })
		assert.are.equal("12 |4yd:yds", arrival.options.formatter(12))
	end)

	it("detail level sets several options at once", function()
		local ns = S.login()
		_G.Settings.SetValue("PATHMARK_SCOPE", "minimal")
		assert.are.same({ 0, false, false, false }, {
			ns.UI.Get("ahead"),
			ns.UI.Get("pins"),
			ns.UI.Get("minipins"),
			ns.UI.Get("sound"),
		})
		_G.Settings.SetValue("PATHMARK_SCOPE", "full")
		assert.are.same({ 3, true, true, true }, {
			ns.UI.Get("ahead"),
			ns.UI.Get("pins"),
			ns.UI.Get("minipins"),
			ns.UI.Get("sound"),
		})
	end)

	it("play style sets route and hint level; the slider is greyed out at 3 for “follow the arrow”", function()
		local ns = S.login({ style = "hints" })
		local page = byName("Play style")
		local style = init(page, "PATHMARK_STYLE")
		local hint = init(page, "PATHMARK_HINT")
		assert.are.equal(style, hint.parentInit)
		local values = {}
		for i, o in ipairs(style.options()) do
			values[i] = o.value .. "=" .. o.label
		end
		assert.are.same({ "arrow=Just follow the arrow", "hints=With hints", "self=Discover on my own" }, values)
		_G.Settings.SetValue("PATHMARK_STYLE", "self")
		assert.are.equal(0, ns.UI.Get("hint"))
		assert.are.equal("explorer", ns.Route.Mode())
		assert.is_true(hint.modifyPredicate())
		_G.Settings.SetValue("PATHMARK_HINT", 2)
		assert.are.equal(2, ns.Connect.HintLevel())
		_G.Settings.SetValue("PATHMARK_STYLE", "arrow")
		assert.are.equal(3, ns.UI.Get("hint"))
		assert.are.equal("speed", ns.Route.Mode())
		assert.is_false(hint.modifyPredicate())
		assert.are.equal("3 • Point", hint.options.formatter(3))
		local header = page.inits[#page.inits]
		assert.are.same({ "header", "Finds by other players" }, { header.kind, header.name })
		assert.matches("Show location", header.tooltip, 1, true)
	end)

	it("indents and greys out the minimap pins under the map pins (E7)", function()
		local ns = S.login()
		local page = byName("Arrow and Map")
		local mini = init(page, "PATHMARK_MINIPINS")
		assert.are.equal(init(page, "PATHMARK_PINS"), mini.parentInit)
		assert.is_true(mini.modifyPredicate())
		ns.UI.Set("pins", false)
		assert.is_false(mini.modifyPredicate())
	end)

	it("buttons: setup again, Edit Mode hint, reset position", function()
		local ns = S.login()
		local main = byName("Pathmark")
		main.inits[7].click()
		assert.is_true(rawget(_G.PathmarkSetupFrame, "shown"))
		main.inits[8].click()
		assert.matches("Edit Mode", wow.world.uiErrors[1], 1, true)
		ns.UI.DB().pos = { window = { "CENTER", "CENTER", 0, 0 } }
		ns.UI.Place("window")
		for _, i in ipairs(byName("Display").inits) do
			if i.kind == "button" then
				i.click()
			end
		end
		assert.are.equal("TOPRIGHT", ns.StepFrame.frame.points[1][1])
	end)

	it("Credits name licence, data sources with licences and the trademark line", function()
		local ns = S.login()
		local texts = {}
		for _, f in ipairs(wow.frames) do
			if rawget(f, "parent") == ns.SettingsPage.credits and f.type == "FontString" then
				texts[#texts + 1] = f.text
			end
		end
		local all = table.concat(texts, "\n")
		assert.matches("GNU General Public License 3.0, without warranty", all, 1, true)
		assert.matches(
			"All The Things (MIT) • EG Link (CC BY 4.0) • Polestar forever-db (GPL-3.0-only)",
			all,
			1,
			true
		)
		assert.matches("Not affiliated with Blizzard Entertainment", all, 1, true)
	end)

	it("open from the menu only out of combat", function()
		local ns = S.login()
		S.combat(true)
		ns.Menu.OpenSettings()
		assert.are.same({}, wow.world.settings.opened)
		S.combat(false)
		assert.are.same({ ns.settingsCategoryID }, wow.world.settings.opened)
	end)
end)

describe("Fonts (view 6)", function()
	it("are copies of Blizzard's font objects; the addon ships and sets no font file", function()
		local ns = S.login()
		for key, def in pairs(ns.Theme.FONT_DEFS) do
			local f = _G[def.name]
			assert.are.equal(_G[def.base], f.copyOf, key)
		end
		local find = assert(io.popen('grep -rlE "SetFont\\(|\\.[tT][tT][fF]" Pathmark/UI Pathmark/Core'))
		local hits = find:read("*a")
		find:close()
		assert.are.equal("", hits)
		local ttf = assert(io.popen('find Pathmark -iname "*.ttf" -o -iname "*.otf"'))
		assert.are.equal("", ttf:read("*a"))
		ttf:close()
	end)

	it("follow Blizzard's text size without scaling twice, and the size slider scales the frames", function()
		local ns = S.login({
			before = function(W)
				W.cvars.userFontScale = "2"
			end,
		})
		assert.are.equal(30, _G.PathmarkFontStep.size)
		assert.are.equal(24, _G.PathmarkFontSmall.size)
		ns.UI.Set("scale", 200)
		assert.are.equal(30, _G.PathmarkFontStep.size) -- the frame scales, the font height stays
		assert.are.equal(2, ns.StepFrame.frame.scale)
		ns.UI.Set("textSize", false)
		assert.are.equal(15, _G.PathmarkFontStep.size)
		ns.UI.Set("textSize", true)
		wow.world.cvars.userFontScale = "0.5" -- below Blizzard's minimum 0.8
		wow.fire("CVAR_UPDATE", "userFontScale", "0.5")
		assert.are.equal(12, _G.PathmarkFontStep.size)
		wow.world.cvars.userFontScale = "1"
		_G.EventRegistry:TriggerEvent("TextSizeManager.OnTextScaleUpdated", 1)
		assert.are.equal(15, _G.PathmarkFontStep.size)
	end)

	it("high-contrast quest text raises the window background to 80 %", function()
		local ns = S.login()
		wow.world.cvars.questTextContrast = "2"
		wow.fire("CVAR_UPDATE", "questTextContrast", "2")
		assert.are.same({ 0, 0, 0, 0.8 }, ns.StepFrame.frame.bg.colorTexture)
	end)
end)
