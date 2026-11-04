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

-- Probe/Preview.lua: developer preview for the design check in the Retail test bed (design stage 2,
-- docs/TESTING-RETAIL.md). "/bd4 preview <state>" puts the real windows into every state of design
-- v2 with the design's example content, also states a test bed cannot reach on its own (abandoned
-- quest, optional dungeon, rumor, route falls short). Developer build only: the TOC lists this file
-- inside #@do-not-package@ and .pkgmeta ignores Braindead4Ever/Probe. The example texts are demo data of the
-- design, not interface texts, so they live here and not in Locales/.
local _, ns = ...
local C, UI, SF, ST = ns.Connect, ns.UI, ns.StepFrame, ns.StepText

local P = {}
ns.Preview = P

local DE = GetLocale() == "deDE"
local function T(de, en)
	return DE and de or en
end

-- Quest IDs of the demo steps; their titles come from here, not from the client.
local Q = {
	wolf = 9000001,
	kob = 9000002,
	echo = 9000003,
	skir = 9000004,
	report = 9000005,
	milly = 9000006,
	harvest = 9000007,
	grapes = 9000008,
	defias = 9000009,
	bandanas = 9000010,
}
local TITLES = {
	[Q.wolf] = T("Wölfe an der Grenze", "Wolves Across the Border"),
	[Q.kob] = T("Säuberung im Koboldlager", "Kobold Camp Cleanup"),
	[Q.echo] = T("Überprüfung der Echokammmine", "Investigate Echo Ridge"),
	[Q.skir] = T("Scharmützel in der Echokammmine", "Skirmish at Echo Ridge"),
	[Q.report] = T("Meldung in Goldhain", "Report to Goldshire"),
	[Q.milly] = "Milly Osworth",
	[Q.harvest] = T("Millys Ernte", "Milly's Harvest"),
	[Q.grapes] = T("Traubenliste", "Grape Manifest"),
	[Q.defias] = T("Die Bruderschaft der Defias", "The Defias Brotherhood"),
	[Q.bandanas] = T("Rote Seidenkopftücher", "Red Silk Bandanas"),
}

local function Gold(text)
	return ns.Theme.Wrap(NORMAL_FONT_COLOR, text)
end

-- A demo step: a note element carries the text, a goto near the player gives arrow and detail line.
local function Step(i, text, quest)
	local map = C_Map.GetBestMapForUnit("player") or 0
	local north, west = UnitPosition("player")
	local step = { id = "p" .. i, { 12, text, 1, 0 } }
	if north then
		step[2] = { 5, map, west - 20 - i * 8, north + 35 + i * 4, 10, 1, 0 }
	end
	return {
		index = 3 + i,
		total = 48,
		key = "preview/p" .. i,
		module = "preview",
		id = step.id,
		lv = 3,
		kind = "quest",
		label = "vorläufig",
		quests = { quest },
		step = step,
	}
end

-- A demo step with a real quest element (verb 1 accept, 3 turn in), so its text comes from the step
-- text code with the NPC name (state "npc", M4).
local function QuestStep(i, verb, quest)
	local s = Step(i, "", quest)
	s.step[1] = { verb, quest, 1, 0 }
	return s
end

local function Steps(kind)
	local s = {
		Step(
			1,
			("%s: %s %s"):format(
				ST.Quest(Q.wolf),
				T("Zähes Wolfsfleisch sammeln", "collect Tough Wolf Meat"),
				Gold("3/8")
			),
			Q.wolf
		),
		Step(
			2,
			T(
				"„Wölfe an der Grenze“ bei Eagan Peltskinner abgeben",
				"Turn in “Wolves Across the Border” to Eagan Peltskinner"
			)
		),
		Step(
			3,
			T(
				"„Säuberung im Koboldlager“: Koboldgezücht besiegen",
				"“Kobold Camp Cleanup”: kill Kobold Vermin"
			)
				-- abandoned: the counter takes the step's color like the window's own counter (S5)
				.. (kind == "abandon" and " 3/8" or ""),
			Q.kob
		),
		Step(
			4,
			T(
				"„Säuberung im Koboldlager“ bei Marshal McBride abgeben",
				"Turn in “Kobold Camp Cleanup” to Marshal McBride"
			),
			Q.kob
		),
	}
	if kind == "npc" then -- accept from and turn in to an NPC (M4); the names come from NpcNames.SetDemo
		s[1] = QuestStep(1, 1, Q.wolf)
		s[2] = QuestStep(2, 3, Q.kob)
	end
	-- More steps for the size states (owner reading 14): the list holds 20, the rest scrolls.
	local order = { Q.echo, Q.skir, Q.report, Q.milly, Q.harvest, Q.grapes, Q.defias, Q.bandanas }
	for i = 5, 24 do
		local q = order[(i - 5) % #order + 1]
		local fmt = i % 2 == 1 and T("%s annehmen", "Accept %s") or T("%s abgeben", "Turn in %s")
		s[#s + 1] = Step(i, fmt:format(ST.Quest(q)), q)
	end
	return s
end

-- Demo source for ns.Connect: the route functions the windows call.
local function Source(kind, westfall)
	local steps, idx = {}, 1
	local history = {}
	local src = { missing = nil, westfall = westfall }
	function src.Build() -- after ns.Connect uses this source, so the titles come from it
		steps = Steps(kind)
		-- the abandoned quest is the current step, so note and marked step name the same quest (M9)
		idx = kind == "abandon" and 3 or 1
	end
	function src.Title(q)
		return TITLES[q]
	end
	function src.Current()
		return steps[idx]
	end
	function src.Upcoming(n)
		local out = {}
		for i = idx + 1, math.min(#steps, idx + n) do
			out[#out + 1] = steps[i]
		end
		return out
	end
	function src.StepState(key)
		for i, s in ipairs(steps) do
			if s.key == key then
				return i < idx and "done" or "open"
			end
		end
	end
	function src.Balance()
		local b = { level = 3, toLevel = 620, step = { xp = 260, source = "log" } }
		if kind == "dungeon" then
			b.level = 18 -- the dungeon fits from level 18 on (K2: "Stufe 18–24" next to level 3)
		elseif kind == "reach" then
			b = { level = 9, toLevel = 1600, step = { xp = 480, source = "log" } }
			b.zone = { nextMap = src.westfall, shortfall = 640, enough = false, kills = 9 }
		elseif kind == "forecast" then
			b.level = 5 -- two levels above the plan of the demo steps (level 3)
		elseif kind == "over" then
			b.level = 6 -- three levels above the plan: the question "over the plan"
		end
		return b
	end
	-- Time forecast: the example of docs/ROUTE-RUNTIME.md §Time forecast, or no runs yet.
	function src.Forecast()
		if kind == "forecast" then
			return {
				state = "ready",
				seconds = 41200,
				level = 30,
				runs = 7,
				plan = { module = "preview", delta = 240 },
				nextLevel = { state = "ready", seconds = 1800, perHour = 12000 },
			}
		end
		return { state = "collecting", nextLevel = { state = "collecting" } }
	end
	function src.Pending()
		return kind == "abandon" and src.pending or nil
	end
	src.pending = Q.kob
	function src.AbandonPreview()
		return kind == "abandon" and src.pending and { Q.echo, Q.skir, Q.report } or nil
	end
	function src.SkipPreview()
		return { Q.milly, Q.harvest, Q.grapes }
	end
	-- Replanning (Welle 7): the question "over the plan", a switch point with an alternative module and
	-- the list of quests skipped earlier (XP tooltip, more names than it shows).
	local offer
	if kind == "over" then
		offer = { kind = "over", id = "preview-over", gap = 3, plan = 3, level = 6, drop = { Q.milly, Q.harvest } }
	elseif kind == "switch" then
		offer = {
			kind = "switch",
			id = "preview-switch",
			plan = 3,
			level = 9,
			choice = { kind = "module", module = "preview", map = src.westfall, plan = 9, gain = 1500 },
			options = {},
		}
	end
	function src.Offer()
		return offer
	end
	function src.AnswerOffer()
		offer = nil
		return true
	end
	function src.Earlier()
		if kind == "earlier" then
			return { Q.kob, Q.echo, Q.skir, Q.report, Q.milly, Q.harvest, Q.grapes }
		end
		return {}
	end
	local function Advance(action)
		history[#history + 1] = { idx = idx, act = action }
		local prev = steps[idx]
		idx = math.min(#steps, idx + 1)
		SF.OnStepChanged(nil, steps[idx], prev)
		return true
	end
	function src.Check()
		return Advance({ kind = "check", quest = Q.wolf })
	end
	function src.Skip()
		src.pending = nil
		return Advance({ kind = "skip", quest = Q.kob })
	end
	function src.ResolveAbandon(choice)
		src.pending = nil
		history[#history + 1] =
			{ idx = idx, act = { kind = choice == "skip" and "skipquest" or "reaccept", quest = Q.kob } }
		SF.Refresh()
		return true
	end
	function src.Back()
		idx = math.max(1, idx - 1)
		return true
	end
	function src.Undo()
		local h = table.remove(history)
		if h then
			idx = h.idx
			return true
		end
		return false
	end
	function src.LastAction()
		local h = history[#history]
		return h and h.act or nil
	end
	function src.Rumor()
		if kind == "rumor" then
			return {
				id = "preview",
				text = T(
					"Jemand hat in den Flusslanden etwas gefunden.",
					"Someone found something in the Riverglades."
				),
			}
		end
	end
	-- Hint level 1: a riddle from the real templates for the player's zone; hint level 2: an area around
	-- the player's position on the world map (Welle 5b, design v2 view 4).
	function src.Riddle()
		if kind == "riddle" then
			local zone = ST.MapName(C_Map.GetBestMapForUnit("player")) or ns.L.ZONE_FALLBACK
			return { id = "preview-riddle", text = ns.Discover.Riddle(ns.L, "book", zone, "s") }
		end
	end
	function src.Finds(map)
		if kind ~= "area" then
			return {}
		end
		local pos = C_Map.GetPlayerMapPosition(map, "player")
		local x, y = 0.5, 0.5
		if pos and pos.GetXY then
			x, y = pos:GetXY()
		end
		-- radii from the map's size in yards like the explorer logic (Routes/Explore.lua); without it
		-- the circle was an oval of 1.5:1 (Welle 5d, S8)
		local w, h
		if C_Map.GetMapWorldSize then
			w, h = C_Map.GetMapWorldSize(map)
		end
		local area = ns.Discover.Area("book:preview", x * 10000, y * 10000, w, h)
		return { { key = "book:preview", kind = "book", map = map, show = "area", area = area } }
	end
	local hidden = false
	function src.DungeonHint()
		if kind ~= "dungeon" or hidden then
			return {}
		end
		return {
			{
				id = 63,
				area = 1581, -- The Deadmines
				lo = 18,
				hi = 24,
				first = steps[2].index,
				quests = { { q = Q.defias, state = "take" }, { q = Q.bandanas, state = "take" } },
			},
		}
	end
	function src.SkipDungeon()
		hidden = true
		return true
	end
	function src.Mode()
		return "speed"
	end
	function src.SetMode()
		return true
	end
	function src.Module()
		return { label = "vorläufig", steps = { { { 1, 0, 7, 0 } } } }
	end
	function src.Seed(n)
		for _ = 1, n do
			history[#history + 1] = { idx = idx, act = { kind = "check", quest = Q.wolf } }
			idx = idx + 1
		end
	end
	return src
end

-- "Your run" (Welle 8): demo numbers of the design for the page and the review card, with and without
-- enough runs of other players. Times rise from about 6 minutes at level 1, as on a real start.
local function DemoLevels(upto, cmp)
	local rows = {}
	for l = 1, upto do
		local s = 360 + l * 230
		local rec = {
			s = s,
			p = l % 4 == 0 and 420 or 0,
			x = 400 + l * 520,
			q = 260 + l * 320,
			k = 120 + l * 170,
			c = s * 0.32,
			m = s * 0.41,
			f = l > 8 and 90 or 0,
			n = 3 + l % 4,
			d = l == 7 and 1 or 0,
			mo = "s",
			o = 100,
			full = true,
		}
		local row = { level = l, rec = rec, g = "r", skipped = l % 5 == 0 and 1 or 0, cur = l == upto }
		if not row.cur then
			if cmp then
				local median = s + (l % 3 - 1) * 140
				row.cmp = { state = "ready", n = 40 + l * 3, median = median, faster = s <= median and 62 or 38 }
			else
				row.cmp = { state = "collecting", n = l % 4 + 2, need = ns.Stats.MIN_RUNS }
			end
		end
		rows[#rows + 1] = row
	end
	return rows
end

local function DemoPage(cmp)
	local m = {
		level = 12,
		race = ns.Util.Str((UnitRace("player"))),
		class = ns.Util.Str((UnitClass("player"))),
		total = 0,
		quests = 0,
		skipped = 0,
		deaths = 0,
		runs = cmp and 4180 or 23,
		levels = DemoLevels(12, cmp),
		modules = {},
		bests = {},
		rate = cmp and { state = "ready", perHour = 9850 } or { state = "collecting" },
		forecast = cmp and { state = "ready", seconds = 41200, level = 30 } or { state = "collecting" },
	}
	for _, r in ipairs(m.levels) do
		m.total = m.total + r.rec.s
		m.quests = m.quests + r.rec.n
		m.skipped = m.skipped + r.skipped
		m.deaths = m.deaths + r.rec.d
	end
	local zones = { T("Wald von Elwynn", "Elwynn Forest"), T("Dun Morogh", "Dun Morogh"), "Westfall" }
	for i = 1, 6 do
		local s = 700 + i * 260
		m.modules[i] = {
			name = ("%s, %s"):format(zones[(i - 1) % 3 + 1], T("Stufe ", "level ") .. (i * 2 - 1) .. "–" .. (i * 2)),
			s = s,
			g = "r",
			cmp = cmp and { state = "ready", n = 30 + i, median = s + 120, faster = 64 }
				or { state = "collecting", n = 2, need = ns.Stats.MIN_RUNS },
		}
	end
	if cmp then
		m.bests[1] = {
			top = 10,
			s = 4 * 3600 + 47 * 60,
			race = ns.RunStats.RaceName(3) or T("Zwerg", "Dwarf"),
			class = ns.RunStats.ClassName(3) or T("Jäger", "Hunter"),
			g = "r",
			day = 20760,
		}
	end
	return m
end

local function DemoRecap(level, cmp)
	local rows, lv = {}, {}
	local lo = math.max(1, level - 10)
	for l = lo, level - 1 do
		local s = 360 + l * 230
		lv[l] = {
			s = s,
			x = 400 + l * 520,
			q = 260 + l * 320,
			k = 120 + l * 170,
			c = s * 0.32,
			m = s * 0.41,
			f = l > 8 and 90 or 0,
			p = 0,
			n = 5,
			d = l == 7 and 1 or 0,
			b = l % 5 == 0 and 1 or 0,
			mo = "s",
			o = 100,
			full = true,
		}
		rows[#rows + 1] = { level = l, s = s, median = cmp and (s + (l % 3 - 1) * 140) or nil }
	end
	local band = ns.Stats.Band(lv, level)
	local m = {
		top = level,
		band = band,
		race = ns.Util.Str((UnitRace("player"))),
		class = ns.Util.Str((UnitClass("player"))),
		g = "r",
		rows = rows,
	}
	if cmp then
		m.cmp = { state = "ready", n = 57, median = band.s + 840, faster = 71 }
		m.best = { s = band.s, own = true }
	else
		m.cmp = { state = "collecting", n = 6, need = ns.Stats.MIN_RUNS }
		m.best = {
			s = band.s - 1500,
			race = ns.RunStats.RaceName(3) or T("Zwerg", "Dwarf"),
			class = ns.RunStats.ClassName(3) or T("Jäger", "Hunter"),
		}
	end
	return m
end

local function StatsSource(cmp)
	return {
		Page = function()
			return DemoPage(cmp)
		end,
		Recap = function(level)
			return DemoRecap(level, cmp)
		end,
		Request = function(owner, fn)
			fn(owner, nil)
		end,
		Cancel = function() end,
	}
end

-- Places the arrow goal `deg` degrees off the player's facing, `yd` yards away (Retail world).
local function ArrowAt(deg, yd)
	local north, west, _, inst = UnitPosition("player")
	local facing = GetPlayerFacing()
	if not north or not facing then
		print("Braindead 4ever preview: no position here (instance?)")
		return
	end
	local a = facing + math.rad(deg)
	-- world angle convention of GetPlayerFacing: 0 = north, counterclockwise (west positive)
	local t = {
		map = C_Map.GetBestMapForUnit("player") or 0,
		wx = west + math.sin(a) * yd,
		wy = north + math.cos(a) * yd,
		inst = inst,
		title = TITLES[Q.wolf],
	}
	ns.Arrow.SetExtra(t)
end

local function Use(kind)
	-- Westfall: 1436 in Forever, 52 in Retail; a map the client does not know gave "bis ?" (M8)
	local src = Source(kind, C_Map.GetMapInfo(1436) and 1436 or 52)
	C.Use(src)
	src.Build()
	return src
end

P.STATES = {
	"normal",
	"tooltip",
	"done",
	"mini",
	"combat",
	"help",
	"menu",
	"status",
	"reach",
	"skip",
	"abandon",
	"dungeon",
	"rumor",
	"riddle",
	"area",
	"narrow",
	"wide",
	"forecast",
	"collecting",
	"over",
	"switch",
	"earlier",
	"npc",
	"questitem",
	"arrow <degrees>",
	"arrival",
	"colorblind",
	"setup",
	"settings",
	"auto",
	"stats",
	"stats0",
	"recap10",
	"recap30",
	"off",
}

-- The size states change the player's size; every other state and "off" put it back.
local function SetSize(width, ahead)
	if not P.size then
		P.size = { width = UI.Get("width"), ahead = UI.Get("ahead") }
	end
	UI.Set("width", width)
	UI.Set("ahead", ahead)
end

local ARROW_STATES = { arrow = true, arrival = true, colorblind = true }

-- Every state starts from a clean window (Welle 5d, K2): the usage hint, the skip dialog, the first
-- start, rumor and riddle lines, a demo arrow goal, mini view, combat dimming and a demo size of the
-- state before are gone. Before, the hint stood in every picture after "help", the dialog from "skip" to
-- "wide", and the rumor in the three extra pictures of "normal".
function P.Clear(state)
	local W = SF.frame
	if state ~= "help" and HelpTip and HelpTip.Hide and W then
		HelpTip:Hide(W, ns.L.HELP_RIGHTCLICK) -- not acknowledged: the real hint stays unused
		SF.View().hintWaiting = nil
	end
	if state ~= "skip" and StaticPopup_Hide then
		StaticPopup_Hide(SF.POPUP)
	end
	local setup = ns.Setup and ns.Setup.frame
	if state ~= "setup" and setup and setup:IsShown() then
		setup:Hide() -- a reopened window: closing changes nothing
	end
	SF.View().rumorShown, SF.View().riddleShown = nil, nil
	if ns.Arrow then
		ns.Arrow.colorblind = ns.Theme.Colorblind()
		ns.Arrow.holdArrival = nil
		if not ARROW_STATES[state] then
			ns.Arrow.SetExtra(nil)
		end
	end
	if P.size and state ~= "narrow" and state ~= "wide" then
		UI.Set("width", P.size.width)
		UI.Set("ahead", P.size.ahead)
		P.size = nil
	end
	UI.DB().mini = nil
	SF.ApplyLook() -- collapse button and combat dimming of the state before
	if ns.NpcNames and state ~= "npc" then
		ns.NpcNames.SetDemo(nil) -- demo NPC names (M4) of the state before
	end
	if ns.QuestItem and state ~= "questitem" then
		ns.QuestItem.SetDemo(nil) -- demo quest item button (M8) of the state before
	end
	local SP = ns.StatsPage -- "Your run" (Welle 8): page and card of the state before close
	if SP then
		SP.Use(nil)
		for _, f in ipairs({ SP.frame, SP.recap }) do
			if f and f:IsShown() then
				f:Hide()
			end
		end
	end
end

function P.Run(state, arg)
	P.Clear(state)
	if state == "off" or state == "" then
		C.Use(nil)
		SF.SetMessage(nil)
		return
	end
	local src = Use(state)
	SF.SetMessage(nil)
	if (state == "rumor" or state == "riddle") and UI.Get("style") == "arrow" then
		print(
			"Braindead 4ever preview: rumors and riddles come with the play styles hints and self (settings, Play style)"
		)
	end
	if state == "riddle" then
		SF.View().riddleShown = nil -- the demo riddle replaces a live one
	end
	if state == "tooltip" then
		SF.ShowOriginTip(SF.frame.cur)
	elseif state == "done" then
		C.Check()
	elseif state == "mini" then
		SF.SetMini(true)
	elseif state == "combat" then
		SF.frame:SetAlpha(UI.COMBAT_ALPHA) -- the look of a fight; the real one comes with any fight
	elseif state == "help" then
		local db = UI.DB()
		local seen = db.hintsSeen
		db.hintsSeen = nil
		SF.ShowHintOnce()
		db.hintsSeen = seen
	elseif state == "menu" then
		src.Seed(1)
		SF.Refresh()
		ns.Menu.Open(SF.frame)
	elseif state == "status" then
		SF.SetMessage(ns.L.STATUS_NEW_VERSION:format("0.9.1"))
	elseif state == "skip" then
		SF.AskSkip()
	elseif state == "narrow" then
		SetSize(SF.MIN_WIDTH, 3) -- German umlauts and two-line steps at the narrowest width (T19)
	elseif state == "wide" then
		SetSize(SF.MAX_WIDTH, SF.MAX_AHEAD) -- ten steps visible, the rest scrolls
	elseif state == "npc" then
		-- M4: the NPC names of the design's example steps (demo data, as in the turn-in demo step)
		ns.NpcNames.SetDemo({
			giver = { [Q.wolf] = "Eagan Peltskinner" },
			turnin = { [Q.kob] = "Marshal McBride" },
		})
	elseif state == "questitem" then
		-- M8: the button with a demo icon, three charges and the gray range dot; it holds no item, so a
		-- click in the preview uses nothing
		ns.QuestItem.SetDemo({ icon = "Interface\\Icons\\INV_Misc_QuestionMark", charges = 3, range = 1 })
	elseif state == "arrow" then
		ArrowAt(tonumber(arg) or 8, 38)
	elseif state == "arrival" then
		ns.Arrow.holdArrival = 10 -- check and "Reached destination" stay ten seconds for the picture
		ArrowAt(0, 8)
	elseif state == "colorblind" then
		ns.Arrow.colorblind = true
		ArrowAt(tonumber(arg) or 160, 38)
	elseif state == "setup" then
		ns.Setup.Open(true, true) -- the first start's footer (S6)
	elseif state == "settings" then
		ns.Menu.OpenSettings()
	elseif state == "auto" then -- the automation switch on the main page (A74), scrolled into view
		UI.OutOfCombat("settings", function()
			Settings.OpenToCategory(ns.settingsCategoryID, ns.L.OPT_AUTO)
		end)
	elseif state == "stats" or state == "stats0" then
		ns.StatsPage.Use(StatsSource(state == "stats")) -- with and without enough runs of other players
		ns.StatsPage.Open()
	elseif state == "recap10" or state == "recap30" then
		local level = state == "recap10" and 10 or 30
		ns.StatsPage.ShowRecap(level, DemoRecap(level, level == 10)) -- 10: with comparison, 30: collecting
	end
end

ns.Commands.preview = function(rest)
	local state, arg = (rest or ""):lower():match("^(%S*)%s*(%S*)")
	local known = state == ""
	for _, s in ipairs(P.STATES) do
		known = known or s:match("^%S+") == state
	end
	if not known then
		print("Braindead 4ever preview: " .. table.concat(P.STATES, " | "))
		return
	end
	if not ns.Modules.IsActive("window") then
		print("Braindead 4ever preview: step window module is off, see /bd4 status")
		return
	end
	SF.Refresh()
	P.Run(state, arg)
	SF.Invalidate()
	SF.Refresh()
	if state == "tooltip" then
		SF.ShowOriginTip(SF.frame.cur)
	elseif state == "forecast" or state == "collecting" or state == "earlier" then
		SF.ShowXPTip(SF.frame.xpHit) -- the tooltip of the XP line
	elseif state == "combat" then
		SF.frame:SetAlpha(UI.COMBAT_ALPHA)
	end
end
