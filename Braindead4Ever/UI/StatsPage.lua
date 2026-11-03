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

-- UI/StatsPage.lua: module "statspage" (Welle 8, docs/RUN-STATS.md). Two windows in Blizzard's look:
--   page    "Your run": a calm table per level, per route section and the best times of the account,
--           each level with a small bar of its time and a line at the median of the class. Opened only
--           by the player (right-click menu, minimap button menu, /bd4 stats).
--   review  a card at level 10, 20 and 30, once per character, closable and switched off with one
--           click or in the settings; never in a fight or an instance, it waits for the next chance.
-- Values come from Routes/RunStats.lua; a comparison shows only with enough runs of other players
-- (Stats.MIN_RUNS), else "collecting data". Color never carries a value alone: every number is text,
-- the bar and the median line differ in shape. No badges, no points.
local _, ns = ...
local L, UI, T, ST = ns.L, ns.UI, ns.Theme, ns.StepText
local M, Guard = ns.Modules, ns.Guard
local S, RS = ns.Stats, ns.RunStats
local U = ns.Util
local Num, Str = U.Num, U.Str

local SP = {
	NAME = "BraindeadForeverStatsFrame", -- named so that Escape closes it (UISpecialFrames)
	RECAP_NAME = "BraindeadForeverRecapFrame",
	W = 680, -- German summary values ("54 erledigt • 2 übersprungen") fit (screenshot round 3)
	H = 480,
	RECAP_W = 500, -- the time split of the card fits in German
	RECAP_H = 500,
	PAD = 16,
	ROW = 18, -- one table row
	GAP = 6, -- between columns
	BAR = 8, -- height of a time bar
	TICK = 2, -- width of the median line
	RECAP_ROW = 14,
	RECAP_DELAY = 3, -- seconds after the level-up: Blizzard's level-up banner first
	REFRESH_DELAY = 0.5, -- changes of the tally while the page is open, coalesced
	ATLAS_FILL = "UI-HUD-ExperienceBar-Fill-Experience", -- Blizzard's XP bar, in the Forever and live inventories
	TABS = { "levels", "modules", "bests" },
	-- Columns per tab: text key of the header, width, justification; "bar" is the time bar.
	COLS = {
		levels = {
			{ "ST_COL_LEVEL", 44, "RIGHT" },
			{ "ST_COL_TIME", 96 },
			{ "bar", 140 },
			{ "ST_COL_MEDIAN", 90 },
			{ "ST_COL_FASTER", 80 },
			{ "ST_COL_RATE", 70, "RIGHT" },
		},
		modules = {
			{ "ST_COL_SECTION", 180 },
			{ "ST_COL_TIME", 84 },
			{ "bar", 110 },
			{ "ST_COL_MEDIAN", 86 },
			{ "ST_COL_FASTER", 70 },
		},
		bests = {
			{ "ST_COL_BAND", 90 },
			{ "ST_COL_TIME", 110 },
			{ "ST_COL_WHO", 230 },
			{ "ST_COL_DAY", 110 },
		},
	},
}
ns.StatsPage = SP

local page, recap -- the windows, made on first use
local source -- nil: live values; the developer preview puts a demo source here
SP.tab = 1

local function Duration(secs)
	return ST.Duration(secs)
end

local function Pct(v)
	return L.ST_PERCENT:format(v)
end

local function Way(g)
	return L["WAY_" .. (g or "p")] or L.WAY_p
end

local function Day(day)
	if not (day and date) then
		return L.ST_NONE
	end
	return date(L.ST_DATE, day * 86400)
end

-- Live source ---------------------------------------------------------------------------------------

local live = {}

function live.Request(owner, fn)
	RS.Request(owner, fn)
end

function live.Cancel(owner)
	RS.Cancel(owner)
end

function live.Building()
	return RS.Building()
end

-- Zone of a route module: the first map its steps go to.
local function ModuleZone(mod)
	local V = ns.Routes and ns.Routes.VERB
	for _, step in ipairs(mod and mod.steps or {}) do
		for _, el in ipairs(step) do
			if V and el[1] == V.TRAVEL then
				return ST.MapName(el[3])
			elseif V and el[1] == V.GOTO then
				return ST.MapName(el[2])
			end
		end
	end
end

local function ModuleName(run)
	local R = ns.Route
	local key = run.key or (R and R.ModuleKey and R.ModuleKey(run.num))
	local mod = key and R and R.Module and R.Module(key)
	local zone = ModuleZone(mod)
	local lv = mod and mod.levels
	if zone and lv then
		local range = lv[1] == lv[2] and tostring(lv[1]) or L.ST_RANGE:format(lv[1], lv[2])
		return L.ST_MODULE_NAME:format(zone, range)
	end
	return zone or L.ST_MODULE_FALLBACK:format(run.num or 0)
end

-- The page's numbers: { level, race, class, total, quests, skipped, deaths, rate, forecast, runs,
-- computing, levels = { row }, modules = { row }, bests = { row } }. A level row: { level, rec, cur,
-- part, g, skipped, cmp }. Comparison only for whole, closed levels and from the index given.
function live.Page(idx)
	local char, acct, tally = RS.Char(), RS.Account(), RS.Tally()
	if not char then
		return { levels = {}, modules = {}, bests = {} }
	end
	local m = {
		level = Num(UnitLevel("player")) or 1,
		race = Str((UnitRace("player"))),
		class = Str((UnitClass("player"))),
		total = 0,
		quests = 0,
		skipped = 0,
		deaths = 0,
		runs = idx and idx.used or nil,
		computing = RS.Building(),
		levels = {},
		modules = {},
		bests = {},
	}
	local skippedNow = RS.Skipped()
	for l = 1, S.TOP do
		local r = char.lv[l]
		if type(r) == "table" then
			local cur = tally and tally.level == l
			local row = {
				level = l,
				rec = r,
				cur = cur,
				part = not r.full,
				g = S.Group(r.mo, r.o),
				skipped = S.Skipped(r, cur and skippedNow or nil),
			}
			if r.full and not cur and idx then
				row.cmp = S.Compare(idx, "l", l, 0, row.g, r.s)
			end
			m.levels[#m.levels + 1] = row
			m.total = m.total + (tonumber(r.s) or 0)
			m.quests = m.quests + (tonumber(r.n) or 0)
			m.skipped = m.skipped + (row.skipped or 0)
			m.deaths = m.deaths + (tonumber(r.d) or 0)
		end
	end
	for _, run in ipairs(char.mods) do
		local g = S.Group(run.mo, run.o)
		local R = ns.Route
		local key = run.key or (R and R.ModuleKey and R.ModuleKey(run.num))
		local mod = key and R and R.Module and R.Module(key)
		m.modules[#m.modules + 1] = {
			name = ModuleName(run),
			lo = mod and mod.levels and mod.levels[1],
			s = run.s,
			g = g,
			level = run.l,
			cmp = idx and S.Compare(idx, "m", run.num, run.v, g, run.s) or nil,
		}
	end
	local tok = RS.Token()
	for top = S.BAND, S.TOP, S.BAND do
		local b = acct.best[top]
		if type(b) == "table" and tonumber(b.s) then
			m.bests[#m.bests + 1] = {
				top = top,
				s = b.s,
				race = RS.RaceName(b.r),
				class = RS.ClassName(b.c),
				g = b.g,
				day = b.d,
				own = tok ~= nil and b.t == tok,
			}
		end
	end
	local R = ns.Route
	local f = R and R.Forecast and R.Forecast()
	if f then
		m.forecast = { state = f.state, seconds = f.seconds, level = f.level }
		m.rate = f.nextLevel
	end
	return m
end

-- The review card's numbers for the band ending at `level`: { top, band (Stats.Band), race, class, g,
-- cmp, best, own, rows = { { level, s, median } } }.
function live.Recap(level, idx)
	local char, acct = RS.Char(), RS.Account()
	local band = S.Band(char.lv, level)
	local m = {
		top = level,
		band = band,
		race = Str((UnitRace("player"))),
		class = Str((UnitClass("player"))),
		g = band.g,
		rows = {},
	}
	if band.complete and idx then
		m.cmp = S.Compare(idx, "b", level, 0, band.g, band.s)
	elseif idx then
		m.cmp = { state = "collecting", n = 0, need = S.MIN_RUNS, partial = true }
	end
	local b = acct.best[level]
	if type(b) == "table" and tonumber(b.s) then
		m.best = {
			s = b.s,
			race = RS.RaceName(b.r),
			class = RS.ClassName(b.c),
			own = b.t ~= nil and b.t == RS.Token() and band.complete and b.s == band.s,
		}
	end
	for l = band.lo, band.hi do
		local r = char.lv[l]
		if type(r) == "table" and r.full then
			local g = S.Group(r.mo, r.o)
			local cmp = idx and S.Compare(idx, "l", l, 0, g, r.s)
			m.rows[#m.rows + 1] = { level = l, s = r.s, median = cmp and cmp.median }
		end
	end
	return m
end

local function Src()
	return source or live
end

-- For the developer preview: a source with Page(idx), Recap(level, idx), Request, Cancel, Building.
function SP.Use(src)
	source = src
end

-- Building ------------------------------------------------------------------------------------------

local function Text(parent, font, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", font)
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	return fs
end

-- A time bar: track, fill in Blizzard's XP bar atlas, a white line at the median (shape, not color).
local function Bar(parent)
	local b = {}
	b.track = parent:CreateTexture(nil, "BACKGROUND")
	b.track:SetColorTexture(0, 0, 0, 0.5) -- shadow black, like the window background
	b.track:SetHeight(SP.BAR)
	b.fill = parent:CreateTexture(nil, "ARTWORK")
	T.SetAtlas(b.fill, SP.ATLAS_FILL)
	b.fill:SetHeight(SP.BAR)
	b.tick = parent:CreateTexture(nil, "OVERLAY")
	b.tick:SetColorTexture(T.RGB(HIGHLIGHT_FONT_COLOR))
	b.tick:SetWidth(SP.TICK)
	return b
end

-- own and median in seconds, scale = seconds of the full width.
local function SetBar(b, parent, x, width, own, median, scale, height)
	local function show(tex, on)
		if on then
			tex:Show()
		else
			tex:Hide()
		end
	end
	scale = (scale and scale > 0) and scale or 1
	b.track:ClearAllPoints()
	b.track:SetPoint("LEFT", parent, "LEFT", x, 0)
	b.track:SetWidth(width)
	show(b.track, own ~= nil)
	local w = own and math.max(1, math.floor(width * math.min(own, scale) / scale + 0.5)) or 0
	b.fill:ClearAllPoints()
	b.fill:SetPoint("LEFT", parent, "LEFT", x, 0)
	b.fill:SetWidth(w)
	show(b.fill, own ~= nil and own > 0)
	b.tick:ClearAllPoints()
	if median then
		local mx = math.floor(width * math.min(median, scale) / scale + 0.5)
		b.tick:SetPoint("LEFT", parent, "LEFT", x + mx - SP.TICK / 2, 0)
		b.tick:SetHeight(height or (SP.BAR + 6))
	end
	show(b.tick, median ~= nil)
end

-- Scroll list of the table: Blizzard's WowScrollBox with a MinimalScrollBar over one content frame,
-- as in the step window (UI/StepFrame.lua); a clipped frame where the client lacks them.
local function BuildList(parent)
	local box, bar
	if ScrollUtil and ScrollUtil.InitScrollBoxWithScrollBar and CreateScrollBoxLinearView then
		local ok1, b1 = pcall(CreateFrame, "Frame", nil, parent, "WowScrollBox")
		local ok2, b2 = pcall(CreateFrame, "EventFrame", nil, parent, "MinimalScrollBar")
		if ok1 and ok2 then
			box, bar = b1, b2
		end
	end
	box = box or CreateFrame("Frame", nil, parent)
	local list = CreateFrame("Frame", nil, box)
	list.scrollable = true -- the linear view takes children with this flag (ScrollBoxLinearView.lua)
	list:SetHeight(1)
	if bar then
		bar:SetHideIfUnscrollable(true)
		local view = CreateScrollBoxLinearView()
		view:SetPanExtent(SP.ROW)
		ScrollUtil.InitScrollBoxWithScrollBar(box, bar, view)
	else
		box:SetClipsChildren(true)
		list:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
		list:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
	end
	return box, list, bar
end

local function Row(i)
	local row = page.rows[i]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, page.list)
	row:SetHeight(SP.ROW)
	row:SetPoint("TOPLEFT", page.list, "TOPLEFT", 0, -(i - 1) * SP.ROW)
	row:SetPoint("RIGHT", page.list, "RIGHT", 0, 0)
	row.cells = {}
	for c = 1, 6 do
		row.cells[c] = Text(row, "GameFontHighlightSmall")
	end
	row.bar = Bar(row)
	row.hl = row:CreateTexture(nil, "HIGHLIGHT")
	row.hl:SetAllPoints()
	row.hl:SetColorTexture(T.RGB(NORMAL_FONT_COLOR))
	row.hl:SetAlpha(0.08)
	row:SetScript("OnEnter", function(self)
		Guard.Call("statspage", SP.RowTip, self)
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	page.rows[i] = row
	return row
end

-- Places a row's cells (or the header's) for the columns of a tab; returns the bar's x and width.
local function Columns(frame, cells, cols)
	local x, c, barX, barW = 0, 0, nil, nil
	for _, col in ipairs(cols) do
		if col[1] == "bar" then
			barX, barW = x, col[2]
		else
			c = c + 1
			local fs = cells[c]
			fs:ClearAllPoints()
			fs:SetPoint("LEFT", frame, "LEFT", x, 0)
			fs:SetWidth(col[2])
			fs:SetJustifyH(col[3] or "LEFT")
			fs:Show()
		end
		x = x + col[2] + SP.GAP
	end
	for i = c + 1, #cells do
		cells[i]:SetText("")
		cells[i]:Hide()
	end
	return barX, barW
end

local function SelectTab(i)
	SP.tab = i
	if PanelTemplates_SetTab and not SP.plainTabs and PanelTemplates_SetNumTabs then
		PanelTemplates_SetTab(page, i)
	else
		for j, tab in ipairs(page.Tabs) do
			tab:SetEnabled(j ~= i)
		end
	end
	SP.Render()
end

local function BuildPage()
	page = CreateFrame("Frame", SP.NAME, UIParent, "BasicFrameTemplateWithInset")
	page:SetSize(SP.W, SP.H)
	page:SetPoint("CENTER")
	page:SetFrameStrata("DIALOG")
	page:SetClampedToScreen(true)
	page:EnableMouse(true)
	page:SetMovable(true)
	page:RegisterForDrag("LeftButton")
	page:SetScript("OnDragStart", function(self)
		if not UI.Fighting() then
			self:StartMoving()
		end
	end)
	page:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
	end)
	tinsert(UISpecialFrames, SP.NAME)
	if page.TitleText then
		page.TitleText:SetText(L.ST_TITLE)
	end
	local P = SP.PAD
	page.head = Text(page, "GameFontNormalLarge")
	page.head:SetPoint("TOPLEFT", P, -34)
	-- summary: three label and value pairs in two columns
	page.sum = {}
	for i = 1, 6 do
		local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
		local x, y = P + col * 330, -62 - line * 18
		local label = Text(page, "GameFontNormal")
		label:SetPoint("TOPLEFT", x, y)
		label:SetWidth(130)
		local value = Text(page, "GameFontHighlight")
		value:SetPoint("TOPLEFT", x + 134, y)
		value:SetWidth(190)
		page.sum[i] = { label = label, value = value }
	end
	-- column headers and the table
	page.header = CreateFrame("Frame", nil, page)
	page.header:SetPoint("TOPLEFT", P, -128)
	page.header:SetPoint("RIGHT", page, "RIGHT", -P - 16, 0)
	page.header:SetHeight(SP.ROW)
	page.header.cells = {}
	for c = 1, 6 do
		page.header.cells[c] = Text(page.header, "GameFontNormalSmall")
	end
	page.header.barLabel = Text(page.header, "GameFontNormalSmall")
	page.listBox, page.list, page.bar = BuildList(page)
	page.listBox:SetPoint("TOPLEFT", page, "TOPLEFT", P, -128 - SP.ROW - 2)
	page.listBox:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -P, 34)
	if page.bar then
		page.bar:SetPoint("TOPLEFT", page.listBox, "TOPRIGHT", -10, 0)
		page.bar:SetPoint("BOTTOMLEFT", page.listBox, "BOTTOMRIGHT", -10, 0)
	end
	page.list:SetWidth(SP.W - 2 * P - 16)
	page.rows = {}
	page.empty = Text(page, "GameFontDisable")
	page.empty:SetPoint("TOPLEFT", page.listBox, "TOPLEFT", 0, -8)
	page.empty:SetWidth(SP.W - 2 * P)
	page.empty:SetWordWrap(true)
	page.legend = Text(page, "GameFontHighlightSmall")
	page.legend:SetPoint("BOTTOMLEFT", P, 14)
	page.legend:SetWidth(SP.W - 2 * P)
	page.legend:SetText(L.ST_LEGEND)
	-- tabs below the window (Blizzard's PanelTabButtonTemplate, SharedUIPanelTemplates.xml forever)
	if type(page.Tabs) ~= "table" then
		page.Tabs = {} -- Blizzard's tabs add themselves here (parentArray "Tabs")
	end
	for i, key in ipairs(SP.TABS) do
		local ok, tab = pcall(CreateFrame, "Button", SP.NAME .. "Tab" .. i, page, "PanelTabButtonTemplate")
		if not ok then
			SP.plainTabs = true
			tab = CreateFrame("Button", SP.NAME .. "Tab" .. i, page, "UIPanelButtonTemplate")
		end
		tab:SetID(i)
		tab:SetText(L["ST_TAB_" .. key:upper()])
		tab:SetScript("OnClick", function()
			Guard.Call("statspage", SelectTab, i)
		end)
		if page.Tabs[i] ~= tab then
			page.Tabs[i] = tab
		end
		local blizzard = not SP.plainTabs and PanelTemplates_SetNumTabs and PanelTemplates_TabResize
		if i == 1 then
			tab:SetPoint("TOPLEFT", page, "BOTTOMLEFT", 11, 2)
		elseif not blizzard then
			tab:SetPoint("TOPLEFT", page.Tabs[i - 1], "TOPRIGHT", 3, 0)
		end
		if blizzard then
			PanelTemplates_TabResize(tab, 0)
		else
			tab:SetSize(110, 24)
		end
	end
	if not SP.plainTabs and PanelTemplates_SetNumTabs and PanelTemplates_TabResize then
		PanelTemplates_SetNumTabs(page, #SP.TABS) -- anchors tabs 2 to 3 and sets page.numTabs
	end
	page:SetScript("OnHide", function()
		Src().Cancel(SP)
	end)
	page:Hide()
	SP.frame = page
	SelectTab(SP.tab)
end

-- Render ------------------------------------------------------------------------------------------

local function Comparison(cmp)
	if not cmp then
		return L.ST_NONE, ""
	end
	if cmp.state ~= "ready" then
		return L.ST_COLLECTING, ""
	end
	return Duration(cmp.median), cmp.faster and Pct(cmp.faster) or ""
end

local function Summary(m)
	local function set(i, label, value)
		page.sum[i].label:SetText(label)
		page.sum[i].value:SetText(value)
	end
	local rate = m.rate
	local rateText = (rate and rate.state == "ready") and T.Number(rate.perHour) or L.STATUS_COLLECTING
	local f = m.forecast
	local endText = L.STATUS_COLLECTING
	if f and f.state == "ready" then
		endText = L.ST_ROUTE_END_AT:format(f.level or 0, Duration(f.seconds))
	elseif f and f.state == "done" then
		endText = L.ST_ROUTE_DONE
	elseif not f then
		endText = L.ST_NONE
	end
	local runs
	if m.computing then
		runs = L.ST_COMPARE_BUSY
	elseif m.runs then
		runs = L.ST_COMPARE_RUNS:format(T.Number(m.runs))
	else
		runs = L.ST_NONE
	end
	set(1, L.ST_PLAYTIME, Duration(m.total or 0))
	set(2, L.ST_QUESTS, L.ST_QUESTS_FMT:format(T.Number(m.quests or 0), T.Number(m.skipped or 0)))
	set(3, L.ST_RATE, rateText)
	set(4, L.ST_DEATHS, T.Number(m.deaths or 0))
	set(5, L.ST_ROUTE_END, endText)
	set(6, L.ST_COMPARE, runs)
end

-- Rows of the current tab: { cells = { text, ... }, own, median, grey, data }.
local function TabRows(m, tab)
	local out = {}
	if tab == "levels" then
		for i = #m.levels, 1, -1 do -- newest level on top
			local r = m.levels[i]
			local rec = r.rec
			local time = Duration(rec.s or 0)
			if r.cur then
				time = L.ST_RUNNING_FMT:format(time)
			elseif r.part then
				time = L.ST_PART:format(time)
			end
			local median, faster = Comparison(r.cmp)
			if r.cur or r.part then
				median, faster = L.ST_NONE, ""
			end
			local rate = ""
			if (rec.s or 0) >= 60 and (rec.x or 0) > 0 then
				rate = T.Number(rec.x * 3600 / rec.s)
			end
			out[#out + 1] = {
				cells = { tostring(r.level), time, median, faster, rate },
				own = rec.s,
				median = r.cmp and r.cmp.state == "ready" and not r.cur and not r.part and r.cmp.median or nil,
				grey = r.cur or r.part,
				data = r,
				kind = "level",
			}
		end
	elseif tab == "modules" then
		for i = #m.modules, 1, -1 do
			local r = m.modules[i]
			local median, faster = Comparison(r.cmp)
			out[#out + 1] = {
				cells = { r.name, Duration(r.s or 0), median, faster },
				own = r.s,
				median = r.cmp and r.cmp.state == "ready" and r.cmp.median or nil,
				data = r,
				kind = "module",
			}
		end
	else
		for _, r in ipairs(m.bests) do
			local lo = math.max(1, r.top - S.BAND)
			local who = L.ST_WHO:format(r.race or L.ST_NONE, r.class or L.ST_NONE, Way(r.g))
			if r.own then
				who = L.ST_OWN:format(who)
			end
			out[#out + 1] = {
				cells = { L.ST_RANGE:format(lo, r.top), Duration(r.s), who, Day(r.day) },
				data = r,
				kind = "best",
			}
		end
	end
	return out
end

local EMPTY = { levels = "ST_EMPTY", modules = "ST_EMPTY_MODULES", bests = "ST_EMPTY_BESTS" }

function SP.Render()
	if not page then
		return
	end
	local m = SP.model or { levels = {}, modules = {}, bests = {} }
	page.head:SetText(L.ST_HEAD:format(m.level or 1, m.race or L.ST_NONE, m.class or L.ST_NONE))
	Summary(m)
	local tab = SP.TABS[SP.tab] or "levels"
	local cols = SP.COLS[tab]
	-- header
	local barX, barW = Columns(page.header, page.header.cells, cols)
	local c = 0
	for _, col in ipairs(cols) do
		if col[1] ~= "bar" then
			c = c + 1
			page.header.cells[c]:SetText(L[col[1]])
		end
	end
	page.header.barLabel:ClearAllPoints()
	if barX then
		page.header.barLabel:SetPoint("LEFT", page.header, "LEFT", barX, 0)
		page.header.barLabel:SetWidth(barW)
		page.header.barLabel:SetText(L.ST_COL_GRAPH)
		page.header.barLabel:Show()
	else
		page.header.barLabel:Hide()
	end
	-- rows
	local rows = TabRows(m, tab)
	local scale = 0
	for _, r in ipairs(rows) do
		scale = math.max(scale, r.own or 0, r.median or 0)
	end
	for i, r in ipairs(rows) do
		local row = Row(i)
		row.data, row.kind = r.data, r.kind
		local bx, bw = Columns(row, row.cells, cols)
		for k, text in ipairs(r.cells) do
			local fs = row.cells[k]
			fs:SetText(text)
			if r.grey then
				fs:SetTextColor(T.Tracker("Complete"))
			else
				fs:SetTextColor(T.RGB(HIGHLIGHT_FONT_COLOR))
			end
		end
		if bx then
			SetBar(row.bar, row, bx, bw, r.own, r.median, scale)
		else
			SetBar(row.bar, row, 0, 1, nil, nil, 1)
		end
		row:Show()
	end
	for i = #rows + 1, #page.rows do
		page.rows[i]:Hide()
	end
	page.list:SetHeight(math.max(1, #rows * SP.ROW))
	page.empty:SetText(L[EMPTY[tab]])
	if #rows == 0 then
		page.empty:Show()
	else
		page.empty:Hide()
	end
	if page.listBox.FullUpdate then
		page.listBox:FullUpdate(ScrollBoxConstants and ScrollBoxConstants.UpdateImmediately or true)
	end
	SP.rendered = rows
end

-- Tooltip lines of a row: list of { text, gold }.
function SP.TipLines(kind, r)
	local out = {}
	local function add(text, gold)
		out[#out + 1] = { text = text, gold = gold }
	end
	local function cmpLines(cmp)
		if not cmp then
			return
		end
		if cmp.state == "ready" then
			add(L.TT_ST_MEDIAN:format(Duration(cmp.median), cmp.n), true)
			if cmp.faster then
				add(L.TT_ST_FASTER:format(cmp.faster), true)
			end
		else
			add(L.TT_ST_COLLECT:format(cmp.n or 0, cmp.need or S.MIN_RUNS), true)
		end
	end
	if kind == "level" then
		local rec = r.rec
		add(L.TT_ST_ACTIVE:format(Duration(rec.s or 0)))
		if (rec.p or 0) >= 60 then
			add(L.TT_ST_BREAK:format(Duration(rec.p)))
		end
		local rate = (rec.s or 0) >= 60 and T.Number((rec.x or 0) * 3600 / rec.s) or L.ST_NONE
		add(L.TT_ST_XP:format(T.Number(rec.x or 0), rate))
		local sh = S.Shares(rec)
		if sh and sh.quest then
			add(L.TT_ST_XP_FROM:format(sh.quest, sh.kill, sh.other))
		end
		if sh and sh.combat then
			add(L.TT_ST_TIME:format(sh.combat, sh.move, sh.taxi, sh.rest))
		end
		if rec.n then
			add(L.TT_ST_QUESTS:format(L.ST_QUESTS_FMT:format(T.Number(rec.n), T.Number(r.skipped or 0))))
			add(L.TT_ST_DEATHS:format(rec.d or 0))
		else
			add(L.TT_ST_DETAILS)
		end
		if r.cur then
			add(L.TT_ST_RUNNING)
		elseif r.part then
			add(L.TT_ST_PART)
		else
			add(L.TT_ST_WAY:format(Way(r.g)))
			cmpLines(r.cmp)
		end
	elseif kind == "module" then
		add(L.TT_ST_ACTIVE:format(Duration(r.s or 0)))
		add(L.TT_ST_WAY:format(Way(r.g)))
		cmpLines(r.cmp)
	else
		add(L.TT_ST_WAY:format(Way(r.g)))
		if r.own then
			add(L.TT_ST_BEST_OWN)
		end
	end
	return out
end

function SP.RowTip(row)
	if not row.data then
		return
	end
	local title
	if row.kind == "level" then
		title = L.TT_ST_LEVEL:format(row.data.level)
	elseif row.kind == "module" then
		title = row.data.name
	else
		title = L.ST_RANGE:format(math.max(1, row.data.top - S.BAND), row.data.top)
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(title, T.RGB(HIGHLIGHT_FONT_COLOR))
	for _, line in ipairs(SP.TipLines(row.kind, row.data)) do
		if line.gold then
			GameTooltip:AddLine(line.text, T.RGB(NORMAL_FONT_COLOR))
		else
			GameTooltip:AddLine(line.text, 1, 1, 1, true)
		end
	end
	GameTooltip:Show()
end

-- Opening and refreshing ------------------------------------------------------------------------------

local refreshQueued = false

-- Own values at once, the comparison when it is built (never in a fight: the build waits).
function SP.Refresh()
	refreshQueued = false
	if not (page and page:IsShown()) then
		return
	end
	if UI.Fighting() then
		SP.afterFight = true -- the refresh comes with the end of the fight (Init)
		return
	end
	SP.afterFight = nil
	local src = Src()
	SP.model = src.Page(RS.Index())
	SP.Render()
	src.Request(SP, function(_, idx)
		if page:IsShown() then
			SP.model = src.Page(idx)
			SP.Render()
		end
	end)
end

function SP.Queue()
	if refreshQueued or not (page and page:IsShown()) then
		return
	end
	refreshQueued = true
	C_Timer.After(SP.REFRESH_DELAY, Guard.Wrap("statspage", SP.Refresh))
end

-- The page, by the player's command; never opens in a fight (it waits for the end).
function SP.Open()
	UI.OutOfCombat("statspage", function()
		if not M.IsActive("statspage") then
			return
		end
		if not page then
			BuildPage()
		end
		page:Show()
		SP.Refresh()
	end)
end

function SP.Toggle()
	if page and page:IsShown() then
		page:Hide()
	else
		SP.Open()
	end
end

-- Review card --------------------------------------------------------------------------------------

local function Fact(parent, y, w)
	local label = Text(parent, "GameFontNormal")
	label:SetPoint("TOPLEFT", SP.PAD, y)
	label:SetWidth(150)
	local value = Text(parent, "GameFontHighlight")
	value:SetPoint("TOPLEFT", SP.PAD + 154, y)
	value:SetWidth(w - 2 * SP.PAD - 154)
	return { label = label, value = value }
end

local function BuildRecap()
	local W = SP.RECAP_W
	recap = CreateFrame("Frame", SP.RECAP_NAME, UIParent, "BasicFrameTemplateWithInset")
	recap:SetSize(W, SP.RECAP_H)
	recap:SetPoint("CENTER")
	recap:SetFrameStrata("DIALOG")
	recap:SetClampedToScreen(true)
	recap:EnableMouse(true)
	tinsert(UISpecialFrames, SP.RECAP_NAME)
	if recap.TitleText then
		recap.TitleText:SetText(L.RC_TITLE)
	end
	local P = SP.PAD
	recap.head = Text(recap, "GameFontNormalLarge")
	recap.head:SetPoint("TOPLEFT", P, -34)
	recap.who = Text(recap, "GameFontHighlightSmall")
	recap.who:SetPoint("TOPLEFT", P, -56)
	recap.timeLabel = Text(recap, "GameFontNormal")
	recap.timeLabel:SetPoint("TOPLEFT", P, -80)
	recap.timeLabel:SetWidth(W - 2 * P)
	recap.time = Text(recap, "GameFontHighlightLarge")
	recap.time:SetPoint("TOPLEFT", P, -98)
	recap.facts = {}
	for i = 1, 7 do
		recap.facts[i] = Fact(recap, -126 - (i - 1) * 18, W)
	end
	recap.rows = {}
	recap.chartTop = -126 - 7 * 18 - 10
	recap.legend = Text(recap, "GameFontHighlightSmall")
	recap.legend:SetText(L.ST_LEGEND)
	recap.check = CreateFrame("CheckButton", nil, recap, "UICheckButtonTemplate")
	recap.check:SetSize(24, 24)
	recap.check:SetPoint("BOTTOMLEFT", P - 4, 34)
	recap.check:SetScript("OnClick", function(self)
		Guard.Call("statspage", function()
			UI.Set("recap", self:GetChecked() == true)
		end)
	end)
	recap.checkText = Text(recap, "GameFontHighlightSmall")
	recap.checkText:SetPoint("LEFT", recap.check, "RIGHT", 2, 0)
	recap.checkText:SetText(L.OPT_RECAP)
	recap.close = CreateFrame("Button", nil, recap, "UIPanelButtonTemplate")
	recap.close:SetSize(100, 22)
	recap.close:SetPoint("BOTTOMRIGHT", -P, 10)
	recap.close:SetText(L.RC_CLOSE)
	recap.close:SetScript("OnClick", function()
		recap:Hide()
	end)
	recap.all = CreateFrame("Button", nil, recap, "UIPanelButtonTemplate")
	recap.all:SetSize(120, 22)
	recap.all:SetPoint("RIGHT", recap.close, "LEFT", -6, 0)
	recap.all:SetText(L.RC_ALL)
	recap.all:SetScript("OnClick", function()
		recap:Hide()
		Guard.Call("statspage", SP.Open)
	end)
	recap.foot = Text(recap, "GameFontDisableSmall")
	recap.foot:SetPoint("BOTTOMLEFT", P, 14)
	recap.foot:SetText(L.TITLE)
	recap:Hide()
	SP.recap = recap
end

local function RecapRow(i)
	local row = recap.rows[i]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, recap)
	row:SetHeight(SP.RECAP_ROW)
	row:SetPoint("TOPLEFT", recap, "TOPLEFT", SP.PAD, recap.chartTop - (i - 1) * SP.RECAP_ROW)
	row:SetPoint("RIGHT", recap, "RIGHT", -SP.PAD, 0)
	row.level = Text(row, "GameFontHighlightSmall", "RIGHT")
	row.level:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.level:SetWidth(60)
	row.time = Text(row, "GameFontHighlightSmall")
	row.time:SetPoint("LEFT", row, "LEFT", 72 + 220 + 8, 0)
	row.time:SetWidth(100)
	row.bar = Bar(row)
	recap.rows[i] = row
	return row
end

-- Fills the card from a recap model (live.Recap or a demo).
function SP.RenderRecap(m)
	local b = m.band
	recap.head:SetText(L.RC_HEAD:format(m.top))
	recap.who:SetText(L.ST_WHO:format(m.race or L.ST_NONE, m.class or L.ST_NONE, Way(m.g)))
	if b.complete then
		recap.timeLabel:SetText(L.RC_TIME_LABEL:format(b.lo, m.top))
	else
		recap.timeLabel:SetText(L.RC_TIME_FROM:format(b.lo, m.top, b.from or b.lo))
	end
	recap.time:SetText(Duration(b.s))
	local facts = {}
	local cmp = m.cmp
	if cmp and cmp.state == "ready" then
		facts[#facts + 1] = { L.RC_MEDIAN, L.RC_MEDIAN_FMT:format(Duration(cmp.median), cmp.n) }
		facts[#facts + 1] = { L.RC_FASTER, L.RC_FASTER_FMT:format(cmp.faster or 0) }
	elseif cmp and cmp.partial then
		facts[#facts + 1] = { L.RC_MEDIAN, L.RC_PARTIAL }
	else
		facts[#facts + 1] = {
			L.RC_MEDIAN,
			L.RC_COLLECT_FMT:format(cmp and cmp.n or 0, cmp and cmp.need or S.MIN_RUNS),
		}
	end
	if m.best then
		local who = L.ST_WHO2:format(m.best.race or L.ST_NONE, m.best.class or L.ST_NONE)
		local text = m.best.own and L.RC_BEST_NEW:format(Duration(m.best.s))
			or L.RC_BEST_FMT:format(Duration(m.best.s), who)
		facts[#facts + 1] = { L.RC_BEST, text }
	end
	if (b.s or 0) >= 60 then
		facts[#facts + 1] = { L.RC_RATE, T.Number((b.x or 0) * 3600 / b.s) }
	end
	if b.tracked then
		facts[#facts + 1] = { L.RC_QUESTS, L.ST_QUESTS_FMT:format(T.Number(b.n or 0), T.Number(b.b or 0)) }
		facts[#facts + 1] = { L.RC_DEATHS, T.Number(b.d or 0) }
		local sh = S.Shares(b)
		if sh and sh.combat then
			facts[#facts + 1] = { L.RC_TIME, L.RC_TIME_FMT:format(sh.combat, sh.move, sh.taxi, sh.rest) }
		end
	end
	for i, f in ipairs(recap.facts) do
		local v = facts[i]
		f.label:SetText(v and v[1] or "")
		f.value:SetText(v and v[2] or "")
	end
	local scale = 0
	for _, r in ipairs(m.rows) do
		scale = math.max(scale, r.s or 0, r.median or 0)
	end
	for i, r in ipairs(m.rows) do
		local row = RecapRow(i)
		row.level:SetText(L.TT_ST_LEVEL:format(r.level))
		row.time:SetText(Duration(r.s or 0))
		SetBar(row.bar, row, 72, 220, r.s, r.median, scale, SP.RECAP_ROW - 2)
		row:Show()
	end
	for i = #m.rows + 1, #recap.rows do
		recap.rows[i]:Hide()
	end
	recap.legend:ClearAllPoints()
	recap.legend:SetPoint("TOPLEFT", recap, "TOPLEFT", SP.PAD, recap.chartTop - #m.rows * SP.RECAP_ROW - 4)
	recap.check:SetChecked(UI.Get("recap") == true)
	SP.recapModel = m
end

-- Shows the card for `level` with a recap model now (developer preview) or from the live values.
function SP.ShowRecap(level, model)
	if not recap then
		BuildRecap()
	end
	SP.RenderRecap(model or Src().Recap(level, RS.Index()))
	recap:Show()
end

local recapQueued = false

-- The card is due once the player is out of a fight and not in an instance. It is marked as shown in
-- the same moment it opens, so it never comes twice.
function SP.TryRecap()
	recapQueued = false
	local level = RS.PendingRecap()
	if not level or not M.IsActive("statspage") then
		return
	end
	if not UI.Get("recap") then
		RS.RecapDone(level) -- switched off: nothing waits for later
		return
	end
	if IsInInstance and IsInInstance() == true then
		return -- the next zone change or loading screen asks again
	end
	UI.OutOfCombat("recap", function()
		live.Request(SP.ShowRecap, function(_, idx)
			if RS.PendingRecap() ~= level or (IsInInstance and IsInInstance() == true) then
				return
			end
			RS.RecapDone(level)
			if not recap then
				BuildRecap()
			end
			SP.RenderRecap(live.Recap(level, idx))
			recap:Show()
		end)
	end)
end

-- After a level-up (Routes/RunStats.lua) and at every loading screen or zone change.
function SP.QueueRecap()
	if recapQueued or not RS.PendingRecap() then
		return
	end
	recapQueued = true
	C_Timer.After(SP.RECAP_DELAY, Guard.Wrap("statspage", SP.TryRecap))
end

ns.Commands.stats = function()
	SP.Toggle()
end

local function Init()
	RS.OnChange(SP, SP.Queue)
	UI.OnChange("combat", SP, function(_, _, fighting)
		if not fighting and SP.afterFight then
			SP.Refresh()
		end
	end)
	UI.OnChange("recap", SP, function(_, _, value)
		if recap and recap:IsShown() then
			recap.check:SetChecked(value == true)
		end
	end)
end

M.Define("statspage", {
	requires = { funcs = { "C_Texture.GetAtlasInfo" }, events = { "PLAYER_ENTERING_WORLD" } },
	optional = {
		funcs = {
			"PanelTemplates_SetTab",
			"PanelTemplates_SetNumTabs",
			"PanelTemplates_TabResize",
			"IsInInstance",
			"BreakUpLargeNumbers",
		},
		events = { "ZONE_CHANGED_NEW_AREA" },
	},
	init = Init,
	events = {
		PLAYER_ENTERING_WORLD = SP.QueueRecap,
		ZONE_CHANGED_NEW_AREA = SP.QueueRecap,
	},
})
