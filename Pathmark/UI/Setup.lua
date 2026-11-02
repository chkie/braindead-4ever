--[[
Pathmark
Copyright (C) 2026 Pathmark contributors (see Git history)

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
-- SPDX-License-Identifier: GPL-3.0-or-later WITH AdditionRef-Pathmark-Ace3-Exception

-- UI/Setup.lua: module "setup", the first start (design v2, view 3; concept §2.5). One window
-- (BasicFrameTemplateWithInset, 560x330, screen center), two seconds after the first login, once per
-- account, never in combat. What the addon can detect it does not ask (race, class, level, start zone).
-- Exactly one question, "How do you want to play?", with three cards; nothing is preselected. A click on
-- a card picks the style and closes the window; closing with the cross or Escape picks "With hints".
-- Card click sound as in Blizzard's experience preset dialog. Reopened from the settings and with
-- /pathmark setup; closing a reopened window changes nothing.
local _, ns = ...
local L, UI, T, C, ST = ns.L, ns.UI, ns.Theme, ns.Connect, ns.StepText
local M, Guard = ns.Modules, ns.Guard

local S = {
	NAME = "PathmarkSetupFrame", -- named so that Escape closes it (UISpecialFrames)
	W = 560,
	H = 330,
	DELAY = 2,
	CARD_W = 168,
	CARD_H = 150,
	SUB_LINES = 2, -- every subtitle takes two lines, so the three card texts start on one line (S7)
}
ns.Setup = S

local d -- dialog

local function Text(parent, font, width)
	local fs = parent:CreateFontString(nil, "OVERLAY", font)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(true)
	if width then
		fs:SetWidth(width)
	end
	return fs
end

local function Card(parent, style, index)
	local b = CreateFrame("Button", nil, parent, "InsetFrameTemplate")
	b:SetSize(S.CARD_W, S.CARD_H)
	b:SetPoint("TOPLEFT", parent, "TOPLEFT", 16 + (index - 1) * (S.CARD_W + 8), -112)
	b.style = style
	local w = S.CARD_W - 20
	b.title = Text(b, "GameFontNormal", w)
	b.title:SetPoint("TOPLEFT", 10, -10)
	b.title:SetText(L["STYLE_" .. style])
	b.sub = Text(b, "GameFontHighlightSmall", w)
	b.sub:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -4)
	b.sub:SetText(L["STYLE_SUB_" .. style])
	-- "Entdecker-Route ohne Hinweise" wraps, and the third card's text stood a line lower (Welle 5d S7)
	local _, size = b.sub:GetFont()
	b.sub:SetJustifyV("TOP")
	b.sub:SetMaxLines(S.SUB_LINES)
	b.sub:SetHeight(S.SUB_LINES * math.ceil((tonumber(size) or 10) * 1.2))
	b.text = Text(b, "GameFontHighlight", w)
	b.text:SetPoint("TOPLEFT", b.sub, "BOTTOMLEFT", 0, -8)
	b.text:SetText(L["STYLE_TEXT_" .. style])
	b.level = Text(b, "GameFontNormalSmall", w)
	b.level:SetPoint("BOTTOMLEFT", 10, 10)
	b.level:SetText(L.HINT_LEVEL_N:format(C.STYLES[style].hint))
	b.hl = b:CreateTexture(nil, "HIGHLIGHT")
	b.hl:SetAllPoints()
	b.hl:SetColorTexture(T.RGB(NORMAL_FONT_COLOR))
	b.hl:SetAlpha(0.1)
	b:SetScript("OnClick", function()
		Guard.Call("setup", S.Choose, style)
	end)
	return b
end

local function Build()
	d = CreateFrame("Frame", S.NAME, UIParent, "BasicFrameTemplateWithInset")
	d:SetSize(S.W, S.H)
	d:SetPoint("CENTER")
	d:SetFrameStrata("DIALOG")
	d:SetClampedToScreen(true)
	d:EnableMouse(true)
	tinsert(UISpecialFrames, S.NAME)
	if d.TitleText then
		d.TitleText:SetText(L.SETUP_TITLE)
	end
	local width = S.W - 32

	d.detectedLabel = Text(d, "GameFontNormal")
	d.detectedLabel:SetPoint("TOPLEFT", 16, -36)
	d.detectedLabel:SetText(L.SETUP_DETECTED)
	d.detected = Text(d, "GameFontHighlight", width - 80)
	d.detected:SetPoint("LEFT", d.detectedLabel, "RIGHT", 8, 0)

	d.question = Text(d, "GameFontNormal", width)
	d.question:SetPoint("TOPLEFT", 16, -86)
	d.question:SetText(L.SETUP_QUESTION)

	d.cards = {}
	for i, style in ipairs(C.STYLE_ORDER) do
		d.cards[i] = Card(d, style, i)
	end

	d.data = Text(d, "GameFontHighlight", width)
	d.data:SetPoint("TOPLEFT", 16, -272)
	d.data:SetText(L.SETUP_DATA)
	d.foot = Text(d, "GameFontHighlightSmall", width)
	d.foot:SetPoint("BOTTOMLEFT", 16, 12)

	-- Cross, Escape or any other hide without a choice.
	d:SetScript("OnHide", function()
		Guard.Call("setup", S.Closed)
	end)
	d:Hide()
	S.frame = d
end

-- "Human • Warrior • Level 1 • Route starts in Elwynn Forest"
function S.DetectedLine()
	local race = ns.Util.Str((UnitRace("player"))) or ""
	local class = ns.Util.Str((UnitClass("player"))) or ""
	local level = ns.Util.Num(UnitLevel("player")) or 1
	local zone = ST.MapName(ST.ZoneMap(C.Current()))
	if zone then
		return L.SETUP_DETECTED_LINE:format(race, class, level, zone)
	end
	return L.SETUP_DETECTED_NOROUTE:format(race, class, level)
end

local function Finish()
	local first = not S.reopened
	UI.DB().setupDone = true
	S.done = true
	if d:IsShown() then
		d:Hide()
	end
	C.ApplyStyle()
	if first and ns.StepFrame then
		ns.StepFrame.ShowHintOnce()
	end
	if ns.StepFrame then
		ns.StepFrame.ResumeHint()
		ns.StepFrame.Refresh()
		ns.StepFrame.PlaceDefault() -- the tracker hides now: the window takes its place (Welle 5c)
	end
	if ns.QuestWatch then -- the quest tracker option starts after the first start (Welle 5b)
		ns.QuestWatch.Queue()
	end
end

-- A card: style and hint level, then the route leads at once.
function S.Choose(style)
	T.Play("UI_EXPERIENCE_PRESET_SELECT_CLICK", true)
	S.choice = style
	UI.DB().setupDone = true
	C.SetStyle(style)
	Finish()
end

-- Closed without a card: the first start takes "With hints"; a reopened window changes nothing.
function S.Closed()
	if S.done then
		return
	end
	if not S.reopened then
		UI.DB().setupDone = true
		C.SetStyle("hints")
	end
	Finish()
end

-- force = reopen from the settings or the slash command. firstLook (developer preview): the footer of
-- the first start, which names what closing picks; closing a reopened window still changes nothing.
function S.Open(force, firstLook)
	if UI.DB().setupDone and not force then
		return false
	end
	UI.OutOfCombat("setup", function()
		if not M.IsActive("setup") then
			return
		end
		if not d then
			Build()
		end
		S.done, S.choice = false, nil
		S.reopened = UI.DB().setupDone == true
		d.detected:SetText(S.DetectedLine())
		d.foot:SetText((S.reopened and not firstLook) and L.SETUP_FOOT_AGAIN or L.SETUP_FOOT)
		if ns.StepFrame then
			ns.StepFrame.SuspendHint() -- the usage hint waits behind the first start (Welle 5d, M13)
		end
		d:Show()
	end)
	return true
end

ns.Commands.setup = function()
	S.Open(true)
end

M.Define("setup", {
	requires = { funcs = { "UnitRace", "UnitClass", "UnitLevel" }, events = { "PLAYER_ENTERING_WORLD" } },
	optional = { funcs = { "PlaySound" } },
	events = {
		PLAYER_ENTERING_WORLD = function(_, _, isInitialLogin)
			if isInitialLogin and not UI.DB().setupDone then
				C_Timer.After(
					S.DELAY,
					Guard.Wrap("setup", function()
						S.Open(false)
					end)
				)
			end
		end,
	},
})
