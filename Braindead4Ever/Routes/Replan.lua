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

-- Routes/Replan.lua: replanning in the client (Welle 7, owner guideline 7, brain chapter 21 §6.2). Adds
-- methods to the route runtime (Runtime.lua); pure Lua like the runtime. Interface and rules:
-- docs/ROUTE-RUNTIME.md §Replanning.
-- * Over the plan: three levels or more above the planned level of the current step, the route asks
--   once per block whether to leave out the quests of the rest of the block whose turn-in would give
--   less than 80 % XP (R01); chains that lead to a quest with good XP stay.
-- * Switch point: at a travel step into a new zone the route offers a block that fits the character's
--   level better (a later block or an alternative module built offline), never in the middle of a
--   block; a zone change is always the player's choice.
-- * Reorder in the block (stage 1): below.
-- Every threshold is a chosen value, to be measured (brain chapter 21 §6).
local _, ns = ...
local RT, XP, R = ns.Runtime, ns.XP, ns.Routes
local V = R.VERB

RT.OVER_LEVEL = 3 -- chosen value: levels above the plan that open the question
RT.DROP_SHARE = 0.8 -- R01: a turn-in under this share of the full XP is left out on "adjust"

-- Block of step i: from the travel step that starts it (or the first step) to the step before the next
-- travel step.
function RT:Block(i)
	local first, last, n = i, i, #self.steps
	while first > 1 and self.steps[first].kind ~= "travel" do
		first = first - 1
	end
	while last < n and self.steps[last + 1].kind ~= "travel" do
		last = last + 1
	end
	return first, last
end

-- Planned level of the block that starts at step i: the first quest step's level, else the step's own.
function RT:BlockPlan(i)
	local _, last = self:Block(i)
	for j = i, last do
		local s = self.steps[j]
		if s.kind == "quest" and s.lv then
			return s.lv
		end
	end
	return self.steps[i] and self.steps[i].lv
end

-- Share of the full quest XP at the character's level (Classic reduction, XP.QuestXP); 1 when the
-- quest level is unknown.
local function Share(info, level)
	local ql = info and info[1]
	if not ql or ql <= 0 then
		return 1
	end
	return XP.QuestXP(1000, ql, level) / 1000
end

-- Quests of steps i..last that "adjust" leaves out: not taken yet, turn-in under DROP_SHARE at the
-- character's level; a quest stays when leaving it out would cut a chain to a quest that is not left
-- out. Sorted by the step that accepts them.
function RT:DropSet(i, last, ctx)
	local w, s = self.world, self.saved
	local cand, any = {}, false
	for j = i, last do
		for _, el in ipairs(self.steps[j].els) do
			local q = el[1] == V.TURNIN and el[2]
			if
				q
				and not ctx.blocked[q]
				and not w.IsFlagged(q)
				and not w.InLog(q)
				and (self.accepts[q] or 0) >= i
				and not self:ClassChain(q) -- class chains stay (KQ-1105)
				and Share(self.quests[q], ctx.level) < RT.DROP_SHARE
			then
				cand[q], any = true, true
			end
		end
	end
	if not any then
		return {}
	end
	local changed = true
	while changed do
		changed = false
		for q in pairs(cand) do
			s.roots[q] = "_drop"
		end
		local after = self:Blocked()
		for q in pairs(cand) do
			s.roots[q] = nil
		end
		for f in pairs(after) do
			if not cand[f] and not ctx.blocked[f] then
				for _, group in ipairs(self:Groups(f)) do
					local dead = #group > 0
					for _, m in ipairs(group) do
						if not after[m] then
							dead = false
							break
						end
					end
					if dead then
						for _, m in ipairs(group) do
							if cand[m] then
								cand[m], changed = nil, true
							end
						end
					end
				end
			end
		end
	end
	local out = {}
	for q in pairs(cand) do
		out[#out + 1] = q
	end
	table.sort(out, function(a, b)
		local ia, ib = self.accepts[a], self.accepts[b]
		if ia ~= ib then
			return ia < ib
		end
		return a < b
	end)
	return out
end

-- The question "N levels above the plan, adjust the route?" for the current step, or nil.
function RT:OverPlan(ctx)
	local i = self.cur
	local s = i and self.steps[i]
	if not s or s.kind ~= "quest" or not s.lv then
		return nil
	end
	local gap = ctx.level - s.lv
	if gap < RT.OVER_LEVEL then
		return nil
	end
	local first, last = self:Block(i)
	local id = "over:" .. self.steps[first].key
	if self.saved.offers and self.saved.offers[id] then
		return nil
	end
	local drop = self:DropSet(i, last, ctx)
	if #drop == 0 then
		return nil
	end
	return { kind = "over", id = id, key = s.key, gap = gap, plan = s.lv, level = ctx.level, drop = drop }
end

-- First travel step after i into a block that fits the level (less than OVER_LEVEL above its plan).
-- The search stops at a class detour (R24: class quests stay in the route).
function RT:FittingBlock(i, level)
	for t = i + 1, #self.steps do
		local s = self.steps[t]
		if s.kind == "travel" then
			if self:Detour(s) then
				return nil
			end
			local plan = self:BlockPlan(t)
			if plan and level - plan < RT.OVER_LEVEL then
				return t, plan
			end
		end
	end
	return nil
end

-- Switch point (stage 2): at a travel step into a new zone, the options that fit the level better than
-- the next block. jump: a later block of the route (the blocks in between are skipped); module: an
-- alternative module built offline (RT:Alternatives, Welle 6b). Returns the question or nil.
function RT:Switch(ctx)
	local i = self.cur
	local s = i and self.steps[i]
	if not s or s.kind ~= "travel" or self:Detour(s) then
		return nil
	end
	local id = "switch:" .. s.key
	if self.saved.offers and self.saved.offers[id] then
		return nil
	end
	local plan = self:BlockPlan(i)
	if not plan then
		return nil
	end
	local level = ctx.level
	local best = { kind = "stay", plan = plan, dev = math.abs(level - plan) }
	if best.dev < RT.OVER_LEVEL then
		return nil -- the next block fits well enough: no question (OVER_LEVEL above or below its plan)
	end
	local options = { best }
	if level - plan >= RT.OVER_LEVEL then
		local t, tplan = self:FittingBlock(i, level)
		if t then
			options[#options + 1] = {
				kind = "jump",
				to = self.steps[t].key,
				map = self.steps[t].travel,
				plan = tplan,
				dev = math.abs(level - tplan),
			}
		end
	end
	for _, alt in ipairs(self:Alternatives(s.module)) do
		options[#options + 1] = {
			kind = "module",
			module = alt.key,
			map = alt.map,
			plan = alt.plan,
			dev = math.abs(level - alt.plan),
			gain = alt.gain,
		}
	end
	-- the option nearest to the character's level; on a tie the one with the larger time gain (a jump
	-- has none, so an alternative module that keeps the zones wins)
	for k = 2, #options do
		local o = options[k]
		if o.dev < best.dev or (o.dev == best.dev and best.kind ~= "stay" and (o.gain or 0) > (best.gain or 0)) then
			best = o
		end
	end
	if best.kind == "stay" then
		return nil
	end
	return {
		kind = "switch",
		id = id,
		key = s.key,
		level = level,
		plan = plan,
		map = s.travel,
		choice = best,
		options = options,
	}
end

-- Alternative modules for the module that starts at a switch point: built offline (Welle 6b), compiled
-- as data.alts = { [module key] = { { key, plan, map, gain }, ... } } (docs/ROUTE-FORMAT.md). Only those
-- whose module the data holds and that apply to the character's race and class; {} without any.
function RT:Alternatives(module)
	local out = {}
	local list = type(self.alts) == "table" and self.alts[module]
	if type(list) ~= "table" then
		return out
	end
	for _, alt in ipairs(list) do
		local m = type(alt) == "table" and alt.key and self.modules[alt.key]
		if m and type(alt.plan) == "number" and (not self.race or R.Applies(m, self.race, self.class)) then
			out[#out + 1] = alt
		end
	end
	return out
end

-- Class quests (owner 2026-11-05, KQ-1105). At the travel step of a class insert the route announces the
-- detour and asks "now or later"; later puts the insert on the list "later" (Runtime.lua). At every
-- later travel step into a new zone, while the list holds quests, it asks whether to play them now as a
-- side trip (RT:TakeLater); no keeps them on the list for the next zone change.
function RT:ClassOffer()
	local s = self.steps[self.cur]
	if not s or s.kind ~= "travel" or not self:Detour(s) or self.saved.side then
		return nil
	end
	local id = "class:" .. s.key
	if self.saved.offers and self.saved.offers[id] then
		return nil
	end
	local quests = {}
	for _, st in ipairs(self.steps) do
		if st.module == s.module then
			for _, q in ipairs(st.quests) do
				if not self.world.IsFlagged(q) then
					quests[#quests + 1] = q
				end
			end
		end
	end
	if #quests == 0 then
		return nil
	end
	return { kind = "class", id = id, key = s.key, map = s.travel, quests = quests }
end

-- Level hint (owner 2026-11-06, ME-1106): once the character has the level of the first quest of a class
-- insert (module field ready), the route says so wherever it stands and asks "now or later". Now plays
-- the insert as a side trip at once (RT:TakeModule) and the route goes on where it was; later leaves it
-- at its planned place, where the travel step asks again (ClassOffer). Not for an insert whose travel
-- step is current or due within RT.LOOKAHEAD steps (ClassOffer comes there), not during a side trip,
-- and not when its first quest is handed in, in the log, skipped or on the list "later".
function RT:ReadyOffer(ctx)
	if self.saved.side or not self.cur then
		return nil
	end
	local level = ctx and ctx.level or (self.world.Level() or 1)
	local offers = type(self.saved.offers) == "table" and self.saved.offers or {}
	local blocked = ctx and ctx.blocked or self:Blocked()
	local seen = {}
	for i = self.cur, #self.steps do
		local s = self.steps[i]
		if not seen[s.module] then
			seen[s.module] = true
			local m = self.modules[s.module]
			local id = "ready:" .. s.module
			if
				m
				and m.kind == "class"
				and type(m.ready) == "number"
				and level >= m.ready
				and self:Detour(s)
				and i > self.cur + RT.LOOKAHEAD
				and not offers[id]
				and not offers["class:" .. s.key]
				and self.saved.marks[s.key] ~= "s"
			then
				local first
				for k = i + 1, #self.steps do
					local t = self.steps[k]
					if t.module ~= s.module then
						break
					end
					for _, el in ipairs(t.els) do
						if el[1] == V.ACCEPT then
							first = el[2]
							break
						end
					end
					if first then
						break
					end
				end
				local w = self.world
				if
					first
					and not w.IsFlagged(first)
					and not w.InLog(first)
					and not blocked[first]
					and not self.saved.later[first]
				then
					return {
						kind = "ready",
						id = id,
						key = s.key,
						module = s.module,
						map = s.travel,
						quest = first,
						level = m.ready,
						plan = s.lv,
					}
				end
			end
		end
	end
	return nil
end

-- Optional quests (owner 2026-11-10: Camping 101 "als Hinweis ... deutlich wegklickbar", in both modes).
-- When the current step accepts a quest of a module's optional list that is neither handed in, in the
-- log nor left out, the route asks once per module and kind "fit them in now or do them on your own".
-- Yes keeps the steps; no leaves the open quests of the list out with their follow-up quests (undo
-- takes it back). Until the answer the optional automation does not take them (RT:OptPending).
function RT:OptOffer(ctx)
	local s = self.steps[self.cur]
	if not s or s.kind ~= "quest" or self.saved.side then
		return nil
	end
	local offers = type(self.saved.offers) == "table" and self.saved.offers or {}
	local blocked = ctx and ctx.blocked or self:Blocked()
	local w = self.world
	local id
	for _, el in ipairs(s.els) do
		local q = el[2]
		local qid = el[1] == V.ACCEPT and self.optQ[q]
		if qid and not offers[qid] and not w.IsFlagged(q) and not w.InLog(q) and not blocked[q] then
			id = qid
			break
		end
	end
	if not id then
		return nil
	end
	local quests = {}
	for q, qid in pairs(self.optQ) do
		if qid == id and not w.IsFlagged(q) and not blocked[q] then
			quests[#quests + 1] = q
		end
	end
	table.sort(quests)
	return { kind = "opt", id = id, key = s.key, quests = quests }
end

-- An optional quest whose question is not answered yes (asked or not yet asked); answered no it is left
-- out anyway (RT:Blocked).
function RT:OptPending(q)
	local id = self.optQ and self.optQ[q]
	if not id then
		return false
	end
	local offers = type(self.saved.offers) == "table" and self.saved.offers or {}
	return offers[id] ~= "y"
end

function RT:LaterOffer()
	local s = self.steps[self.cur]
	if not s or s.kind ~= "travel" or self:Detour(s) or self.saved.side then
		return nil
	end
	local id = "later:" .. s.key
	if self.saved.offers and self.saved.offers[id] then
		return nil
	end
	local list = self:Later()
	if #list == 0 then
		return nil
	end
	local n = 0 -- class quests among them, for the question's text
	for _, q in ipairs(list) do
		if self.classQ[q] then
			n = n + 1
		end
	end
	return { kind = "later", id = id, key = s.key, quests = list, classes = math.max(n, 1) }
end

-- The open question of the current step: the class detour, a switch point, the list "later", the
-- level hint of a class insert (ME-1106), optional quests, then "over the plan"; nil when none. Nothing is asked while
-- an abandon question waits.
function RT:Offer(ctx)
	if self.saved.pending or not self.cur or not self.steps[self.cur] then
		return nil
	end
	ctx = ctx or self:Context()
	-- a switch point first: it decides where the route goes next; the list "later" asks after it at
	-- the same travel step (or at the new block's), the level hint after both
	return self:ClassOffer()
		or self:Switch(ctx)
		or self:LaterOffer()
		or self:ReadyOffer(ctx)
		or self:OptOffer(ctx)
		or self:OverPlan(ctx)
end

-- Answer to the open question with this id: yes = true takes it. Returns true when answered, or
-- "rebuild" and the module key when the route must be put together again with an alternative module
-- (saved.alts maps the replaced module to it).
function RT:AnswerOffer(id, yes)
	local o = self:Offer()
	if not o or o.id ~= id then
		return false
	end
	local s = self.saved
	s.offers = type(s.offers) == "table" and s.offers or {}
	if o.kind == "class" then
		-- yes: now (the route goes on as planned); no: later, the insert waits on the list "later"
		if yes then
			s.offers[id] = "y"
			return true
		end
		self:Push("later", o.key, o.quests[1])
		s.offers[id] = "n"
		self:DeferModule(self.steps[self.cur].module)
		self:Changed("later")
		return true
	end
	if o.kind == "ready" then
		-- yes: the insert now as a side trip, its travel step asks no more; no: it stays where planned
		s.offers[id] = yes and "y" or "n"
		if yes then
			s.offers["class:" .. o.key] = "y"
			self:TakeModule(o.module, o.quest)
		end
		return true
	end
	if o.kind == "opt" then
		-- yes: the steps stay; no: the open quests of the list leave the route with their follow-ups
		if yes then
			s.offers[id] = "y"
			return true
		end
		self:Push("optional", o.key)
		s.offers[id] = "n"
		for _, q in ipairs(o.quests) do
			local a = self.accepts[q]
			s.roots[q] = a and self.steps[a].key or o.key
		end
		self:Changed("skip")
		return true
	end
	if o.kind == "later" then
		s.offers[id] = yes and "y" or "n"
		if yes then
			self:TakeLater()
		end
		return true
	end
	if not yes then
		s.offers[id] = "n"
		return true
	end
	if o.kind == "over" then
		self:Push("adjust", o.key)
		s.offers[id] = "y"
		for _, q in ipairs(o.drop) do
			s.roots[q] = self.steps[self.accepts[q]].key
		end
		self:Changed("adjust")
		return true
	end
	local c = o.choice
	s.offers[id] = "y"
	if c.kind == "module" then
		-- the caller puts the route together again with the alternative module and starts there; a
		-- switch of modules cannot be undone, and the undo list starts empty (its steps may be gone)
		s.alts = type(s.alts) == "table" and s.alts or {}
		s.alts[self.steps[self.cur].module] = c.module
		s.undo = {}
		return "rebuild", c.module
	end
	self:Push("switch", o.key)
	local to = self.index[c.to]
	for k = self.cur, to - 1 do
		local step = self.steps[k]
		s.marks[step.key] = "s"
		for _, q in ipairs(step.quests) do
			if
				not s.roots[q]
				and not self.world.IsFlagged(q)
				and not self.world.InLog(q)
				and not self:Defer(q, step.key) -- a class chain waits on the list "later" (KQ-1105)
			then
				s.roots[q] = step.key
			end
		end
	end
	s.anchor = c.to
	self:Changed("switch")
	return true
end

-- Stage 1: reorder the rest of the block -----------------------------------------------------------
-- After a skip, an abandoned quest skipped, "adjust" or an entry in the middle of a block, the open
-- steps of the current block are ordered again from the player's position: nearest neighbour with
-- precedence (accept, objectives, turn-in of a quest in this order; a prerequisite's turn-in before the
-- follow-up's accept), then 2-opt over valid moves only, with the quest log limit. As a coroutine with
-- REORDER_BUDGET per frame and never in a fight (brain chapter 21 §6.2, Code E/G; chapter 12 §7).
-- A new order is kept only when it is clearly shorter (REORDER_GAIN), so nothing jumps for nothing.
-- Done, skipped and passed steps of the range move along without a way to walk (free acts), so the
-- precedence holds when one of them opens again.

RT.REORDER_BUDGET = 0.002 -- seconds per frame outside a fight (chapter 21 §6.2)
RT.REORDER_GAIN = 0.05 -- chosen value: a new order must be at least 5 % shorter
RT.LOG_CAP = 20 -- planning limit of the quest log (R30, chosen value); the plan's own peak is allowed
RT.REORDER_MIN = 3 -- fewer open steps than this: nothing to reorder
RT.REORDER_MAX = 80 -- chosen value: only the next 80 open steps of the segment move (measured time: spec)
RT.REORDER_ON = { skip = true, skipquest = true, adjust = true, entry = true }

-- Elements a step may hold and still move inside its block. Any other element (travel, collect,
-- hearthstone, flight path, trainer, level) keeps the step in place; so do new kinds of steps.
local MOVABLE = { [V.ACCEPT] = true, [V.COMPLETE] = true, [V.TURNIN] = true, [V.GOTO] = true, [V.NOTE] = true }

local function Movable(s)
	if s.kind ~= "quest" then
		return false
	end
	local gotos = 0
	for _, el in ipairs(s.els) do
		if not MOVABLE[el[1]] then
			return false
		end
		if el[1] == V.GOTO then
			gotos = gotos + 1
		end
	end
	return gotos <= 1
end

local function Goto(s)
	for _, el in ipairs(s.els) do
		if el[1] == V.GOTO then
			return el
		end
	end
end

-- Segments: runs of movable steps of one module on one continent, from the plan order. Their place in
-- the route never changes, only the order inside.
function RT:InitReplan(opts)
	opts = opts or {}
	self.maps = opts.maps
	self.alts = opts.alts -- compiled data.alts (docs/ROUTE-FORMAT.md), RT:Alternatives
	self.race, self.class = opts.race, opts.class
	self.segs, self.segAt = {}, {}
	self.plan = {} -- the steps in plan order; saved orders are applied on top of it
	for i, s in ipairs(self.steps) do
		self.plan[i] = s
	end
	local seg, lastWorld
	for i, s in ipairs(self.steps) do
		local g = Goto(s)
		local world = g and (self.maps and self.maps[g[2]] or g[2])
		if
			Movable(s)
			and seg
			and self.steps[seg.last].module == s.module
			and (world == nil or lastWorld == nil or world == lastWorld)
		then
			seg.last = i
		elseif Movable(s) then
			seg = { first = i, last = i, id = s.key }
			self.segs[#self.segs + 1] = seg
			lastWorld = nil
		else
			seg = nil
		end
		if seg then
			self.segAt[i] = seg
			lastWorld = world or lastWorld
		end
	end
	self:LoadOrders()
end

-- Rebuilds the step index and the accept index after a change of order.
function RT:ReindexSteps(from, to)
	for i = from, to do
		self.index[self.steps[i].key] = i
	end
	local accepts = {}
	for i, s in ipairs(self.steps) do
		for _, el in ipairs(s.els) do
			if el[1] == V.ACCEPT and not accepts[el[2]] then
				accepts[el[2]] = i
			end
		end
	end
	self.accepts = accepts
end

-- Saved orders (saved.orders[segment id] = "id,id,..."): applied when they still name exactly the
-- segment's steps, else dropped (the route data changed).
function RT:LoadOrders()
	local orders = self.saved.orders
	if type(orders) ~= "table" then
		self.saved.orders = nil
		return
	end
	local any = false
	for _, seg in ipairs(self.segs) do
		local list = orders[seg.id]
		if type(list) == "string" then
			local byId, out = {}, {}
			for i = seg.first, seg.last do
				byId[self.steps[i].id] = self.steps[i]
			end
			for id in list:gmatch("[^,]+") do
				out[#out + 1] = byId[id]
				byId[id] = nil
			end
			if #out == seg.last - seg.first + 1 and next(byId) == nil then
				for k, s in ipairs(out) do
					self.steps[seg.first + k - 1] = s
				end
				any = true
			else
				orders[seg.id] = nil
			end
		end
	end
	if any then
		self:ReindexSteps(1, #self.steps)
	end
	if next(orders) == nil then
		self.saved.orders = nil
	end
end

-- Replaces the saved orders (undo, Runtime.lua): the steps go back to plan order, then the given orders
-- are applied. Nothing happens when they are the same.
function RT:SetOrders(orders)
	local cur = self.saved.orders
	local same = (cur == nil) == (orders == nil)
	if same and orders then
		for k, v in pairs(orders) do
			if cur[k] ~= v then
				same = false
			end
		end
		for k in pairs(cur) do
			if orders[k] == nil then
				same = false
			end
		end
	end
	if same then
		return
	end
	for i, s in ipairs(self.plan) do
		self.steps[i] = s
	end
	self.saved.orders = orders
	self:LoadOrders()
	self:ReindexSteps(1, #self.steps)
end

-- Hook of RT:Changed: every change of the route makes a running job stale; some reasons ask for one.
function RT:Replan(reason)
	self.gen = (self.gen or 0) + 1
	if RT.REORDER_ON[reason] then
		self.want = reason
	end
end

-- Work waits: an entry, a reason from RT:Changed, or a job in progress.
function RT:Busy()
	return self.job ~= nil or self.want ~= nil or self.entered ~= nil
end

local function Dist(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end

-- The point of a step: its goto; without one, the middle of the other steps of its quests in the
-- range (objectives without a known place, chosen estimate). Free acts (free[a]: done, skipped or
-- passed steps) need no point. nil when an open step has none.
local function Points(self, slots, free)
	local pts, byQuest = {}, {}
	for a, j in ipairs(slots) do
		local g = Goto(self.steps[j])
		if g then
			pts[a] = { x = g[3], y = g[4], map = g[2] }
			for _, q in ipairs(self.steps[j].quests) do
				local list = byQuest[q] or {}
				byQuest[q] = list
				list[#list + 1] = pts[a]
			end
		end
	end
	for a, j in ipairs(slots) do
		if free[a] then
			pts[a] = nil
		elseif not pts[a] then
			local sx, sy, n = 0, 0, 0
			for _, q in ipairs(self.steps[j].quests) do
				for _, p in ipairs(byQuest[q] or {}) do
					sx, sy, n = sx + p.x, sy + p.y, n + 1
				end
			end
			if n == 0 then
				return nil
			end
			pts[a] = { x = sx / n, y = sy / n }
		end
	end
	return pts
end

-- Builds the reorder job for the current step, or nil when there is nothing to do.
function RT:NewReorder(reason, now, budget)
	local s, w = self.saved, self.world
	local i = self.cur
	local seg = i and self.segAt and self.segAt[i]
	if s.pin or s.pending or not seg then
		return nil
	end
	local px, py, inst
	if w.Position then
		px, py, inst = w.Position()
	end
	if not (px and py) then
		return nil
	end
	local ctx = self:Context()
	-- The range: every step from the current one on, up to the REORDER_MAX-th open step. Steps that are
	-- done, skipped or passed move too, as free acts (no point, no way to walk): they keep the precedence
	-- with the open steps, so a step reopened later (Back, undo of a mark, a quest abandoned and taken
	-- again) never stands behind a step that needs it.
	local slots, free, opened = {}, {}, 0
	for j = i, seg.last do
		slots[#slots + 1] = j
		if self:StepState(j, ctx) == "open" and not self:Passed(j, ctx) then
			opened = opened + 1
			if opened == RT.REORDER_MAX then
				break
			end
		else
			free[#slots] = true
		end
	end
	if opened < RT.REORDER_MIN then
		return nil
	end
	local pts = Points(self, slots, free)
	if not pts then
		return nil
	end
	local g = pts[1] and pts[1].map and self.maps and inst and self.maps[pts[1].map]
	if g and g ~= inst then
		return nil -- the player is on another continent
	end
	-- precedence and quest log change per step
	local n = #slots
	local preds, delta, last, turnin = {}, {}, {}, {}
	for a = 1, n do
		local step = self.steps[slots[a]]
		local p, d = {}, 0
		-- the builder's level gate: a step planned above the character's level stays behind every step
		-- planned lower (its quest may not be offered yet)
		if step.lv and step.lv > ctx.level then
			for b = a - 1, 1, -1 do
				local lv = self.steps[slots[b]].lv
				if lv and lv < step.lv then
					p[b] = true
					break
				end
			end
		end
		for _, q in ipairs(step.quests) do
			if last[q] then
				p[last[q]] = true
			end
		end
		for _, el in ipairs(step.els) do
			local v, q = el[1], el[2]
			if v == V.ACCEPT then
				for _, group in ipairs(self:Groups(q)) do
					for _, m in ipairs(group) do
						if turnin[m] then
							p[turnin[m]] = true
						end
					end
				end
				if not free[a] and not w.InLog(q) and not w.IsFlagged(q) then
					d = d + 1
				end
			elseif v == V.TURNIN and not free[a] then
				d = d - 1
			end
		end
		for _, q in ipairs(step.quests) do
			last[q] = a
		end
		for _, el in ipairs(step.els) do
			if el[1] == V.TURNIN then
				turnin[el[2]] = a
			end
		end
		local list = {}
		for k in pairs(p) do
			list[#list + 1] = k
		end
		preds[a], delta[a] = list, d
	end
	local open = 0
	for q in pairs(self.routeQuests) do
		if w.InLog(q) then
			open = open + 1
		end
	end
	local job = { gen = self.gen, seg = seg, slots = slots, reason = reason, t0 = now() }
	local start = { x = px, y = py }
	job.co = coroutine.create(function()
		local function check()
			if now() - job.t0 > budget then
				coroutine.yield()
			end
		end
		return RT.Order(pts, preds, delta, open, start, check)
	end)
	return job
end

-- Peak of open quests along an order (k: position after which a reversal i..k is read, optional).
local function Peak(order, delta, open, i, k)
	local peak, cur = open, open
	for m = 1, #order do
		local a = (i and m >= i and m <= k) and order[i + k - m] or order[m]
		cur = cur + delta[a]
		if cur > peak then
			peak = cur
		end
	end
	return peak
end

-- The ordering itself (pure, also used by the timing test): nearest neighbour with precedence, then
-- 2-opt over valid reversals. pts[a] = { x, y }, nil for a free act (no point, no way to walk);
-- preds[a] = list of acts that must come before a; delta[a] = change of open quests; open = quests in
-- the log at the start; start = { x, y }; check() yields when the frame budget is used. Returns order
-- (list of acts) and its length, and the length of the given order 1..n.
function RT.Order(pts, preds, delta, open, start, check)
	local n = #preds
	local identity = {}
	for a = 1, n do
		identity[a] = a
	end
	local function Length(order)
		local cur, sum = start, 0
		for m = 1, n do
			local p = pts[order[m]]
			if p then
				sum = sum + Dist(cur, p)
				cur = p
			end
		end
		return sum
	end
	local cap = math.max(RT.LOG_CAP, Peak(identity, delta, open))
	-- nearest neighbour: only acts whose predecessors are placed; a free act goes as soon as it can
	local placed, order, cur = {}, {}, start
	for _ = 1, n do
		local best, bd
		for a = 1, n do
			if not placed[a] then
				local ready = true
				for _, p in ipairs(preds[a]) do
					if not placed[p] then
						ready = false
						break
					end
				end
				if ready then
					if not pts[a] then
						best = a
						break
					end
					local d = Dist(cur, pts[a])
					if not bd or d < bd then
						best, bd = a, d
					end
				end
			end
		end
		placed[best] = true
		order[#order + 1] = best
		cur = pts[best] or cur
		check()
	end
	if Peak(order, delta, open) > cap then
		order = { unpack(identity) }
	end
	-- 2-opt: reverse order[i..k] when it shortens the path and no precedence lies inside the reversed
	-- part. Free acts cost nothing: the change is read between the points next to the reversed part.
	local pos, prevP, nextP = {}, {}, {}
	local function Scan()
		local last = 0
		for m = 1, n do
			pos[order[m]] = m
			if pts[order[m]] then
				last = m
			end
			prevP[m] = last -- last position with a point at or before m (0: the start)
		end
		prevP[0] = 0
		local nxt = n + 1
		for m = n, 1, -1 do
			if pts[order[m]] then
				nxt = m
			end
			nextP[m] = nxt -- first position with a point at or after m (n + 1: none)
		end
		nextP[n + 1] = n + 1
	end
	local function At(m)
		return m == 0 and start or pts[order[m]]
	end
	Scan()
	local improved = true
	while improved do
		improved = false
		for i = 1, n - 1 do
			for k = i + 1, n do
				local fi, lk = nextP[i], prevP[k] -- first and last point inside i..k
				if fi < lk then
					local before, after = At(prevP[i - 1]), nextP[k + 1]
					local d = Dist(before, At(lk)) - Dist(before, At(fi))
					if after <= n then
						d = d + Dist(At(fi), At(after)) - Dist(At(lk), At(after))
					end
					if d < -1e-6 then
						local ok = true
						for m = i, k do
							for _, p in ipairs(preds[order[m]]) do
								if pos[p] >= i and pos[p] <= k then
									ok = false
									break
								end
							end
							if not ok then
								break
							end
						end
						if ok and Peak(order, delta, open, i, k) <= cap then
							local a, b = i, k
							while a < b do
								order[a], order[b] = order[b], order[a]
								a, b = a + 1, b - 1
							end
							Scan()
							improved = true
						end
					end
				end
				check()
			end
		end
	end
	return order, Length(order), Length(identity)
end

-- One slice of work per frame (driver: Routes/Guide.lua). now() in seconds. Returns true while work
-- remains. In a fight nothing is computed and nothing changes: the job waits.
function RT:RunJob(now, budget)
	if self.entered then
		self.want = self.want or "entry"
		self.entered = nil
	end
	if not self.job and not self.want then
		return false
	end
	local w = self.world
	if w.InCombat and w.InCombat() then
		return true
	end
	local job = self.job
	if not job then
		local reason = self.want
		self.want = nil
		self.job = self:NewReorder(reason, now, budget or RT.REORDER_BUDGET)
		-- building the job (positions, precedence) is this frame's work; the ordering starts next frame
		return self:Busy()
	end
	if job.gen ~= self.gen or self.cur ~= job.slots[1] then
		-- the route changed meanwhile (the player played on, skipped again): start again from there
		self.job = nil
		self.want = self.want or job.reason
		return true
	end
	job.t0 = now()
	local ok, order, len, before = coroutine.resume(job.co)
	if not ok then
		self.job = nil
		error(order, 0)
	end
	if coroutine.status(job.co) ~= "dead" then
		return true
	end
	self.job = nil
	job.len, job.before = len, before
	self:ApplyOrder(job, order)
	return self:Busy()
end

-- Puts the new order into the places of the range, saves it and moves the current step to the first of
-- them. Only when it is clearly shorter than the order before.
function RT:ApplyOrder(job, order)
	if not (job.len and job.before) or job.len > job.before * (1 - RT.REORDER_GAIN) then
		return false
	end
	local slots, seg = job.slots, job.seg
	local moved = {}
	for a = 1, #slots do
		moved[a] = self.steps[slots[order[a]]]
	end
	for a = 1, #slots do
		self.steps[slots[a]] = moved[a]
	end
	self:ReindexSteps(seg.first, seg.last)
	local ids = {}
	for i = seg.first, seg.last do
		ids[#ids + 1] = self.steps[i].id
	end
	local s = self.saved
	s.orders = type(s.orders) == "table" and s.orders or {}
	s.orders[seg.id] = table.concat(ids, ",")
	s.anchor = self.steps[slots[1]].key
	self.reordered = { reason = job.reason, len = job.len, before = job.before }
	self:Evaluate()
	self.notify("RouteRecalculated", "reorder")
	return true
end
