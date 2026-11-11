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

-- Routes/Guide.lua: module "route". Connects the route runtime (Runtime.lua) with the game: picks
-- the route for faction, race and class, feeds quest, level, zone and XP events in, saves progress
-- per character and offers the interface the step window (AP 6) will use. No frame, no text: the
-- window waits for the owner's design approval. Interface: docs/ROUTE-RUNTIME.md.
-- Quest events: abandon vs. turn-in after QUEST_REMOVED via the completion flag 1 s later, because
-- Forever sends QUEST_TURNED_IN late or not at all (brain chapter 06 §3, §4).
local _, ns = ...
local U, M, Guard = ns.Util, ns.Modules, ns.Guard
local R, RT, P, Fc = ns.Routes, ns.Runtime, ns.Prereq, ns.Forecast
local Num, Str = U.Num, U.Str

local Route = {
	MODES = { speed = true, explorer = true },
	EVENTS = {
		StepChanged = true,
		RouteRecalculated = true,
		XPBalance = true,
		QuestAbandoned = true,
		OfferChanged = true,
		NotOffered = true, -- the giver did not offer the quest of the step (Route.Offers)
	},
	EVALUATE_DELAY = 0.1, -- quest events come in bursts; one evaluation per burst
	JOB_BUDGET = 0.002, -- seconds of replanning per frame outside a fight (brain chapter 21 §6.2)
	REMOVED_DELAY = 1, -- completion flag check after QUEST_REMOVED (Questie, chapter 06 §3)
	TAXI_DELAY = 1, -- UnitOnTaxi after PLAYER_CONTROL_LOST (as Collector/Collect.lua)
	HEARTHSTONE_SPELL = 8690, -- spell of the hearthstone, item 6948 (client data, brain chapter 14 §4.6)
	-- C_Trainer.GetTrainerType: 0 general (class trainers), 2 professions, 3 pets (Forever UI source,
	-- TrainerConstantsDocumentation); a `train` step is the class trainer, so 2 and 3 do not count
	OTHER_TRAINER = { [2] = true, [3] = true },
	SAVE_FORMAT = 1,
}
ns.Route = Route

local LISTENER = "route-listener" -- errors of other modules' callbacks are recorded under this name
local api = {} -- optional client functions
local listeners = {} -- event -> { { owner, fn }, ... }
local rt, root -- runtime; BraindeadForeverCharDB.route
local store -- prerequisite observations, account-wide (BraindeadForeverDB.prereq)
local modules -- compiled modules of the played faction (read only)
local turnedIn = {} -- quests handed in this session (QUEST_TURNED_IN), the flag can lag behind
local levelSeen -- PLAYER_LEVEL_UP payload; UnitLevel can lag behind
local evalQueued, balanceQueued, offerQueued = false, false, false
local offer -- open question of the replanning (Routes/Replan.lua), or nil
local driver -- frame whose OnUpdate runs the replanning job one slice per frame
local lastXP, lastMax
local lastActive -- GetTime() of the last game event; gaps up to Forecast.IDLE_CAP count as play
local onTaxi = false -- on a flight since PLAYER_CONTROL_LOST (landing marks a `travel fly` step)

-- Callbacks -------------------------------------------------------------------------------------

-- fn(owner, ...) like Blizzard's CallbackRegistry. One callback per owner and event.
function Route.RegisterCallback(event, owner, fn)
	assert(Route.EVENTS[event], "unknown route event")
	assert(owner ~= nil and type(fn) == "function", "owner and function required")
	local list = listeners[event] or {}
	listeners[event] = list
	for _, l in ipairs(list) do
		if l.owner == owner then
			l.fn = fn
			return
		end
	end
	list[#list + 1] = { owner = owner, fn = fn }
end

function Route.UnregisterCallback(event, owner)
	local list = listeners[event] or {}
	for i = #list, 1, -1 do
		if list[i].owner == owner then
			table.remove(list, i)
		end
	end
end

-- A failing listener is recorded in the error buffer and does not stop the others.
local function Fire(event, ...)
	for _, l in ipairs(listeners[event] or {}) do
		Guard.Call(LISTENER, l.fn, l.owner, ...)
	end
end

-- World: the client state the runtime reads. Every value goes through Num/Str (secret values).
local world = {
	IsFlagged = function(q)
		return turnedIn[q] == true or C_QuestLog.IsQuestFlaggedCompleted(q) == true
	end,
	InLog = function(q)
		return Num(C_QuestLog.GetLogIndexForQuestID(q)) ~= nil
	end,
	IsComplete = function(q)
		return C_QuestLog.IsComplete(q) == true
	end,
	-- Objective progress (entry anchor, brain chapter 21 §6.1): an objective with a count above zero.
	Progress = function(q)
		if C_QuestLog.IsComplete(q) == true then
			return true
		end
		local list = api.GetQuestObjectives and api.GetQuestObjectives(q)
		for _, o in ipairs(type(list) == "table" and list or {}) do
			if o.finished == true or (Num(o.numFulfilled) or 0) > 0 then
				return true
			end
		end
		return false
	end,
	Level = function()
		local level = Num(UnitLevel("player")) or 1
		return math.max(level, levelSeen or 0)
	end,
	Map = function()
		return Num(C_Map.GetBestMapForUnit("player"))
	end,
	MapParent = function(map)
		local info = api.GetMapInfo and api.GetMapInfo(map)
		return info and Num(info.parentMapID) or nil
	end,
	XP = function()
		local rested = api.GetXPExhaustion and Num(api.GetXPExhaustion()) or 0
		return Num(UnitXP("player")) or 0, Num(UnitXPMax("player")) or 0, rested
	end,
	-- GetQuestLogRewardXP is undocumented and may vanish (Polestar): optional, only for quests in the log.
	RewardXP = function(q)
		if not api.GetQuestLogRewardXP or Num(C_QuestLog.GetLogIndexForQuestID(q)) == nil then
			return nil
		end
		local ok, xp = pcall(api.GetQuestLogRewardXP, q)
		return ok and Num(xp) or nil
	end,
	ItemCount = function(item)
		return api.GetItemCount and Num(api.GetItemCount(item)) or 0
	end,
	-- World position (west, north) and instance, for reordering a block from where the player stands;
	-- nil inside instances (restricted there).
	Position = function()
		if not api.UnitPosition then
			return nil
		end
		local north, west, _, inst = api.UnitPosition("player")
		return Num(west), Num(north), Num(inst)
	end,
	InCombat = function()
		return api.InCombatLockdown ~= nil and api.InCombatLockdown() == true
	end,
}
Route.world = world

-- Play time (time forecast, docs/ROUTE-RUNTIME.md §Time forecast) --------------------------------

local MODE_LETTER = { speed = "s", explorer = "e" }

-- Whether the player follows the route right now: a route, the step window on, no guidance pause.
-- Run sections played mostly otherwise count as free play (mode "f", docs/RUN-TIMES.md).
local function Following()
	if not rt then
		return false
	end
	local UI = ns.UI
	if UI and UI.Paused and UI.Paused() then
		return false
	end
	return M.IsActive("window")
end

-- Mode letter of a section: the route mode when the guidance was on for at least half of its active
-- seconds (chosen share), else "f".
local function ModeOf(part)
	if root and MODE_LETTER[root.mode] and (part.guided or 0) * 2 >= (part.secs or 0) then
		return MODE_LETTER[root.mode]
	end
	return "f"
end

-- Active play since the last game event, added to the own XP rate (per character), to the run of
-- the current module and to the current level section. xp: XP gained with this event.
local function Active(xp)
	local now = GetTime()
	local raw = lastActive and math.max(0, now - lastActive) or 0
	local d = math.min(raw, Fc.IDLE_CAP)
	lastActive = now
	local guided = Following() and d or 0
	if root then
		root.rate = type(root.rate) == "table" and root.rate or {}
		Fc.Add(root.rate, d, xp)
		local lv = root.lvl
		if type(lv) == "table" and lv.full then
			lv.secs, lv.xp, lv.guided = (lv.secs or 0) + d, (lv.xp or 0) + (xp or 0), (lv.guided or 0) + guided
		end
	end
	local sp = rt and rt.saved.split
	if type(sp) == "table" then
		sp.secs = (sp.secs or 0) + d
		sp.xp, sp.guided = (sp.xp or 0) + (xp or 0), (sp.guided or 0) + guided
	end
	-- The player's own statistics (Routes/RunStats.lua, Welle 8) take the same gap.
	local St = ns.RunStats
	if St and M.IsActive("stats") then
		Guard.Call("stats", St.Play, now, d, raw, xp)
	end
end

-- Level sections (Collector/Runs.lua): one section per level, from one level-up to the next, saved
-- per character so a /reload keeps its seconds. A section counts only when it started at a level-up
-- (or at level 1 without XP); the level the addon first sees is partial and never reported.
local function StartLevel(level, full)
	if root then
		root.lvl = { l = level, full = full or nil, secs = 0, xp = 0, guided = 0, n = 0, d = 0 }
	end
end

local function LevelUp(level)
	if not (root and level) then
		return
	end
	local lv = root.lvl
	if type(lv) == "table" and lv.l == level then
		return -- the same level-up twice
	end
	local sec
	if type(lv) == "table" and lv.l == level - 1 then
		local inOrder = (lv.n or 0) > 0 and 100 * (lv.d or 0) / lv.n or 0
		sec = { secs = lv.secs, xp = lv.xp, mode = ModeOf(lv), inOrder = inOrder, full = lv.full == true }
		local C = ns.Collector
		if lv.full and C and C.RecordRun then
			C.RecordRun("l", lv.l, 0, lv.secs, lv.xp, inOrder, level, sec.mode)
		end
	end
	local St = ns.RunStats
	if St and M.IsActive("stats") then
		Guard.Call("stats", St.LevelUp, level, sec)
	end
	StartLevel(level, true)
end

-- At login: continue the saved section of this level, else start a partial one (a new character at
-- level 1 without XP starts a full one).
local function ResumeLevel()
	local level = Num(UnitLevel("player"))
	if not (root and level) then
		return
	end
	local lv = root.lvl
	if type(lv) == "table" and lv.l == level then
		return
	end
	StartLevel(level, level == 1 and Num(UnitXP("player")) == 0)
end

-- Module runs: a run is clean when it starts at the module's first step and every step up to its end
-- is done (not skipped, not passed by the route). A clean run goes to the collector as a "split"
-- record (tools/routekit/observe.py builds the module times from them).
local function Split(cur, prev)
	if not rt then
		return
	end
	local s = rt.saved
	local sp = type(s.split) == "table" and s.split or nil
	rt.ranges = rt.ranges or Fc.Ranges(rt)
	local ranges = rt.ranges
	local from = prev and prev.index
	local to = cur and cur.index or #rt.steps + 1
	-- Steps the route passed in this level section, and how many of them were done (in route order).
	local lv = root and root.lvl
	if type(lv) == "table" and from and to > from then
		for j = from, to - 1 do
			lv.n = (lv.n or 0) + 1
			if rt:StepState(j) == "done" then
				lv.d = (lv.d or 0) + 1
			end
		end
	end
	if sp and from and to > from then
		for j = from, to - 1 do
			if rt.steps[j] and rt.steps[j].module == sp.m and rt:StepState(j) ~= "done" then
				sp.clean = false
			end
		end
	end
	if sp and cur and sp.m == cur.module then
		return
	end
	local r = sp and ranges[sp.m]
	if sp and r and to > r.last then
		local C = ns.Collector
		if sp.clean and C and C.RecordSplit then
			C.RecordSplit(sp.m, sp.secs or 0, root and root.mode)
		end
		-- Every run from the module's first step past its last goes to the exchange, with the share of
		-- its steps done (a clean run: 100).
		if sp.full and C and C.RecordRun then
			local done = 0
			for j = r.first, r.last do
				if rt:StepState(j) == "done" then
					done = done + 1
				end
			end
			local m = modules and modules[sp.m]
			local version = m and Num(m.version) or 0
			local inOrder = 100 * done / (r.last - r.first + 1)
			local number = ns.Proto.ModuleNumber(sp.m)
			C.RecordRun("m", number, version, sp.secs, sp.xp, inOrder, world.Level(), ModeOf(sp))
			local St = ns.RunStats
			if St and M.IsActive("stats") then
				Guard.Call("stats", St.Module, number, sp.m, version, sp.secs, inOrder, ModeOf(sp), world.Level())
			end
		end
	end
	local first = cur and ranges[cur.module].first == cur.index
	s.split = cur and { m = cur.module, secs = 0, xp = 0, guided = 0, clean = first, full = first or nil } or nil
end

-- Replanning job (Routes/Replan.lua): one slice of at most JOB_BUDGET per frame, nothing in a fight.
local function Clock()
	return debugprofilestop() / 1000
end

local function Tick()
	if not rt or not rt:RunJob(Clock, Route.JOB_BUDGET) then
		driver:Hide()
	end
end

local function Drive()
	if driver and rt and rt:Busy() then
		driver:Show()
	end
end

-- Balance and evaluation, bundled per burst of events ---------------------------------------------

local function SendBalance()
	balanceQueued = false
	if rt then
		Fire("XPBalance", rt:Balance())
	end
end

local function QueueBalance()
	if balanceQueued then
		return
	end
	balanceQueued = true
	C_Timer.After(Route.EVALUATE_DELAY, Guard.Wrap("route", SendBalance))
end

local function Evaluate()
	evalQueued = false
	if rt then
		rt:Evaluate()
		Drive()
	end
end

local function QueueEvaluate()
	Active()
	if evalQueued or not rt then
		return
	end
	evalQueued = true
	C_Timer.After(Route.EVALUATE_DELAY, Guard.Wrap("route", Evaluate))
end

-- Open question of the replanning ("over the plan", switch point): computed after a step change, a
-- recalculation or a level-up, not per frame; OfferChanged when it changes.
local function UpdateOffer()
	offerQueued = false
	local o = rt and rt:Offer() or nil
	if (o and o.id) ~= (offer and offer.id) then
		offer = o
		Fire("OfferChanged", o)
	else
		offer = o
	end
end

local function QueueOffer()
	if offerQueued then
		return
	end
	offerQueued = true
	C_Timer.After(Route.EVALUATE_DELAY, Guard.Wrap("route", UpdateOffer))
end

local function OnRuntime(event, ...)
	Drive()
	if event == "StepChanged" then
		Split(...)
		QueueBalance()
	end
	if event == "StepChanged" or event == "RouteRecalculated" then
		QueueOffer()
	end
	Fire(event, ...)
end

-- Saved state: BraindeadForeverCharDB.route = { mode = "speed", speed = {...}, explorer = {...} }.
local function Root()
	if type(BraindeadForeverCharDB) ~= "table" then
		BraindeadForeverCharDB = {}
	end
	if type(BraindeadForeverCharDB.route) ~= "table" then
		BraindeadForeverCharDB.route = {}
	end
	return BraindeadForeverCharDB.route
end

local function Build()
	rt, Route.missing, offer = nil, nil, nil
	root = Root()
	local mode = Route.MODES[root.mode] and root.mode or "speed"
	root.mode = mode
	local faction = Str((UnitFactionGroup("player")))
	local _, _, raceID = UnitRace("player")
	local _, _, classID = UnitClass("player")
	raceID, classID = Num(raceID), Num(classID)
	local saved = root[mode]
	local fresh = type(saved) ~= "table"
		or saved.v ~= Route.SAVE_FORMAT
		or saved.race ~= raceID
		or saved.class ~= classID
	-- alternative modules the player chose at switch points (Routes/Replan.lua, stage 2)
	local swap = not fresh and type(saved.alts) == "table" and saved.alts or nil
	local steps = faction and raceID and classID and R.Steps(faction, mode, raceID, classID, swap)
	if not steps then
		-- New race/class pairs are announced (brain chapter 14 §1): report, do not fail.
		Route.missing = ("no route for %s %s/%s"):format(tostring(faction), tostring(raceID), tostring(classID))
		Fire("RouteRecalculated", "missing")
		return
	end
	local data = R.Load(faction)
	R.Release()
	modules = data.modules
	if fresh then
		saved = { v = Route.SAVE_FORMAT, race = raceID, class = classID }
		root[mode] = saved
	end
	rt = RT.New(steps, data.quests, world, saved, {
		race = raceID,
		class = classID,
		modules = data.modules,
		unsure = data.unsure,
		maps = data.maps,
		alts = data.alts,
	})
	rt.data, rt.race, rt.class = data, raceID, classID
	if store then
		for q, r in pairs(store:Known()) do
			rt:SetObserved(q, r.state, r.groups)
		end
	end
	rt.notify = OnRuntime
	Fire("RouteRecalculated", "start")
	rt:Evaluate()
	Drive()
	QueueBalance()
end

-- Public interface (docs/ROUTE-RUNTIME.md) --------------------------------------------------------

local function Call(fn, ...)
	if not rt or not M.IsActive("route") then
		return nil
	end
	return Guard.Call("route", fn, ...)
end

function Route.Current()
	return Call(function()
		return rt:Current()
	end)
end

function Route.Upcoming(n)
	return Call(function()
		return rt:Upcoming(n or 3)
	end) or {}
end

function Route.StepState(key)
	return Call(function()
		local i = rt.index[key]
		return i and rt:StepState(i) or nil
	end)
end

function Route.Check(key)
	return Call(rt and rt.Check, rt, key) == true
end

function Route.Skip(key)
	return Call(rt and rt.Skip, rt, key) == true
end

function Route.Back()
	return Call(rt and rt.Back, rt) == true
end

function Route.Undo()
	return Call(rt and rt.Undo, rt) == true
end

function Route.Pending()
	return rt and rt:Pending() or nil
end

function Route.ResolveAbandon(choice)
	return Call(rt and rt.ResolveAbandon, rt, choice) == true
end

function Route.Balance()
	return Call(function()
		return rt:Balance()
	end)
end

-- For the step window: follow-up quests a skip takes with it, before anything moves.
function Route.SkipPreview(key)
	return Call(rt and rt.SkipPreview, rt, key)
end

-- Whether a skip of the step (or the answer "skip" to an abandon question) postpones a class chain
-- (KQ-1105): it comes back at the next zone change.
function Route.SkipPostpones(key)
	return Call(rt and rt.Postpones, rt, key) == true
end

function Route.AbandonPreview()
	return Call(rt and rt.AbandonPreview, rt)
end

-- The action Undo takes back ({ kind, key, quest }), nil when there is nothing to undo.
function Route.LastAction()
	return Call(rt and rt.LastAction, rt)
end

-- Compiled module (read only) of a module key or a step key "<module>/<step id>": label, version,
-- levels, steps. For the step window's "provisional" symbol and origin tooltip.
function Route.Module(key)
	if not modules or type(key) ~= "string" then
		return nil
	end
	return modules[key] or modules[key:match("^(.-)/[^/]*$") or ""]
end

-- Key of the module with this module number (Proto.ModuleNumber), for run sections that carry only the
-- number (Routes/RunStats.lua takes them over from the run vault). Nil when the faction has none.
local numbers, numbered
function Route.ModuleKey(num)
	if not modules then
		return nil
	end
	if numbered ~= modules then
		numbers, numbered = {}, modules
		for key in pairs(modules) do
			numbers[ns.Proto.ModuleNumber(key)] = key
		end
	end
	return numbers[num]
end

function Route.Mode()
	return root and root.mode or nil
end

-- Highest level the route data reaches (the top of the highest module band), or nil without a route.
-- The step window names it at the end of the route (requirement A32: no promise beyond the data).
function Route.TopLevel()
	if not modules then
		return nil
	end
	local top
	for _, m in pairs(modules) do
		local hi = type(m.levels) == "table" and tonumber(m.levels[2])
		if hi and (not top or hi > top) then
			top = hi
		end
	end
	return top
end

function Route.SetMode(mode)
	if not Route.MODES[mode] or not M.IsActive("route") then
		return false
	end
	Root().mode = mode
	Guard.Call("route", Build)
	return rt ~= nil
end

-- Time forecast (docs/ROUTE-RUNTIME.md §Time forecast) -------------------------------------------

-- { state, seconds, level, runs, plan, minRuns, nextLevel }: state "ready" | "collecting" | "done";
-- nextLevel = { state, seconds, perHour }. A part in state "collecting" has no numbers.
function Route.Forecast()
	return Call(function()
		local out = Fc.Route(rt, rt.data.times, rt.saved.split)
		local b = rt:Balance()
		out.minRuns = Fc.MIN_RUNS
		out.nextLevel = Fc.Level(root.rate, not b.stopped and b.toLevel or nil)
		return out
	end)
end

-- Dungeon hint (owner wish 11, docs/ROUTE-RUNTIME.md §Dungeon hint) -------------------------------

-- Dungeons that fit now with givers on the way: list (Routes/Dungeon.lua), {} when none. In speed mode
-- only those the XP balance justifies. Call on StepChanged and XPBalance.
function Route.DungeonHint()
	return Call(function()
		return ns.Dungeon.Hints(rt, rt.data, {
			mode = root.mode,
			level = world.Level(),
			race = rt.race,
			class = rt.class,
			balance = rt:Balance(),
			skipped = rt.saved.dungeons,
		})
	end) or {}
end

-- Hardcore-safe mode (Routes/Hardcore.lua): danger of a step for the character, or nil. Only the quests
-- the step sends the player to (accept, complete) count; the elite mark comes from the client.
local function IsElite(q)
	if not api.IsEliteQuest then
		return nil
	end
	local ok, elite = pcall(api.IsEliteQuest, q)
	return ok and elite == true
end

function Route.Danger(info)
	return Call(function()
		local s = info and rt.steps[info.index]
		if not s or s.key ~= info.key then
			return nil
		end
		return ns.Hardcore.Check(ns.Hardcore.Quests(s.els, R.VERB), rt.quests, world.Level(), IsElite)
	end)
end

-- Hides a dungeon hint (or shows it again with show = true). The route does not change.
function Route.SkipDungeon(id, show)
	return Call(function()
		id = tonumber(id)
		if not (id and rt.data.dungeons and rt.data.dungeons[id]) then
			return false
		end
		local s = rt.saved
		s.dungeons = type(s.dungeons) == "table" and s.dungeons or {}
		s.dungeons[id] = (not show) or nil
		return true
	end) == true
end

-- Prerequisites from player data (Welle 4, docs/ROUTE-RUNTIME.md) -------------------------------

local function Store()
	if not store then
		local db = ns.db or (type(BraindeadForeverDB) == "table" and BraindeadForeverDB) or {}
		db.prereq = type(db.prereq) == "table" and db.prereq or {}
		store = P.New(db.prereq)
	end
	return store
end

-- One observation of quest q (own, from the collector, or received): token of the observer, the
-- quest turned in directly before at the giver (0 = none), whether that turn-in unlocked q, quests
-- done and checked candidates not done. A changed result changes the route at once
-- (RouteRecalculated "prereq"). Returns true when the result for q changed.
function Route.Observe(q, token, link, unlock, done, missing)
	if not M.IsActive("route") then
		return false
	end
	return Guard.Call("route", function()
		local s = Store()
		if not s:Add(q, token, link, unlock, done, missing) then
			return false
		end
		q = tonumber(q)
		local state, groups = s:Result(q)
		if rt and rt:SetObserved(q, state, groups) then
			rt:Changed("prereq")
		end
		return true
	end) == true
end

-- A prerequisite message from another player (Collector/Exchange.lua, kind "p").
function Route.ObserveFind(find)
	return Route.Observe(find[2], find[1], find[3], tonumber(find[4]) == 1, P.Ids(find[5]), P.Ids(find[6]))
end

-- "known" | "observed" | "none" | "incomplete"; nil without a route.
function Route.ChainState(q)
	return Call(function()
		return rt:ChainState(q)
	end)
end

-- Quests that may be prerequisites of q: what observers reported and what the route data names.
function Route.Candidates(q)
	local set = {}
	if store then
		for _, c in ipairs(store:Candidates(q)) do
			set[c] = true
		end
	end
	if rt then
		for _, group in ipairs(rt:Groups(q)) do
			for _, c in ipairs(group) do
				set[c] = true
			end
		end
	end
	local out = {}
	for c in pairs(set) do
		out[#out + 1] = c
	end
	table.sort(out)
	return out
end

-- Whether an offer of q is worth recording: its prerequisites are not secured by a source, or
-- observers already named candidates for it.
function Route.Wants(q)
	if not M.IsActive("route") then
		return false
	end
	if rt and rt.unsure[q] then
		return true
	end
	return store ~= nil and #store:Candidates(q) > 0
end

-- Quests the route still follows: set { [questID] = true } of the route's quests without the ones the
-- player skipped and their follow-up quests. For Blizzard's quest tracker (UI/QuestWatch.lua).
function Route.Quests()
	return Call(function()
		local blocked, out = rt:Blocked(), {}
		for q in pairs(rt.routeQuests) do
			if not blocked[q] then
				out[q] = true
			end
		end
		return out
	end) or {}
end

-- Quests the current part of the route takes and hands in, for the optional automation (UI/Auto.lua):
-- the current step and the next DIALOG_AHEAD open steps, without quests the player skipped and their
-- follow-up quests and without optional quests whose question is not answered yes (RT:OptPending).
-- { accept = { [questID] = true }, turnin = { [questID] = true } }, nil without a route.
-- Steps the route passed (level rule, entry anchor) are not part of it.
Route.DIALOG_AHEAD = 3
function Route.DialogQuests()
	return Call(function()
		local out = { accept = {}, turnin = {} }
		local ctx = rt:Context()
		local i, n = rt.cur, 0
		while i and rt.steps[i] and n <= Route.DIALOG_AHEAD do
			if i == rt.cur or (rt:StepState(i, ctx) == "open" and not rt:Passed(i, ctx)) then
				n = n + 1
				for _, el in ipairs(rt.steps[i].els) do
					local v, q = el[1], el[2]
					if not ctx.blocked[q] and not (v == R.VERB.ACCEPT and rt:OptPending(q)) then
						if v == R.VERB.ACCEPT then
							out.accept[q] = true
						elseif v == R.VERB.TURNIN then
							out.turnin[q] = true
						end
					end
				end
			end
			i = i + 1
		end
		return out
	end)
end

-- An NPC listed the quests it offers (GOSSIP_SHOW, QUEST_GREETING; Collector/Collect.lua). kind and id
-- name the NPC (Util.Ref: "c" for a creature), set holds the offered quest IDs. A quest the route set
-- aside comes back when it is offered; an accept of the current part of the route whose giver this NPC
-- is and which it does not offer is set aside (RT:NotOffered). Only creatures with a known single giver
-- (Routes/Data_Npcs.lua): a quest box or a poster lists nothing.
function Route.Offers(kind, id, set)
	return Call(function()
		if type(set) ~= "table" then
			return false
		end
		local changed = false
		for q in pairs(set) do
			if rt:Offered(q) then
				changed = true
			end
		end
		local Names = ns.NpcNames
		if kind ~= "c" or not id or not (Names and Names.GiverID) then
			return changed
		end
		local dq = Route.DialogQuests()
		for q in pairs(dq and dq.accept or {}) do
			if not set[q] and Names.GiverID(q) == id and rt:NotOffered(q) then
				changed = true
			end
		end
		return changed
	end)
end

-- Danger of one quest for the character by the hardcore-safe rule (Routes/Hardcore.lua): elite mark of
-- the client or a quest level too far above; nil when none or without a route.
function Route.QuestDanger(q)
	return Call(function()
		return ns.Hardcore.Check({ q }, rt.quests, world.Level(), IsElite)
	end)
end

-- Open question of the replanning (docs/ROUTE-RUNTIME.md §Replanning), or nil:
-- { kind = "over", id, gap, plan, level, drop } or { kind = "switch", id, plan, level, map, choice, options }.
function Route.Offer()
	if not rt or not M.IsActive("route") then
		return nil
	end
	return offer
end

-- Answers the open question: yes = true takes it (leaves out quests, switches the zone), false keeps the
-- route; the question does not come again. True if answered.
function Route.AnswerOffer(yes)
	return Call(function()
		local o = offer
		if not o then
			return false
		end
		local r, module = rt:AnswerOffer(o.id, yes == true)
		if r == "rebuild" then
			local m = modules and modules[module]
			local first = m and m.steps and m.steps[1]
			rt.saved.anchor = first and (module .. "/" .. first.id) or nil
			Build()
		end
		UpdateOffer()
		return r ~= false
	end) == true
end

-- Quests the route passed on entry although they were neither done nor in the log (anchor rule,
-- docs/ROUTE-RUNTIME.md §Replanning): list of quest IDs in route order, {} when none.
function Route.Earlier()
	return Call(function()
		return rt:Earlier()
	end) or {}
end

-- Number of quests the route leaves out now (skipped by the player and their follow-ups), for the
-- player's statistics (Routes/RunStats.lua); nil without a route.
function Route.Skipped()
	return Call(function()
		local n = 0
		for _ in pairs(rt:Blocked()) do
			n = n + 1
		end
		return n
	end)
end

-- The current level section (read only): { l, full, secs, xp, guided, n, d }, nil before the login.
function Route.LevelSection()
	return root and root.lvl or nil
end

-- Last XP gain seen (for the probe check xp.kill).
function Route.LastGain()
	return Route.lastGain
end

-- For diagnostics and tests: the runtime object, nil without a route.
function Route.Runtime()
	return rt
end

-- Current step for the problem report (Core/Report.lua).
ns.CurrentStep = function()
	local c = rt and rt:Current()
	return c and c.key or (rt and "end") or Route.missing
end

-- Events ----------------------------------------------------------------------------------------

local function Init()
	for name, path in pairs({
		GetQuestLogRewardXP = "GetQuestLogRewardXP",
		GetXPExhaustion = "GetXPExhaustion",
		GetMapInfo = "C_Map.GetMapInfo",
		GetItemCount = "C_Item.GetItemCount",
		GetQuestObjectives = "C_QuestLog.GetQuestObjectives",
		UnitPosition = "UnitPosition",
		InCombatLockdown = "InCombatLockdown",
		IsEliteQuest = "C_QuestLog.IsEliteQuest", -- Forever only (hardcore-safe mode)
		UnitOnTaxi = "UnitOnTaxi",
		GetTrainerType = "C_Trainer.GetTrainerType",
	}) do
		api[name] = M.Optional(path)
	end
	driver = CreateFrame("Frame")
	driver:Hide() -- OnUpdate runs only while the frame is shown
	driver:SetScript("OnUpdate", function()
		Guard.Call("route", Tick)
	end)
	Route.driver = driver
	root = Root()
	Store()
end

local function TrackXP()
	local xp, max = Num(UnitXP("player")), Num(UnitXPMax("player"))
	if xp and lastXP then
		local gain = xp - lastXP
		if gain < 0 then -- level-up between two updates: rest of the old level plus the new XP
			gain = (lastMax or lastXP) - lastXP + xp
		end
		if gain > 0 then
			Route.lastGain = { xp = gain, level = Num(UnitLevel("player")), at = GetTime() }
		end
		Active(math.max(0, gain))
	end
	lastXP, lastMax = xp, max
end

local events = {
	PLAYER_LOGIN = function()
		lastXP, lastMax = Num(UnitXP("player")), Num(UnitXPMax("player"))
		lastActive = GetTime() -- time offline is no play
		Build()
		ResumeLevel()
	end,
	PLAYER_LOGOUT = function()
		-- Write the live table back into whatever BraindeadForeverCharDB holds now (Polestar trap, chapter 15).
		Root()
		if root then
			BraindeadForeverCharDB.route = root
		end
		if store and type(BraindeadForeverDB) == "table" and BraindeadForeverDB.prereq ~= store.db then
			BraindeadForeverDB.prereq = store.db
		end
	end,
	QUEST_ACCEPTED = function(_, _, questID)
		local q = Num(questID)
		if q and rt then
			rt:OnAccepted(q)
		end
		QueueEvaluate()
	end,
	QUEST_TURNED_IN = function(_, _, questID)
		local q = Num(questID)
		if q then
			turnedIn[q] = true
		end
		QueueEvaluate()
	end,
	QUEST_REMOVED = function(_, _, questID)
		local q = Num(questID)
		if not q then
			return
		end
		C_Timer.After(
			Route.REMOVED_DELAY,
			Guard.Wrap("route", function()
				if rt and not world.IsFlagged(q) and not world.InLog(q) then
					rt:OnAbandoned(q)
				end
				QueueEvaluate()
			end)
		)
	end,
	QUEST_LOG_UPDATE = QueueEvaluate,
	QUEST_WATCH_UPDATE = QueueEvaluate,
	-- Forever duel and emote quests progress only with this event and QUEST_LOG_UPDATE (Questie).
	QUEST_LOG_CRITERIA_UPDATE = QueueEvaluate,
	UNIT_QUEST_LOG_CHANGED = function(_, _, unit)
		if unit == "player" then
			QueueEvaluate()
		end
	end,
	ZONE_CHANGED_NEW_AREA = QueueEvaluate,
	BAG_UPDATE_DELAYED = QueueEvaluate,
	PLAYER_LEVEL_UP = function(_, _, level)
		levelSeen = Num(level)
		Active() -- the seconds up to the level-up belong to the old level
		LevelUp(levelSeen)
		if rt then
			rt:Recheck() -- played without the route meanwhile? (brain chapter 21 §6.1)
		end
		QueueEvaluate()
		QueueOffer()
		QueueBalance()
	end,
	PLAYER_XP_UPDATE = function(_, _, unit)
		if unit ~= "player" then
			return
		end
		TrackXP()
		QueueBalance()
	end,
	UPDATE_EXHAUSTION = QueueBalance,
	UI_INFO_MESSAGE = function(_, _, _, message)
		if rt and Str(message) and message == ERR_NEWTAXIPATH then
			rt:MarkEvent(R.VERB.FP)
		end
	end,
	-- The flight map opens only at a flight master whose flight point the character knows (talking to
	-- an unknown one teaches it first), so an `fp` step is done also when the point was known before.
	TAXIMAP_OPENED = function()
		if rt then
			rt:MarkEvent(R.VERB.FP)
		end
	end,
	HEARTHSTONE_BOUND = function()
		if rt then
			rt:MarkEvent(R.VERB.SETHOME)
		end
	end,
	UNIT_SPELLCAST_SUCCEEDED = function(_, _, unit, _, spellID)
		if rt and Str(unit) == "player" and Num(spellID) == Route.HEARTHSTONE_SPELL then
			rt:MarkEvent(R.VERB.HS)
		end
	end,
	TRAINER_SHOW = function()
		if not rt then
			return
		end
		local kind = api.GetTrainerType and Num(api.GetTrainerType())
		if not (kind and Route.OTHER_TRAINER[kind]) then
			rt:MarkEvent(R.VERB.TRAIN)
		end
	end,
	PLAYER_CONTROL_LOST = function()
		if not api.UnitOnTaxi then
			return
		end
		C_Timer.After(
			Route.TAXI_DELAY,
			Guard.Wrap("route", function()
				if api.UnitOnTaxi("player") == true then
					onTaxi = true
				end
			end)
		)
	end,
	PLAYER_CONTROL_GAINED = function()
		if onTaxi then
			onTaxi = false
			if rt then
				rt:MarkEvent(R.VERB.TRAVEL, 2) -- 2: travel fly
			end
		end
	end,
}

M.Define("route", {
	core = true,
	requires = {
		funcs = {
			"C_QuestLog.IsQuestFlaggedCompleted",
			"C_QuestLog.GetLogIndexForQuestID",
			"C_QuestLog.IsComplete",
			"C_Map.GetBestMapForUnit",
			"UnitLevel",
			"UnitRace",
			"UnitClass",
			"UnitFactionGroup",
			"UnitXP",
			"UnitXPMax",
		},
		events = { "PLAYER_LOGIN", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_LOG_UPDATE" },
	},
	optional = {
		funcs = {
			"GetQuestLogRewardXP",
			"GetXPExhaustion",
			"C_Map.GetMapInfo",
			"C_Item.GetItemCount",
			"C_QuestLog.GetQuestObjectives",
			"UnitPosition",
			"InCombatLockdown",
			"C_QuestLog.IsEliteQuest",
			"UnitOnTaxi",
			"C_Trainer.GetTrainerType",
		},
		events = {
			"PLAYER_LOGOUT",
			"QUEST_TURNED_IN",
			"QUEST_WATCH_UPDATE",
			"QUEST_LOG_CRITERIA_UPDATE",
			"UNIT_QUEST_LOG_CHANGED",
			"ZONE_CHANGED_NEW_AREA",
			"BAG_UPDATE_DELAYED",
			"PLAYER_LEVEL_UP",
			"PLAYER_XP_UPDATE",
			"UPDATE_EXHAUSTION",
			"UI_INFO_MESSAGE",
			"HEARTHSTONE_BOUND",
			"TAXIMAP_OPENED",
			"UNIT_SPELLCAST_SUCCEEDED",
			"TRAINER_SHOW",
			"PLAYER_CONTROL_LOST",
			"PLAYER_CONTROL_GAINED",
		},
	},
	init = Init,
	events = events,
})
