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

-- Routes/Stats.lua: the player's own run in numbers ("Dein Lauf", Welle 8, docs/RUN-STATS.md). Pure
-- Lua, no WoW API: clock values, saved tables and vault texts come in, so the tests run this code.
--   tally    per level of a character: active seconds (the same gaps as the run sections of
--            Routes/Guide.lua), break time beyond the idle cap, XP and where it came from (quest
--            rewards, kills, other), time by activity (fighting, moving, flying, other), quests done
--            and skipped, deaths; module runs played from their first step
--   compare  median and rank of the player's class from the run vault (Collector/Runs.lua), apart by
--            way of play (follows the route, free play, partly); only from MIN_RUNS runs of other
--            players on, below that the state is "collecting" and no number exists
--   bands    ten levels together (1 to 10, 10 to 20, ...); best times per band over every character of
--            the account
local _, ns = ...

local S = {}
ns.Stats = S

-- Chosen values, not measured. MIN_RUNS: other players' runs of the class in one section and way of
-- play before median and rank show (Forecast.lua shows a median from 5; a rank needs more). FOLLOW_MIN:
-- in-order share from which a section follows the route, as tools/routekit/runs.py. KILL_WINDOW:
-- seconds between a kill and the XP it gives.
S.MIN_RUNS = 10
S.FOLLOW_MIN = 80
S.BAND = 10
S.TOP = 60
S.KILL_WINDOW = 1
-- Levels that bring the review card once per character (plan: 10, 20, 30; 60 follows with the routes
-- to 60).
S.RECAP = { [10] = true, [20] = true, [30] = true }

local floor, max, min, tonumber, concat = math.floor, math.max, math.min, tonumber, table.concat

-- Way of play of a section from its mode letter and in-order share: "r" follows the route (mode s or
-- e, at least FOLLOW_MIN), "f" free play (mode f), "p" partly (the rest).
function S.Group(mode, inOrder)
	if mode == "f" then
		return "f"
	end
	if (mode == "s" or mode == "e") and (tonumber(inOrder) or 0) >= S.FOLLOW_MIN then
		return "r"
	end
	return "p"
end

-- Saved tables ------------------------------------------------------------------------------------

-- PathmarkCharDB.stats: lv = { [level] = record }, mods = { run, ... }, recap = { [level] = true,
-- pending = level }. A record: s active seconds, p break seconds, x XP, q XP of quest rewards, k XP of
-- kills, c m f seconds fighting, moving, flying, n quests done, b quests skipped, d deaths, full (the
-- whole level was seen), mo mode letter and o in-order share of the closed section, day server day.
-- Records taken over from the run vault have only s, x, mo, o, full.
function S.CharDB(t)
	t = type(t) == "table" and t or {}
	t.lv = type(t.lv) == "table" and t.lv or {}
	t.mods = type(t.mods) == "table" and t.mods or {}
	t.recap = type(t.recap) == "table" and t.recap or {}
	return t
end

-- PathmarkDB.stats: best = { [top level of the band] = { s, r race, c class, g way of play, d day,
-- t run token } }, account-wide.
function S.AccountDB(t)
	t = type(t) == "table" and t or {}
	t.best = type(t.best) == "table" and t.best or {}
	return t
end

local FIELDS = { "s", "p", "x", "q", "k", "c", "m", "f", "n", "d" }

-- Tally ------------------------------------------------------------------------------------------

local Tally = {}
Tally.__index = Tally
S.Tally = Tally

function S.NewTally(db)
	return setmetatable({ db = db, acc = { combat = 0, move = 0, taxi = 0, rest = 0 }, flags = {} }, Tally)
end

-- The record of the current level; made when missing. full: the level was seen from its start (the
-- route's level section says so, Routes/Guide.lua).
function Tally:Level(level, full)
	local lv = self.db.lv
	local r = lv[level] ---@type table<string, any>
	if type(r) ~= "table" then
		r = { full = full and true or nil }
		lv[level] = r
	end
	for _, k in ipairs(FIELDS) do
		r[k] = tonumber(r[k]) or 0
	end
	self.level, self.rec = level, r
	return r
end

-- What the player does now: a flight beats a fight beats moving.
function Tally:Activity()
	local f = self.flags
	return (f.taxi and "taxi") or (f.combat and "combat") or (f.move and "move") or "rest"
end

-- Time since the last mark goes to the activity that held it.
function Tally:Mark(now)
	local m = self.mark
	if m and now > m then
		local a = self:Activity()
		self.acc[a] = self.acc[a] + (now - m)
	end
	self.mark = now
end

-- kind "combat", "move" or "taxi" starts or ends at now.
function Tally:Flag(now, kind, on)
	self:Mark(now)
	self.flags[kind] = on and true or nil
end

-- One gap of play from the route (Routes/Guide.lua, Active): d seconds count as play (raw capped at
-- Forecast.IDLE_CAP), raw - d is a break. The activities of the gap share d in proportion to their
-- time. xp: experience gained with this event; it counts as a kill when a kill came at most
-- KILL_WINDOW seconds before (or comes that soon after, Kill).
function Tally:Play(now, d, raw, xp)
	self:Mark(now)
	local acc, r = self.acc, self.rec
	d = d or 0
	if r then
		r.s = r.s + d
		r.p = r.p + max(0, (raw or d) - d)
		local sum = acc.combat + acc.move + acc.taxi + acc.rest
		if sum > 0 and d > 0 then
			local k = d / sum
			r.c = r.c + acc.combat * k
			r.m = r.m + acc.move * k
			r.f = r.f + acc.taxi * k
		end
		if xp and xp > 0 then
			r.x = r.x + xp
			if self.lastKill and now - self.lastKill <= S.KILL_WINDOW then
				r.k = r.k + xp
				self.lastKill = nil -- one XP gain per kill
			else
				self.pendXP, self.pendAt, self.pendRec = xp, now, r
			end
		end
	end
	acc.combat, acc.move, acc.taxi, acc.rest = 0, 0, 0, 0
end

-- The player or a group member killed something (PARTY_KILL).
function Tally:Kill(now)
	if self.pendXP and now - self.pendAt <= S.KILL_WINDOW then
		self.pendRec.k = self.pendRec.k + self.pendXP
		self.lastKill = nil
	else
		self.lastKill = now
	end
	self.pendXP, self.pendRec = nil, nil
end

-- A quest handed in; xp = its reward when the client said it (QUEST_TURNED_IN).
function Tally:Quest(xp)
	local r = self.rec
	if r then
		r.n = r.n + 1
		if xp and xp > 0 then
			r.q = r.q + xp
		end
	end
end

function Tally:Death()
	local r = self.rec
	if r then
		r.d = r.d + 1
	end
end

-- Level-up to `level`. sec: the level section the route measured ({ secs, xp, mode, inOrder, full },
-- Routes/Guide.lua), so the closed record says what the run vault says. skipped: quests the route
-- leaves out now (Route.Skipped); the difference to the level's start counts. day: server day.
function Tally:LevelUp(level, sec, skipped, day)
	local r = self.rec
	if r and self.level == level - 1 then
		if sec then
			r.s, r.x = tonumber(sec.secs) or r.s, tonumber(sec.xp) or r.x
			r.mo, r.o, r.full = sec.mode, tonumber(sec.inOrder), sec.full and true or nil
		end
		if skipped and r.b0 then
			r.b = max(0, skipped - r.b0)
		end
		r.b0, r.day = nil, day
	end
	local n = self:Level(level, true)
	n.b0 = skipped
	return r
end

-- A module run from its first step past its last (the same as the run vault's "m" section). Only the
-- first run of a module and version is kept, as in the vault.
function Tally:Module(num, key, version, secs, inOrder, mode, level)
	local mods = self.db.mods
	for _, m in ipairs(mods) do
		if m.num == num and m.v == version then
			return false
		end
	end
	mods[#mods + 1] = { num = num, key = key, v = version, s = secs, o = inOrder, mo = mode, l = level }
	return true
end

-- Skipped quests of the current level so far.
function S.Skipped(rec, skippedNow)
	if rec.b then
		return rec.b
	end
	if rec.b0 and skippedNow then
		return max(0, skippedNow - rec.b0)
	end
end

-- Bands -------------------------------------------------------------------------------------------

-- Levels of the band that ends at `top`: 10 takes levels 1 to 9, 20 takes 10 to 19.
function S.BandRange(top)
	return max(1, top - S.BAND), top - 1
end

-- Sum of the band's records. complete: every level was seen whole; from: the first level counted;
-- tracked: every counted level has the tally's details (not only vault values); g: one way of play for
-- all levels, else "p".
function S.Band(lv, top)
	local lo, hi = S.BandRange(top)
	local out = { top = top, lo = lo, hi = hi, s = 0, x = 0, levels = 0, complete = true, tracked = true }
	for _, k in ipairs(FIELDS) do
		out[k] = out[k] or 0
	end
	out.b = 0
	for l = lo, hi do
		local r = lv[l]
		if type(r) == "table" and r.full then
			for _, k in ipairs(FIELDS) do
				out[k] = out[k] + (tonumber(r[k]) or 0)
			end
			out.b = out.b + (tonumber(r.b) or 0)
			if r.c == nil then
				out.tracked = false
			end
			local g = S.Group(r.mo, r.o)
			if out.g == nil then
				out.g = g
			elseif out.g ~= g then
				out.g = "p"
			end
			out.from = out.from or l
			out.levels = out.levels + 1
			out.day = tonumber(r.day) or out.day
		else
			out.complete = false
		end
	end
	return out
end

-- Best time of the account for the band ending at `top`. True when this run is the new best (an equal
-- time keeps the older one).
function S.Best(best, top, secs, race, class, g, day, tok)
	local b = best[top]
	if type(b) == "table" and tonumber(b.s) and b.s <= secs then
		return false
	end
	best[top] = { s = secs, r = race, c = class, g = g, d = day, t = tok }
	return true
end

-- Every complete band of one character's records goes into the best times.
function S.BestOf(best, lv, race, class, tok)
	for top = S.BAND, S.TOP, S.BAND do
		local b = S.Band(lv, top)
		if b.complete then
			S.Best(best, top, b.s, race, class, b.g, b.day, tok)
		end
	end
end

-- Run vault -----------------------------------------------------------------------------------------

-- "s" message fields (Collector/Proto.lua): token, race, class, mode, kind, section, version, seconds,
-- xp, in order, level, day.
local FULL = "^s;%d+;([0-9a-z]+);(%d+);(%d+);([sef]);([lm]);(%d+);(%d+);(%d+);(%d+);(%d+);(%d+);(%d+)$"
-- The fields the comparison needs: token, class, mode, kind, section, version, seconds, in order.
local SHORT = "^s;%d+;([0-9a-z]+);%d+;(%d+);([sef]);([lm]);(%d+);(%d+);(%d+);%d+;(%d+);%d+;%d+$"

-- Sections of the tokens in `want` from the vault list (seq first..last): { [token] = { race, class,
-- lv = { [level] = record }, mods = { run, ... } } }. Level sections in the vault are whole levels.
function S.FromVault(list, first, last, want)
	local out = {}
	for seq = first or 1, last or 0 do
		local msg = list[seq]
		if type(msg) == "string" then
			local tok, race, class, mode, kind, sec, ver, secs, xp, inOrder, level, day = msg:match(FULL)
			if tok and want[tok] then
				local t = out[tok]
				if not t then
					t = { race = tonumber(race), class = tonumber(class), lv = {}, mods = {} }
					out[tok] = t
				end
				if kind == "l" then
					t.lv[tonumber(sec)] = {
						s = tonumber(secs),
						x = tonumber(xp),
						mo = mode,
						o = tonumber(inOrder),
						full = true,
						day = tonumber(day),
					}
				else
					t.mods[#t.mods + 1] = {
						num = tonumber(sec),
						v = tonumber(ver),
						s = tonumber(secs),
						o = tonumber(inOrder),
						mo = mode,
						l = tonumber(level),
					}
				end
			end
		end
	end
	return out
end

-- Comparison index of one class: other players' sections grouped by kind, section, version and way of
-- play, plus band sums per token. Built a slice at a time (Feed), then sorted once (Seal).
function S.NewIndex(class, mine)
	return { class = tostring(class), mine = mine or {}, groups = {}, toks = {}, used = 0 }
end

local function Key(kind, sec, ver, g)
	return concat({ kind, sec, ver or 0, g }, ";")
end
S.Key = Key

-- One vault text. True when it counts for the class.
function S.Feed(idx, msg)
	local tok, class, mode, kind, sec, ver, secs, inOrder = msg:match(SHORT)
	if not tok or class ~= idx.class or idx.mine[tok] then
		return false
	end
	local g = S.Group(mode, inOrder)
	local key = Key(kind, sec, ver, g)
	local list = idx.groups[key]
	if not list then
		list = {}
		idx.groups[key] = list
	end
	secs = tonumber(secs)
	list[#list + 1] = secs
	if kind == "l" then
		local t = idx.toks[tok]
		if not t then
			t = { s = {}, g = {} }
			idx.toks[tok] = t
		end
		local l = tonumber(sec) or 0
		t.s[l], t.g[l] = secs, g
	end
	idx.used = idx.used + 1
	return true
end

-- Band sums of every token with all levels of a band, then every group sorted.
function S.Seal(idx)
	for _, t in pairs(idx.toks) do
		for top = S.BAND, S.TOP, S.BAND do
			local lo, hi = S.BandRange(top)
			local sum, g, whole = 0, nil, true
			for l = lo, hi do
				local secs = t.s[l]
				if not secs then
					whole = false
					break
				end
				sum = sum + secs
				if g == nil then
					g = t.g[l]
				elseif g ~= t.g[l] then
					g = "p"
				end
			end
			if whole then
				local key = Key("b", top, 0, g)
				local list = idx.groups[key]
				if not list then
					list = {}
					idx.groups[key] = list
				end
				list[#list + 1] = sum
			end
		end
	end
	idx.toks = nil
	for _, list in pairs(idx.groups) do
		table.sort(list)
	end
	idx.sealed = true
	return idx
end

-- Median and rank of `own` seconds among the class's runs of one section and way of play:
-- { state = "ready", n, median, faster } (faster = share of runs slower than own, ties count half, in
-- whole percent) or { state = "collecting", n, need } below MIN_RUNS. Kind "b" is a band (section = its
-- top level).
function S.Compare(idx, kind, sec, ver, g, own)
	local list = idx and idx.groups and idx.groups[Key(kind, sec, ver, g)]
	local n = list and #list or 0
	if n == 0 or n < S.MIN_RUNS then
		return { state = "collecting", n = n, need = S.MIN_RUNS }
	end
	local median
	if n % 2 == 1 then
		median = list[(n + 1) / 2]
	else
		median = (list[n / 2] + list[n / 2 + 1]) / 2
	end
	local out = { state = "ready", n = n, median = median }
	if own then
		local slower, tie = 0, 0
		for i = 1, n do
			local v = list[i]
			if v > own then
				slower = slower + 1
			elseif v == own then
				tie = tie + 1
			end
		end
		out.faster = floor(100 * (slower + tie / 2) / n + 0.5)
	end
	return out
end

-- Shares of a record's active time and XP, in whole percent (nil without tally details).
-- Activity: fighting, moving, flying, other. XP: quests, kills, other; quest rewards and kills above
-- the gained XP (a reward that brought the level-up) are cut to it.
function S.Shares(r)
	if r.c == nil then
		return nil
	end
	local s = max(tonumber(r.s) or 0, 0)
	local c, m, f = r.c or 0, r.m or 0, r.f or 0
	local rest = max(0, s - c - m - f)
	local total = c + m + f + rest
	local out = {}
	if total > 0 then
		out.combat, out.move, out.taxi =
			floor(100 * c / total + 0.5), floor(100 * m / total + 0.5), floor(100 * f / total + 0.5)
		out.rest = max(0, 100 - out.combat - out.move - out.taxi)
	end
	local x = max(tonumber(r.x) or 0, 0)
	if x > 0 then
		local q, k = min(r.q or 0, x), r.k or 0
		k = min(k, x - q)
		out.quest = floor(100 * q / x + 0.5)
		out.kill = floor(100 * k / x + 0.5)
		out.other = max(0, 100 - out.quest - out.kill)
	end
	return out
end
