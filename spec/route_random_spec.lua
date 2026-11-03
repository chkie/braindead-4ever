-- SPDX-License-Identifier: GPL-3.0-or-later
-- Random sequences on the real Elwynn route (owner wish 10, 2026-11-01): accept, abandon, play, check,
-- skip, back, undo, answer the abandon question, level up and /reload in any order; since Welle 7 also
-- moving around, fights and the reorder job, which runs up to ten frame slices after every action
-- (an action every 170 ms, so a long job spans several actions and often gets stale). After every action
-- the route must be valid. The generator is seeded, so a failure repeats with the same sequence.
local wow = require("spec.helpers.wow")

local V = { ACCEPT = 1, COMPLETE = 2, TURNIN = 3, TRAVEL = 6 }
local ACTIONS = 2500

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

-- Linear congruential generator: the same numbers on every Lua 5.1 build.
local function Random(seed)
	local s = seed
	return function(n)
		s = (s * 1103515245 + 12345) % 2147483648
		return math.floor(s / 65536) % n + 1
	end
end

local function newWorld()
	local w = { flagged = {}, log = {}, level = 1, map = 1429, x = 0, y = 0, combat = false }
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
		Level = function()
			return w.level
		end,
		Map = function()
			return w.map
		end,
		XP = function()
			return 0, 400, 0
		end,
		Position = function()
			return w.x, w.y, 0
		end,
		InCombat = function()
			return w.combat
		end,
	}
	return w
end

describe("Route runtime under random actions", function()
	wow.reset({})
	local ns = wow.loadFiles({
		"BraindeadForever/Routes/Routes.lua",
		"BraindeadForever/Routes/Data_Alliance.lua",
		"BraindeadForever/Routes/XP.lua",
		"BraindeadForever/Routes/Runtime.lua",
		"BraindeadForever/Routes/Replan.lua",
	})
	local RT = ns.Runtime
	local data = ns.Routes.Load("Alliance")
	-- Elwynn and the first core blocks: long enough for chains, short enough for thousands of actions.
	local all = ns.Routes.Steps("Alliance", "speed", 1, 1)
	local steps = {}
	for i = 1, 160 do
		steps[i] = all[i]
	end

	local planIndex = {}
	for i, e in ipairs(steps) do
		planIndex[e.module .. "/" .. e.step.id] = i
	end

	-- Reordering only permutes movable steps inside their segment; every step keeps its index entry,
	-- the accept index stays right, and open steps keep accept, objectives, turn-in and prerequisite order.
	local function checkOrder(rt, label)
		local n = #rt.steps
		assert.are.equal(#steps, n, label .. ": step count")
		local first = {}
		for i, step in ipairs(rt.steps) do
			assert.are.equal(i, rt.index[step.key], label .. ": index of " .. step.key)
			local seg = rt.segAt[planIndex[step.key]]
			if seg then
				assert.is_true(i >= seg.first and i <= seg.last, label .. ": " .. step.key .. " left its segment")
			else
				assert.are.equal(planIndex[step.key], i, label .. ": " .. step.key .. " moved")
			end
			for _, el in ipairs(step.els) do
				if el[1] == V.ACCEPT and not first[el[2]] then
					first[el[2]] = i
				end
			end
		end
		assert.are.same(first, rt.accepts, label .. ": accept index")
		local ctx = rt:Context()
		local stage, turnin = {}, {}
		for i = rt.cur, n do
			local step = rt.steps[i]
			if rt:StepState(i, ctx) == "open" and not rt:Passed(i, ctx) then
				for _, el in ipairs(step.els) do
					local v, q = el[1], el[2]
					if v <= V.TURNIN then
						assert.is_true((stage[q] or 0) <= v, label .. ": " .. q .. " out of order at " .. step.key)
						stage[q] = v
						if v == V.ACCEPT then
							for _, group in ipairs(rt:Groups(q)) do
								for _, m in ipairs(group) do
									local t = turnin[m]
									assert.is_true(t == nil or t < i, label .. ": " .. q .. " before its prerequisite")
								end
							end
						end
					end
				end
				for _, el in ipairs(step.els) do
					if el[1] == V.TURNIN then
						turnin[el[2]] = i
					end
				end
			end
		end
	end

	local function check(rt, w, label)
		local n = #rt.steps
		local s = rt.saved
		assert.is_true(rt.cur >= 1 and rt.cur <= n + 1, label .. ": current " .. tostring(rt.cur))
		assert.is_true(s.anchor == "_end" or rt.index[s.anchor] ~= nil, label .. ": anchor " .. tostring(s.anchor))
		assert.is_true(#s.undo <= RT.UNDO_MAX, label .. ": undo list")
		if s.pending then
			assert.is_number(rt.accepts[s.pending], label .. ": pending quest not on the route")
		elseif rt.cur <= n then
			local state = rt:StepState(rt.cur)
			assert.are.equal("open", state, label .. ": current step " .. rt.steps[rt.cur].key)
		end
		-- The skip set is closed under the prerequisite rule and holds nothing else.
		local blocked = rt:Blocked()
		for _, step in ipairs(rt.steps) do
			for _, q in ipairs(step.quests) do
				local dead = not w.flagged[q] and rt:Dead(q, blocked)
				if dead then
					assert.is_true(blocked[q] == true, label .. ": " .. q .. " needs a skipped quest")
				end
				if blocked[q] then
					assert.is_true(s.roots[q] ~= nil or dead, label .. ": " .. q .. " skipped without reason")
					assert.is_false(w.flagged[q] == true, label .. ": handed-in quest " .. q .. " skipped")
				end
			end
		end
		for _, u in ipairs(rt:Upcoming(3)) do
			assert.is_true(u.index > rt.cur, label .. ": upcoming before current")
			assert.are.equal("open", rt:StepState(u.index), label .. ": upcoming " .. u.key)
		end
		checkOrder(rt, label)
	end

	-- Plan positions of the route's goto points, to stand somewhere on the route.
	local spots = {}
	for _, e in ipairs(steps) do
		for _, el in ipairs(e.step) do
			if el[1] == 5 then
				spots[#spots + 1] = { el[3], el[4] }
			end
		end
	end

	for _, seed in ipairs({ 1, 20261101, 424242 }) do
		it("stays valid for " .. ACTIONS .. " random actions (seed " .. seed .. ")", function()
			local rand = Random(seed)
			local w = newWorld()
			local saved = {}
			local rt = RT.New(steps, data.quests, w.api, saved, { race = 1, class = 1, modules = data.modules })
			rt:Evaluate()
			local counts = {}
			local t = 0
			local function clock()
				t = t + 0.000002 -- every clock call stands for 2 µs of work (about the measured cost)
				return t
			end

			local function randomStep()
				local i = math.min(#rt.steps, rt.cur + rand(6) - 2)
				return rt.steps[math.max(1, i)]
			end

			local function play(step)
				for _, el in ipairs(step.data) do
					local v, q = el[1], el[2]
					if v == V.ACCEPT and not w.log[q] and not w.flagged[q] then
						w.log[q] = { complete = false }
						rt:OnAccepted(q)
					elseif v == V.COMPLETE and w.log[q] then
						w.log[q].complete = true
					elseif v == V.TURNIN and w.log[q] then
						w.log[q] = nil
						w.flagged[q] = true
					elseif v == V.TRAVEL then
						w.map = el[3]
					end
				end
			end

			local actions = {
				function()
					if rt.cur <= #rt.steps then
						play(rt.steps[rt.cur])
					end
					return "play"
				end,
				function()
					play(randomStep())
					return "play-other"
				end,
				function()
					local list = {}
					for q in pairs(w.log) do
						list[#list + 1] = q
					end
					table.sort(list)
					if #list > 0 then
						local q = list[rand(#list)]
						w.log[q] = nil
						rt:OnAbandoned(q)
					end
					return "abandon"
				end,
				function()
					rt:Check(rand(2) == 1 and randomStep().key or nil)
					return "check"
				end,
				function()
					rt:Skip(rand(2) == 1 and randomStep().key or nil)
					return "skip"
				end,
				function()
					rt:Back()
					return "back"
				end,
				function()
					rt:Undo()
					return "undo"
				end,
				function()
					rt:ResolveAbandon(rand(2) == 1 and "reaccept" or "skip")
					return "resolve"
				end,
				function()
					w.level = math.min(60, w.level + 1)
					return "level"
				end,
				function()
					local key = rt:Current() and rt:Current().key
					local order = {}
					for i, step in ipairs(rt.steps) do
						order[i] = step.key
					end
					saved = deepcopy(saved)
					rt = RT.New(steps, data.quests, w.api, saved, { race = 1, class = 1, modules = data.modules })
					for i, step in ipairs(rt.steps) do
						assert.are.equal(order[i], step.key, "reload changed the order")
					end
					rt:Evaluate()
					local now = rt:Current() and rt:Current().key
					if not saved.pending then
						-- after a reload only server progress made meanwhile may move the step forward
						assert.is_true(key == nil or now == nil or rt.index[now] >= rt.index[key], "reload moved back")
					else
						assert.are.equal(key, now, "reload changed the step during a question")
					end
					return "reload"
				end,
				function()
					local p = spots[rand(#spots)]
					w.x, w.y = p[1] + rand(401) - 201, p[2] + rand(401) - 201
					return "move"
				end,
				function()
					w.combat = not w.combat
					return "fight"
				end,
			}
			-- Playing the current step is the most common action, as in the game.
			local weights = { 6, 2, 1, 2, 2, 1, 2, 1, 1, 1, 2, 1 }
			local total = 0
			for _, x in ipairs(weights) do
				total = total + x
			end
			for k = 1, ACTIONS do
				local r, pick = rand(total), 1
				while r > weights[pick] do
					r = r - weights[pick]
					pick = pick + 1
				end
				local name = actions[pick]()
				counts[name] = (counts[name] or 0) + 1
				local before = rt.reordered
				for _ = 1, 10 do
					if not rt:RunJob(clock, 0.002) then
						break
					end
				end
				if rt.reordered ~= before then
					counts.reorder = (counts.reorder or 0) + 1
				end
				rt:Evaluate()
				check(rt, w, ("seed %d action %d (%s)"):format(seed, k, name))
			end
			for _, name in ipairs({ "play", "abandon", "check", "skip", "back", "undo", "resolve", "reload", "move" }) do
				assert.is_true((counts[name] or 0) > 50, name .. " ran only " .. tostring(counts[name]))
			end
			-- measured 4 to 8 applied reorders per seed (the rest: no clear gain, a question waits, the player
			-- went back, the current step is no movable quest step); every action after one runs on the new order
			assert.is_true((counts.reorder or 0) >= 3, "reordered only " .. tostring(counts.reorder))
			io.stdout:write(
				("\n[replan] seed %d: %d reorders applied in %d actions"):format(seed, counts.reorder or 0, ACTIONS)
			)
		end)
	end
end)
