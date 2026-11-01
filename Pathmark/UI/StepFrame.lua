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

-- UI/StepFrame.lua: module "window", the step display of design v2 (view 1). One background for the
-- whole window (black, 35 %), header band and content on the same width and edges (owner reading 1),
-- 300 units wide, fonts 15/13/12 (owner reading 2). States: normal, origin tooltip, done (check, glow,
-- sound), mini, combat (60 %), usage hint (HelpTip), right-click menu, status line, route falls short,
-- skip with follow-ups (StaticPopup), quest abandoned, optional dungeon step, rumor line; check box;
-- XP line. Reads the logic only through ns.Connect.
local ADDON, ns = ...
local L, UI, T, C, ST, Nav = ns.L, ns.UI, ns.Theme, ns.Connect, ns.StepText, ns.Nav
local M, Guard = ns.Modules, ns.Guard

local SF = {
	WIDTH = 300,
	HEADER = 36,
	ICON = 19,
	LEFT = 8, -- body padding left
	RIGHT = 12, -- body padding right
	GAP_ICON = 6,
	INDENT = 25, -- next steps, XP line and notes start under the step text
	BULLET = 11,
	DONE_DELAY = 0.9, -- the checked line stays this long before the next one moves up
	DETAIL_EVERY = 0.5, -- distance in the detail line at most twice per second
	POPUP = "PATHMARK_SKIP_CHAIN",
	DEFAULT = { "TOPRIGHT", -80, -260 },
}
ns.StepFrame = SF

local W -- the window
local view = {} -- what is shown: info, mode, target, rumor, message
local lastCount = {} -- step key -> needed count, for the final "8/8" of a done step

local function TextX()
	return SF.LEFT + SF.ICON + SF.GAP_ICON
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
	W:SetSize(SF.WIDTH, 120)
	W:SetFrameStrata("MEDIUM")
	W:EnableMouse(true)

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
	W.btnReaccept = Button(W, L.REACCEPT, function()
		C.ResolveAbandon("reaccept")
	end)
	W.btnSkipChain = Button(W, L.SKIP_FOLLOW, function()
		SF.AskSkip()
	end)
	W.btnShow = Button(W, L.SHOW_LOCATION, function()
		SF.RevealRumor()
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

	-- Next steps, dimmed, at most two lines each (T19); an optional step carries a gold tag line
	W.next = {}
	for i = 1, 3 do
		local row = {}
		row.bullet = FS(W, "line")
		row.bullet:SetText("·")
		row.tag = FS(W, "small")
		row.tag:SetTextColor(T.RGB(NORMAL_FONT_COLOR))
		row.text = FS(W, "line")
		row.text:SetTextColor(T.RGB(HIGHLIGHT_FONT_COLOR))
		row.hit = CreateFrame("Frame", nil, W)
		row.hit:SetAllPoints(row.text)
		row.hit:EnableMouse(true)
		row.hit:Hide()
		row.hit:SetScript("OnMouseUp", function(_, button)
			if button == "RightButton" then
				SF.DungeonMenu(row)
			end
		end)
		W.next[i] = row
	end

	W.rule = W:CreateTexture(nil, "ARTWORK")
	W.rule:SetHeight(1)
	W.rule:SetColorTexture(T.RGB(HIGHLIGHT_FONT_COLOR))
	W.rule:SetAlpha(0.14)
	W.xp = FS(W, "small")
	W.xp:SetTextColor(T.Tracker("Normal"))
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
	UI.Mover(W, "window", L.EDIT_WINDOW, SF.DEFAULT, true)
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

-- Anchors every visible part from top to bottom and sizes the window to its content.
function SF.Layout()
	local mini = UI.DB().mini == true
	local x = TextX()
	local width = SF.WIDTH - x - SF.RIGHT
	local y = SF.HEADER + 10

	-- banner
	local bannerShown = W.banner:IsShown()
	if bannerShown then
		W.banner:SetWidth(width)
		Place(W.banner, x, y)
		y = y + Height(W.banner) + 7
		local bx, rowH = x, 0
		for _, b in ipairs({ W.btnReaccept, W.btnSkipChain, W.btnShow }) do
			if b:IsShown() then
				local bw = FitButton(b)
				if bx > x and bx + bw > SF.WIDTH - SF.RIGHT then
					bx, y = x, y + rowH + 6
				end
				Place(b, bx, y)
				bx, rowH = bx + bw + 6, 22
			end
		end
		y = y + rowH + 10
	end

	-- current step
	local curTop = y
	W.step:SetWidth(width)
	Place(W.step, x, y)
	W.box:ClearAllPoints()
	W.box:SetPoint("TOPLEFT", W, "TOPLEFT", SF.LEFT, -(y + 1))
	y = y + Height(W.step)
	if W.detail:IsShown() and not mini then
		W.detail:SetWidth(width)
		Place(W.detail, x, y + 4)
		y = y + 4 + Height(W.detail)
	end
	W.cur:ClearAllPoints()
	W.cur:SetPoint("TOPLEFT", W, "TOPLEFT", 0, -curTop)
	W.cur:SetPoint("RIGHT", W, "RIGHT", 0, 0)
	W.cur:SetHeight(y - curTop)
	W.glow:ClearAllPoints()
	W.glow:SetPoint("LEFT", W, "TOPLEFT", 0, -(curTop + 10))
	W.glow:SetPoint("RIGHT", W, "TOPRIGHT", 0, -(curTop + 10))

	-- next steps
	local nx = SF.LEFT + SF.INDENT
	local nwidth = SF.WIDTH - nx - SF.BULLET - SF.RIGHT
	local first = true
	for _, row in ipairs(W.next) do
		if row.text:IsShown() and not mini then
			y = y + (first and 12 or 6)
			first = false
			Place(row.bullet, nx, y)
			if row.tag:IsShown() then
				row.tag:SetWidth(nwidth)
				Place(row.tag, nx + SF.BULLET, y)
				y = y + Height(row.tag)
			end
			row.text:SetWidth(nwidth)
			Place(row.text, nx + SF.BULLET, y)
			y = y + Height(row.text)
		end
		row.bullet:SetShown(row.text:IsShown() and not mini)
	end

	-- XP line, route falls short, status
	local lx = SF.LEFT + SF.INDENT
	local lwidth = SF.WIDTH - lx - SF.RIGHT
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
	else
		W.rule:Hide()
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
		row.text:SetAlpha(mini and 0 or row.alpha or 0.6)
		row.tag:SetAlpha(mini and 0 or 1)
		row.bullet:SetAlpha(mini and 0 or row.alpha or 0.6)
	end
	W:SetHeight(y + 12)
	SF.height = y + 12
end

-- Looks: background, scale, combat dim, mini toggle -----------------------------------------------

function SF.BackgroundAlpha()
	local contrast = tonumber(UI.CVar("questTextContrast") or "0") or 0
	if contrast >= 1 then
		return 0.8 -- concept §2.8: high-contrast quest text raises the window background to 80 %
	end
	return (UI.Get("bgAlpha") or 35) / 100
end

function SF.ApplyLook()
	if not W then
		return
	end
	W.bg:SetColorTexture(0, 0, 0, SF.BackgroundAlpha()) -- black like the shadow (rule N4)
	W:SetScale((UI.Get("scale") or 100) / 100)
	local dim = UI.Fighting() and UI.Get("dim")
	W:SetAlpha(dim and UI.COMBAT_ALPHA or 1)
	T.SetAtlas(W.toggle.tex, UI.DB().mini and "expand" or "collapse")
end

function SF.SetMini(on)
	UI.DB().mini = on and true or nil
	SF.ApplyLook()
	SF.Refresh()
end

-- Content ---------------------------------------------------------------------------------------------

local function StatusMessage()
	local newer = C.NewerVersion()
	if newer then
		return L.STATUS_NEW_VERSION
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
		return L.STATUS_END
	end
end

local function SetLine(fs, text)
	fs:SetText(text or "")
	fs:SetShown(text ~= nil and text ~= "")
end

local function Counter(have, need, done)
	if not need then
		return ""
	end
	if done then
		have = need
	end
	return " " .. T.Wrap(NORMAL_FONT_COLOR, ("%d/%d"):format(have or 0, need))
end

local function RenderBanner(info)
	local pending = C.Pending()
	W.btnReaccept:Hide()
	W.btnSkipChain:Hide()
	W.btnShow:Hide()
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

function SF.NextRows(info)
	local ahead = UI.Get("ahead") or 3
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
	for i, row in ipairs(W.next) do
		local r = rows[i]
		row.dungeon = r and r.dungeon
		if r and r.dungeon then
			SetLine(row.tag, r.tag)
			row.alpha = 0.78
			row.text:SetMaxLines(4)
		else
			SetLine(row.tag, nil)
			row.alpha = 0.6
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
		root:CreateTitle(ADDON)
		root:CreateButton(L.MENU_SKIP, function()
			C.SkipDungeon(hint.id)
			SF.Invalidate()
			SF.Refresh()
		end)
	end)
end

-- Draws a step. mode: "open" (default) or "done" (the check feedback before the next step).
function SF.Render(info, mode)
	if not W then
		return
	end
	mode = mode or "open"
	view.info, view.mode = info, mode
	local pending = info and mode ~= "done" and C.Pending()
	W.title:SetText(ST.Header(info))
	local module = info and C.Module(info.key)
	W.clock:SetShown(info ~= nil and (info.label or (module and module.label)) == "vorläufig")

	RenderBanner(mode ~= "done" and info or nil)

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
		W.step:SetText(text .. Counter(have, need, mode == "done"))
		W.step:Show()
		if pending then
			W.step:SetTextColor(T.Tracker("Failed"))
		elseif mode == "done" then
			W.step:SetTextColor(T.Tracker("Complete"))
		else
			W.step:SetTextColor(T.RGB(HIGHLIGHT_FONT_COLOR))
		end
		view.target = Nav.Target(info)
		local dist = view.target and Nav.Vector(view.target)
		view.dist = dist and math.floor(dist + 0.5)
		SetLine(W.detail, ST.Detail(view.target, dist))
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
		return
	end
	if view.playing then
		return -- the done feedback finishes first, then Refresh runs again
	end
	local before = view.info and view.info.key
	local cur = C.Current()
	view.started = view.started or cur ~= nil or C.Missing() ~= nil
	SF.Render(cur)
	W:Show()
	if light == true and before == (cur and cur.key) then
		return
	end
	if ns.Arrow then
		ns.Arrow.SetTarget(view.target, view.info)
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
		view.rumorShown = nil
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

local function SkippedMessage(name, n)
	local key = n == 0 and "SKIPPED_0" or n == 1 and "SKIPPED_1" or "SKIPPED_N"
	return L[key]:format(name, n)
end

-- Skip the current step, or answer an open abandon question with "skip". With follow-up quests the
-- player confirms in a dialog that names each of them (design v2 "Überspringen mit Folgequests").
function SF.AskSkip(key)
	local pending = C.Pending()
	local info = C.Current()
	local follow, name, run
	if pending then
		follow = C.AbandonPreview() or {}
		name = ST.Quest(pending)
		run = function()
			if C.ResolveAbandon("skip") then
				view.message = SkippedMessage(name, #follow)
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
				view.message = SkippedMessage(name or "", #follow)
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
	local text = L.SKIP_ASK:format(name or "") .. "\n\n" .. table.concat(names, "\n")
	view.dialog = { text = text, run = run }
	StaticPopup_Show(SF.POPUP, text, nil, { run = run })
	return true
end

local function DefinePopup()
	if not StaticPopupDialogs or StaticPopupDialogs.PATHMARK_SKIP_CHAIN then
		return
	end
	-- Pattern of Blizzard's ABANDON_QUEST: text from the argument, Skip / Cancel.
	StaticPopupDialogs.PATHMARK_SKIP_CHAIN = {
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
		local shown = HelpTip
			and HelpTip.Show
			and HelpTip:Show(W, {
				text = L.HELP_RIGHTCLICK,
				buttonStyle = HelpTip.ButtonStyle and HelpTip.ButtonStyle.GotIt,
				targetPoint = HelpTip.Point and HelpTip.Point.LeftEdgeCenter,
				system = ADDON,
				acknowledgeOnHide = true,
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
		W.detail:SetText(ST.Detail(t, dist))
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
	C.OnFinds(SF, function()
		SF.Queue()
	end)
	for _, key in ipairs({ "bgAlpha", "scale", "dim", "combat" }) do
		UI.OnChange(key, SF, SF.ApplyLook)
	end
	for _, key in ipairs({ "ahead", "paused", "style", "hint" }) do
		UI.OnChange(key, SF, SF.Refresh)
	end
	UI.OnChange("textSize", SF, function()
		T.ApplyFontScale()
		SF.Refresh()
	end)
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
		},
		events = { "QUEST_DATA_LOAD_RESULT", "CVAR_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" },
	},
	init = Init,
	events = {
		PLAYER_LOGIN = function()
			C.ApplyStyle()
			SF.Invalidate()
			SF.Refresh()
		end,
		PLAYER_ENTERING_WORLD = SF.Queue,
		ZONE_CHANGED_NEW_AREA = SF.Queue,
		QUEST_LOG_UPDATE = SF.Queue,
		QUEST_DATA_LOAD_RESULT = SF.Queue,
		CVAR_UPDATE = OnCVar,
	},
})
