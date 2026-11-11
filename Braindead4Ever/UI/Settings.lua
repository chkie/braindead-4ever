--[[
Braindead 4ever
Copyright (C) 2026 Braindead 4ever contributors (see Git history)

This program is free software: you can redistribute it and/or modify it under the
terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

Additional permission under GNU GPL version 3 section 7

If you modify this Program, or any covered work, by linking or combining it with
the Ace3 libraries (or a modified version of that library), containing parts
covered by the terms of the Ace3 license, the licensors of this Program grant you
additional permission to convey the resulting work. Corresponding Source for a
non-source form of such a combination shall include the source code for the parts
of the Ace3 libraries used as well as that of the covered work.
]]
-- SPDX-License-Identifier: GPL-3.0-or-later WITH AdditionRef-Braindead4Ever-Ace3-Exception

-- UI/Settings.lua: module "settings" (design v2, view 5; concept §2.6). Blizzard's settings panel →
-- AddOns → Braindead 4ever as vertical lists, so Blizzard's search finds every option (rule E5). Main page:
-- five options (the most rule E1 allows; the fifth is the optional automation, A74) and two buttons; sub
-- pages Play style, Display, Arrow and Map, Accessibility, Credits
-- (canvas, licence text only). Every change applies at once (no CommitFlag.Apply, E4); the Defaults
-- button comes from Blizzard. Dependent options are indented and greyed out with SetParentInitializer
-- (E7). Tooltips are one sentence each (E2), labels are positive (E3).
local _, ns = ...
local L, UI, T = ns.L, ns.UI, ns.Theme
local M = ns.Modules

local SET = { registered = {} }
ns.SettingsPage = SET

local function Register(cat, key, vtype, label)
	local db = UI.DB()
	local variable = "BRAINDEADFOREVER_" .. key:upper()
	local s = Settings.RegisterAddOnSetting(cat, variable, key, db, vtype, label, UI.DEFAULTS[key])
	s:SetValueChangedCallback(function()
		UI.Changed(key)
	end)
	UI.settings[key] = s
	SET.registered[#SET.registered + 1] = { key = key, variable = variable, label = label }
	return s
end

local function Check(cat, key, label, tip)
	local s = Register(cat, key, Settings.VarType.Boolean, label)
	return Settings.CreateCheckbox(cat, s, tip)
end

local function Slider(cat, key, label, tip, min, max, step, fmt)
	local s = Register(cat, key, Settings.VarType.Number, label)
	local opts = Settings.CreateSliderOptions(min, max, step)
	if opts.SetLabelFormatter and MinimalSliderWithSteppersMixin then
		opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt)
	end
	return Settings.CreateSlider(cat, s, opts, tip)
end

local function Dropdown(cat, key, label, tip, values)
	local s = Register(cat, key, Settings.VarType.String, label)
	return Settings.CreateDropdown(cat, s, function()
		local box = Settings.CreateControlTextContainer()
		for _, v in ipairs(values) do
			box:Add(v[1], v[2], v[3])
		end
		return box:GetData()
	end, tip)
end

local function Button(layout, label, text, fn, tip)
	layout:AddInitializer(CreateSettingsButtonInitializer(label, text, function()
		ns.Guard.Call("settings", fn)
	end, tip, true))
end

local function Header(layout, name, tip)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name, tip))
end

local function Percent(v)
	return L.PERCENT:format(math.floor(v + 0.5))
end

local HINT_NAMES = { "HINT_0", "HINT_1", "HINT_2", "HINT_3" }

-- Credits: copyright, licence without warranty, data sources, libraries, trademark line (concept §3.3).
local function Credits(parent)
	local f = CreateFrame("Frame")
	local y = -16
	local function add(text, font, color)
		local fs = f:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
		fs:SetPoint("TOPLEFT", 16, y)
		fs:SetWidth(560)
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(true)
		fs:SetText(text)
		if color then
			fs:SetTextColor(T.RGB(color))
		end
		local h = fs.GetStringHeight and fs:GetStringHeight()
		y = y - ((type(h) == "number" and h > 0) and h or 14) - 8
		return fs
	end
	add(L.TITLE, "GameFontNormalLarge", NORMAL_FONT_COLOR)
	add(L.CREDITS_LICENSE)
	add(L.CREDITS_SOURCES_TITLE, "GameFontNormal", NORMAL_FONT_COLOR)
	add(L.CREDITS_SOURCES)
	add(L.CREDITS_LIBS_TITLE, "GameFontNormal", NORMAL_FONT_COLOR)
	add(L.CREDITS_LIBS)
	-- Discord link: a label and a box the player copies from (links are not clickable in the game).
	local label = add(L.CREDITS_DISCORD)
	label:SetWidth(0)
	ns.CreateLinkBox(f, 200):SetPoint("LEFT", label, "RIGHT", 8, 0)
	add(L.CREDITS_TRADEMARK)
	SET.credits = f
	return Settings.RegisterCanvasLayoutSubcategory(parent, f, L.PAGE_CREDITS)
end

local function Build()
	local cat, layout = Settings.RegisterVerticalLayoutCategory(L.TITLE)
	SET.category = cat
	ns.settingsCategoryID = cat:GetID()

	-- Main page: five options, two buttons (E1: at most five options; a new option goes to a sub page)
	Header(layout, L.SEC_BASICS)
	Dropdown(cat, "scope", L.OPT_SCOPE, L.TIP_SCOPE, {
		{ "minimal", L.SCOPE_MINIMAL, L.TIP_SCOPE_MINIMAL },
		{ "standard", L.SCOPE_STANDARD, L.TIP_SCOPE_STANDARD },
		{ "full", L.SCOPE_FULL, L.TIP_SCOPE_FULL },
	})
	Check(cat, "arrow", L.OPT_ARROW, L.TIP_ARROW)
	Slider(cat, "scale", L.OPT_SCALE, L.TIP_SCALE, 75, 200, 5, Percent)
	Check(cat, "sound", L.OPT_SOUND, L.TIP_SOUND)
	-- Optional automation (A74), off by default: one switch for accept, hand-in and the single reward
	-- (brain chapter 18 §8 and pattern D put it on the main page); only while the client offers its API.
	if M.IsActive("auto") then
		Check(cat, "auto", L.OPT_AUTO, L.TIP_AUTO)
	end
	Header(layout, L.SEC_SETUP)
	Button(layout, L.BTN_SETUP_LABEL, L.BTN_SETUP, function()
		ns.Setup.Open(true)
	end, L.TIP_BTN_SETUP)
	Button(layout, L.BTN_POSITION_LABEL, L.BTN_POSITION, UI.EditModeHint, L.TIP_BTN_POSITION)

	-- Play style
	local play = Settings.RegisterVerticalLayoutSubcategory(cat, L.PAGE_PLAY)
	local styleInit = Dropdown(play, "style", L.OPT_STYLE, L.TIP_STYLE, {
		{ "arrow", L.STYLE_arrow },
		{ "hints", L.STYLE_hints },
		{ "self", L.STYLE_self },
	})
	local hintInit = Slider(play, "hint", L.OPT_HINT, L.TIP_HINT, 0, 3, 1, function(v)
		v = math.floor(v + 0.5)
		return L.HINT_FMT:format(v, L[HINT_NAMES[v + 1]] or "")
	end)
	hintInit:SetParentInitializer(styleInit, function()
		return UI.Get("style") ~= "arrow"
	end)
	-- hardcore-safe mode (Welle 9, M3): the tooltip names the chosen level gap of Routes/Hardcore.lua
	Dropdown(play, "hardcore", L.OPT_HARDCORE, L.TIP_HARDCORE:format(ns.Hardcore.GAP + 1), {
		{ "auto", L.HC_auto, L.TIP_HC_auto },
		{ "on", L.HC_on, L.TIP_HC_on },
		{ "off", L.HC_off, L.TIP_HC_off },
	})

	-- Display
	local disp, dispLayout = Settings.RegisterVerticalLayoutSubcategory(cat, L.PAGE_DISPLAY)
	Slider(disp, "ahead", L.OPT_AHEAD, L.TIP_AHEAD, 0, ns.StepFrame and ns.StepFrame.MAX_AHEAD or 10, 1, function(v)
		return tostring(math.floor(v + 0.5))
	end)
	Slider(disp, "bgAlpha", L.OPT_BGALPHA, L.TIP_BGALPHA, 0, 80, 5, Percent)
	Check(disp, "dim", L.OPT_DIM, L.TIP_DIM)
	if M.defs.questwatch then -- Blizzard's quest tracker (owner reading 15)
		Dropdown(disp, "tracker", L.OPT_TRACKER, L.TIP_TRACKER, {
			{ "keep", L.TRACKER_keep, L.TIP_TRACKER_keep },
			{ "route", L.TRACKER_route, L.TIP_TRACKER_route },
			{ "hide", L.TRACKER_hide, L.TIP_TRACKER_hide },
		})
	end
	Check(disp, "lock", L.OPT_LOCK, L.TIP_LOCK) -- the header band drags the window (owner reading 16)
	Check(disp, "recap", L.OPT_RECAP, L.TIP_RECAP) -- review card at level 10, 20 and 30 (Welle 8)
	Button(dispLayout, L.BTN_RESET_LABEL, L.BTN_RESET, UI.ResetPositions, L.TIP_BTN_RESET)

	-- Arrow and map
	local nav = Settings.RegisterVerticalLayoutSubcategory(cat, L.PAGE_NAV)
	Slider(nav, "arrival", L.OPT_ARRIVAL, L.TIP_ARRIVAL, 5, 30, 1, function(v)
		return T.Distance(v)
	end)
	local pinsInit = Check(nav, "pins", L.OPT_PINS, L.TIP_PINS)
	local miniInit = Check(nav, "minipins", L.OPT_MINIPINS, L.TIP_MINIPINS)
	miniInit:SetParentInitializer(pinsInit, function()
		return UI.Get("pins") == true
	end)
	Check(nav, "blizzNav", L.OPT_BLIZZNAV, L.TIP_BLIZZNAV)
	Check(nav, "mmButton", L.OPT_MMBUTTON, L.TIP_MMBUTTON)
	if M.IsActive("tomtom") then -- only with TomTom installed (UI/TomTom.lua)
		Check(nav, "tomtom", L.OPT_TOMTOM, L.TIP_TOMTOM)
	end

	-- Accessibility
	local a11y = Settings.RegisterVerticalLayoutSubcategory(cat, L.PAGE_A11Y)
	Check(a11y, "textSize", L.OPT_TEXTSIZE, L.TIP_TEXTSIZE)

	-- Sharing on the hidden channel (owner 2026-11-11): the player's choice, on by default
	local share = Settings.RegisterVerticalLayoutSubcategory(cat, L.PAGE_SHARE)
	Check(share, "share", L.OPT_SHARE, L.TIP_SHARE)

	Credits(cat)
	Settings.RegisterAddOnCategory(cat)
end

-- The hidden channel follows the option "share" at once (Collector/Exchange.lua).
UI.OnChange("share", SET, function(_, _, value)
	if ns.Exchange and ns.Exchange.SetChannel then
		ns.Exchange.SetChannel(value ~= false)
	end
end)

-- "Anzeigeumfang" sets several options at once (brain chapter 18 pattern D).
local applying = false
UI.OnChange("scope", SET, function(_, _, value)
	if applying then
		return
	end
	applying = true
	for key, v in pairs(UI.SCOPES[value] or {}) do
		UI.Set(key, v)
	end
	applying = false
end)

M.Define("settings", {
	requires = {
		funcs = {
			"Settings.RegisterVerticalLayoutCategory",
			"Settings.RegisterVerticalLayoutSubcategory",
			"Settings.RegisterCanvasLayoutSubcategory",
			"Settings.RegisterAddOnSetting",
			"Settings.RegisterAddOnCategory",
			"Settings.CreateCheckbox",
			"Settings.CreateSlider",
			"Settings.CreateSliderOptions",
			"Settings.CreateDropdown",
			"Settings.CreateControlTextContainer",
			"CreateSettingsButtonInitializer",
			"CreateSettingsListSectionHeaderInitializer",
		},
	},
	optional = { funcs = { "Settings.OpenToCategory" } },
	init = Build,
})
