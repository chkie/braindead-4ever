-- SPDX-License-Identifier: GPL-3.0-or-later
-- Replanning in the client (Welle 7, owner guideline 7: "three levels ground, the route checks again"):
-- the entry anchor (Polestar #86, brain chapter 21 §6.1) on the real Alliance route, with a fake world.
local wow = require("spec.helpers.wow")

local V = { ACCEPT = 1, COMPLETE = 2, TURNIN = 3, TRAVEL = 6 }

local function newWorld()
	local w = { flagged = {}, log = {}, progress = {}, level = 1, map = 1429 }
	w.api = {
		IsFlagged = function(q)
			return w.flagged[q] == true
		end,
		InLog = function(q)
			return w.log[q] ~= nil
		end,
		IsComplete = function(q)
			return w.log[q] ~= nil and w.log[q].complete == true
		end,
		Progress = function(q)
			return w.log[q] ~= nil and (w.log[q].complete == true or w.progress[q] == true)
		end,
		Level = function()
			return w.level
		end,
		Map = function()
			return w.map
		end,
		XP = function()
			return 0, 400, 0
		end,
	}
	return w
end

local function deepcopy(t)
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in pairs(t) do
		c[deepcopy(k)] = deepcopy(v)
	end
	return c
end

describe("Replanning: entry anchor", function()
	wow.reset({})
	local ns = wow.loadFiles({
		"Pathmark/Routes/Routes.lua",
		"Pathmark/Routes/Data_Alliance.lua",
		"Pathmark/Routes/XP.lua",
		"Pathmark/Routes/Runtime.lua",
	})
	local RT = ns.Runtime
	local data = ns.Routes.Load("Alliance")
	local steps = ns.Routes.Steps("Alliance", "speed", 1, 1)
	-- elements with their own race or class filter belong to other combinations (R.Steps keeps them)
	local function mine(el)
		return ns.Routes.Applies(el, 1, 1)
	end

	local function new(w, saved)
		local rt = RT.New(steps, data.quests, w.api, saved or {}, { race = 1, class = 1, modules = data.modules })
		rt:Evaluate()
		return rt
	end

	-- Quest IDs of a step kind in route order: first step of each quest that has this verb.
	local function firstOf(verb, upTo)
		local out, seen = {}, {}
		for i = 1, upTo do
			for _, el in ipairs(steps[i].step) do
				if el[1] == verb and mine(el) and not seen[el[2]] then
					seen[el[2]] = true
					out[#out + 1] = { q = el[2], i = i }
				end
			end
		end
		return out
	end

	-- Last step with a quest handed in (the anchor of Polestar #86 without objective progress).
	local function anchorOf(w)
		local anchor = 0
		for i = 1, #steps do
			for _, el in ipairs(steps[i].step) do
				if el[1] <= V.TURNIN and mine(el) and w.flagged[el[2]] then
					anchor = i
				end
			end
		end
		return anchor
	end

	-- Index of the last step whose planned level is at most lv.
	local function lastAt(lv)
		local last = 0
		for i, s in ipairs(steps) do
			if s.step.lv <= lv then
				last = i
			end
		end
		return last
	end

	-- Mixed progress up to step `upTo`: every quest taken there, except every `gap`-th one (never
	-- taken) and every `logEvery`-th one (still in the log); a quest whose turn-in lies after `upTo`
	-- is still in the log, the others are handed in. Returns the gaps.
	local function play(w, upTo, gap, logEvery)
		local turnin = {}
		for _, a in ipairs(firstOf(V.TURNIN, #steps)) do
			turnin[a.q] = a.i
		end
		local gaps, k = {}, 0
		for _, a in ipairs(firstOf(V.ACCEPT, upTo)) do
			k = k + 1
			if gap and k % gap == 0 then
				gaps[a.q] = a.i
			elseif logEvery and k % logEvery == 0 or (turnin[a.q] or 0) > upTo then
				w.log[a.q] = { complete = false }
			else
				w.flagged[a.q] = true
			end
		end
		return gaps
	end

	it("enters at levels 1, 8, 15 and 24 with mixed progress at the right step", function()
		for _, level in ipairs({ 1, 8, 15, 24 }) do
			local w = newWorld()
			w.level = level
			local upTo = level == 1 and 0 or lastAt(level - 2)
			local gaps = play(w, upTo, 7, 11)
			local rt = new(w)
			local cur = rt:Current()
			local label = "level " .. level
			assert.is_table(cur, label)
			assert.are.equal("open", rt:StepState(cur.index), label)
			if level == 1 then
				assert.are.equal(1, cur.index, label)
				assert.are.same({}, rt:Earlier(), label)
			else
				-- the anchor is the last step with a turn-in; the route starts behind it, unless a quest of
				-- an earlier step is in the log (it stays to be finished)
				local anchor = anchorOf(w)
				assert.is_true(anchor > 0, label)
				assert.is_true(cur.index > anchor or rt:HoldsLogQuest(cur.index), label .. " at " .. cur.key)
				for i = 1, cur.index - 1 do
					local st = rt:StepState(i)
					assert.is_true(
						st ~= "open" or rt:Passed(i, rt:Context()) or i < anchor,
						label .. ": step " .. steps[i].step.id .. " left open behind the current one"
					)
				end
				-- every quest taken before the anchor but neither done nor in the log is in the list
				-- "skipped earlier", in route order: the gaps and those taken between the last played step
				-- and the anchor
				local expected = {}
				for _, a in ipairs(firstOf(V.ACCEPT, anchor - 1)) do
					if not w.flagged[a.q] and not w.log[a.q] then
						expected[#expected + 1] = a.q
					end
				end
				assert.are.same(expected, rt:Earlier(), label)
				local n = 0
				for _, i in pairs(gaps) do
					n = n + (i < anchor and 1 or 0)
				end
				assert.is_true(n > 0, label .. ": the test needs gaps")
			end
		end
	end)

	it("falls back to the start when less than half of the quests up to the anchor are done", function()
		local w = newWorld()
		w.level = 24
		local list = firstOf(V.ACCEPT, lastAt(22))
		for k, a in ipairs(list) do
			if k % 3 == 0 then -- a third done: other zones played, a few route quests on the way
				w.flagged[a.q] = true
			end
		end
		local rt = new(w)
		assert.are.same({}, rt:Earlier())
		-- only the level rule passes steps: planned more than 5 below level 24
		assert.is_true(rt:Current().lv >= 19, "at planned level " .. rt:Current().lv)
	end)

	it("a carried breadcrumb in the log does not throw the player ahead", function()
		local w = newWorld()
		w.level = 6
		play(w, 60)
		local real = new(w):Current().index
		-- a quest taken far ahead of the real progress, carried in the log (breadcrumb)
		local anchor = anchorOf(w)
		local crumb
		for _, a in ipairs(firstOf(V.ACCEPT, #steps)) do
			if a.i > anchor + 10 and steps[a.i].step.lv <= 10 then
				crumb = a
				break
			end
		end
		assert.is_table(crumb)
		w.log[crumb.q] = { complete = false }
		local rt = new(w)
		assert.are.equal(real, rt:Current().index, "thrown ahead to " .. rt:Current().key)
		assert.is_true(rt:Current().index < crumb.i)
	end)

	it("objective progress counts as an anchor", function()
		local w = newWorld()
		w.level = 4
		play(w, 30)
		-- the furthest quest with progress: its objective step becomes the current step
		local target
		for i = 60, 80 do
			for _, el in ipairs(steps[i].step) do
				if el[1] == V.COMPLETE and not target then
					target = { q = el[2], i = i }
				end
			end
		end
		assert.is_table(target)
		-- the route quests between 31 and the target are taken and done (more than half)
		for _, a in ipairs(firstOf(V.ACCEPT, target.i)) do
			if a.i > 30 and a.q ~= target.q then
				w.flagged[a.q] = true
			end
		end
		w.log[target.q] = { complete = false }
		w.progress[target.q] = true
		local rt = new(w)
		assert.are.equal(target.i, rt:Current().index)
	end)

	it("checks the anchor again on re-entry and after a level-up, never during a question", function()
		local w = newWorld()
		w.level = 3
		local rt = new(w)
		local saved = rt.saved
		assert.are.equal(1, rt:Current().index)
		-- played the first 60 steps without the route (addon off), one quest left out
		local gaps = play(w, 60, 9)
		local again = new(w, deepcopy(saved))
		assert.is_true(again:Current().index > 50, "re-entry at " .. again:Current().key)
		-- the list holds the gaps taken before the anchor (the last step with a turn-in)
		local anchor, n = anchorOf(w), 0
		for _, i in pairs(gaps) do
			n = n + (i < anchor and 1 or 0)
		end
		assert.is_true(n > 0, "the test needs gaps before the anchor")
		assert.are.equal(n, #again:Earlier())
		-- in the session: nothing jumps until the level-up asks for a check
		local w2 = newWorld()
		w2.level = 3
		local live = new(w2)
		play(w2, 60, 9)
		live:Evaluate()
		local before = live:Current().index
		w2.level = 6
		live:Recheck()
		live:Evaluate()
		assert.is_true(live:Current().index > before, "level-up re-check moved on")
		-- an open abandon question holds everything, also the re-check
		local w3 = newWorld()
		w3.level = 3
		local held = new(w3)
		w3.log[33] = { complete = false }
		held:Evaluate()
		w3.log[33] = nil
		held.saved.pending = 33
		local at = held:Current().index
		play(w3, 60)
		held:Recheck()
		held:Evaluate()
		assert.are.equal(at, held:Current().index)
	end)

	it("keeps the list over /reload and drops quests done since", function()
		local w = newWorld()
		w.level = 8
		play(w, lastAt(6), 5)
		local rt = new(w)
		local list = rt:Earlier()
		assert.is_true(#list > 1)
		local again = new(w, deepcopy(rt.saved))
		assert.are.same(list, again:Earlier())
		w.flagged[list[1]] = true
		assert.are.equal(#list - 1, #again:Earlier())
	end)
end)

-- A made-up route (quest IDs 900101 and up) with four zones, so every level gap is exact.
-- Zone A (plan 10): A2 and A3 are low (quest level 6), A3 leads to A4 (level 11), A5 is level 7.
local SA = { A1 = 900101, A2 = 900102, A3 = 900103, A4 = 900104, A5 = 900105 }
local SB = { B1 = 900201, B2 = 900202 }
local SYN_QUESTS = {
	[SA.A1] = { 10, 500 },
	[SA.A2] = { 6, 300 },
	[SA.A3] = { 6, 300 },
	[SA.A4] = { 11, 600, { { SA.A3 } } },
	[SA.A5] = { 7, 300 },
	[SB.B1] = { 13, 700 },
	[SB.B2] = { 13, 700 },
	[900301] = { 16, 900 },
	[900401] = { 19, 1100 },
}

local function q(code, quest)
	return { code, quest, 1, 0 }
end
local function go(map, x, y)
	return { 5, map, x or 0, y or 0, 10, 1, 0, 1 }
end
local function st(module, id, lv, ...)
	return { module = module, step = { id = id, lv = lv, ... } }
end
local function travel(module, id, lv, map)
	return st(module, id, lv, { 6, 1, map, 16, 0 })
end

local function synthRoute()
	local A, B = SA, SB
	return {
		st("m-a", "a1", 10, q(1, A.A1), go(1429, 0, 0)),
		st("m-a", "a2", 10, q(1, A.A2), go(1429, 10, 0)),
		st("m-a", "a3", 10, q(1, A.A3), go(1429, 20, 0)),
		st("m-a", "c1", 10, q(2, A.A1), go(1429, 100, 0)),
		st("m-a", "c2", 10, q(2, A.A2), go(1429, 100, 50)),
		st("m-a", "c3", 10, q(2, A.A3), go(1429, 100, 100)),
		st("m-a", "t1", 10, q(3, A.A1), go(1429, 0, 0)),
		st("m-a", "t2", 10, q(3, A.A2), go(1429, 10, 0)),
		st("m-a", "t3", 10, q(3, A.A3), q(1, A.A4), go(1429, 20, 0)),
		st("m-a", "c4", 10, q(2, A.A4), go(1429, 200, 0)),
		st("m-a", "t4", 10, q(3, A.A4), go(1429, 20, 0)),
		st("m-a", "a5", 10, q(1, A.A5), go(1429, 30, 0)),
		st("m-a", "c5", 10, q(2, A.A5), go(1429, 50, 50)),
		st("m-a", "t5", 10, q(3, A.A5), go(1429, 30, 0)),
		travel("m-b", "rB", 12, 1436),
		st("m-b", "aB1", 13, q(1, B.B1), go(1436, 0, 0)),
		st("m-b", "aB2", 13, q(1, B.B2), go(1436, 5, 0)),
		st("m-b", "cB1", 13, q(2, B.B1), go(1436, 50, 0)),
		st("m-b", "cB2", 13, q(2, B.B2), go(1436, 60, 0)),
		st("m-b", "tB1", 13, q(3, B.B1), go(1436, 0, 0)),
		st("m-b", "tB2", 13, q(3, B.B2), go(1436, 5, 0)),
		travel("m-c", "rC", 15, 1433),
		st("m-c", "aC1", 16, q(1, 900301), go(1433, 0, 0)),
		st("m-c", "cC1", 16, q(2, 900301), go(1433, 40, 0)),
		st("m-c", "tC1", 16, q(3, 900301), go(1433, 0, 0)),
		travel("m-d", "rD", 18, 1439),
		st("m-d", "aD1", 19, q(1, 900401), go(1439, 0, 0)),
		st("m-d", "cD1", 19, q(2, 900401), go(1439, 40, 0)),
		st("m-d", "tD1", 19, q(3, 900401), go(1439, 0, 0)),
	}
end

describe("Replanning: over the plan and switch points", function()
	wow.reset({})
	local ns = wow.loadFiles({
		"Pathmark/Routes/Routes.lua",
		"Pathmark/Routes/XP.lua",
		"Pathmark/Routes/Runtime.lua",
		"Pathmark/Routes/Replan.lua",
	})
	local RT = ns.Runtime

	-- A session that started at level 10 at the first step; then the player plays without the route.
	local function session()
		local w = newWorld()
		w.level = 10
		local rt = RT.New(synthRoute(), SYN_QUESTS, w.api, {}, {})
		rt:Evaluate()
		assert.are.equal("a1", rt:Current().id)
		return rt, w
	end

	local function grind(rt, w, level)
		w.level = level
		rt:Recheck()
		rt:Evaluate()
	end

	it("three levels of grinding: asks once, leaves out quests under 80 % XP, keeps chains", function()
		local rt, w = session()
		grind(rt, w, 12)
		assert.is_nil(rt:Offer(), "two levels above the plan: no question")
		grind(rt, w, 13)
		local o = rt:Offer()
		assert.are.equal("over", o.kind)
		assert.are.equal(3, o.gap)
		assert.are.equal(10, o.plan)
		-- A2 (level 6) gives 60 % at level 13; A3 is as low but leads to A4 (level 11): it stays.
		-- A5 (level 7) gives 80 % and stays.
		assert.are.same({ SA.A2 }, o.drop)
		assert.is_true(rt:AnswerOffer(o.id, true))
		assert.are.equal("adjust", rt:LastAction().kind)
		assert.is_true(rt:Blocked()[SA.A2])
		assert.is_nil(rt:Blocked()[SA.A3])
		for _, id in ipairs({ "a2", "c2", "t2" }) do
			assert.are.equal("skipped", rt:StepState(rt.index["m-a/" .. id]), id)
		end
		assert.is_nil(rt:Offer(), "asked once per block")
		-- the next zone fits level 13: no switch question at its travel step
		for _, quest in ipairs({ SA.A1, SA.A3, SA.A4, SA.A5 }) do
			w.flagged[quest] = true
		end
		rt:Evaluate()
		assert.are.equal("rB", rt:Current().id)
		assert.is_nil(rt:Offer())
		-- undo brings the quest back
		rt:Undo()
		assert.is_nil(rt:Blocked()[SA.A2])
	end)

	it("six levels of grinding: stops at the zone change and offers the block that fits", function()
		local rt, w = session()
		grind(rt, w, 16)
		-- every step of zone A is passed (planned more than 5 below), the travel step stays
		assert.are.equal("rB", rt:Current().id, "no zone change without asking")
		local o = rt:Offer()
		assert.are.equal("switch", o.kind)
		assert.are.equal(13, o.plan)
		assert.are.equal("jump", o.choice.kind)
		assert.are.equal("m-c/rC", o.choice.to)
		assert.are.equal(16, o.choice.plan)
		-- "keep": nothing changes, the question does not come again
		local again = RT.New(synthRoute(), SYN_QUESTS, w.api, {}, {})
		again:Evaluate()
		w.level = 16
		again:Recheck()
		again:Evaluate()
		assert.is_true(again:AnswerOffer(again:Offer().id, false))
		assert.is_nil(again:Offer())
		assert.are.equal("rB", again:Current().id)
		-- "go there": zone B is skipped with its quests, the route goes on at the travel step to C
		assert.is_true(rt:AnswerOffer(o.id, true))
		assert.are.equal("rC", rt:Current().id)
		assert.is_true(rt:Blocked()[SB.B1] and rt:Blocked()[SB.B2])
		assert.are.equal("switch", rt:LastAction().kind)
		assert.is_true(rt:Undo())
		assert.are.equal("rB", rt:Current().id)
		-- far above the whole route: still never passes the zone change on its own
		grind(rt, w, 30)
		assert.are.equal("rB", rt:Current().id)
	end)

	it("a dungeon in between: done quests are passed, the question comes, no keeps the route", function()
		local rt, w = session()
		-- the dungeon run handed in A1 (a group did it there) and gave four levels
		w.flagged[SA.A1] = true
		grind(rt, w, 14)
		assert.are.equal("a2", rt:Current().id)
		local o = rt:Offer()
		assert.are.equal("over", o.kind)
		assert.are.equal(4, o.gap)
		assert.are.same({ SA.A2, SA.A5 }, o.drop, "A5 (level 7) gives 60 % at level 14")
		assert.is_true(rt:AnswerOffer(o.id, false))
		assert.is_nil(rt:Offer())
		assert.are.equal("a2", rt:Current().id, "the route stays as it is")
		assert.is_nil(next(rt:Blocked()))
		-- at the end of zone A, zone B (plan 13) fits level 14: no switch question
		for _, quest in ipairs({ SA.A2, SA.A3, SA.A4, SA.A5 }) do
			w.flagged[quest] = true
		end
		rt:Evaluate()
		assert.are.equal("rB", rt:Current().id)
		assert.is_nil(rt:Offer())
	end)

	it("asks nothing while an abandon question waits and never on a class detour", function()
		local rt, w = session()
		grind(rt, w, 13)
		rt.saved.pending = SA.A1
		assert.is_nil(rt:Offer())
		rt.saved.pending = nil
		local steps = synthRoute()
		steps[15].step.ret = "Klassenquest"
		local detour = RT.New(steps, SYN_QUESTS, w.api, {}, {})
		w.level = 10
		detour:Evaluate()
		w.level = 18
		detour:Recheck()
		detour:Evaluate()
		-- a class detour's travel step is passed by level as before (Welle 3) and asks nothing
		assert.are.equal("aB1", detour:Current().id)
		assert.is_nil(detour:Offer())
	end)
end)

-- Three quests whose objectives lie 1000 yards east of their givers: the plan does them one after
-- another (accept, objective, turn-in), three times the way; from the givers it is shorter to take all
-- three, do the objectives, and come back.
local function triple(extra)
	local X, Y, Z, W = 900501, 900502, 900503, 900504
	local steps = {
		st("m-r", "aW", 5, q(1, W), go(1429, 0, 0)),
		st("m-r", "aX", 5, q(1, X), go(1429, 0, 0)),
		st("m-r", "cX", 5, q(2, X), go(1429, 1000, 0)),
		st("m-r", "tX", 5, q(3, X), go(1429, 0, 0)),
		st("m-r", "aY", 5, q(1, Y), go(1429, 0, 10)),
		st("m-r", "cY", 5, q(2, Y), go(1429, 1000, 10)),
		st("m-r", "tY", 5, q(3, Y), go(1429, 0, 10)),
		st("m-r", "aZ", 5, q(1, Z), go(1429, 0, 20)),
		st("m-r", "cZ", 5, q(2, Z), go(1429, 1000, 20)),
		st("m-r", "tZ", 5, q(3, Z), go(1429, 0, 20)),
	}
	if extra then
		extra(steps)
	end
	steps[#steps + 1] = travel("m-s", "rS", 6, 1436)
	steps[#steps + 1] = st("m-s", "aS", 6, q(1, 900601), go(1436, 0, 0))
	local quests =
		{ [X] = { 5, 100 }, [Y] = { 5, 100 }, [Z] = { 5, 100, { { X } } }, [W] = { 5, 100 }, [900601] = { 6, 100 } }
	return steps, quests, { X = X, Y = Y, Z = Z, W = W }
end

local function ids(rt, from, to)
	local out = {}
	for i = from, to do
		out[#out + 1] = rt.steps[i].id
	end
	return out
end

describe("Replanning: reorder in the block", function()
	wow.reset({})
	local ns = wow.loadFiles({
		"Pathmark/Routes/Routes.lua",
		"Pathmark/Routes/XP.lua",
		"Pathmark/Routes/Runtime.lua",
		"Pathmark/Routes/Replan.lua",
	})
	local RT = ns.Runtime

	-- A fake clock: every call moves on by tick seconds, so the frame budget runs out in the tests too.
	local function Clock(tick)
		local t = 0
		return function()
			t = t + (tick or 0)
			return t
		end
	end

	local function placed(w, x, y)
		w.combat = false
		w.api.Position = function()
			return x, y, 0
		end
		w.api.InCombat = function()
			return w.combat
		end
		return w
	end

	local function run(rt, now, budget, max)
		local frames = 0
		while rt:RunJob(now or Clock(), budget or 1) do
			frames = frames + 1
			assert.is_true(frames < (max or 1000), "job does not end")
		end
		return frames
	end

	local function setup(extra)
		local steps, quests, Q = triple(extra)
		local w = placed(newWorld(), 0, 0)
		w.level = 5
		local rt = RT.New(steps, quests, w.api, {}, {})
		rt:Evaluate()
		return rt, w, Q, steps, quests
	end

	it("a skip reorders the rest of the block from the player's position", function()
		local rt, w, Q = setup()
		assert.is_false(rt:Busy(), "a first start at the first step reorders nothing")
		rt:Skip() -- W is not offered here
		assert.is_true(rt:Busy())
		local recalculated
		rt.notify = function(event, reason)
			if event == "RouteRecalculated" then
				recalculated = reason
			end
		end
		run(rt)
		assert.are.equal("reorder", recalculated)
		-- X and Y together; Z needs X, so its accept waits for X's turn-in
		assert.are.same({ "aW", "aX", "aY", "cY", "cX", "tX", "tY", "aZ", "cZ", "tZ" }, ids(rt, 1, 10))
		assert.are.equal("aX", rt:Current().id)
		assert.is_true(rt.reordered.len < rt.reordered.before * 0.95)
		-- the travel step and the next zone keep their place
		assert.are.equal("rS", rt.steps[11].id)
		-- the order survives a /reload
		local again = RT.New(triple(), select(2, triple()), w.api, deepcopy(rt.saved), {})
		again:Evaluate()
		assert.are.same(ids(rt, 1, 12), ids(again, 1, 12))
		assert.are.equal("aX", again:Current().id)
		assert.is_true(rt:Blocked()[Q.W])
	end)

	it("never reorders in a fight: the job waits and runs after it", function()
		local rt, w = setup()
		rt:Skip()
		w.combat = true
		for _ = 1, 200 do
			assert.is_true(rt:RunJob(Clock(), 1), "the job waits")
		end
		assert.are.equal("aX", rt.steps[2].id)
		assert.are.equal("cX", rt.steps[3].id, "nothing moved in the fight")
		assert.is_nil(rt.saved.orders)
		w.combat = false
		run(rt)
		assert.are.equal("aY", rt.steps[3].id)
	end)

	it("works in slices of the frame budget and gets the same order", function()
		local rt = setup()
		rt:Skip()
		-- every clock call costs 0.5 ms: a 2 ms budget yields every few moves
		local frames = run(rt, Clock(0.0005), 0.002)
		assert.is_true(frames > 3, "only " .. frames .. " frames")
		local whole = setup()
		whole:Skip()
		run(whole)
		assert.are.same(ids(whole, 1, 12), ids(rt, 1, 12))
	end)

	it("keeps the plan when a new order is not clearly shorter", function()
		local rt, w = setup()
		-- standing at the objectives, the plan order is about as long as any other
		w.api.Position = function()
			return 0, 0, 0
		end
		rt:Check() -- a check is no reason to reorder
		assert.is_false(rt:Busy())
		local steps, quests = triple()
		for i, step in ipairs(steps) do
			if i <= 10 then
				step.step[2] = go(1429, i * 10, 0) -- the plan already walks in a straight line
			end
		end
		local straight = RT.New(steps, quests, w.api, {}, {})
		straight:Evaluate()
		straight:Skip()
		run(straight)
		assert.is_nil(straight.saved.orders)
		assert.is_nil(straight.reordered)
	end)

	it("keeps steps of other kinds in place (trainer, hearthstone and kinds that come later)", function()
		local rt = setup(function(steps)
			table.insert(steps, 6, st("m-r", "train", 5, { 10, 16, 0 }, go(1429, 500, 500)))
			table.insert(steps, 8, st("m-r", "hs", 5, { 7, 16, 0 }))
		end)
		rt:Skip()
		run(rt)
		assert.are.equal("train", rt.steps[6].id)
		assert.are.equal("hs", rt.steps[8].id)
		for _, seg in ipairs(rt.segs) do
			for i = seg.first, seg.last do
				assert.is_true(rt.steps[i].id ~= "train" and rt.steps[i].id ~= "hs")
			end
		end
	end)

	it("an abandoned quest skipped and an entry in the middle of the block reorder too", function()
		local rt, w, Q = setup()
		w.log[Q.W] = { complete = false }
		rt:Evaluate()
		w.log[Q.W] = nil
		rt:OnAbandoned(Q.W)
		rt:ResolveAbandon("skip")
		run(rt)
		assert.are.equal("aY", rt.steps[3].id)
		-- a fresh start at level 12: the level rule places the route in the middle of nowhere; with the
		-- first quest handed in the anchor places it behind aW
		local w2 = placed(newWorld(), 0, 0)
		w2.flagged[Q.W] = true
		local steps, quests = triple()
		local fresh = RT.New(steps, quests, w2.api, {}, {})
		fresh:Evaluate()
		assert.are.equal("aX", fresh:Current().id)
		assert.is_true(fresh:Busy(), "entry asks for a reorder")
		run(fresh)
		assert.are.equal("aY", fresh.steps[3].id)
	end)

	it("does nothing while the player went back or a question waits", function()
		local rt = setup()
		rt:Skip()
		rt.saved.pin = rt:Current().key
		run(rt)
		assert.is_nil(rt.saved.orders)
	end)
end)

describe("Replanning: reorder and steps that open again", function()
	wow.reset({})
	local ns = wow.loadFiles({
		"Pathmark/Routes/Routes.lua",
		"Pathmark/Routes/XP.lua",
		"Pathmark/Routes/Runtime.lua",
		"Pathmark/Routes/Replan.lua",
	})
	local RT = ns.Runtime

	local function setup()
		local steps, quests, Q = triple()
		local w = newWorld()
		w.level = 5
		w.api.Position = function()
			return 0, 0, 0
		end
		w.api.InCombat = function()
			return false
		end
		local rt = RT.New(steps, quests, w.api, {}, {})
		rt:Evaluate()
		return rt, w, Q
	end

	local function run(rt)
		local n = 0
		while rt:RunJob(os.clock, 1) do
			n = n + 1
			assert.is_true(n < 1000, "job does not end")
		end
	end

	local function at(rt, id)
		for i, s in ipairs(rt.steps) do
			if s.id == id then
				return i
			end
		end
	end

	it("a done step moves with the open ones: taken again, it still comes before its objectives", function()
		local rt, w, Q = setup()
		w.log[Q.Y] = { complete = false } -- Y taken before: its accept step is done
		rt:Evaluate()
		rt:Skip() -- W
		run(rt)
		assert.is_not_nil(rt.reordered, "the skip reordered the block")
		-- Y abandoned and taken again: the accept step opens again
		w.log[Q.Y] = nil
		rt:OnAbandoned(Q.Y)
		rt:ResolveAbandon("reaccept")
		assert.are.equal("aY", rt:Current().id)
		assert.is_true(at(rt, "aY") < at(rt, "cY"), "objective before the accept")
		assert.is_true(at(rt, "cY") < at(rt, "tY"))
	end)

	it("undo of the skip takes the reorder back", function()
		local rt = setup()
		local plan = {}
		for i, s in ipairs(rt.steps) do
			plan[i] = s.id
		end
		rt:Skip()
		run(rt)
		assert.is_not_nil(rt.saved.orders)
		rt:Undo()
		for i, s in ipairs(rt.steps) do
			assert.are.equal(plan[i], s.id)
			assert.are.equal(i, rt.index[s.key])
		end
		assert.is_nil(rt.saved.orders)
		assert.are.equal("aW", rt:Current().id)
	end)
end)

-- Measured time of the reorder on the real Alliance route (brain chapter 21 §6.2: DR 22d measured
-- 0.66 ms at 40 and 7.37 ms at 80 points) and the frame budget (chapter 12: under 0.1 ms per frame on
-- average). Offline on stock Lua 5.1: the order of magnitude; the binding number comes from the client.
describe("Replanning: time and frame budget of the reorder", function()
	wow.reset({})
	local ns = wow.loadFiles({
		"Pathmark/Routes/Routes.lua",
		"Pathmark/Routes/Data_Alliance.lua",
		"Pathmark/Routes/XP.lua",
		"Pathmark/Routes/Runtime.lua",
		"Pathmark/Routes/Replan.lua",
	})
	local RT = ns.Runtime
	local data = ns.Routes.Load("Alliance")
	local all = ns.Routes.Steps("Alliance", "speed", 1, 1)

	local function report(fmt, ...)
		io.stdout:write("\n[replan] " .. fmt:format(...))
	end

	-- The longest segment of movable steps of the real route (a step with an `xp` or `fp` element stays
	-- in place and ends a segment), with every quest handed in before it.
	local longest = (function()
		local w = newWorld()
		local rt = RT.New(all, data.quests, w.api, {}, { race = 1, class = 1, modules = data.modules })
		local best
		for _, seg in ipairs(rt.segs) do
			if not best or seg.last - seg.first > best.last - best.first then
				best = seg
			end
		end
		return best
	end)()

	-- A runtime on n steps of that segment, the player at its first quest giver, nothing of it done:
	-- n open points.
	local function route(n)
		assert.is_true(longest.last - longest.first + 1 >= n, "segment of " .. n .. " movable steps")
		local steps = {}
		for i = 1, n do
			steps[i] = all[longest.first + i - 1]
		end
		local w = newWorld()
		w.level = steps[1].step.lv
		for i = 1, longest.first - 1 do
			for _, el in ipairs(all[i].step) do
				if el[1] == V.TURNIN and ns.Routes.Applies(el, 1, 1) then
					w.flagged[el[2]] = true
				end
			end
		end
		w.api.Position = function()
			for _, el in ipairs(steps[1].step) do
				if el[1] == 5 then -- goto: { 5, uiMapID, wx, wy, ... }
					return el[3], el[4], 0
				end
			end
			return -163, -8869, 0
		end
		w.api.InCombat = function()
			return false
		end
		local rt = RT.New(steps, data.quests, w.api, {}, { race = 1, class = 1, modules = data.modules })
		rt:Evaluate()
		assert.are.equal(1, #rt.segs, "one segment")
		return rt
	end

	local function measure(n)
		local rt = route(n)
		local reps, job = 20, nil
		local start = os.clock()
		for _ = 1, reps do
			job = rt:NewReorder("skip", os.clock, 1e9)
			assert.is_true(coroutine.resume(job.co))
		end
		local ms = (os.clock() - start) * 1000 / reps
		assert.are.equal(n, #job.slots)
		return ms
	end

	it("orders 40 and 80 points within a few milliseconds", function()
		local ms40, ms80 = measure(40), measure(80)
		report("reorder 40 points: %.2f ms, 80 points: %.2f ms (whole job, without slices)", ms40, ms80)
		assert.is_true(ms40 < 20, ("40 points %.2f ms"):format(ms40))
		assert.is_true(ms80 < 80, ("80 points %.2f ms"):format(ms80))
	end)

	it("keeps to 2 ms per frame and stays far under 0.1 ms per frame on average", function()
		local rt = route(140) -- longer than REORDER_MAX: the job takes the next 80 open steps
		rt.want = "skip"
		local frames, worst, total = 0, 0, 0
		repeat
			local t = os.clock()
			local more = rt:RunJob(os.clock, RT.REORDER_BUDGET)
			local ms = (os.clock() - t) * 1000
			frames, total = frames + 1, total + ms
			worst = math.max(worst, ms)
		until not more
		-- chapter 21 §6.2: about 10 reorders per hour at 60 frames per second
		local mean = total * 10 / (3600 * 60)
		report(
			"reorder in slices: %d frames, worst %.3f ms, job %.2f ms; mean over an hour %.5f ms per frame (budget 0.1)",
			frames,
			worst,
			total,
			mean
		)
		assert.is_true(frames > 1, "the job runs in slices")
		assert.is_true(worst < RT.REORDER_BUDGET * 1000 + 1, ("worst frame %.3f ms"):format(worst))
		assert.is_true(mean < 0.1, ("mean %.5f ms per frame"):format(mean))
	end)
end)

-- Stage 2 (brain chapter 21 §6.2): at a switch point the route chooses among alternative modules built
-- offline (Welle 6b) by the deviation from the plan; the player decides.
describe("Replanning: alternative modules at switch points", function()
	wow.reset({})
	local ns = wow.loadFiles({
		"Pathmark/Routes/Routes.lua",
		"Pathmark/Routes/XP.lua",
		"Pathmark/Routes/Runtime.lua",
		"Pathmark/Routes/Replan.lua",
	})
	local RT, R = ns.Runtime, ns.Routes

	local MODULES = {
		["m-a"] = {},
		["m-b"] = {},
		["m-c"] = {},
		["m-d"] = {},
		["m-b-hi"] = { r = { 1 } }, -- built for a higher level, humans only
		["m-b-lo"] = {},
		["m-b-dwarf"] = { r = { 3 } },
	}
	local ALTS = {
		["m-b"] = {
			{ key = "m-b-hi", plan = 16, map = 1437, gain = 900 },
			{ key = "m-b-lo", plan = 11, map = 1438, gain = 300 },
			{ key = "m-b-dwarf", plan = 16, map = 1426, gain = 1200 }, -- not for this race
			{ key = "m-b-gone", plan = 16, map = 1426 }, -- the data does not hold it
		},
	}

	-- Zone A done, the character at the given level at the travel step into zone B (plan 13).
	local function at(level)
		local w = newWorld()
		w.level = 10
		local rt = RT.New(synthRoute(), SYN_QUESTS, w.api, {}, { race = 1, class = 1, modules = MODULES, alts = ALTS })
		rt:Evaluate()
		for _, quest in pairs(SA) do
			w.flagged[quest] = true
		end
		w.level = level
		rt:Recheck()
		rt:Evaluate()
		assert.are.equal("rB", rt:Current().id)
		return rt, w
	end

	it("offers the alternative nearest to the level, above and below the plan", function()
		-- 16: three above zone B; the jump to zone C (plan 16) fits as well, the module with its time
		-- gain wins the tie and keeps the zones
		local o = at(16):Offer()
		assert.are.equal("switch", o.kind)
		assert.are.equal("module", o.choice.kind)
		assert.are.equal("m-b-hi", o.choice.module)
		assert.are.equal(1437, o.choice.map)
		assert.are.equal(900, o.choice.gain)
		local kinds = {}
		for _, opt in ipairs(o.options) do
			kinds[#kinds + 1] = opt.module or opt.kind
		end
		assert.are.same({ "stay", "jump", "m-b-hi", "m-b-lo" }, kinds, "other races and missing modules left out")
		-- 10: three below the plan; no jump backwards, the lower module fits
		o = at(10):Offer()
		assert.are.equal("m-b-lo", o.choice.module)
		assert.are.equal(11, o.choice.plan)
		-- 12 and 15: less than three away from the plan, nothing to ask
		assert.is_nil(at(12):Offer())
		assert.is_nil(at(15):Offer())
	end)

	it("yes: the choice is saved, the route is built again with it; no keeps the route", function()
		local rt = at(16)
		local o = rt:Offer()
		local r, module = rt:AnswerOffer(o.id, true)
		assert.are.equal("rebuild", r)
		assert.are.equal("m-b-hi", module)
		assert.are.same({ ["m-b"] = "m-b-hi" }, rt.saved.alts)
		assert.are.same({}, rt.saved.undo, "a switch of modules cannot be undone")
		assert.is_nil(rt:Offer(), "asked once")
		local no = at(16)
		assert.is_true(no:AnswerOffer(no:Offer().id, false))
		assert.is_nil(no.saved.alts)
		assert.are.equal("rB", no:Current().id)
	end)

	it("puts the route together with the chosen module; class inserts stay, unknown choices are ignored", function()
		local data = {
			modules = { s = {}, ["m-b"] = {}, ["m-b-hi"] = {}, ["m-c"] = {}, ins = {} },
			compose = {
				speed = {
					starts = { { key = "s" } },
					core = { "m-b", "m-c" },
					inserts = { { after = "m-b", key = "ins" } },
				},
			},
		}
		assert.are.same({ "s", "m-b", "ins", "m-c" }, R.ModuleKeys(data, "speed", 1, 1))
		assert.are.same({ "s", "m-b-hi", "ins", "m-c" }, R.ModuleKeys(data, "speed", 1, 1, { ["m-b"] = "m-b-hi" }))
		assert.are.same({ "s", "m-b", "ins", "m-c" }, R.ModuleKeys(data, "speed", 1, 1, { ["m-b"] = "gone" }))
	end)

	it("without alternatives in the data the switch point works as before", function()
		local w = newWorld()
		w.level = 16
		local rt = RT.New(synthRoute(), SYN_QUESTS, w.api, {}, { race = 1, class = 1, modules = MODULES })
		assert.are.same({}, rt:Alternatives("m-b"))
	end)
end)
