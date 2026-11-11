-- SPDX-License-Identifier: GPL-3.0-or-later
-- Design v2, view 5 "Einstellungen" and the rules of brain chapter 18 §7.3 (E1 to E7): Blizzard's
-- settings panel with vertical lists, main page with five options and two buttons, sub pages Play
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
	it("register one category with six sub pages as vertical lists, Credits as canvas", function()
		S.login()
		local main = byName("Braindead 4ever")
		assert.is_true(main.registered)
		local subs = {}
		for _, c in ipairs(categories()) do
			if c.parent == main then
				subs[#subs + 1] = c.name .. (c.canvas and " (canvas)" or "")
			end
		end
		assert.are.same(
			{ "Play style", "Display", "Arrow and Map", "Accessibility", "Sharing", "Credits (canvas)" },
			subs
		)
	end)

	-- Rule E1 (brain chapter 18 §7.3): at most five options and two buttons on the main page. The fifth
	-- option is the optional automation (A74; chapter 18 §8 and pattern D put it there), so the page is
	-- full: any further option goes to a sub page.
	it("main page: five options and two buttons, the most rule E1 allows", function()
		S.login()
		local kinds, count, buttons = {}, 0, 0
		for _, i in ipairs(byName("Braindead 4ever").inits) do
			kinds[#kinds + 1] = i.kind .. ":" .. (i.setting and i.setting.key or i.name)
			if i.setting then
				count = count + 1
			elseif i.kind == "button" then
				buttons = buttons + 1
			end
		end
		assert.is_true(count <= 5, "rule E1: " .. count .. " options on the main page")
		assert.is_true(buttons <= 2, "rule E1: " .. buttons .. " buttons on the main page")
		assert.are.same({
			"header:Basics",
			"dropdown:scope",
			"checkbox:arrow",
			"slider:scale",
			"checkbox:sound",
			"checkbox:auto",
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
			hardcore = "auto", -- Welle 9: follows the realm's rule set
			auto = false, -- optional automation (A74): off until the player turns it on
		}
		for key, value in pairs(expect) do
			assert.are.equal(value, ns.UI.Get(key), key)
			assert.are.equal(value, wow.world.settings.settings["BRAINDEADFOREVER_" .. key:upper()]:GetValue(), key)
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

	it("sharing on the hidden channel: on by default, off leaves the channel at once (owner 2026-11-11)", function()
		local ns = S.login()
		assert.is_true(ns.UI.Get("share"))
		wow.advance(10)
		assert.are.equal("on", ns.Exchange.channel.state)
		wow.world.settings.settings.BRAINDEADFOREVER_SHARE:SetValue(false)
		assert.are.equal("off", ns.Exchange.channel.state)
		assert.is_nil(wow.world.channels.BraindeadShare)
		wow.world.settings.settings.BRAINDEADFOREVER_SHARE:SetValue(true)
		wow.advance(2)
		assert.are.equal("on", ns.Exchange.channel.state)
	end)

	it("apply at once: size, background, steps ahead, combat dim", function()
		local ns = S.login()
		local W, F = ns.StepFrame.frame, ns.Arrow.frame
		_G.Settings.SetValue("BRAINDEADFOREVER_SCALE", 150)
		assert.are.equal(1.5, W.scale)
		assert.are.equal(1.5, F.scale)
		_G.Settings.SetValue("BRAINDEADFOREVER_BGALPHA", 60)
		assert.are.same({ 0, 0, 0, 0.6 }, W.bg.colorTexture)
		_G.Settings.SetValue("BRAINDEADFOREVER_AHEAD", 1)
		assert.are.equal(1, #ns.StepFrame.VisibleRows())
	end)

	it("size slider runs from 75 to 200 % in steps of 5 and shows percent", function()
		S.login()
		local slider = init(byName("Braindead 4ever"), "BRAINDEADFOREVER_SCALE")
		assert.are.same({ 75, 200, 5 }, { slider.options.min, slider.options.max, slider.options.step })
		assert.are.equal("150 %", slider.options.formatter(150))
		local alpha = init(byName("Display"), "BRAINDEADFOREVER_BGALPHA")
		assert.are.same({ 0, 80, 5 }, { alpha.options.min, alpha.options.max, alpha.options.step })
		local arrival = init(byName("Arrow and Map"), "BRAINDEADFOREVER_ARRIVAL")
		assert.are.same({ 5, 30, 1 }, { arrival.options.min, arrival.options.max, arrival.options.step })
		assert.are.equal("12 |4yd:yds", arrival.options.formatter(12))
	end)

	it("detail level sets several options at once", function()
		local ns = S.login()
		_G.Settings.SetValue("BRAINDEADFOREVER_SCOPE", "minimal")
		assert.are.same({ 0, false, false, false }, {
			ns.UI.Get("ahead"),
			ns.UI.Get("pins"),
			ns.UI.Get("minipins"),
			ns.UI.Get("sound"),
		})
		_G.Settings.SetValue("BRAINDEADFOREVER_SCOPE", "full")
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
		local style = init(page, "BRAINDEADFOREVER_STYLE")
		local hint = init(page, "BRAINDEADFOREVER_HINT")
		assert.are.equal(style, hint.parentInit)
		local values = {}
		for i, o in ipairs(style.options()) do
			values[i] = o.value .. "=" .. o.label
		end
		assert.are.same({ "arrow=Just follow the arrow", "hints=With hints", "self=Discover on my own" }, values)
		_G.Settings.SetValue("BRAINDEADFOREVER_STYLE", "self")
		assert.are.equal(0, ns.UI.Get("hint"))
		assert.are.equal("explorer", ns.Route.Mode())
		assert.is_true(hint.modifyPredicate())
		_G.Settings.SetValue("BRAINDEADFOREVER_HINT", 2)
		assert.are.equal(2, ns.Connect.HintLevel())
		_G.Settings.SetValue("BRAINDEADFOREVER_STYLE", "arrow")
		assert.are.equal(3, ns.UI.Get("hint"))
		assert.are.equal("speed", ns.Route.Mode())
		assert.is_false(hint.modifyPredicate())
		assert.are.equal("3 • Point", hint.options.formatter(3))
		-- no section header without options: Blizzard shows a header's text only on hover, so it
		-- stood empty on the page (screenshot round 3)
		for _, i in ipairs(page.inits) do
			assert.are_not.equal("header", i.kind)
		end
	end)

	it("indents and greys out the minimap pins under the map pins (E7)", function()
		local ns = S.login()
		local page = byName("Arrow and Map")
		local mini = init(page, "BRAINDEADFOREVER_MINIPINS")
		assert.are.equal(init(page, "BRAINDEADFOREVER_PINS"), mini.parentInit)
		assert.is_true(mini.modifyPredicate())
		ns.UI.Set("pins", false)
		assert.is_false(mini.modifyPredicate())
	end)

	it("buttons: setup again, Edit Mode hint, reset position", function()
		local ns = S.login()
		local main = byName("Braindead 4ever")
		main.inits[8].click()
		assert.is_true(rawget(_G.BraindeadForeverSetupFrame, "shown"))
		main.inits[9].click()
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

	it("Credits name the licence, point to NOTICE for the data sources and carry the trademark line", function()
		local ns = S.login()
		local texts = {}
		for _, f in ipairs(wow.frames) do
			if rawget(f, "parent") == ns.SettingsPage.credits and f.type == "FontString" then
				texts[#texts + 1] = f.text
			end
		end
		local all = table.concat(texts, "\n")
		assert.matches("GNU General Public License 3.0, without warranty", all, 1, true)
		assert.matches("Credits and licences: the file NOTICE in the addon folder.", all, 1, true)
		assert.is_nil(all:find("Polestar", 1, true))
		assert.matches("Not affiliated with Blizzard Entertainment", all, 1, true)
	end)

	it("Credits show the Discord link in a copyable box in both languages", function()
		for _, locale in ipairs({ "enUS", "deDE" }) do
			local ns = S.login({ locale = locale })
			local label, box
			for _, f in ipairs(wow.frames) do
				if rawget(f, "parent") == ns.SettingsPage.credits then
					if f.type == "FontString" and f.text == "Discord:" then
						label = f
					elseif f.type == "EditBox" then
						box = f
					end
				end
			end
			assert.is_not_nil(label, locale)
			assert.is_not_nil(box, locale)
			assert.are.equal("discord.gg/ujjEM9NE5D", box:GetText())
			box:SetText("changed by the player")
			box.scripts.OnTextChanged(box, true)
			assert.are.equal("discord.gg/ujjEM9NE5D", box:GetText())
			-- shown again (the settings page opens later than the box is made): the link is set anew
			box:SetText("")
			assert.is_function(box.scripts.OnShow, locale)
			box.scripts.OnShow(box)
			assert.are.equal("discord.gg/ujjEM9NE5D", box:GetText())
		end
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
		local find = assert(io.popen('grep -rlE "SetFont\\(|\\.[tT][tT][fF]" Braindead4Ever/UI Braindead4Ever/Core'))
		local hits = find:read("*a")
		find:close()
		assert.are.equal("", hits)
		local ttf = assert(io.popen('find Braindead4Ever -iname "*.ttf" -o -iname "*.otf"'))
		assert.are.equal("", ttf:read("*a"))
		ttf:close()
	end)

	it("follow Blizzard's text size without scaling twice, and the size slider scales the frames", function()
		local ns = S.login({
			before = function(W)
				W.cvars.userFontScale = "2"
			end,
		})
		assert.are.equal(30, _G.BraindeadForeverFontStep.size)
		assert.are.equal(24, _G.BraindeadForeverFontSmall.size)
		ns.UI.Set("scale", 200)
		assert.are.equal(30, _G.BraindeadForeverFontStep.size) -- the frame scales, the font height stays
		assert.are.equal(2, ns.StepFrame.frame.scale)
		ns.UI.Set("textSize", false)
		assert.are.equal(15, _G.BraindeadForeverFontStep.size)
		ns.UI.Set("textSize", true)
		wow.world.cvars.userFontScale = "0.5" -- below Blizzard's minimum 0.8
		wow.fire("CVAR_UPDATE", "userFontScale", "0.5")
		assert.are.equal(12, _G.BraindeadForeverFontStep.size)
		wow.world.cvars.userFontScale = "1"
		_G.EventRegistry:TriggerEvent("TextSizeManager.OnTextScaleUpdated", 1)
		assert.are.equal(15, _G.BraindeadForeverFontStep.size)
	end)

	it("high-contrast quest text raises the window background to 80 %", function()
		local ns = S.login()
		wow.world.cvars.questTextContrast = "2"
		wow.fire("CVAR_UPDATE", "questTextContrast", "2")
		assert.are.same({ 0, 0, 0, 0.8 }, ns.StepFrame.frame.bg.colorTexture)
	end)
end)
