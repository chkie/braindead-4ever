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
-- * Class quests are never lost (owner 2026-11-05, KQ-1105): skipping, abandoning or passing a quest
--   of a class chain puts it on the list "later" (saved.later); it comes back at the next zone change
--   (Replan.lua, question "later") and is played as a side trip (RT:TakeLater).
local _, ns = ...
local R, XP = ns.Routes, ns.XP
local V = R.VERB

local RT = {}
RT.__index = RT
ns.Runtime = RT

-- Chosen values, not measured: a step planned more than LEVEL_MARGIN levels below the character
-- counts as passed (its quests give at most 80 % XP from quest level + 6 on, see XP.QuestXP).
RT.LEVEL_MARGIN = 5
-- Chosen value (Polestar #86, brain chapter 21 §6.1): the entry anchor holds only when at least this
-- share of the route quests up to it is handed in or in the log; else the route starts from the top.
RT.ANCHOR_SHARE = 0.5
RT.EARLIER_MAX = 200 -- quests kept in the list "skipped earlier"
RT.UNDO_MAX = 20
RT.LOOKAHEAD = 3 -- an event (flight path, hearthstone, trainer, landing) counts for the current and next 3 steps

local QUEST = { [V.ACCEPT] = true, [V.COMPLETE] = true, [V.TURNIN] = true }
local EVENT = { [V.HS] = true, [V.SETHOME] = true, [V.FP] = true, [V.TRAIN] = true }
local FLY = 2 -- travel how: fly (docs/ROUTE-FORMAT.md, compiled form)

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
	saved.later = type(saved.later) == "table" and saved.later or {}
	local self = setmetatable({
		world = world,
		quests = quests or {},
		saved = saved,
		modules = opts.modules or {},
		steps = {},
		index = {},
		dependents = {},
		accepts = {},
		classQ = {}, -- questID -> true: a class quest (element class filter or a class insert module)
		unsure = {}, -- questID -> true: no source secures its prerequisites (data: unsure)
		observed = {}, -- questID -> prerequisite groups confirmed by player observations
		resolved = {}, -- questID -> "observed" | "observed-none" (Routes/Prereq.lua)
		notify = noop,
		recheck = true, -- the first evaluation places the route by the anchor rule (RT:Anchor)
	}, RT)
	for _, q in ipairs(opts.unsure or {}) do
		self.unsure[q] = true
	end
	local seen = {}
	local zone -- zone of the steps so far: target of the last travel, else the map of a goto
	for i, entry in ipairs(steps) do
		local data = entry.step
		local mod = self.modules[entry.module]
		local classModule = mod and mod.kind == "class"
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
		local hasQuest, travel, gotoMap = false, nil, nil
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
					if el.c or classModule then
						self.classQ[q] = true
					end
					if v == V.ACCEPT and not self.accepts[q] then
						self.accepts[q] = i
					end
					seen[q] = true
				elseif v == V.TRAVEL then
					travel = el[3]
					if el[2] == FLY then
						s.flyFrom = zone or false -- zone the flight starts in (false: unknown)
					end
				elseif v == V.GOTO and not gotoMap then
					gotoMap = el[2]
				end
			end
		end
		s.kind = hasQuest and "quest" or travel and "travel" or "other"
		-- What the character sees of the step (RT:Info): the compiled step without the elements filtered
		-- out above. Built once per step; the compiled data stays read only and is used as it is when no
		-- element was filtered out.
		if #s.els == #data then
			s.view = data
		else
			local view = {}
			for k, v in pairs(data) do
				if type(k) ~= "number" then
					view[k] = v
				end
			end
			for n, el in ipairs(s.els) do
				view[n] = el
			end
			s.view = view
		end
		s.travel = travel
		zone = travel or gotoMap or zone
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
	if self.InitReplan then
		self:InitReplan(opts) -- Routes/Replan.lua: blocks for reordering, saved orders, alternatives
	end
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
	self.chainMemo = nil
end

-- Class chain (KQ-1105): a class quest, or a quest that a class quest of the route needs (directly or
-- through other quests; one member of a group is enough to count).
function RT:ClassChain(q)
	if self.classQ[q] then
		return true
	end
	self.chainMemo = self.chainMemo or {}
	local memo = self.chainMemo
	if memo[q] ~= nil then
		return memo[q]
	end
	memo[q] = false -- guards against cycles in the data
	for _, f in ipairs(self.dependents[q] or {}) do
		if self:ClassChain(f) then
			memo[q] = true
			break
		end
	end
	return memo[q]
end

-- Puts a quest of a class chain on the list "later" instead of skipping it; true when it did.
function RT:Defer(q, key)
	if not self:ClassChain(q) or self.world.IsFlagged(q) then
		return false
	end
	self.saved.later[q] = self.saved.later[q] or key or true
	self.saved.roots[q] = nil
	return true
end

-- Every step of a module (a class insert) is skipped now and its quests wait on the list "later".
function RT:DeferModule(module)
	for _, st in ipairs(self.steps) do
		if st.module == module then
			self.saved.marks[st.key] = "s"
			for _, q in ipairs(st.quests) do
				self:Defer(q, st.key)
			end
		end
	end
end

-- Quests on the list "later" that are still to do, with the quests of a class chain that need them,
-- in route order. Quests without a class bond that wait with them are not listed: they open again by
-- themselves once the postponed quest is handed in.
function RT:Later()
	local out, w = {}, self.world
	for q in pairs(self.saved.later) do
		if w.IsFlagged(q) then
			self.saved.later[q] = nil
		end
	end
	local base = self:Spread({ self.saved.roots })
	for q in pairs(self:Spread({ self.saved.roots, self.saved.later })) do
		if not base[q] and self:ClassChain(q) then
			out[#out + 1] = q
		end
	end
	table.sort(out, function(a, b)
		local ia, ib = self.accepts[a] or math.huge, self.accepts[b] or math.huge
		if ia ~= ib then
			return ia < ib
		end
		return a < b
	end)
	return out
end

-- Side trip for the quests on the list "later" (KQ-1105): their steps, and every step of a class insert
-- they belong to, open again and come first; when they are done, the route goes on where it was.
function RT:TakeLater()
	local list = self:Later()
	if #list == 0 or self.saved.side then
		return false
	end
	self:Push("takelater", nil, list[1])
	local want, mods, keys = {}, {}, {}
	for _, q in ipairs(list) do
		want[q] = true
	end
	for _, st in ipairs(self.steps) do
		for _, q in ipairs(st.quests) do
			if want[q] then
				keys[st.key] = true
				local m = self.modules[st.module]
				if m and m.kind == "class" then
					mods[st.module] = true
				end
			end
		end
	end
	for _, st in ipairs(self.steps) do
		if mods[st.module] then
			keys[st.key] = true
		end
		if keys[st.key] and self.saved.marks[st.key] == "s" then
			self.saved.marks[st.key] = nil
		end
	end
	self.saved.side = { back = self.saved.anchor, keys = keys }
	self:Changed("takelater")
	return true
end

-- Side trip into one class insert (ME-1106, level hint "now"): its steps come first, the level rule does
-- not pass them, and when they are done the route goes on at the step it left. Undo takes it back.
function RT:TakeModule(module, quest)
	if self.saved.side then
		return false
	end
	local keys, any = {}, false
	for _, st in ipairs(self.steps) do
		if st.module == module then
			keys[st.key] = true
			any = true
			if self.saved.marks[st.key] == "s" then
				self.saved.marks[st.key] = nil
			end
		end
	end
	if not any then
		return false
	end
	self:Push("takelater", nil, quest)
	self.saved.side = { back = self.saved.anchor, keys = keys }
	self:Changed("takelater")
	return true
end

-- Quests the route leaves out now: skipped by the player, waiting on the list "later" (not during the
-- side trip, RT:TakeLater), and every quest that needs one of them. rootsOnly: the skipped ones only.
function RT:Blocked(rootsOnly)
	local seeds = { self.saved.roots }
	if not rootsOnly and not self.saved.side then
		seeds[2] = self.saved.later
	end
	return self:Spread(seeds)
end

-- The quests of the seed tables (keys) and, transitively, every quest with a prerequisite group of
-- them only; handed-in quests never.
function RT:Spread(seeds)
	local flagged = self.world.IsFlagged
	local blocked, queue = {}, {}
	for _, t in ipairs(seeds) do
		for q in pairs(t) do
			if not blocked[q] and not flagged(q) then
				blocked[q] = true
				queue[#queue + 1] = q
			end
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

-- true/false for elements that decide whether a step is done, nil for the rest (goto, note).
-- A flight (travel fly) is done at the landing; when it leads into another zone, also when the
-- player is in that zone (a /reload in the air misses the landing).
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
		if el[2] == FLY and s.flyFrom ~= nil then
			if self.saved.marks[s.key] == "e" then
				return true
			end
			return s.flyFrom ~= el[3] and InZone(self, el[3], ctx.map)
		end
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

-- Entry anchor (Polestar #86, brain chapter 21 §6.1, Code E): the furthest step from `from` on with a
-- turn-in or with objective progress of one of its quests. A quest that is only in the log does not
-- count, so a carried breadcrumb cannot throw the player ahead. The anchor holds only when at least
-- ANCHOR_SHARE of the route quests from `from` up to it are handed in or in the log; else nil (the
-- route moves on from `from` by the other rules). Accepts before the anchor whose quest is neither
-- done nor in the log go to the list "skipped earlier" (RT:Earlier). Steps before the anchor count
-- as passed, unless a quest of them is in the log.
function RT:Anchor(from, ctx)
	local w = self.world
	local progress = w.Progress or function(q)
		return w.IsComplete(q)
	end
	local anchor
	for j = #self.steps, from + 1, -1 do
		for _, el in ipairs(self.steps[j].els) do
			local v, q = el[1], el[2]
			if QUEST[v] and (w.IsFlagged(q) or (v == V.COMPLETE and w.InLog(q) and progress(q))) then
				anchor = j
				break
			end
		end
		if anchor then
			break
		end
	end
	if not anchor then
		return nil
	end
	local seen, total, ok, skipped = {}, 0, 0, {}
	for j = from, anchor do
		for _, q in ipairs(self.steps[j].quests) do
			if not seen[q] then
				seen[q] = true
				total = total + 1
				if w.IsFlagged(q) or w.InLog(q) then
					ok = ok + 1
				elseif self.accepts[q] and self.accepts[q] < anchor and not ctx.blocked[q] then
					skipped[#skipped + 1] = q
				end
			end
		end
	end
	if ok < total * RT.ANCHOR_SHARE then
		return nil
	end
	local list, have = type(self.saved.earlier) == "table" and self.saved.earlier or {}, {}
	for _, q in ipairs(list) do
		have[q] = true
	end
	for _, q in ipairs(skipped) do
		if not have[q] and #list < RT.EARLIER_MAX then
			list[#list + 1] = q
		end
	end
	self.saved.earlier = #list > 0 and list or nil
	return anchor
end

-- The next evaluation checks the anchor again from the current step (after a level-up: the player
-- may have played without the route meanwhile).
function RT:Recheck()
	self.recheck = true
end

-- Quests the route passed on entry although they were neither done nor in the log, in route order;
-- without those done, taken or skipped since. For the line "N quests skipped earlier".
function RT:Earlier()
	local out, w = {}, self.world
	local list = self.saved.earlier
	if type(list) ~= "table" then
		return out
	end
	local blocked = self:Blocked()
	for _, q in ipairs(list) do
		if not w.IsFlagged(q) and not w.InLog(q) and not blocked[q] then
			out[#out + 1] = q
		end
	end
	return out
end

-- A detour of the route: a travel step of a class insert (R24: class quests in zones the route does
-- not visit, `!return "Klassenquest"`). A return of a core module into a zone left earlier
-- (`!return "<reason>"`, R09) is a zone change like any other. Without module data every return step
-- counts as a detour (the route data before Welle 6b had class returns only).
function RT:Detour(s)
	if not s or not s.ret then
		return false
	end
	local m = self.modules[s.module]
	return not m or m.kind == "class"
end

-- An open step the route may pass without the player: far below the character's level (a travel step
-- into a new zone only on the first start), before the entry anchor (RT:Anchor), or a travel step
-- whose next quest shows progress.
-- A step the player went back to (pin) is never passed by these rules.
function RT:Passed(i, ctx)
	local s = self.steps[i]
	if self.saved.pin == s.key then
		return false
	end
	if ctx.anchor and i < ctx.anchor and not self:HoldsLogQuest(i) then
		return true
	end
	-- A zone change is the player's choice (brain chapter 21 §6.2): during play the level rule never
	-- passes a travel step into a new zone; the switch question there offers a block that fits.
	if
		s.lv
		and s.lv + RT.LEVEL_MARGIN < ctx.level
		and not self:HoldsLogQuest(i)
		and (s.kind ~= "travel" or self:Detour(s) or ctx.fresh)
	then
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
		step = s.view, -- the elements of this race and class only
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
		local from
		if not i then
			ctx.fresh = true
			i, from = 1, 1
		elseif self.recheck and not saved.pin and i <= n then
			from = i
		end
		self.recheck = nil
		local side = type(saved.side) == "table" and saved.side or nil
		if side then
			-- side trip (RT:TakeLater): its first open step in route order; the level rule does not pass
			-- its steps. When none is left, the route goes on at the step it left.
			for k = 1, n do
				if side.keys[self.steps[k].key] and self:StepState(k, ctx) == "open" then
					self.cur = k
					if prev ~= k then
						self.notify("StepChanged", self:Info(k), prev and self:Info(prev) or nil)
					end
					return self:Current()
				end
			end
			saved.side = nil
			i, from = side.back and self.index[side.back] or i, nil
		end
		if from then
			ctx.anchor = self:Anchor(from, ctx)
		end
		while i <= n do
			if self:StepState(i, ctx) == "open" then
				if not self:Passed(i, ctx) then
					break
				end
				-- a class chain the route passes is not lost (KQ-1105): it waits on the list "later"
				for _, q in ipairs(self.steps[i].quests) do
					if not self.world.InLog(q) and not ctx.blocked[q] then
						self:Defer(q, self.steps[i].key)
					end
				end
			end
			i = i + 1
		end
		if saved.pin and self.index[saved.pin] ~= i then
			saved.pin = nil
		end
		if from and (ctx.anchor or (ctx.fresh and i > 1)) then
			self.entered = true -- entry in the middle of the route: reorder the block's rest (Replan.lua)
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
	local side = type(self.saved.side) == "table" and self.saved.side.keys or nil
	while self.steps[i] and #out < (n or 3) do
		if (not side or side[self.steps[i].key]) and self:StepState(i, ctx) == "open" and not self:Passed(i, ctx) then
			out[#out + 1] = self:Info(i)
		end
		i = i + 1
	end
	return out
end

-- Undo -----------------------------------------------------------------------------------------

-- kind names the action for the right-click menu ("undo: ..."): check, skip, back, reaccept, skipquest.
function RT:Push(kind, key, quest)
	local s, u = self.saved, self.saved.undo
	u[#u + 1] = {
		marks = copy(s.marks),
		roots = copy(s.roots),
		later = copy(s.later),
		side = s.side and { back = s.side.back, keys = copy(s.side.keys) } or nil,
		anchor = s.anchor,
		pin = s.pin,
		pending = s.pending,
		orders = type(s.orders) == "table" and copy(s.orders) or nil, -- block orders (Replan.lua)
		act = kind and { kind = kind, key = key, quest = quest } or nil,
	}
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
	s.later = type(snap.later) == "table" and copy(snap.later) or {}
	s.side = snap.side
	s.anchor, s.pin, s.pending = snap.anchor, snap.pin, snap.pending
	if self.SetOrders then
		-- a reorder that followed the action goes back with it (Routes/Replan.lua)
		self:SetOrders(type(snap.orders) == "table" and copy(snap.orders) or nil)
	end
	self:Changed("undo")
	return true
end

-- The action the next Undo takes back: { kind, key, quest }, { kind = "unknown" } for undo entries
-- saved before actions were named, nil when there is nothing to undo.
function RT:LastAction()
	local u = self.saved.undo
	local snap = u[#u]
	if not snap then
		return nil
	end
	local act = snap.act
	return act and copy(act) or { kind = "unknown" }
end

function RT:Changed(reason)
	if self.Replan then
		self:Replan(reason) -- Routes/Replan.lua: a skip or abandon reorders the rest of the block
	end
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
	self:Push("check", key, self.steps[self.index[key]].quests[1])
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
	self:Push("skip", key, self.steps[self.index[key]].quests[1])
	local s = self.saved
	s.marks[key] = "s"
	if self:Detour(self.steps[self.index[key]]) then
		-- the travel step of a class insert: the whole insert waits on the list "later" (KQ-1105)
		self:DeferModule(self.steps[self.index[key]].module)
	end
	for _, q in ipairs(self.steps[self.index[key]].quests) do
		if not s.roots[q] and not self.world.IsFlagged(q) and not self:Defer(q, key) then
			s.roots[q] = key
		end
	end
	self:Changed("skip")
	return true
end

-- Not offered (owner 2026-11-05, first game test): the giver of an accept in the current part of the
-- route listed its quests and this one was not among them. The open data can be wrong about a
-- prerequisite or a level, and a step the game does not offer must not hold the route. The quest is set
-- aside like a skip (its follow-up quests with it) and comes back as soon as an NPC offers it (Offered)
-- or the player takes it (OnAccepted). Undo and Back work as for a skip.
-- Only when the game should offer it by the route's own data: every prerequisite group has a quest
-- handed in, and no turn-in before it in its step is still open (a chain at the same NPC lists the
-- next quest only after the hand-in, so its absence before that says nothing).
function RT:Expected(q)
	local w = self.world
	for _, group in ipairs(self:Groups(q)) do
		local any = #group == 0
		for _, m in ipairs(group) do
			if w.IsFlagged(m) then
				any = true
				break
			end
		end
		if not any then
			return false
		end
	end
	local i = self.accepts[q]
	for _, el in ipairs(i and self.steps[i].els or NONE) do
		if el[1] == V.ACCEPT and el[2] == q then
			break
		end
		if el[1] == V.TURNIN and not w.IsFlagged(el[2]) then
			return false
		end
	end
	return true
end

function RT:NotOffered(q)
	local s, w = self.saved, self.world
	local i = self.accepts[q]
	if not i or s.roots[q] or w.IsFlagged(q) or w.InLog(q) or not self:Expected(q) then
		return false
	end
	self:Push("notoffered", self.steps[i].key, q)
	s.roots[q] = self.steps[i].key
	s.deferred = type(s.deferred) == "table" and s.deferred or {}
	s.deferred[q] = true
	self:Changed("notoffered")
	self.notify("NotOffered", q) -- after the step change, which clears the window's message
	return true
end

-- An NPC offers a quest the route set aside as not offered: it is back in the route.
function RT:Offered(q)
	local s = self.saved
	if not (type(s.deferred) == "table" and s.deferred[q]) then
		return false
	end
	s.deferred[q] = nil
	if s.roots[q] then
		s.roots[q] = nil
		-- The player stands at the NPC that offers it now: its step is the current one again.
		local i = self.accepts[q]
		if i and self.cur and i < self.cur then
			s.anchor = self.steps[i].key
		end
		self:Changed("offered")
	end
	return true
end

-- Quests that skipping the given quests would take with them (not the quests themselves), sorted.
-- Changes nothing: the roots are added for the computation and removed again.
function RT:FollowUps(list)
	local s, flagged = self.saved, self.world.IsFlagged
	local before = self:Blocked()
	local added, own = {}, {}
	for _, q in ipairs(list) do
		own[q] = true
		if not s.roots[q] and not flagged(q) then
			s.roots[q] = "_preview"
			added[#added + 1] = q
		end
	end
	local after = self:Blocked()
	for _, q in ipairs(added) do
		s.roots[q] = nil
	end
	local out = {}
	for q in pairs(after) do
		if not before[q] and not own[q] then
			out[#out + 1] = q
		end
	end
	table.sort(out)
	return out
end

-- Follow-up quests a Skip(key) would take with it (default: current step); nil for an unknown key.
function RT:SkipPreview(key)
	key = Key(self, key)
	if not key then
		return nil
	end
	return self:FollowUps(self.steps[self.index[key]].quests)
end

-- Whether skipping postpones instead (KQ-1105): the step (default: current) or, while an abandon
-- question waits, its quest belongs to a class chain that is not handed in.
function RT:Postpones(key)
	local q = self.saved.pending
	if q and key == nil then
		return self:ClassChain(q) and not self.world.IsFlagged(q)
	end
	key = Key(self, key)
	if not key then
		return false
	end
	for _, x in ipairs(self.steps[self.index[key]].quests) do
		if self:ClassChain(x) and not self.world.IsFlagged(x) then
			return true
		end
	end
	return self:Detour(self.steps[self.index[key]])
end

-- Follow-up quests of the quest an open abandon question is about; nil without a question.
function RT:AbandonPreview()
	local q = self.saved.pending
	if not q then
		return nil
	end
	return self:FollowUps({ q })
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
				self:Push("back", step.key, step.quests[1])
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

-- Event seen in the game (flight path learned or flight map opened, hearthstone set or used, trainer
-- window opened, landing after a flight): marks the first open step among the current and the next
-- LOOKAHEAD steps that has this element; `how` narrows travel elements to one way of travel.
function RT:MarkEvent(verb, how)
	local cur = self.cur
	if not cur then
		return false
	end
	for i = cur, math.min(cur + RT.LOOKAHEAD, #self.steps) do
		local s = self.steps[i]
		for _, el in ipairs(s.els) do
			if el[1] == verb and (how == nil or el[2] == how) and self.saved.marks[s.key] == nil then
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
	if self:Offered(q) then
		return true
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
	local key = self.steps[self.accepts[q]].key
	self:Push(choice == "skip" and "skipquest" or "reaccept", key, q)
	s.pending = nil
	if choice == "skip" then
		if not self:Defer(q, key) then
			s.roots[q] = key
		end
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
		if s.kind == "travel" and not self:Detour(s) and st ~= "skipped" then
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
	-- stepsLeft: steps from the current one to the zone end; the step window names a shortfall only
	-- near the end (owner 2026-11-05: at level 1 the line counted the whole start zone as grinding).
	local zone = {
		endIndex = j - 1,
		stepsLeft = j - i,
		nextMap = self.steps[j].travel,
		nextLevel = nextLevel,
		routeXP = routeXP,
	}
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
