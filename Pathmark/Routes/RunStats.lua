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

-- Routes/RunStats.lua: module "stats" (Welle 8, docs/RUN-STATS.md). Keeps the tally of Routes/Stats.lua
-- per character (PathmarkCharDB.stats) and the best times of the account (PathmarkDB.stats), feeds it
-- the game events, and builds the comparison with the class from the run vault when a window asks.
-- Active seconds and XP come from the route (Routes/Guide.lua calls Play, LevelUp and Module), so a
-- level here has the same seconds as its run section in the vault.
-- Events (Forever docs, wow-ui-source forever aff0d8c 1.60.1 build 70707, Blizzard_APIDocumentationGenerated):
--   PLAYER_REGEN_DISABLED, PLAYER_REGEN_ENABLED, PLAYER_STARTED_MOVING, PLAYER_STOPPED_MOVING
--   (UnitDocumentation.lua, no payload), PLAYER_DEAD (DeathInfoDocumentation.lua), PARTY_KILL
--   (UnitDocumentation.lua, GUIDs secret when unit identity is restricted; only the moment is used),
--   QUEST_TURNED_IN (questID, xpReward, moneyReward; QuestLogDocumentation.lua); flights as in the
--   collector (PLAYER_CONTROL_LOST, then UnitOnTaxi).
-- Nothing is computed in a fight: the comparison waits, and so does a window that wants it.
local _, ns = ...
local U, M, Guard = ns.Util, ns.Modules, ns.Guard
local S, Migrate = ns.Stats, ns.Migrate
local Num, Str = U.Num, U.Str

local RS = {
	SCHEMA = 1, -- layout of PathmarkCharDB.stats and PathmarkDB.stats
	SLICE = 250, -- vault texts read per frame while the comparison is built (chosen value)
	SLICE_MS = 1, -- and at most this many milliseconds per frame
	REFRESH = 30, -- seconds: a comparison older than this is built again when the vault changed
	REMOVED_DELAY = 1, -- completion flag check after QUEST_REMOVED (as Collect.lua and Guide.lua)
	TAXI_DELAY = 1, -- UnitOnTaxi after PLAYER_CONTROL_LOST (as Collect.lua)
}
ns.RunStats = RS

local api = {}
local tally, char, acct -- S tally; PathmarkCharDB.stats; PathmarkDB.stats
local driver -- hidden frame: its OnUpdate builds the comparison, shown only while a window waits
local index, indexSig, indexAt, job
local waiters = {} -- owner -> fn(owner, index)
local listeners = {} -- owner -> fn(owner): the tally changed (level-up, module run, quest, death)
local turnedIn = {}

local function Now()
	return GetTime()
end

local function Day()
	return math.floor((Num(GetServerTime()) or 0) / 86400)
end

local function Runs()
	local C = ns.Collector
	return C and C.runs
end

function RS.Fighting()
	return RS.fighting == true or (api.InCombatLockdown ~= nil and api.InCombatLockdown() == true)
end

function RS.Token()
	local C = ns.Collector
	return C and C.runToken
end

function RS.Race()
	local _, _, id = UnitRace("player")
	return Num(id)
end

function RS.Class()
	local _, _, id = UnitClass("player")
	return Num(id)
end

function RS.Char()
	return char
end

function RS.Account()
	return acct
end

function RS.Tally()
	return tally
end

-- Callbacks for the windows: fn(owner) after the tally changed. One per owner.
function RS.OnChange(owner, fn)
	listeners[owner] = fn
end

local function Changed()
	for owner, fn in pairs(listeners) do
		Guard.Call("stats", fn, owner)
	end
end

-- Quests the route leaves out now (skipped and their follow-ups), nil without a route.
local function Skipped()
	local R = ns.Route
	return R and R.Skipped and R.Skipped() or nil
end
RS.Skipped = Skipped

-- From the route (Routes/Guide.lua) -------------------------------------------------------------------

-- One gap of active play: d counted seconds, raw the whole gap, xp gained with the event.
function RS.Play(now, d, raw, xp)
	if tally then
		tally:Play(now, d, raw, xp)
	end
end

-- Level-up: closes the last level with the route's section, starts the new one, keeps a whole band in
-- the best times and marks the review card of levels 10, 20 and 30 as due.
function RS.LevelUp(level, sec)
	if not tally then
		return
	end
	tally:LevelUp(level, sec, Skipped(), Day())
	if level % S.BAND == 0 then
		local band = S.Band(char.lv, level)
		if band.complete then
			S.Best(acct.best, level, band.s, RS.Race(), RS.Class(), band.g, Day(), RS.Token())
		end
		if S.RECAP[level] and band.levels > 0 and not char.recap[level] then
			char.recap.pending = level
			local P = ns.StatsPage
			if P and P.QueueRecap then
				Guard.Call("statspage", P.QueueRecap)
			end
		end
	end
	Changed()
end

-- A module played from its first step past its last (the run vault's "m" section).
function RS.Module(num, key, version, secs, inOrder, mode, level)
	if tally and tally:Module(num, key, version, secs, inOrder, mode, level) then
		Changed()
	end
end

-- Review card ---------------------------------------------------------------------------------------

-- The level whose review card is due, nil when none.
function RS.PendingRecap()
	local level = char and char.recap.pending
	if level and not char.recap[level] then
		return level
	end
end

-- The card was shown (or the player turned it off): never again for this level.
function RS.RecapDone(level)
	if char and level then
		char.recap[level] = true
		if char.recap.pending == level then
			char.recap.pending = nil
		end
	end
end

-- Comparison with the class --------------------------------------------------------------------------

local function Signature(runs)
	local db = runs.db
	return db.first * 1000003 + db.last
end

-- The comparison as built last (may be older than the vault), nil before the first build.
function RS.Index()
	return index
end

-- Is a build running or waiting for the end of a fight?
function RS.Building()
	return job ~= nil
end

-- For tests: the running build ({ seq, last, sig, idx }) or nil.
function RS.Job()
	return job
end

local function Deliver()
	for owner, fn in pairs(waiters) do
		waiters[owner] = nil
		Guard.Call("stats", fn, owner, index)
	end
end

-- One slice of the build per frame: at most SLICE texts and SLICE_MS, nothing in a fight.
function RS.Step()
	if not job then
		driver:Hide()
		return
	end
	if RS.Fighting() then
		return
	end
	local runs = Runs()
	local list = runs and runs.db.list or {}
	local start, n = debugprofilestop(), 0
	while job.seq <= job.last do
		local msg = list[job.seq]
		job.seq = job.seq + 1
		if msg then
			S.Feed(job.idx, msg)
		end
		n = n + 1
		if n >= RS.SLICE or debugprofilestop() - start >= RS.SLICE_MS then
			return
		end
	end
	index, indexSig, indexAt = S.Seal(job.idx), job.sig, Now()
	job = nil
	driver:Hide()
	Deliver()
end

-- fn(owner, index) once the comparison is up to date (at once when it is). A comparison younger than
-- REFRESH seconds counts as up to date even when new sections arrived meanwhile.
function RS.Request(owner, fn)
	local runs, class = Runs(), RS.Class()
	if not (runs and class and driver) then
		Guard.Call("stats", fn, owner, nil)
		return
	end
	local sig = Signature(runs)
	if index and (indexSig == sig or Now() - indexAt < RS.REFRESH) and index.class == tostring(class) then
		Guard.Call("stats", fn, owner, index)
		return
	end
	waiters[owner] = fn
	if not job then
		job = {
			seq = runs.db.first,
			last = runs.db.last,
			sig = sig,
			idx = S.NewIndex(class, runs.db.mine),
		}
	end
	driver:Show()
end

-- The window closed: it waits no longer. The build stops with the last waiter and goes on later.
function RS.Cancel(owner)
	waiters[owner] = nil
	if not next(waiters) and driver then
		driver:Hide()
	end
end

-- Saved tables and migration ------------------------------------------------------------------------

-- Version 1 takes over what the run vault already holds: the own level and module sections of this
-- character (token) and the complete bands of every own character for the best times.
local function CharSteps(runs, tok)
	return {
		[1] = function(t)
			S.CharDB(t)
			local db = runs and runs.db
			local own = db and tok and S.FromVault(db.list, db.first, db.last, { [tok] = true })[tok]
			if own then
				for l, r in pairs(own.lv) do
					if t.lv[l] == nil then
						r.day = nil
						t.lv[l] = r
					end
				end
				for _, m in ipairs(own.mods) do
					t.mods[#t.mods + 1] = m
				end
			end
		end,
	}
end

local function AccountSteps(runs)
	return {
		[1] = function(t)
			S.AccountDB(t)
			local db = runs and runs.db
			if not db then
				return
			end
			for tok, own in pairs(S.FromVault(db.list, db.first, db.last, db.mine)) do
				S.BestOf(t.best, own.lv, own.race, own.class, tok)
			end
		end,
	}
end

local function Upgrade(saved, steps)
	saved = type(saved) == "table" and saved or {}
	local t, why = Migrate.Upgrade(saved, RS.SCHEMA, steps)
	if not t then
		error(why, 0)
	end
	return t
end

local function Init()
	api.InCombatLockdown = M.Optional("InCombatLockdown")
	api.UnitOnTaxi = M.Optional("UnitOnTaxi")
	api.IsQuestFlaggedCompleted = M.Optional("C_QuestLog.IsQuestFlaggedCompleted")
	local runs = Runs()
	PathmarkCharDB = type(PathmarkCharDB) == "table" and PathmarkCharDB or {}
	char = S.CharDB(Upgrade(PathmarkCharDB.stats, CharSteps(runs, RS.Token())))
	PathmarkCharDB.stats = char
	local db = ns.db or {}
	acct = S.AccountDB(Upgrade(db.stats, AccountSteps(runs)))
	db.stats = acct
	tally = S.NewTally(char)
	driver = CreateFrame("Frame")
	driver:Hide() -- OnUpdate runs only while the frame is shown
	driver:SetScript("OnUpdate", function()
		Guard.Call("stats", RS.Step)
	end)
	RS.driver = driver
end

-- Write the live tables back into whatever the globals hold now (Polestar trap, brain chapter 15 §7).
local function Save()
	if type(PathmarkCharDB) ~= "table" then
		PathmarkCharDB = {}
	end
	PathmarkCharDB.stats = char
	if type(PathmarkDB) == "table" then
		PathmarkDB.stats = acct
	end
end

local function OnTaxi()
	if api.UnitOnTaxi and api.UnitOnTaxi("player") == true then
		tally:Flag(Now(), "taxi", true)
	end
end

local events = {
	-- After the route's PLAYER_LOGIN (module order): its level section says whether this level is whole.
	PLAYER_LOGIN = function()
		local level = Num(UnitLevel("player"))
		if not level then
			return
		end
		local R = ns.Route
		local sec = R and R.LevelSection and R.LevelSection()
		local full = type(sec) == "table" and sec.l == level and sec.full == true
		local r = tally:Level(level, full)
		if r.b0 == nil then
			r.b0 = Skipped()
		end
		tally.mark = Now()
		tally.flags.combat = RS.Fighting() or nil
	end,
	PLAYER_LOGOUT = Save,
	PLAYER_REGEN_DISABLED = function()
		RS.fighting = true
		tally:Flag(Now(), "combat", true)
	end,
	PLAYER_REGEN_ENABLED = function()
		RS.fighting = false
		tally:Flag(Now(), "combat", false)
	end,
	PLAYER_STARTED_MOVING = function()
		tally:Flag(Now(), "move", true)
	end,
	PLAYER_STOPPED_MOVING = function()
		tally:Flag(Now(), "move", false)
	end,
	PLAYER_CONTROL_LOST = function()
		C_Timer.After(RS.TAXI_DELAY, Guard.Wrap("stats", OnTaxi))
	end,
	PLAYER_CONTROL_GAINED = function()
		if tally.flags.taxi then
			tally:Flag(Now(), "taxi", false)
		end
	end,
	PLAYER_DEAD = function()
		tally:Death()
		Changed()
	end,
	PARTY_KILL = function()
		tally:Kill(Now())
	end,
	QUEST_TURNED_IN = function(_, _, questID, xpReward)
		local q = Num(questID)
		if not q or turnedIn[q] then
			return
		end
		turnedIn[q] = true
		tally:Quest(Num(xpReward))
		Changed()
	end,
	-- Forever may send QUEST_TURNED_IN late or never (brain chapter 06 §3): after 1 s the completion
	-- flag decides, as in Collect.lua.
	QUEST_REMOVED = function(_, _, questID)
		local q = Num(questID)
		if not q or not api.IsQuestFlaggedCompleted then
			return
		end
		C_Timer.After(
			RS.REMOVED_DELAY,
			Guard.Wrap("stats", function()
				if not turnedIn[q] and api.IsQuestFlaggedCompleted(q) == true then
					turnedIn[q] = true
					tally:Quest(nil)
					Changed()
				end
			end)
		)
	end,
}

-- For tests and diagnostics: forget the built comparison.
function RS.Reset()
	index, indexSig, indexAt, job = nil, nil, nil, nil
	waiters = {}
end

-- Local name of a race or class for the best times (C_CreatureInfo, Forever docs CreatureInfoDocumentation.lua).
function RS.RaceName(id)
	local f = M.Optional("C_CreatureInfo.GetRaceInfo")
	local info = f and id and f(id)
	return type(info) == "table" and Str(info.raceName) or nil
end

function RS.ClassName(id)
	local f = M.Optional("C_CreatureInfo.GetClassInfo")
	local info = f and id and f(id)
	return type(info) == "table" and Str(info.className) or nil
end

M.Define("stats", {
	requires = {
		funcs = { "UnitLevel", "UnitRace", "UnitClass", "GetServerTime" },
		events = { "PLAYER_LOGIN" },
	},
	optional = {
		funcs = {
			"InCombatLockdown",
			"UnitOnTaxi",
			"C_QuestLog.IsQuestFlaggedCompleted",
			"C_CreatureInfo.GetRaceInfo",
			"C_CreatureInfo.GetClassInfo",
		},
		events = {
			"PLAYER_LOGOUT",
			"PLAYER_REGEN_DISABLED",
			"PLAYER_REGEN_ENABLED",
			"PLAYER_STARTED_MOVING",
			"PLAYER_STOPPED_MOVING",
			"PLAYER_CONTROL_LOST",
			"PLAYER_CONTROL_GAINED",
			"PLAYER_DEAD",
			"PARTY_KILL",
			"QUEST_TURNED_IN",
			"QUEST_REMOVED",
		},
	},
	init = Init,
	events = events,
})
