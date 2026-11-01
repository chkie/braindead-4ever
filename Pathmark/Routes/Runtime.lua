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

-- Routes/Runtime.lua: the logic behind the step display, without any frame (owner wish 9 and 10,
-- 2026-11-01). Pure Lua: the client state comes in through a world table, so the offline tests run
-- the same code. Interface and rules: docs/ROUTE-RUNTIME.md.
--
-- Rules (brain chapter 08 §6 and the design template there):
-- * Progress hangs on step keys "<module>/<step id>", never on line numbers. Saved per character:
--   the current step (anchor), the player's marks (checked, skipped, event seen), the quests the
--   player skipped (roots), a question that waits for an answer (pending) and an undo list.
-- * Quest state is never saved: it comes from the server each time (quest log, completion flag).
-- * From the anchor the route moves forward over every step that is done, skipped or passed.
-- * Skipping a quest skips every quest that needs it (prerequisite groups from the route data; one
--   quest per group is enough), transitively; a quest already handed in is never skipped.
local _, ns = ...
local R, XP = ns.Routes, ns.XP
local V = R.VERB

local RT = {}
RT.__index = RT
ns.Runtime = RT

-- Chosen values, not measured: a step planned more than LEVEL_MARGIN levels below the character
-- counts as passed (its quests give at most 80 % XP from quest level + 6 on, see XP.QuestXP).
RT.LEVEL_MARGIN = 5
RT.UNDO_MAX = 20
RT.LOOKAHEAD = 3 -- an event (flight path, hearthstone bound) counts for the current and next 3 steps

local QUEST = { [V.ACCEPT] = true, [V.COMPLETE] = true, [V.TURNIN] = true }
local EVENT = { [V.HS] = true, [V.SETHOME] = true, [V.FP] = true }

local function copy(t)
	local c = {}
	for k, v in pairs(t) do
		c[k] = v
	end
	return c
end

local function noop() end

-- steps: list of { module = key, step = compiled step } (Routes.Steps). quests: compiled quest facts
-- { [questID] = { level, xp, { { id, ... }, ... } } }. world: client state (docs/ROUTE-RUNTIME.md).
-- saved: the per-character table, changed in place. opts: race, class, modules (compiled modules).
function RT.New(steps, quests, world, saved, opts)
	opts = opts or {}
	saved.marks = type(saved.marks) == "table" and saved.marks or {}
	saved.roots = type(saved.roots) == "table" and saved.roots or {}
	saved.undo = type(saved.undo) == "table" and saved.undo or {}
	local self = setmetatable({
		world = world,
		quests = quests or {},
		saved = saved,
		modules = opts.modules or {},
		steps = {},
		index = {},
		dependents = {},
		accepts = {},
		unsure = {}, -- questID -> true: no source secures its prerequisites (data: unsure)
		observed = {}, -- questID -> prerequisite groups confirmed by player observations
		resolved = {}, -- questID -> "observed" | "observed-none" (Routes/Prereq.lua)
		notify = noop,
	}, RT)
	for _, q in ipairs(opts.unsure or {}) do
		self.unsure[q] = true
	end
	local seen = {}
	for i, entry in ipairs(steps) do
		local data = entry.step
		local s = {
			key = entry.module .. "/" .. data.id,
			module = entry.module,
			id = data.id,
			lv = data.lv,
			ret = data.ret,
			data = data,
			els = {},
			quests = {}, -- quest IDs in element order
			has = {}, -- questID -> true
		}
		local hasQuest, travel = false, nil
		for _, el in ipairs(data) do
			if not (el.r or el.c) or not opts.race or R.Applies(el, opts.race, opts.class) then
				s.els[#s.els + 1] = el
				local v = el[1]
				if QUEST[v] then
					hasQuest = true
					local q = el[2]
					if not s.has[q] then
						s.has[q] = true
						s.quests[#s.quests + 1] = q
					end
					if v == V.ACCEPT and not self.accepts[q] then
						self.accepts[q] = i
					end
					seen[q] = true
				elseif v == V.TRAVEL then
					travel = el[3]
				end
			end
		end
		s.kind = hasQuest and "quest" or travel and "travel" or "other"
		s.travel = travel
		self.steps[i], self.index[s.key] = s, i
	end
	-- Travel steps: the block they lead into ends before the next travel step.
	local nextTravel = #self.steps + 1
	for i = #self.steps, 1, -1 do
		local s = self.steps[i]
		s.blockEnd = nextTravel - 1
		if s.kind == "travel" then
			nextTravel = i
		end
	end
	self.routeQuests = seen
	self:Reindex()
	return self
end

-- Prerequisite groups of a quest: groups confirmed by player observations replace the groups of
-- the sources (own measurements replace foreign data); otherwise the route data.
local NONE = {}
function RT:Groups(q)
	local own = self.observed[q]
	if own and #own > 0 then
		return own
	end
	local info = self.quests[q]
	return info and info[3] or NONE
end

-- Reverse prerequisites: quest -> route quests that name it in one of their groups.
function RT:Reindex()
	local dependents = {}
	for q in pairs(self.routeQuests) do
		for _, group in ipairs(self:Groups(q)) do
			for _, m in ipairs(group) do
				local list = dependents[m] or {}
				dependents[m] = list
				list[#list + 1] = q
			end
		end
	end
	self.dependents = dependents
end

-- Quests that cannot be done any more because the player skipped them or a quest they need.
function RT:Blocked()
	local flagged = self.world.IsFlagged
	local blocked, queue = {}, {}
	for q in pairs(self.saved.roots) do
		if not flagged(q) then
			blocked[q] = true
			queue[#queue + 1] = q
		end
	end
	local head = 1
	while queue[head] do
		local q = queue[head]
		head = head + 1
		for _, f in ipairs(self.dependents[q] or {}) do
			if not blocked[f] and not flagged(f) and self:Dead(f, blocked) then
				blocked[f] = true
				queue[#queue + 1] = f
			end
		end
	end
	return blocked
end

-- A quest is dead when one of its prerequisite groups has only blocked quests left.
function RT:Dead(q, blocked)
	for _, group in ipairs(self:Groups(q)) do
		local all = #group > 0
		for _, m in ipairs(group) do
			if not blocked[m] then
				all = false
				break
			end
		end
		if all then
			return true
		end
	end
	return false
end

function RT:Context()
	local w = self.world
	return { blocked = self:Blocked(), level = w.Level() or 1, map = w.Map() }
end

local function InZone(self, target, map)
	local parent = self.world.MapParent
	for _ = 1, 6 do
		if not map then
			return false
		end
		if map == target then
			return true
		end
		map = parent and parent(map) or nil
	end
	return false
end

-- true/false for elements that decide whether a step is done, nil for the rest (goto, note, train).
function RT:ElementDone(s, el, ctx)
	local v, w = el[1], self.world
	if QUEST[v] then
		local q = el[2]
		if ctx.blocked[q] or w.IsFlagged(q) then
			return true
		end
		if v == V.ACCEPT then
			return w.InLog(q)
		elseif v == V.COMPLETE then
			return w.InLog(q) and w.IsComplete(q)
		end
		return false
	elseif v == V.TRAVEL then
		return InZone(self, el[3], ctx.map)
	elseif v == V.XP then
		return ctx.level >= el[2]
	elseif v == V.COLLECT then
		local n = w.ItemCount and w.ItemCount(el[2])
		return (n or 0) >= el[3]
	elseif EVENT[v] then
		return self.saved.marks[s.key] == "e"
	end
	return nil
end

-- "done" | "skipped" | "open", and why: manual, skip, chain, server.
function RT:StepState(i, ctx)
	local s = self.steps[i]
	if not s then
		return nil
	end
	ctx = ctx or self:Context()
	local mark = self.saved.marks[s.key]
	if mark == "s" then
		return "skipped", "skip"
	elseif mark == "c" then
		return "done", "manual"
	end
	if s.kind == "quest" then
		local all = true
		for _, q in ipairs(s.quests) do
			if not ctx.blocked[q] then
				all = false
				break
			end
		end
		if all then
			return "skipped", "chain"
		end
	elseif s.kind == "travel" and s.blockEnd > i then
		local all = true
		for j = i + 1, s.blockEnd do
			if self:StepState(j, ctx) ~= "skipped" then
				all = false
				break
			end
		end
		if all then
			return "skipped", "chain"
		end
	end
	local counted, done = 0, true
	for _, el in ipairs(s.els) do
		local d = self:ElementDone(s, el, ctx)
		if d ~= nil then
			counted = counted + 1
			if not d then
				done = false
			end
		end
	end
	if counted > 0 and done then
		return "done", "server"
	end
	return "open"
end

-- The server shows progress on a quest of this step (handed in, in the log, objectives done).
function RT:Evidence(i)
	local w = self.world
	for _, el in ipairs(self.steps[i].els) do
		local v = el[1]
		if QUEST[v] then
			local q = el[2]
			if w.IsFlagged(q) or (v ~= V.TURNIN and w.InLog(q) and (v == V.ACCEPT or w.IsComplete(q))) then
				return true
			end
		end
	end
	return false
end

function RT:HoldsLogQuest(i)
	for _, q in ipairs(self.steps[i].quests) do
		if self.world.InLog(q) then
			return true
		end
	end
	return false
end

-- An open step the route may pass without the player: far below the character's level, before the
-- last step with server progress on a fresh start, or a travel step whose next quest shows progress.
-- A step the player went back to (pin) is never passed by these rules.
function RT:Passed(i, ctx)
	local s = self.steps[i]
	if self.saved.pin == s.key then
		return false
	end
	if ctx.fresh and i < ctx.evidence and not self:HoldsLogQuest(i) then
		return true
	end
	if s.lv and s.lv + RT.LEVEL_MARGIN < ctx.level and not self:HoldsLogQuest(i) then
		return true
	end
	if s.kind ~= "quest" then
		for j = i + 1, #self.steps do
			if self.steps[j].kind == "quest" then
				return self:Evidence(j)
			end
		end
	end
	return false
end

function RT:Info(i)
	local s = self.steps[i]
	if not s then
		return nil
	end
	local m = self.modules[s.module]
	local chain
	for _, q in ipairs(s.quests) do
		if self:ChainState(q) == "incomplete" then
			chain = "incomplete"
			break
		end
	end
	return {
		index = i,
		total = #self.steps,
		key = s.key,
		module = s.module,
		id = s.id,
		lv = s.lv,
		ret = s.ret,
		kind = s.kind,
		label = m and m.label,
		quests = copy(s.quests),
		step = s.data,
		chain = chain,
	}
end

function RT:Current()
	return self.cur and self:Info(self.cur) or nil
end

function RT:Pending()
	return self.saved.pending
end

-- Moves the current step forward from the anchor. While a question waits (abandoned quest), the
-- current step stays where it is: nothing happens without the player's answer.
function RT:Evaluate()
	local saved, prev, n = self.saved, self.cur, #self.steps
	local i
	if saved.anchor == "_end" then
		i = n + 1
	else
		i = self.index[saved.anchor]
	end
	if saved.pending then
		i = i or prev or 1
	else
		local ctx = self:Context()
		if not i then
			ctx.fresh = true
			ctx.evidence = 0
			for j = n, 1, -1 do
				if self.steps[j].kind == "quest" and self:Evidence(j) then
					ctx.evidence = j
					break
				end
			end
			i = 1
		end
		while i <= n do
			if self:StepState(i, ctx) == "open" and not self:Passed(i, ctx) then
				break
			end
			i = i + 1
		end
		if saved.pin and self.index[saved.pin] ~= i then
			saved.pin = nil
		end
	end
	self.cur = i
	saved.anchor = self.steps[i] and self.steps[i].key or "_end"
	if prev ~= i then
		self.notify("StepChanged", self:Info(i), prev and self:Info(prev) or nil)
	end
	return self:Current()
end

-- The next n open steps after the current one.
function RT:Upcoming(n)
	local out, ctx = {}, self:Context()
	local i = (self.cur or 0) + 1
	while self.steps[i] and #out < (n or 3) do
		if self:StepState(i, ctx) == "open" and not self:Passed(i, ctx) then
			out[#out + 1] = self:Info(i)
		end
		i = i + 1
	end
	return out
end

-- Undo -----------------------------------------------------------------------------------------

function RT:Push()
	local s, u = self.saved, self.saved.undo
	u[#u + 1] = { marks = copy(s.marks), roots = copy(s.roots), anchor = s.anchor, pin = s.pin, pending = s.pending }
	while #u > RT.UNDO_MAX do
		table.remove(u, 1)
	end
end

function RT:Undo()
	local u = self.saved.undo
	local snap = table.remove(u)
	if not snap then
		return false
	end
	local s = self.saved
	s.marks, s.roots = copy(snap.marks), copy(snap.roots)
	s.anchor, s.pin, s.pending = snap.anchor, snap.pin, snap.pending
	self:Changed("undo")
	return true
end

function RT:Changed(reason)
	self:Evaluate()
	self.notify("RouteRecalculated", reason)
end

-- Player actions ---------------------------------------------------------------------------------

local function Key(self, key)
	if key == nil then
		local s = self.cur and self.steps[self.cur]
		return s and s.key
	end
	return self.index[key] and key or nil
end

-- Check: the player marks a step as done (default: the current step).
function RT:Check(key)
	key = Key(self, key)
	if not key then
		return false
	end
	self:Push()
	self.saved.marks[key] = "c"
	self:Evaluate()
	return true
end

-- Skip: the step and every quest it names, with all quests that need them.
function RT:Skip(key)
	key = Key(self, key)
	if not key then
		return false
	end
	self:Push()
	local s = self.saved
	s.marks[key] = "s"
	for _, q in ipairs(self.steps[self.index[key]].quests) do
		if not s.roots[q] and not self.world.IsFlagged(q) then
			s.roots[q] = key
		end
	end
	self:Changed("skip")
	return true
end

-- Back: reopens the nearest earlier step that the player marked or the route passed by itself; a
-- skip made there is taken back with its follow-up quests. Steps the server state has done stay done.
function RT:Back()
	local s, ctx, empty = self.saved, self:Context(), { blocked = {} }
	for j = (self.cur or 1) - 1, 1, -1 do
		local step = self.steps[j]
		local owns = false
		for _, k in pairs(s.roots) do
			if k == step.key then
				owns = true
				break
			end
		end
		local candidate = s.marks[step.key] ~= nil or owns
		if not candidate then
			candidate = self:StepState(j, ctx) == "open"
		end
		if candidate then
			-- Done by the server without any mark: nothing to reopen.
			empty.level, empty.map = ctx.level, ctx.map
			local mark = s.marks[step.key]
			s.marks[step.key] = nil
			local st = self:StepState(j, empty)
			s.marks[step.key] = mark
			if st ~= "done" then
				self:Push()
				s.marks[step.key] = nil
				for q, k in pairs(s.roots) do
					if k == step.key then
						s.roots[q] = nil
					end
				end
				s.anchor, s.pin = step.key, step.key
				self:Changed("back")
				return true
			end
		end
	end
	return false
end

-- Event seen in the game (flight path learned, hearthstone set or used): marks the first open step
-- among the current and the next LOOKAHEAD steps that has this element.
function RT:MarkEvent(verb)
	local cur = self.cur
	if not cur then
		return false
	end
	for i = cur, math.min(cur + RT.LOOKAHEAD, #self.steps) do
		local s = self.steps[i]
		for _, el in ipairs(s.els) do
			if el[1] == verb and self.saved.marks[s.key] == nil then
				self.saved.marks[s.key] = "e"
				self:Evaluate()
				return true
			end
		end
	end
	return false
end

-- Abandoned quests (owner wish 10) ---------------------------------------------------------------

-- The game removed a quest without handing it in. Asks only when the route had counted it as taken
-- (its accept step lies behind the current step); the answer comes through ResolveAbandon.
function RT:OnAbandoned(q)
	local s, w = self.saved, self.world
	local accept = self.accepts[q]
	if not accept or not self.cur or accept >= self.cur then
		return false
	end
	if s.pending == q then
		return true
	end
	if w.IsFlagged(q) or w.InLog(q) or self:Blocked()[q] then
		return false
	end
	s.pending = q
	self.notify("QuestAbandoned", q)
	return true
end

-- The player took the quest again: an open question about it is answered.
function RT:OnAccepted(q)
	if self.saved.pending == q then
		self.saved.pending = nil
	end
	return self:Evaluate()
end

-- "reaccept": back to the quest giver; "skip": skip the quest with every quest that needs it.
function RT:ResolveAbandon(choice)
	local s = self.saved
	local q = s.pending
	if not q or (choice ~= "reaccept" and choice ~= "skip") then
		return false
	end
	self:Push()
	s.pending = nil
	local key = self.steps[self.accepts[q]].key
	if choice == "skip" then
		s.roots[q] = key
	else
		for _, step in ipairs(self.steps) do
			if step.has[q] and s.marks[step.key] == "c" then
				s.marks[step.key] = nil
			end
		end
		s.anchor, s.pin = key, key
	end
	self:Changed(choice)
	return true
end

-- XP balance (owner wish 9) ----------------------------------------------------------------------

-- XP of a quest's turn-in: the client value while the quest is in the log, else the route data with
-- the Classic level reduction.
function RT:QuestXP(q, level)
	local w = self.world
	local fromLog = w.RewardXP and w.RewardXP(q)
	if fromLog and fromLog > 0 then
		return fromLog, "log"
	end
	local info = self.quests[q]
	if info and info[2] and info[2] > 0 then
		return XP.QuestXP(info[2], info[1], level), "data"
	end
	return 0, nil
end

-- XP of the turn-ins of step i that are still open.
function RT:TurninXP(i, ctx)
	local sum, source = 0, nil
	for _, el in ipairs(self.steps[i].els) do
		local q = el[1] == V.TURNIN and el[2]
		if q and not ctx.blocked[q] and not self.world.IsFlagged(q) then
			local xp, src = self:QuestXP(q, ctx.level)
			sum = sum + xp
			if src then
				source = (source == nil or source == src) and src or "mixed"
			end
		end
	end
	return sum, source
end

-- XP to the next level, XP of the current step, and whether the route up to the next zone reaches
-- the level planned there; if not, about how many kills of creatures at the character's level close
-- the gap. Every value derived from data or formulas is an estimate (b.estimate).
function RT:Balance()
	local w = self.world
	local xp, xpMax, rested = w.XP()
	xp, xpMax, rested = xp or 0, xpMax or 0, rested or 0
	local ctx = self:Context()
	local level = ctx.level
	local b = {
		level = level,
		xp = xp,
		xpMax = xpMax,
		rested = rested,
		toLevel = math.max(0, xpMax - xp),
		estimate = true,
	}
	if xpMax <= 0 then
		b.stopped = true -- maximum level or XP turned off
		return b
	end
	local i, n = self.cur, #self.steps
	if not i or i > n then
		return b
	end
	local sx, src = self:TurninXP(i, ctx)
	b.step = { xp = sx, source = src }
	-- Zone end: the next travel step that is no detour (class quests) and not skipped.
	local j, routeXP = i, 0
	if self.steps[i].kind == "travel" then
		j = i + 1
	end
	while j <= n do
		local s = self.steps[j]
		local st = self:StepState(j, ctx)
		if s.kind == "travel" and not s.ret and st ~= "skipped" then
			break
		end
		if st ~= "skipped" then
			routeXP = routeXP + (self:TurninXP(j, ctx))
		end
		j = j + 1
	end
	if j > n then
		return b
	end
	local nextLevel
	for k = j + 1, n do
		if self.steps[k].kind ~= "travel" and self.steps[k].lv then
			nextLevel = self.steps[k].lv
			break
		end
	end
	local zone = { endIndex = j - 1, nextMap = self.steps[j].travel, nextLevel = nextLevel, routeXP = routeXP }
	b.zone = zone
	local needed = nextLevel and XP.Needed(level, xp, xpMax, nextLevel)
	if needed then
		zone.needed = needed
		zone.shortfall = math.max(0, needed - routeXP)
		zone.enough = zone.shortfall == 0
		zone.kills, zone.killXP = XP.Kills(zone.shortfall, level, rested)
	end
	return b
end

-- Prerequisites from player data (docs/ROUTE-RUNTIME.md) ------------------------------------------

-- "known": a source secures the prerequisites; "observed": players confirmed them (Routes/Prereq.lua);
-- "none": players confirmed there is none; "incomplete": nobody knows yet, so skipping a quest may
-- leave a follow-up quest in the route that the game will not offer.
function RT:ChainState(q)
	local r = self.resolved[q]
	if r == "observed" then
		return "observed"
	elseif r == "observed-none" then
		return "none"
	elseif self.quests[q] and not self.unsure[q] then
		return "known"
	end
	return "incomplete"
end

-- Result of the prerequisite rule for one quest (Prereq:Result). Returns true when the route changed;
-- the caller then recalculates (RT:Changed("prereq")). An observed "none" keeps prerequisites a
-- source states (same as tools/routekit/merge.py).
function RT:SetObserved(q, state, groups)
	local before = self.resolved[q]
	local beforeKey = ns.Prereq and ns.Prereq.GroupKey(self.observed[q]) or ""
	if state == "observed" then
		self.resolved[q], self.observed[q] = state, groups
	elseif state == "observed-none" then
		self.resolved[q], self.observed[q] = state, nil
	else
		self.resolved[q], self.observed[q] = nil, nil
	end
	local key = ns.Prereq and ns.Prereq.GroupKey(self.observed[q]) or ""
	if before == self.resolved[q] and beforeKey == key then
		return false
	end
	self:Reindex()
	return true
end
