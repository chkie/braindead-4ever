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

-- UI/StepFrame.lua: module "window", the step display of design v2 (view 1). One background for the
-- whole window (black, 70 % since Welle 5d), header band and content on the same width and edges (owner
-- reading 1),
-- 300 units wide, fonts 15/13/12 (owner reading 2). States: normal, origin tooltip, done (check, glow,
-- sound), mini, combat (60 %), usage hint (HelpTip), right-click menu, status line, route falls short,
-- skip with follow-ups (StaticPopup), quest abandoned, optional dungeon step, rumor line; check box;
-- XP line. Reads the logic only through ns.Connect.
-- Size (owner reading 14): a grip at the bottom right (Blizzard's PanelResizeButtonTemplate) drags the
-- width (260 to 500) and the height; the height sets how many next steps are visible (0 to 10, the
-- option "steps ahead" follows), the next LIST_MAX steps sit in a Blizzard ScrollBox and the rest
-- scrolls. Not while fighting.
local ADDON, ns = ...
local L, UI, T, C, ST, Nav = ns.L, ns.UI, ns.Theme, ns.Connect, ns.StepText, ns.Nav
local M, Guard = ns.Modules, ns.Guard

local SF = {
	WIDTH = 300, -- default width; the player's width is UI.Get("width")
	MIN_WIDTH = 260,
	MAX_WIDTH = 500,
	MAX_AHEAD = 10,
	LIST_MAX = 20, -- next steps in the scroll list (chosen value)
	LIST_GAP = 12, -- space between the current step and the list
	-- Room below the last visible row for the descenders of g, p, y: GetStringHeight ends at the line,
	-- and the scroll box clips at its edge ("abgeben", "besiegen" lost their lower part, Welle 5d M7).
	-- Smaller than ROW_GAP, so nothing of the next row shows.
	DESCENT = 4,
	-- Next steps are dimmed (rule R4). Contrast on white ground behind 70 % black (WCAG formula, Welle 5d
	-- M1): white at 0.6 gives 4.3:1, at 0.7 5.2:1; the dungeon step at 0.78 gives 6.0:1.
	NEXT_ALPHA = 0.7,
	DUNGEON_ALPHA = 0.78,
	ROW_GAP = 6,
	ROW_PAN = 20, -- one mouse wheel notch scrolls about one line
	HEADER = 36,
	-- The header atlas has transparent edges: drawn part from 3.0 % to 94.1 % of its width (alpha above
	-- 20 of 255 in files 5320671 and 5320674, Welle 5d). The band reaches past the window by these parts,
	-- so its gold lines end at the window edges like the content (owner reading 1, Q1).
	HEADER_TRIM = { 0.030, 0.059 },
	ICON = 19,
	LEFT = 8, -- body padding left
	RIGHT = 12, -- body padding right
	GAP_ICON = 6,
	INDENT = 25, -- next steps, XP line and notes start under the step text
	BULLET = 11,
	DONE_DELAY = 0.9, -- the checked line stays this long before the next one moves up
	DETAIL_EVERY = 0.5, -- distance in the detail line at most twice per second
	POPUP = "BRAINDEADFOREVER_SKIP_CHAIN",
	-- Default place (owner readings 16 and 17): where Blizzard's quest tracker stands, top right, with a
	-- gap to the right action bars and the minimap; left of the tracker while the tracker shows. Measured
	-- from Blizzard's frames at every placement (SF.DefaultPoint); the fixed values are the fallback.
	-- Sources: Gethe/wow-ui-source live 12.1.5 (d07eb00) and forever 1.60.1 (ca8368f), same in both.
	GAP = 10, -- Blizzard's gap below the minimap cluster (Mainline/EditModeManagerOverrides.lua)
	TOP = 260, -- RIGHT_CONTAINER_OFFSET_Y, top of the tracker's container (Mainline/EditModePresetLayouts.lua)
	BARS = 105, -- room of the right bars: |offset 55| + width 45 + 5 (Shared/EditModeUtil.lua, 45 = action button)
	TRACKER = 260, -- width of ObjectiveTrackerFrame (ObjectiveTrackerContainerTemplate)
	MINIMAP = 256, -- height of MinimapCluster (Blizzard_Minimap/Mainline/Minimap.xml)
	-- Right bars (EditModeManagerFrameMixin:GetRightActionBars) count shown or not; bars 6 to 8 only when
	-- they stand at the right edge.
	BARS_RIGHT = { "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7" },
}
ns.StepFrame = SF

local W -- the window
SF.below, SF.listTop, SF.rowTops, SF.rowBottoms = 0, 0, {}, {}
local view = {} -- what is shown: info, mode, target, rumor, message
local lastCount = {} -- step key -> needed count, for the final "8/8" of a done step

local function TextX()
	return SF.LEFT + SF.ICON + SF.GAP_ICON
end

local function Clamp(v, lo, hi)
	return math.max(lo, math.min(hi, v))
end

-- Width the layout uses: the dragged width while sizing, else the saved one.
function SF.Width()
	if W and SF.sizing then
		return Clamp(W:GetWidth() or SF.WIDTH, SF.MIN_WIDTH, SF.MAX_WIDTH)
	end
	return Clamp(tonumber(UI.Get("width")) or SF.WIDTH, SF.MIN_WIDTH, SF.MAX_WIDTH)
end

function SF.Ahead()
	return Clamp(math.floor(tonumber(UI.Get("ahead")) or 3), 0, SF.MAX_AHEAD)
end

-- Building ------------------------------------------------------------------------------------------

local function FS(parent, font, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs:SetFontObject(T.Font(font))
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	fs:SetWordWrap(true)
	fs:SetSpacing(2) -- extra line spacing (owner reading 2)
	return fs
end

local function Button(parent, text, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetHeight(22)
	b:SetText(text)
	b:SetScript("OnClick", function()
		Guard.Call("window", onClick)
	end)
	return b
end

local function FitButton(b)
	local fs = b.GetFontString and b:GetFontString()
	local w = fs and fs.GetStringWidth and fs:GetStringWidth() or 0
	b:SetWidth(math.max(80, (w or 0) + 24))
	return b:GetWidth() or 80
end

local function Build()
	W = CreateFrame("Frame", nil, UIParent)
	SF.frame = W
	W:SetSize(SF.Width(), 120)
	W:SetFrameStrata("MEDIUM")
	W:EnableMouse(true)
	W:SetResizable(true)

	W.bg = W:CreateTexture(nil, "BACKGROUND")
	W.bg:SetAllPoints()

	-- Header band on the full width (atlas 300x40)
	W.header = W:CreateTexture(nil, "BORDER")
	W.header:SetPoint("TOPLEFT", 0, 0)
	W.header:SetPoint("TOPRIGHT", 0, 0)
	W.header:SetHeight(SF.HEADER)
	T.SetAtlas(W.header, "header")

	W.toggle = CreateFrame("Button", nil, W)
	W.toggle:SetSize(18, 19)
	W.toggle:SetPoint("RIGHT", W, "TOPRIGHT", -8, -SF.HEADER / 2)
	W.toggle.tex = W.toggle:CreateTexture(nil, "ARTWORK")
	W.toggle.tex:SetAllPoints()
	W.toggle:SetScript("OnClick", function()
		SF.SetMini(not UI.DB().mini)
	end)

	W.clock = CreateFrame("Button", nil, W)
	W.clock:SetSize(18, 18)
	W.clock:SetPoint("RIGHT", W.toggle, "LEFT", -8, 0)
	W.clock.tex = W.clock:CreateTexture(nil, "ARTWORK")
	W.clock.tex:SetAllPoints()
	T.SetAtlas(W.clock.tex, "clock")
	W.clock:SetScript("OnEnter", function(self)
		SF.ShowProvisionalTip(self)
	end)
	W.clock:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	W.title = FS(W, "header")
	W.title:SetPoint("LEFT", W, "TOPLEFT", 10, -SF.HEADER / 2)
	W.title:SetPoint("RIGHT", W.clock, "LEFT", -8, 0)
	W.title:SetWordWrap(false)
	W.title:SetMaxLines(1)
	W.title:SetTextColor(T.RGB(NORMAL_FONT_COLOR))

	-- Banner: abandoned quest or rumor, with buttons (UIPanelButtonTemplate)
	W.banner = FS(W, "line")
	W.banner:SetTextColor(T.RGB(NORMAL_FONT_COLOR))
	-- Hint level 1: the riddle of the zone as its own line in the look of the rumor line (Welle 5b)
	W.riddle = FS(W, "line")
	W.riddle:SetTextColor(T.RGB(NORMAL_FONT_COLOR))
	W.btnReaccept = Button(W, L.REACCEPT, function()
		C.ResolveAbandon("reaccept")
	end)
	W.btnSkipChain = Button(W, L.SKIP_FOLLOW, function()
		SF.AskSkip()
	end)
	W.btnShow = Button(W, L.SHOW_LOCATION, function()
		SF.RevealRumor()
	end)
	-- Replanning (Welle 7): "over the plan" and the switch point, yes and no
	W.btnYes = Button(W, L.ADJUST, function()
		SF.AnswerOffer(true)
	end)
	W.btnNo = Button(W, L.KEEP_ROUTE, function()
		SF.AnswerOffer(false)
	end)

	-- Current step: check box in place of the nub, text, counter, detail
	W.cur = CreateFrame("Frame", nil, W)
	W.cur:EnableMouse(true)
	W.cur:SetScript("OnEnter", function(self)
		SF.ShowOriginTip(self)
	end)
	W.cur:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	W.cur:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then
			ns.Menu.Open(W)
		elseif button == "LeftButton" and W.box:IsShown() and W.box:IsMouseOver() then
			-- the line lies over the box: a left click on the box must still check the step (owner 10.11.2026)
			SF.CheckCurrent()
		end
	end)

	W.box = CreateFrame("Button", nil, W)
	W.box:SetSize(SF.ICON, SF.ICON)
	W.box.tex = W.box:CreateTexture(nil, "ARTWORK")
	W.box.tex:SetAllPoints()
	T.SetAtlas(W.box.tex, "box")
	W.box:SetScript("OnClick", function()
		SF.CheckCurrent()
	end)
	-- above the line of the current step, which also takes the mouse (tooltip, right-click menu)
	W.box:SetFrameLevel(W.cur:GetFrameLevel() + 2)
	W.icon = W:CreateTexture(nil, "ARTWORK") -- check or fail
	W.icon:SetSize(SF.ICON, SF.ICON)
	W.icon:SetPoint("CENTER", W.box, "CENTER")
	W.tick = W:CreateTexture(nil, "OVERLAY") -- check mark over the box while a click is confirmed
	W.tick:SetAllPoints(W.box)
	T.SetAtlas(W.tick, "tick")
	W.tick:Hide()

	W.glow = W:CreateTexture(nil, "OVERLAY")
	W.glow:SetPoint("LEFT", W, "LEFT", 0, 0)
	W.glow:SetPoint("RIGHT", W, "RIGHT", 0, 0)
	W.glow:SetHeight(28)
	T.SetAtlas(W.glow, "glow")
	W.glow:SetAlpha(0)
	W.glowAnim = W.glow:CreateAnimationGroup()
	local a1 = W.glowAnim:CreateAnimation("Alpha")
	a1:SetFromAlpha(0)
	a1:SetToAlpha(0.9)
	a1:SetDuration(0.15)
	a1:SetOrder(1)
	local a2 = W.glowAnim:CreateAnimation("Alpha")
	a2:SetFromAlpha(0.9)
	a2:SetToAlpha(0)
	a2:SetDuration(0.6)
	a2:SetOrder(2)

	W.step = FS(W, "step")
	W.detail = FS(W, "line")
	W.detail:SetTextColor(T.Tracker("Normal"))
	-- hardcore-safe mode (Welle 9, M3): elite quest or quest too far above the character, gold like the
	-- banner; also in the mini view
	W.warn = FS(W, "line")
	W.warn:SetTextColor(T.RGB(NORMAL_FONT_COLOR))

	-- Next steps, dimmed, at most two lines each (T19); an optional step carries a gold tag line.
	-- They sit in a scroll list (owner reading 14); rows are made when first needed (SF.Row).
	W.next = {}
	SF.BuildList()

	W.rule = W:CreateTexture(nil, "ARTWORK")
	W.rule:SetHeight(1)
	W.rule:SetColorTexture(T.RGB(HIGHLIGHT_FONT_COLOR))
	W.rule:SetAlpha(0.14)
	W.xp = FS(W, "small")
	W.xp:SetTextColor(T.Tracker("Normal"))
	-- hover the XP line: planned level here, own deviation, time forecast (Welle 5b)
	W.xpHit = CreateFrame("Frame", nil, W)
	W.xpHit:SetAllPoints(W.xp)
	W.xpHit:EnableMouse(true)
	W.xpHit:SetScript("OnEnter", function(self)
		SF.ShowXPTip(self)
	end)
	W.xpHit:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	W.xpHit:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" and not UI.editing then
			ns.Menu.Open(W)
		end
	end)
	W.reach = FS(W, "small")
	W.reach:SetTextColor(T.RGB(NORMAL_FONT_COLOR))
	W.status = FS(W, "status")
	W.status:SetTextColor(T.RGB(NORMAL_FONT_COLOR))

	W:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" and not UI.editing then
			ns.Menu.Open(self)
		end
	end)
	W:SetScript("OnUpdate", function(_, elapsed)
		SF.Tick(elapsed)
	end)
	W:SetScript("OnSizeChanged", function(_, width, height)
		SF.OnSized(width, height)
	end)
	SF.BuildGrip()
	UI.Mover(W, "window", L.EDIT_WINDOW, SF.DefaultPoint, { mouse = true, drag = SF.CanDrag, top = true })
end

-- Position --------------------------------------------------------------------------------------------

-- Free drag (owner reading 16): left button on the header band, not locked, not while sizing. The
-- fight is checked by UI.CanMove.
function SF.CanDrag()
	if not W or SF.sizing or UI.Get("lock") or not GetCursorPosition then
		return false
	end
	local _, y = GetCursorPosition()
	local scale, top = W:GetEffectiveScale(), W:GetTop()
	if type(y) ~= "number" or type(scale) ~= "number" or scale <= 0 or type(top) ~= "number" then
		return false
	end
	return y / scale >= top - SF.HEADER
end

-- Does Blizzard's quest tracker show? Not with "hidden", unless the module that hides it is off or
-- the first start is still open (the option starts after it, UI/QuestWatch.lua QW.Mode).
function SF.TrackerShown()
	if UI.Get("tracker") ~= "hide" or not UI.DB().setupDone then
		return true
	end
	local state = M.state.questwatch
	return state ~= nil and state ~= "on" and state ~= "planned"
end

local function Overlaps(a1, a2, b1, b2)
	return a1 < b2 and b1 < a2
end

-- Left edge of the action bars that stand at the right screen edge, one next to the other.
local function BarsLeft(screenR)
	local rects = {}
	for _, name in ipairs(SF.BARS_RIGHT) do
		local l, r = UI.Rect(_G[name])
		if l then
			rects[#rects + 1] = { l, r }
		end
	end
	local wall, moved = screenR, true
	while moved do
		moved = false
		for _, b in ipairs(rects) do
			if b[1] < wall and b[2] >= wall - SF.GAP then
				wall, moved = b[1], true
			end
		end
	end
	return math.min(wall, screenR - SF.BARS) -- room for both right bars, shown or not
end

-- Top of the column right..right-width: below the minimap cluster when it stands above, never higher
-- than the top of Blizzard's right container.
local function TopFor(screenT, right, width)
	local top = screenT - SF.TOP
	local l, r, _, b = UI.Rect(_G.MinimapCluster)
	if not l then
		return math.min(top, screenT - SF.MINIMAP - SF.GAP)
	end
	if Overlaps(right - width, right, l, r) and b > screenT / 2 then
		top = math.min(top, b - SF.GAP)
	end
	return top
end

-- Default anchor of the step window: { "TOPRIGHT", x, y } against UIParent's top right corner.
function SF.DefaultPoint()
	local screenR, screenT = UIParent:GetRight(), UIParent:GetTop()
	if type(screenR) ~= "number" or type(screenT) ~= "number" or ns.Util.IsSecret(screenR) then
		return { "TOPRIGHT", -(SF.BARS + SF.GAP), -(SF.MINIMAP + SF.GAP) }
	end
	local s = 1
	if W then
		local ws, ps = W:GetEffectiveScale(), UIParent:GetEffectiveScale()
		if type(ws) == "number" and type(ps) == "number" and ps > 0 then
			s = ws / ps
		end
	end
	local width = SF.Width() * s
	local height = math.max(tonumber(W and W:GetHeight()) or 0, SF.HEADER) * s
	local right = BarsLeft(screenR) - SF.GAP
	local top = TopFor(screenT, right, width)
	if SF.TrackerShown() then
		local l, r, t, b = UI.Rect(_G.ObjectiveTrackerFrame)
		if not l then -- Blizzard's default place of the tracker
			l, r, t, b = screenR - SF.BARS - SF.TRACKER, screenR - SF.BARS, screenT - SF.TOP, 0
		end
		if Overlaps(right - width, right, l, r) and Overlaps(top - height, top, b, t) then
			right = l - SF.GAP
			top = TopFor(screenT, right, width)
		end
	end
	-- rounded away from the corner, so the gaps hold at every window scale
	return { "TOPRIGHT", math.floor((right - screenR) / s), math.floor((top - screenT) / s) }
end

-- Places the window at its default again when it has no saved place (login, layout, tracker option,
-- scale). Not during a drag or sizing, and like every position change not in a fight.
function SF.PlaceDefault()
	local m = UI.movers.window
	if not W or not m or m.moving or SF.sizing or UI.Position("window") then
		return
	end
	UI.OutOfCombat("place-window", function()
		if not (m.moving or SF.sizing or UI.Position("window")) then
			UI.Place("window")
		end
	end)
end

-- Blizzard lays out its bars in its own handler of the same event: measure one frame later.
local placeQueued = false
function SF.QueuePlace()
	if placeQueued then
		return
	end
	placeQueued = true
	C_Timer.After(0, function()
		placeQueued = false
		Guard.Call("window", SF.PlaceDefault)
	end)
end

-- Scroll list of the next steps: Blizzard's WowScrollBox with a MinimalScrollBar and a linear view
-- over one content frame (brain chapter 04 §6; wow-ui-source forever Shared/Scroll/ScrollTemplates.xml:
-- "Intended for static scroll boxes"). Without these Blizzard parts the list is a clipped frame: the
-- steps ahead show, the rest does not scroll.
function SF.BuildList()
	local box, bar
	if ScrollUtil and ScrollUtil.InitScrollBoxWithScrollBar and CreateScrollBoxLinearView then
		local ok1, b1 = pcall(CreateFrame, "Frame", nil, W, "WowScrollBox")
		local ok2, b2 = pcall(CreateFrame, "EventFrame", nil, W, "MinimalScrollBar")
		if ok1 and ok2 then
			box, bar = b1, b2
		end
	end
	box = box or CreateFrame("Frame", nil, W)
	local list = CreateFrame("Frame", nil, box)
	list.scrollable = true -- the linear view takes children with this flag (ScrollBoxLinearView.lua)
	list:SetHeight(1)
	if bar then
		bar:SetHideIfUnscrollable(true)
		local scrollView = CreateScrollBoxLinearView()
		scrollView:SetPanExtent(SF.ROW_PAN)
		ScrollUtil.InitScrollBoxWithScrollBar(box, bar, scrollView)
	else
		box:SetClipsChildren(true)
		list:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
		list:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
	end
	W.listBox, W.list, SF.bar = box, list, bar
end

-- Row i of the next steps (made on first use).
function SF.Row(i)
	local row = W.next[i]
	if row then
		return row
	end
	local parent = W.list
	row = {}
	row.bullet = FS(parent, "line")
	row.bullet:SetText(L.BULLET)
	row.tag = FS(parent, "small")
	row.tag:SetTextColor(T.RGB(NORMAL_FONT_COLOR))
	row.text = FS(parent, "line")
	row.text:SetTextColor(T.RGB(HIGHLIGHT_FONT_COLOR))
	row.hit = CreateFrame("Frame", nil, parent)
	row.hit:SetAllPoints(row.text)
	row.hit:EnableMouse(true)
	row.hit:Hide()
	row.hit:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then
			SF.DungeonMenu(row)
		end
	end)
	W.next[i] = row
	return row
end

-- Grip at the bottom right: Blizzard's PanelResizeButtonTemplate for the look and the resize cursor
-- (wow-ui-source forever Mainline/SharedUIPanelTemplates.xml), own mouse scripts for the rules.
function SF.BuildGrip()
	local ok, grip = pcall(CreateFrame, "Button", nil, W, "PanelResizeButtonTemplate")
	if not ok or not grip then
		return
	end
	grip:SetPoint("BOTTOMRIGHT", W, "BOTTOMRIGHT", -2, 2)
	grip:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then
			Guard.Call("window", SF.StartSizing)
		end
	end)
	grip:SetScript("OnMouseUp", function()
		Guard.Call("window", SF.StopSizing)
	end)
	SF.grip = grip
end

-- Layout --------------------------------------------------------------------------------------------

local function Height(fs)
	local h = fs.GetStringHeight and fs:GetStringHeight()
	return (type(h) == "number" and h > 0) and h or 14
end

local function Place(region, x, y)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", W, "TOPLEFT", x, -y)
end

-- Inside the scroll list; x counts from the window's left edge (the list spans the full width).
local function PlaceIn(region, x, y)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", W.list, "TOPLEFT", x, -y)
end

-- The collapse button follows the mini view on every draw, whoever changed it (Welle 5d, M5: the
-- developer preview cleared the mini flag without it, and the button kept showing "+").
local function ToggleLook()
	T.SetAtlas(W.toggle.tex, UI.DB().mini and "expand" or "collapse")
end

-- Quest item button (M8, UI/QuestItem.lua): room at the right of the current step, and the button
-- follows the step after every layout. Nothing of it is protected in the window itself.
local function ItemRoom()
	local qi = ns.QuestItem
	return qi and M.IsActive("questitem") and qi.Room() or 0
end

local function ItemFollow(top)
	local qi = ns.QuestItem
	if qi and M.IsActive("questitem") then
		Guard.Call("questitem", qi.Follow, top)
	end
end
SF.ItemFollow = ItemFollow

-- Anchors every visible part from top to bottom and sizes the window to its content.
function SF.Layout()
	local mini = UI.DB().mini == true
	ToggleLook()
	local total = SF.Width()
	local x = TextX()
	local width = total - x - SF.RIGHT
	local y = SF.HEADER + 10
	if not SF.sizing then
		W:SetWidth(total)
	end
	local trimL, trimR = SF.HEADER_TRIM[1], SF.HEADER_TRIM[2]
	local band = total / (1 - trimL - trimR)
	W.header:ClearAllPoints()
	W.header:SetPoint("TOPLEFT", W, "TOPLEFT", -band * trimL, 0)
	W.header:SetPoint("TOPRIGHT", W, "TOPRIGHT", band * trimR, 0)

	-- banner
	local bannerShown = W.banner:IsShown()
	if bannerShown then
		W.banner:SetWidth(width)
		Place(W.banner, x, y)
		y = y + Height(W.banner) + 7
		local bx, rowH = x, 0
		for _, b in ipairs({ W.btnReaccept, W.btnSkipChain, W.btnShow, W.btnYes, W.btnNo }) do
			if b:IsShown() then
				local bw = FitButton(b)
				if bx > x and bx + bw > total - SF.RIGHT then
					bx, y = x, y + rowH + 6
				end
				Place(b, bx, y)
				bx, rowH = bx + bw + 6, 22
			end
		end
		y = y + rowH + 10
	end
	W.icon:ClearAllPoints()
	if bannerShown and view.failAt == "banner" then
		W.icon:SetPoint("TOPLEFT", W, "TOPLEFT", SF.LEFT, -(SF.HEADER + 10))
	else
		W.icon:SetPoint("CENTER", W.box, "CENTER")
	end
	if W.riddle:IsShown() and not mini then
		W.riddle:SetWidth(width)
		Place(W.riddle, x, y)
		y = y + Height(W.riddle) + 8
	end
	W.riddle:SetAlpha(mini and 0 or 1)

	-- current step; the quest item button (M8) stands at its right
	local curTop = y
	local room = W.step:IsShown() and ItemRoom() or 0
	W.step:SetWidth(width - room)
	Place(W.step, x, y)
	W.box:ClearAllPoints()
	W.box:SetPoint("TOPLEFT", W, "TOPLEFT", SF.LEFT, -(y + 1))
	y = y + Height(W.step)
	if W.detail:IsShown() and not mini then
		W.detail:SetWidth(width - room)
		Place(W.detail, x, y + 4)
		y = y + 4 + Height(W.detail)
	end
	if W.warn:IsShown() then
		W.warn:SetWidth(width - room)
		Place(W.warn, x, y + 4)
		y = y + 4 + Height(W.warn)
	end
	if room > 0 then
		y = math.max(y, curTop + ns.QuestItem.SIZE + 4) -- the next steps start below the button
	end
	W.cur:ClearAllPoints()
	W.cur:SetPoint("TOPLEFT", W, "TOPLEFT", 0, -curTop)
	W.cur:SetPoint("RIGHT", W, "RIGHT", 0, 0)
	W.cur:SetHeight(y - curTop)
	W.glow:ClearAllPoints()
	W.glow:SetPoint("LEFT", W, "TOPLEFT", 0, -(curTop + 10))
	W.glow:SetPoint("RIGHT", W, "TOPRIGHT", 0, -(curTop + 10))

	-- next steps in the scroll list; tops and bottoms of each row inside the list
	local nx = SF.LEFT + SF.INDENT
	local nwidth = total - nx - SF.BULLET - SF.RIGHT
	local tops, bottoms, ly = {}, {}, 0
	for _, row in ipairs(W.next) do
		local on = row.text:IsShown() and not mini
		if on then
			ly = ly + (#tops > 0 and SF.ROW_GAP or 0)
			tops[#tops + 1] = ly
			PlaceIn(row.bullet, nx, ly)
			if row.tag:IsShown() then
				row.tag:SetWidth(nwidth)
				PlaceIn(row.tag, nx + SF.BULLET, ly)
				ly = ly + Height(row.tag)
			end
			row.text:SetWidth(nwidth)
			PlaceIn(row.text, nx + SF.BULLET, ly)
			ly = ly + Height(row.text)
			bottoms[#bottoms + 1] = ly
		end
		row.bullet:SetShown(on)
	end
	SF.rowTops, SF.rowBottoms = tops, bottoms
	W.list:SetHeight(math.max(ly, 1))
	local shown = math.min(SF.Ahead(), #bottoms)
	local listH = shown > 0 and (bottoms[shown] + SF.DESCENT) or 0
	local listTop = y + SF.LIST_GAP
	SF.listTop = listTop
	if SF.sizing then
		local maxH = bottoms[math.min(SF.MAX_AHEAD, #bottoms)] or 0
		listH = Clamp((W:GetHeight() or 0) - listTop - SF.below, 0, maxH + SF.DESCENT)
	end
	if listH > 0 then
		y = listTop
		W.listBox:ClearAllPoints()
		W.listBox:SetPoint("TOPLEFT", W, "TOPLEFT", 0, -y)
		W.listBox:SetPoint("RIGHT", W, "RIGHT", 0, 0)
		W.listBox:SetHeight(listH)
		W.listBox:Show()
		y = y + listH
	else
		W.listBox:SetHeight(1)
		W.listBox:Hide()
	end
	if SF.bar then
		SF.bar:ClearAllPoints()
		SF.bar:SetPoint("TOPRIGHT", W.listBox, "TOPRIGHT", -2, 0)
		SF.bar:SetPoint("BOTTOMRIGHT", W.listBox, "BOTTOMRIGHT", -2, 0)
		SF.ShowBar(listH > 0 and not mini and (SF.sizing or SF.Ahead() > UI.DEFAULTS.ahead))
		W.listBox:FullUpdate(ScrollBoxConstants and ScrollBoxConstants.UpdateImmediately or true)
	end
	local fixedTop = y - listH - (listH > 0 and SF.LIST_GAP or 0)

	-- XP line, route falls short, status
	local lx = SF.LEFT + SF.INDENT
	local lwidth = total - lx - SF.RIGHT
	if W.xp:IsShown() and not mini then
		y = y + 12
		W.rule:ClearAllPoints()
		W.rule:SetPoint("TOPLEFT", W, "TOPLEFT", lx, -y)
		W.rule:SetPoint("RIGHT", W, "RIGHT", -SF.RIGHT, 0)
		W.rule:Show()
		y = y + 7
		W.xp:SetWidth(lwidth)
		Place(W.xp, lx, y)
		y = y + Height(W.xp)
		W.xpHit:Show()
	else
		W.rule:Hide()
		W.xpHit:Hide()
	end
	if W.reach:IsShown() and not mini then
		W.reach:SetWidth(lwidth)
		Place(W.reach, lx, y + 4)
		y = y + 4 + Height(W.reach)
	end
	if W.status:IsShown() then
		W.status:SetWidth(lwidth)
		Place(W.status, lx, y + 10)
		y = y + 10 + Height(W.status)
	end
	-- mini view hides details, next steps, XP and the route note (design v2 "Mini-Modus")
	W.detail:SetAlpha(mini and 0 or 1)
	W.xp:SetAlpha(mini and 0 or 1)
	W.reach:SetAlpha(mini and 0 or 1)
	for _, row in ipairs(W.next) do
		row.text:SetAlpha(mini and 0 or row.alpha or SF.NEXT_ALPHA)
		row.tag:SetAlpha(mini and 0 or 1)
		row.bullet:SetAlpha(mini and 0 or row.alpha or SF.NEXT_ALPHA)
	end
	local height = y + 12
	-- what lies below the list: a height drag changes only the list
	SF.below = height - (listH > 0 and (listTop + listH) or fixedTop)
	SF.height = height
	if not SF.sizing then
		W:SetHeight(height)
		local maxRows = math.min(SF.MAX_AHEAD, #bottoms)
		local fixed = height - listH - (listH > 0 and SF.LIST_GAP or 0)
		local maxH = fixed + (maxRows > 0 and (SF.LIST_GAP + bottoms[maxRows]) or 0)
		W:SetResizeBounds(SF.MIN_WIDTH, fixed, SF.MAX_WIDTH, math.max(fixed, maxH))
	end
	if SF.grip then
		SF.grip:SetShown(not mini)
	end
	ItemFollow(curTop)
end

-- Looks: background, scale, combat dim, mini toggle -----------------------------------------------

function SF.BackgroundAlpha()
	local contrast = tonumber(UI.CVar("questTextContrast") or "0") or 0
	if contrast >= 1 then
		return 0.8 -- concept §2.8: high-contrast quest text raises the window background to 80 %
	end
	return (UI.Get("bgAlpha") or UI.DEFAULTS.bgAlpha) / 100
end

-- Scroll bar of the list (Welle 5d): only while the window is drawn larger than the default steps
-- ahead or being sized (design v2 shows it only then, Q4), never in the mini view, where it hung below
-- the window (M6). Blizzard's bar shows itself when the list can scroll only while hideIfUnscrollable is
-- on; with it off, "explicit Show or Hide calls from owning code" stay (ScrollBar.lua, live and
-- forever). The mouse wheel scrolls the box either way.
function SF.ShowBar(on)
	local bar = SF.bar
	if not bar then
		return
	end
	bar:SetHideIfUnscrollable(on == true)
	if not on then
		bar:Hide()
	end
	SF.barWanted = on == true
end

function SF.ApplyLook()
	if not W then
		return
	end
	W.bg:SetColorTexture(0, 0, 0, SF.BackgroundAlpha()) -- black like the shadow (rule N4)
	W:SetScale((UI.Get("scale") or 100) / 100)
	local dim = UI.Fighting() and UI.Get("dim")
	W:SetAlpha(dim and UI.COMBAT_ALPHA or 1)
	ToggleLook()
end

function SF.SetMini(on)
	UI.DB().mini = on and true or nil
	SF.ApplyLook()
	SF.Refresh()
end

-- Size (owner reading 14) -----------------------------------------------------------------------------

-- Next steps whose middle fits into a list of height h (0..MAX_AHEAD).
function SF.RowsFor(h)
	local n = 0
	for i, bottom in ipairs(SF.rowBottoms or {}) do
		if i > SF.MAX_AHEAD or h < (SF.rowTops[i] + bottom) / 2 then
			break
		end
		n = i
	end
	return n
end

-- Rows of the list inside its visible part, top to bottom (tests and the developer preview).
function SF.VisibleRows()
	local out = {}
	local h = W.listBox:IsShown() and (W.listBox:GetHeight() or 0) or 0
	local k = 0
	for _, row in ipairs(W.next) do
		if row.text:IsShown() and row.bullet:IsShown() then
			k = k + 1
			if (SF.rowBottoms[k] or math.huge) > h + 0.5 then
				break
			end
			out[#out + 1] = row
		end
	end
	return out
end

-- Grip pressed: never in a fight, in Edit Mode or in the mini view.
function SF.StartSizing()
	if not W or SF.sizing or UI.Fighting() or UI.editing or UI.DB().mini then
		return false
	end
	SF.sizing = true
	SF.Refresh() -- the whole list, also at 0 steps ahead, so the drag can show more
	W:StartSizing("BOTTOMRIGHT", true)
	W:SetUserPlaced(false) -- own saving (brain chapter 04 §4)
	return true
end

-- While dragging: the width follows at once, the height decides the steps ahead ("steps ahead" follows).
function SF.OnSized(_, height)
	if not (W and SF.sizing) then
		return
	end
	local n = SF.RowsFor((height or 0) - (SF.listTop or 0) - (SF.below or 0))
	if n ~= SF.Ahead() then
		UI.Set("ahead", n) -- the settings page and the map pins follow; Refresh lays out again
	else
		SF.Layout()
	end
end

-- Grip released (or a fight starts): width saved per account, height snaps to the shown steps; the top
-- left corner stays where it is.
function SF.StopSizing()
	if not (W and SF.sizing) then
		return false
	end
	W:StopMovingOrSizing()
	local width = math.floor(Clamp(W:GetWidth() or SF.WIDTH, SF.MIN_WIDTH, SF.MAX_WIDTH) + 0.5)
	SF.sizing = false
	UI.SavePosition("window") -- held at the top edge (UI.AnchorTop), the top stays where it is
	UI.Set("width", width)
	SF.Refresh()
	return true
end

local function OnFight(_, _, fighting)
	if SF.grip then
		SF.grip:SetEnabled(not fighting)
	end
	if fighting then
		SF.StopSizing()
	end
end

-- Content ---------------------------------------------------------------------------------------------

local function StatusMessage()
	local newer = C.NewerVersion()
	if newer then
		view.versionShown = true
		return L.STATUS_NEW_VERSION:format(newer)
	end
	if ns.db and ns.db.safeMode then
		return L.STATUS_SAFE
	end
	for _, name in ipairs(M.order) do
		local s = M.state[name]
		if s == "disabled" or s == "error" then
			return L.STATUS_MODULE_OFF:format(name)
		end
	end
	if C.Missing() then
		return L.STATUS_NO_ROUTE
	end
	if view.message then
		return view.message
	end
	if view.navProblem == "instance" then
		return L.STATUS_INSTANCE
	elseif view.navProblem == "continent" then
		return L.STATUS_CONTINENT
	end
	if not view.info and view.started then
		-- Routes end below the level cap until the 1.x updates: say where it goes on (A32).
		local top = C.TopLevel()
		if top and top < C.MAX_LEVEL then
			return L.STATUS_END_MORE:format(top)
		end
		return L.STATUS_END
	end
end

local function SetLine(fs, text)
	fs:SetText(text or "")
	fs:SetShown(text ~= nil and text ~= "")
end

-- " 3/8" in gold behind the goal. plain: in the step's own color (abandoned quest, S5: the counter of a
-- failed step is no progress any more).
local function Counter(have, need, done, plain)
	if not need then
		return ""
	end
	if done then
		have = need
	end
	local text = ("%d/%d"):format(have or 0, need)
	-- L.NBSP keeps the counter with the last word (deDE: U+00A0, K1); "3/8" stood alone on a line
	return L.NBSP .. (plain and text or T.Wrap(NORMAL_FONT_COLOR, text))
end

-- Does a step concern quest q (accept, objectives, turn-in)? The abandon question marks the current
-- step only when it is about the abandoned quest (Welle 5d, M9); the runtime asks about a quest whose
-- accept step lies behind the current step, so the current step is often another quest.
function SF.StepHasQuest(info, q)
	if not (info and q) then
		return false
	end
	for _, v in ipairs(info.quests or {}) do
		if v == q then
			return true
		end
	end
	local V = ns.Routes.VERB
	for _, el in ipairs(info.step or {}) do
		if (el[1] == V.ACCEPT or el[1] == V.COMPLETE or el[1] == V.TURNIN) and el[2] == q then
			return true
		end
	end
	return false
end

local function RenderBanner(info)
	local pending = C.Pending()
	W.btnReaccept:Hide()
	W.btnSkipChain:Hide()
	W.btnShow:Hide()
	W.btnYes:Hide()
	W.btnNo:Hide()
	view.rumor = nil
	if pending then
		local follow = C.AbandonPreview() or {}
		local n = #follow
		local key = n == 0 and "ABANDONED_0" or n == 1 and "ABANDONED_1" or "ABANDONED_N"
		SetLine(W.banner, L[key]:format(ST.Quest(pending), n))
		W.btnReaccept:Show()
		W.btnSkipChain:SetText(n > 0 and L.SKIP_FOLLOW or L.SKIP)
		W.btnSkipChain:Show()
		return true
	end
	-- Replanning question (Welle 7): a new one never appears in a fight; one shown before stays.
	local offer = info and C.Offer()
	if offer and (offer.id == view.offerId or not UI.Fighting()) then
		view.offerId = offer.id
		SetLine(W.banner, ST.Offer(offer))
		local class = offer.kind == "class" or offer.kind == "later" or offer.kind == "ready"
		local opt = offer.kind == "opt"
		W.btnYes:SetText(
			opt and L.OPT_NOW or class and L.CLASS_NOW or offer.kind == "switch" and L.SWITCH_GO or L.ADJUST
		)
		W.btnNo:SetText(opt and L.OPT_OWN or class and L.CLASS_LATER or L.KEEP_ROUTE)
		W.btnYes:Show()
		W.btnNo:Show()
		return true
	end
	view.offerId = nil
	local rumor = view.rumorShown or (not UI.Fighting() and C.Rumor())
	if rumor and info then
		view.rumorShown, view.rumor = rumor, rumor
		SetLine(W.banner, L.RUMOR:format(rumor.text or ""))
		W.btnShow:Show()
		return true
	end
	SetLine(W.banner, nil)
	return false
end

-- Riddle line: not with an open abandon question, no new one in a fight; it goes after the next
-- completed step like the rumor.
local function RenderRiddle(info, pending)
	local riddle = info and not pending and (view.riddleShown or (not UI.Fighting() and C.Riddle())) or nil
	view.riddleShown = riddle or view.riddleShown
	SetLine(W.riddle, riddle and riddle.text and L.RIDDLE_LINE:format(riddle.text) or nil)
end

-- Dungeon hint (owner wish 11) as an optional step: "The Deadmines: accept “…”", tagged with Blizzard's
-- OPTIONAL and LFG_TYPE_DUNGEON and the level band. It sits behind the step where its first giver is
-- passed, or on top when that is now; right-click on it skips it like any step.
local function DungeonRow(hint)
	local titles = {}
	for _, q in ipairs(hint.quests or {}) do
		if q.state == "take" then
			titles[#titles + 1] = ST.Quest(q.q)
		end
	end
	local name = ST.Area(hint.area) or (LFG_TYPE_DUNGEON or "Dungeon")
	return {
		dungeon = hint,
		tag = L.OPT_TAG:format(OPTIONAL or "Optional", LFG_TYPE_DUNGEON or "Dungeon", hint.lo or 0, hint.hi or 0),
		text = #titles > 0 and L.DUNGEON_TAKE:format(name, ST.List(titles)) or name,
	}
end

-- Rows of the scroll list: the next LIST_MAX steps while any are shown (or the window is being sized).
function SF.NextRows(info)
	local ahead = (SF.Ahead() > 0 or (W and SF.sizing)) and SF.LIST_MAX or 0
	local rows = {}
	if not info or ahead <= 0 then
		return rows
	end
	local list = C.Upcoming(ahead)
	local hint = view.dungeon
	local placed = hint == nil
	if hint and (hint.first or 0) <= info.index then
		rows[1] = DungeonRow(hint)
		placed = true
	end
	for _, n in ipairs(list) do
		if #rows >= ahead then
			break
		end
		rows[#rows + 1] = { info = n, text = (ST.Step(n, false)) }
		if not placed and n.index >= (hint.first or 0) and #rows < ahead then
			rows[#rows + 1] = DungeonRow(hint)
			placed = true
		end
	end
	return rows
end

local function RenderNext(info)
	local rows = SF.NextRows(info)
	for i = 1, math.max(#rows, #W.next) do
		local r = rows[i]
		local row = r and SF.Row(i) or W.next[i]
		row.dungeon = r and r.dungeon
		if r and r.dungeon then
			SetLine(row.tag, r.tag)
			row.alpha = SF.DUNGEON_ALPHA
			row.text:SetMaxLines(4)
		else
			SetLine(row.tag, nil)
			row.alpha = SF.NEXT_ALPHA
			row.text:SetMaxLines(2)
		end
		SetLine(row.text, r and r.text or nil)
		row.hit:SetShown(row.dungeon ~= nil)
	end
end

-- Right-click on the optional dungeon step: skip it like a step (the route does not change).
function SF.DungeonMenu(row)
	local hint = row.dungeon
	if not (hint and MenuUtil and MenuUtil.CreateContextMenu) then
		return
	end
	MenuUtil.CreateContextMenu(row.hit, function(_, root)
		root:CreateTitle(L.TITLE)
		root:CreateButton(L.MENU_SKIP, function()
			C.SkipDungeon(hint.id)
			SF.Invalidate()
			SF.Refresh()
		end)
	end)
end

-- Draws a step. mode: "open" (default) or "done" (the check feedback before the next step).
-- Text of the hardcore warning (UI/Connect.lua C.Danger), or nil.
function SF.Warning(danger)
	if not danger then
		return nil
	elseif danger.elite then
		return L.WARN_ELITE
	end
	return L.WARN_GAP:format(danger.gap)
end

function SF.Render(info, mode)
	if not W then
		return
	end
	mode = mode or "open"
	view.info, view.mode = info, mode
	local pending = info and mode ~= "done" and C.Pending()
	W.title:SetText(ST.Header(info))
	view.zone = ST.HeaderZone(info)
	local module = info and C.Module(info.key)
	W.clock:SetShown(info ~= nil and (info.label or (module and module.label)) == "vorläufig")

	RenderBanner(mode ~= "done" and info or nil)
	RenderRiddle(mode ~= "done" and info or nil, pending)

	-- The fail symbol stands at the step when the step is about the abandoned quest, else in front of
	-- the abandon note (Welle 5d, M9).
	local here = pending and SF.StepHasQuest(info, pending)
	view.failAt = pending and (here and "step" or "banner") or nil
	if info then
		local text, have, need = ST.Step(info, true)
		if need then
			lastCount[info.key] = need
		elseif mode == "done" then
			need = lastCount[info.key]
		end
		if mode == "done" and T.Colorblind() then
			text = text .. L.DONE_MARK
		end
		W.step:SetText(text .. Counter(have, need, mode == "done", here))
		W.step:Show()
		-- An abandoned step keeps white text: Blizzard's DIM_RED stays under 2.5:1 behind any background
		-- opacity on bright ground (Welle 5d, M2); the fail symbol and the gold note carry the state.
		if mode == "done" then
			W.step:SetTextColor(T.Tracker("Complete"))
		else
			W.step:SetTextColor(T.RGB(HIGHLIGHT_FONT_COLOR))
		end
		view.target = Nav.Target(info)
		local dist = view.target and Nav.Vector(view.target)
		view.dist = dist and math.floor(dist + 0.5)
		SetLine(W.detail, ST.Detail(view.target, dist, view.zone))
		SetLine(W.warn, mode ~= "done" and SF.Warning(C.Danger(info)) or nil)
		-- icon: check box (open), check (done), fail (abandoned)
		W.box:SetShown(mode ~= "done" and not pending)
		W.tick:Hide()
		if mode == "done" then
			T.SetAtlas(W.icon, "check")
			W.icon:Show()
		elseif pending then
			T.SetAtlas(W.icon, "fail")
			W.icon:Show()
		else
			W.icon:Hide()
		end
		W.cur:Show()
	else
		W.step:SetText("")
		W.step:Hide()
		SetLine(W.detail, nil)
		SetLine(W.warn, nil)
		W.box:Hide()
		W.icon:Hide()
		W.tick:Hide()
		W.cur:Hide()
		view.target = nil
	end

	RenderNext(mode ~= "done" and info or nil)
	local b = info and view.balance
	SetLine(W.xp, info and ST.XP(b) or nil)
	SetLine(W.reach, info and ST.Reach(b) or nil)
	SetLine(W.status, StatusMessage())
	SF.Layout()
end

-- XP balance and dungeon hint cost a walk over the route: recomputed only when the step, the route or
-- the XP changes (Routes/Guide.lua: "call on StepChanged and XPBalance"), not on every quest log update.
function SF.Invalidate(balance)
	view.balance = balance or C.Balance()
	view.dungeon = C.Dungeon()
end

-- light = only the window's texts (quest log counts, titles loaded): the map pins and the arrow goal
-- follow only when the current step changed. A full refresh updates everything.
function SF.Refresh(light)
	if not W or not M.IsActive("window") then
		return
	end
	if UI.Paused() then
		W:Hide()
		ItemFollow()
		return
	end
	if view.playing then
		return -- the done feedback finishes first, then Refresh runs again
	end
	local before = view.info and view.info.key
	local cur = C.Current()
	view.started = view.started or cur ~= nil or C.Missing() ~= nil
	SF.Render(cur)
	W:SetShown(not SF.hidden)
	if light == true and before == (cur and cur.key) then
		return
	end
	if SF.bar and before ~= (cur and cur.key) then
		W.listBox:ScrollToBegin(true) -- a new current step: the list starts at its next step again
	end
	if ns.Arrow then
		ns.Arrow.SetTarget(view.target, view.info)
	end
	if ns.TomTom then
		ns.TomTom.SetTarget(view.target, view.info)
	end
	if ns.MapPins then
		ns.MapPins.Refresh()
	end
end

-- Coalesce bursts (quest log updates, quest titles loading) into one refresh.
local queued = false
function SF.Queue()
	if queued then
		return
	end
	queued = true
	C_Timer.After(
		0.2,
		Guard.Wrap("window", function()
			queued = false
			SF.Refresh(true)
		end)
	)
end

-- Done feedback: the check replaces the box, the counter shows the final count, a short glow inside the
-- window edges and one sound; after DONE_DELAY the next step moves up. In combat without glow and sound.
function SF.PlayDone(prev)
	if UI.Fighting() or not W:IsShown() then
		SF.Refresh()
		return
	end
	SF.Render(prev, "done")
	view.playing = true
	W.glowAnim:Restart()
	T.Play("IG_QUEST_LIST_COMPLETE")
	C_Timer.After(
		SF.DONE_DELAY,
		Guard.Wrap("window", function()
			view.playing = false
			SF.Refresh()
		end)
	)
end

function SF.OnStepChanged(_, cur, prev)
	view.message = nil
	SF.Invalidate()
	if prev and C.StepState(prev.key) == "done" then
		if view.rumorShown then -- a rumor goes after the next completed step (design v2, view 4)
			C.RumorDone(view.rumorShown.id)
		end
		if view.riddleShown then -- the riddle too; the next riddle of the zone follows
			C.RiddleDone(view.riddleShown.id)
		end
		view.rumorShown, view.riddleShown = nil, nil
		if view.versionShown then -- the version notice goes after the next completed step, once per session
			C.NewerVersionDone()
			view.versionShown = nil
		end
		SF.PlayDone(prev)
		return
	end
	SF.Refresh()
	if cur == nil then
		view.started = true
	end
end

-- Actions -------------------------------------------------------------------------------------------

function SF.CheckCurrent()
	if C.Pending() or view.playing then
		return false
	end
	W.tick:Show()
	return C.Check()
end

function SF.Undo()
	view.message = nil
	C.Undo()
	SF.Invalidate()
	SF.Refresh()
end

function SF.Back()
	view.message = nil
	C.Back()
	SF.Invalidate()
	SF.Refresh()
end

local function SkippedMessage(name, n, later)
	local key = n == 0 and "SKIPPED_0" or n == 1 and "SKIPPED_1" or "SKIPPED_N"
	if later then
		key = n == 0 and "LATER_0" or n == 1 and "LATER_1" or "LATER_N"
	end
	return L[key]:format(name, n)
end

-- Skip the current step, or answer an open abandon question with "skip". With follow-up quests the
-- player confirms in a dialog that names each of them (design v2 "Überspringen mit Folgequests").
function SF.AskSkip(key)
	local pending = C.Pending()
	local info = C.Current()
	local follow, name, run
	-- a class chain is postponed, never skipped for good (KQ-1105)
	local later = C.SkipPostpones(not pending and key or nil)
	if pending then
		follow = C.AbandonPreview() or {}
		name = ST.Quest(pending)
		run = function()
			if C.ResolveAbandon("skip") then
				view.message = SkippedMessage(name, #follow, later)
			end
			SF.Refresh()
		end
	else
		if not info and not key then
			return false
		end
		key = key or info.key
		follow = C.SkipPreview(key) or {}
		name = info and info.quests and info.quests[1] and ST.Quest(info.quests[1]) or (info and (ST.Step(info, false)))
		run = function()
			if C.Skip(key) then
				view.message = SkippedMessage(name or "", #follow, later)
			end
			SF.Refresh()
		end
	end
	if #follow == 0 then
		run()
		return true
	end
	local names = {}
	for i, q in ipairs(follow) do
		names[i] = ST.Quest(q)
	end
	local text = (later and L.LATER_SKIP_ASK or L.SKIP_ASK):format(name or "") .. "\n\n" .. table.concat(names, "\n")
	view.dialog = { text = text, run = run }
	StaticPopup_Show(SF.POPUP, text, nil, { run = run })
	return true
end

local function DefinePopup()
	if not StaticPopupDialogs or StaticPopupDialogs.BRAINDEADFOREVER_SKIP_CHAIN then
		return
	end
	-- Pattern of Blizzard's ABANDON_QUEST: text from the argument, Skip / Cancel.
	StaticPopupDialogs.BRAINDEADFOREVER_SKIP_CHAIN = {
		text = "%s",
		button1 = L.SKIP,
		button2 = CANCEL,
		OnAccept = function(_, data)
			if data and data.run then
				Guard.Call("window", data.run)
			end
		end,
		timeout = 0,
		whileDead = 1,
		exclusive = 1,
		hideOnEscape = 1,
	}
end

-- Answer to the replanning question. After "adjust" the status line names how many quests were left out.
function SF.AnswerOffer(yes)
	local offer = C.Offer()
	if not offer then
		return false
	end
	local ok = C.AnswerOffer(yes)
	if ok and yes and offer.kind == "over" then
		view.message = ST.Adjusted(#offer.drop)
	elseif ok and not yes and offer.kind == "opt" then
		local n = offer.quests and #offer.quests or 0
		view.message = n == 1 and L.OPT_LEFT_1 or L.OPT_LEFT_N:format(n)
	end
	view.offerId = nil
	SF.Invalidate()
	SF.Refresh()
	return ok
end

function SF.RevealRumor()
	local r = view.rumor
	if not r then
		return false
	end
	local t = C.Reveal(r.id)
	if t and ns.Arrow then
		ns.Arrow.SetExtra(t)
	end
	if ns.MapPins then
		ns.MapPins.Reveal(t)
	end
	return t ~= nil
end

-- Tooltips ------------------------------------------------------------------------------------------

function SF.ShowOriginTip(owner)
	local info = view.info
	if not info then
		return
	end
	local title, stepLine, lines = ST.Origin(info)
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:SetText(title, T.RGB(HIGHLIGHT_FONT_COLOR))
	GameTooltip:AddLine(stepLine, T.RGB(HIGHLIGHT_FONT_COLOR))
	GameTooltip:AddLine(L.TT_ORIGIN, T.RGB(NORMAL_FONT_COLOR))
	for _, line in ipairs(lines) do
		GameTooltip:AddLine(line, 1, 1, 1, true)
	end
	if info.chain == "incomplete" then -- prerequisites nobody confirmed yet (Welle 4)
		GameTooltip:AddLine(L.TT_CHAIN:format(L.STATUS_COLLECTING), 1, 1, 1, true)
	end
	GameTooltip:Show()
end

function SF.ShowXPTip(owner)
	local info = view.info
	if not info then
		return
	end
	local title, lines = ST.XPTip(info, view.balance, C.Forecast(), C.Earlier())
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:SetText(title, T.RGB(HIGHLIGHT_FONT_COLOR))
	for _, line in ipairs(lines) do
		if line.gold then
			GameTooltip:AddLine(line.text, T.RGB(NORMAL_FONT_COLOR))
		else
			GameTooltip:AddLine(line.text, 1, 1, 1, true)
		end
	end
	GameTooltip:Show()
end

function SF.ShowProvisionalTip(owner)
	local info = view.info
	if not info then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
	GameTooltip:SetText(L.PROV_TITLE, T.RGB(HIGHLIGHT_FONT_COLOR))
	GameTooltip:AddLine(ST.Provisional(C.Module(info.key), C.Runs(info.key)), 1, 1, 1, true)
	GameTooltip:Show()
end

-- Usage hint once per account after the setup, never in combat (concept §2.4, rule O5). Without a
-- HelpTip (help switched off, gamepad UI, kiosk) the sentence goes once into the status line.
-- The hint waits while Blizzard's settings or the first start are open; it lay over the slider "Size"
-- and on the corner of the first start (Welle 5d, M13). Only "Got It" counts as seen: a hide for a
-- window in front (HelpTip:Hide closes without acknowledging when acknowledgeOnHide is off, HelpTip.lua
-- HelpTipTemplateMixin:Close, live and forever) brings it back afterwards.
function SF.HintBlocked()
	local panel = _G.SettingsPanel
	if panel and panel.IsShown and panel:IsShown() then
		return true
	end
	local setup = ns.Setup and ns.Setup.frame
	return setup ~= nil and setup:IsShown() == true
end

function SF.SuspendHint()
	if W and HelpTip and HelpTip.IsShowing and HelpTip:IsShowing(W, L.HELP_RIGHTCLICK) then
		HelpTip:Hide(W, L.HELP_RIGHTCLICK)
		view.hintWaiting = true
	end
end

function SF.ResumeHint()
	if view.hintWaiting and not SF.HintBlocked() then
		view.hintWaiting = nil
		SF.ShowHintOnce()
	end
end

-- Blizzard's settings window: hide the hint while it is open, show it again after. HookScript runs
-- after Blizzard's own handler.
function SF.WatchSettings()
	local panel = _G.SettingsPanel
	if SF.watching or not (panel and panel.HookScript) then
		return
	end
	SF.watching = true
	panel:HookScript("OnShow", function()
		Guard.Call("window", SF.SuspendHint)
	end)
	panel:HookScript("OnHide", function()
		Guard.Call("window", SF.ResumeHint)
	end)
end

function SF.ShowHintOnce()
	local db = UI.DB()
	db.hintsSeen = type(db.hintsSeen) == "table" and db.hintsSeen or {}
	if db.hintsSeen.rightclick then
		return
	end
	UI.OutOfCombat("hint-rightclick", function()
		if db.hintsSeen.rightclick or not W then
			return
		end
		if SF.HintBlocked() then
			view.hintWaiting = true
			return
		end
		local shown = HelpTip
			and HelpTip.Show
			and HelpTip:Show(W, {
				text = L.HELP_RIGHTCLICK,
				buttonStyle = HelpTip.ButtonStyle and HelpTip.ButtonStyle.GotIt,
				targetPoint = HelpTip.Point and HelpTip.Point.LeftEdgeCenter,
				system = ADDON,
				onAcknowledgeCallback = function()
					db.hintsSeen.rightclick = true
				end,
			})
		if not shown then
			db.hintsSeen.rightclick = true
			view.message = L.HELP_RIGHTCLICK
			SF.Refresh()
		end
	end)
end

-- Distance in the detail line, at most every DETAIL_EVERY seconds and only when the number changed.
local acc = 0
function SF.Tick(elapsed)
	acc = acc + elapsed
	if acc < SF.DETAIL_EVERY then
		return
	end
	acc = 0
	local t = view.target
	if not t or view.mode == "done" then
		return
	end
	local dist, why = Nav.Vector(t)
	local problem = dist == nil and why or nil
	if problem ~= view.navProblem then
		view.navProblem = problem
		SetLine(W.status, StatusMessage())
		SF.Layout()
	end
	local yd = dist and math.floor(dist + 0.5)
	if yd ~= view.dist then
		view.dist = yd
		W.detail:SetText(ST.Detail(t, dist, view.zone))
	end
end

-- For tests and the developer preview.
function SF.View()
	return view
end

function SF.SetMessage(text)
	view.message = text
	SF.Refresh()
end

-- Key binding "step window on/off" (UI/Bindings.lua): hides the window only, the arrow and the map pins
-- keep guiding. For this session only, so a /reload always brings the window back.
SF.hidden = false
function SF.ToggleWindow()
	SF.hidden = not SF.hidden
	SF.Refresh()
	return SF.hidden
end

-- Module ----------------------------------------------------------------------------------------------

local function Init()
	T.BuildFonts()
	Build()
	DefinePopup()
	SF.ApplyLook()
	W:Hide()
	C.Register("StepChanged", SF, SF.OnStepChanged)
	C.Register("RouteRecalculated", SF, function()
		SF.Invalidate()
		SF.Refresh()
	end)
	C.Register("XPBalance", SF, function(_, balance)
		SF.Invalidate(balance)
		SF.Queue()
	end)
	C.Register("QuestAbandoned", SF, function()
		SF.Refresh()
	end)
	-- The giver did not offer the quest of the step (Route.Offers): say so where the step was.
	C.Register("NotOffered", SF, function(_, q)
		SF.SetMessage(L.NOT_OFFERED:format(ST.Quest(q)))
	end)
	C.Register("OfferChanged", SF, function()
		SF.Refresh()
	end)
	C.OnFinds(SF, function()
		SF.Queue()
	end)
	for _, key in ipairs({ "bgAlpha", "scale", "dim", "combat" }) do
		UI.OnChange(key, SF, SF.ApplyLook)
	end
	for _, key in ipairs({ "ahead", "width", "paused", "style", "hint" }) do
		UI.OnChange(key, SF, SF.Refresh)
	end
	UI.OnChange("combat", OnFight, OnFight)
	UI.OnChange("hardcore", SF, function() -- warning and dungeon step follow the mode at once
		SF.Invalidate()
		SF.Refresh()
	end)
	-- default place: Blizzard's tracker shown or not, window scale and width, after Edit Mode
	for _, key in ipairs({ "tracker", "scale", "width", "editing" }) do
		UI.OnChange(key, SF.PlaceDefault, SF.PlaceDefault)
	end
	UI.OnChange("textSize", SF, function()
		T.ApplyFontScale()
		SF.Refresh()
	end)
	SF.WatchSettings()
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("TextSizeManager.OnTextScaleUpdated", function()
			T.ApplyFontScale()
			SF.Queue()
		end, SF)
	end
end

local function OnCVar(_, _, name)
	name = type(name) == "string" and name:lower() or ""
	if name == "questtextcontrast" or name == "colorblindmode" then
		SF.ApplyLook()
		SF.Queue()
	elseif name == "userfontscale" then
		T.ApplyFontScale()
		SF.Queue()
	end
end

M.Define("window", {
	core = true, -- the status line must still say "safe mode" in safe mode
	requires = {
		funcs = { "C_Texture.GetAtlasInfo", "CreateFont", "C_QuestLog.GetQuestObjectives", "C_Map.GetMapInfo" },
		events = { "PLAYER_LOGIN" },
	},
	optional = {
		funcs = {
			"C_QuestLog.GetTitleForQuestID",
			"C_QuestLog.RequestLoadQuestByID",
			"C_Item.GetItemNameByID",
			"MenuUtil.CreateContextMenu",
			"StaticPopup_Show",
			"HelpTip.Show",
			"PlaySound",
			"BreakUpLargeNumbers",
			"UnitPosition",
			"GetCursorPosition",
			"C_InputInterfaceStyle.GetCurrentStyle", -- places per UI type (UI/Core.lua, Welle 9 K8)
		},
		events = {
			"INPUT_DEVICE_INTERFACE_TRANSITION",
			"QUEST_DATA_LOAD_RESULT",
			"CVAR_UPDATE",
			"PLAYER_REGEN_DISABLED",
			"PLAYER_REGEN_ENABLED",
			"EDIT_MODE_LAYOUTS_UPDATED",
			"DISPLAY_SIZE_CHANGED",
			"UI_SCALE_CHANGED",
		},
	},
	init = Init,
	events = {
		PLAYER_LOGIN = function()
			C.ApplyStyle()
			SF.Invalidate()
			SF.Refresh()
		end,
		PLAYER_ENTERING_WORLD = function()
			SF.Queue()
			SF.QueuePlace() -- without a saved place the default is computed again at every login
		end,
		EDIT_MODE_LAYOUTS_UPDATED = SF.QueuePlace,
		DISPLAY_SIZE_CHANGED = SF.QueuePlace,
		UI_SCALE_CHANGED = SF.QueuePlace,
		ZONE_CHANGED_NEW_AREA = SF.Queue,
		QUEST_LOG_UPDATE = SF.Queue,
		QUEST_DATA_LOAD_RESULT = SF.Queue,
		CVAR_UPDATE = OnCVar,
	},
})
