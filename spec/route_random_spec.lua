-- SPDX-License-Identifier: GPL-3.0-or-later
-- Random sequences on the real Elwynn route (owner wish 10, 2026-11-01): accept, abandon, play, check,
-- skip, back, undo, answer the abandon question, level up and /reload in any order. After every action
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
	local w = { flagged = {}, log = {}, level = 1, map = 1429 }
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
	}
	return w
end

describe("Route runtime under random actions", function()
	wow.reset({})
	local ns = wow.loadFiles({
		"Pathmark/Routes/Routes.lua",
		"Pathmark/Routes/Data_Alliance.lua",
		"Pathmark/Routes/XP.lua",
		"Pathmark/Routes/Runtime.lua",
	})
	local RT = ns.Runtime
	local data = ns.Routes.Load("Alliance")
	-- Elwynn and the first core blocks: long enough for chains, short enough for thousands of actions.
	local all = ns.Routes.Steps("Alliance", "speed", 1, 1)
	local steps = {}
	for i = 1, 160 do
		steps[i] = all[i]
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
	end

	for _, seed in ipairs({ 1, 20261101, 424242 }) do
		it("stays valid for " .. ACTIONS .. " random actions (seed " .. seed .. ")", function()
			local rand = Random(seed)
			local w = newWorld()
			local saved = {}
			local rt = RT.New(steps, data.quests, w.api, saved, { race = 1, class = 1, modules = data.modules })
			rt:Evaluate()
			local counts = {}

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
					saved = deepcopy(saved)
					rt = RT.New(steps, data.quests, w.api, saved, { race = 1, class = 1, modules = data.modules })
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
			}
			-- Playing the current step is the most common action, as in the game.
			local weights = { 6, 2, 1, 2, 2, 1, 2, 1, 1, 1 }
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
				rt:Evaluate()
				check(rt, w, ("seed %d action %d (%s)"):format(seed, k, name))
			end
			for _, name in ipairs({ "play", "abandon", "check", "skip", "back", "undo", "resolve", "reload" }) do
				assert.is_true((counts[name] or 0) > 50, name .. " ran only " .. tostring(counts[name]))
			end
		end)
	end
end)
