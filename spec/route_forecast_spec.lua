-- SPDX-License-Identifier: GPL-3.0-or-later
-- Time forecast (Welle 4, task 4): values only from enough real runs, else "collecting"; module runs
-- measured as active play and handed to the collector as split records; the own XP rate for the time
-- to the next level.
local wow = require("spec.helpers.wow")

local function records(ns, kind)
	local store = ns.Collector.own
	store:Flush()
	local out = {}
	for seq = store.db.first, store.db.seq do
		for line in ((store.db.chunks[seq] or "") .. "\n"):gmatch("(.-)\n") do
			if line:match("^" .. kind .. "\t") then
				local f = {}
				for v in (line .. "\t"):gmatch("([^\t]*)\t") do
					f[#f + 1] = v
				end
				out[#out + 1] = f
			end
		end
	end
	return out
end

-- Gives every module of the Alliance data a measured time.
local function measure(ns, runs, seconds)
	local data = ns.Routes.Load("Alliance")
	for key in pairs(data.modules) do
		data.times[key] = { runs, seconds }
	end
	return data
end

describe("Forecast rules (pure)", function()
	wow.reset({})
	local F = wow.loadFiles({ "Braindead4Ever/Routes/Forecast.lua" }).Forecast
	-- Route of two modules: a (steps 1-4), b (steps 5-6); the player is at step 2.
	local function rt(cur)
		local steps = {}
		for i = 1, 6 do
			steps[i] = { module = i <= 4 and "a" or "b", lv = i }
		end
		return { steps = steps, cur = cur }
	end

	it("collects data while a module has fewer runs than the minimum", function()
		assert.are.same({ state = "collecting" }, F.Route(rt(2), {}))
		local few = { a = { F.MIN_RUNS, 1000 }, b = { F.MIN_RUNS - 1, 500 } }
		assert.are.same({ state = "collecting" }, F.Route(rt(2), few))
	end)

	it("sums the rest of the current module and the following modules", function()
		local t = { a = { 7, 1000 }, b = { F.MIN_RUNS, 500 } }
		local r = F.Route(rt(2), t)
		assert.are.equal("ready", r.state)
		assert.are.equal(750 + 500, r.seconds, "three of four steps of a, all of b")
		assert.are.equal(F.MIN_RUNS, r.runs)
		assert.are.equal(6, r.level)
		assert.is_nil(r.plan, "no clean run of the module: no comparison")
	end)

	it("compares a clean module run with the median", function()
		local t = { a = { 7, 1000 }, b = { 7, 500 } }
		local r = F.Route(rt(3), t, { m = "a", secs = 300, clean = true })
		assert.are.same({ module = "a", delta = 200 }, r.plan, "half of a planned at 500 s, played in 300 s")
		assert.is_nil(F.Route(rt(3), t, { m = "a", secs = 300, clean = false }).plan)
	end)

	it("gives the time to the next level only after enough active play", function()
		assert.are.equal("collecting", F.Level({ secs = F.RATE_MIN - 1, xp = 5000 }, 1000).state)
		assert.are.equal("collecting", F.Level({ secs = 3600, xp = 0 }, 1000).state)
		assert.are.equal("collecting", F.Level(nil, 1000).state)
		local l = F.Level({ secs = 3600, xp = 12000 }, 6000)
		assert.are.same({ state = "ready", seconds = 1800, perHour = 12000 }, l)
	end)

	it("keeps the rate to the recent window", function()
		local r = {}
		F.Add(r, F.RATE_WINDOW, 10000)
		F.Add(r, F.RATE_WINDOW, 30000)
		assert.are.equal(F.RATE_WINDOW, r.secs)
		assert.are.equal(20000, r.xp)
	end)
end)

describe("Time forecast in the route", function()
	it("reports 'collecting' without measured module times and values with them", function()
		local ns = wow.session()
		local f = ns.Route.Forecast()
		assert.are.equal("collecting", f.state)
		assert.is_nil(f.seconds)
		assert.are.equal("collecting", f.nextLevel.state)
		assert.are.equal("collecting data", ns.L.STATUS_COLLECTING)
		measure(ns, ns.Forecast.MIN_RUNS - 1, 3600)
		assert.are.equal("collecting", ns.Route.Forecast().state, "one run short")
		local data = measure(ns, ns.Forecast.MIN_RUNS, 3600)
		f = ns.Route.Forecast()
		assert.are.equal("ready", f.state)
		assert.is_true(f.seconds > 0)
		local modules = {}
		for _, s in ipairs(ns.Route.Runtime().steps) do
			modules[s.module] = true
		end
		local n = 0
		for _ in pairs(modules) do
			n = n + 1
		end
		assert.are.equal(n * 3600, f.seconds, "the player stands at the first step of the first module")
		assert.is_number(f.level)
		data.times = {}
	end)

	it("measures the XP rate from active play and gives the time to the next level", function()
		local ns = wow.session()
		local P = wow.world.player
		for _ = 1, 12 do
			wow.advance(60)
			P.xp = P.xp + 20
			wow.fire("PLAYER_XP_UPDATE", "player")
		end
		local f = ns.Route.Forecast()
		assert.are.equal("ready", f.nextLevel.state)
		assert.are.equal(1200, f.nextLevel.perHour, "240 XP in 720 s")
		assert.are.equal(math.floor((P.xpMax - P.xp) / (240 / 720) + 0.5), f.nextLevel.seconds)
	end)

	it("counts a long pause as idle, not as play", function()
		local ns = wow.session()
		wow.advance(5000)
		wow.fire("QUEST_LOG_UPDATE")
		assert.are.equal(ns.Forecast.IDLE_CAP, _G.BraindeadForeverCharDB.route.rate.secs)
	end)
end)

describe("Module runs", function()
	-- The player checks every step of the first module, one minute each, and walks into the next.
	local function playModule(ns, skipAt)
		local first = ns.Route.Current()
		local module, n = first.module, 0
		while ns.Route.Current() and ns.Route.Current().module == module do
			wow.advance(60)
			wow.fire("QUEST_LOG_UPDATE")
			n = n + 1
			if n == skipAt then
				ns.Route.Skip()
			else
				ns.Route.Check()
			end
		end
		return module, n
	end

	it("hands a clean run to the collector as a split record with active seconds and mode", function()
		local ns = wow.session()
		local module, n = playModule(ns)
		local splits = records(ns, "split")
		assert.are.equal(1, #splits)
		-- kind, dt, map, x, y, module, seconds, mode (tools/routekit/observe.py)
		assert.are.same({ module, tostring(n * 60), "speed" }, { splits[1][6], splits[1][7], splits[1][8] })
		assert.are.equal("", splits[1][3], "no position")
	end)

	it("leaves out a run with a skipped step", function()
		local ns = wow.session()
		playModule(ns, 3)
		assert.are.same({}, records(ns, "split"))
	end)

	it("leaves out a run that did not start at the module's first step", function()
		local ns = wow.session()
		ns.Route.Check()
		local rt = ns.Route.Runtime()
		rt.saved.split.clean = false -- like an entry in the middle of a module after /reload
		playModule(ns)
		assert.are.same({}, records(ns, "split"))
	end)

	it("keeps the run over /reload", function()
		local ns = wow.session()
		for _ = 1, 3 do
			wow.advance(60)
			wow.fire("QUEST_LOG_UPDATE")
			ns.Route.Check()
		end
		local secs = ns.Route.Runtime().saved.split.secs
		assert.are.equal(180, secs)
		wow.fire("PLAYER_LOGOUT")
		ns = wow.session({
			char = _G.BraindeadForeverCharDB,
			saved = _G.BraindeadForeverDB,
			collect = _G.BraindeadForeverCollectDB,
		})
		assert.are.equal(180, ns.Route.Runtime().saved.split.secs)
		assert.is_true(ns.Route.Runtime().saved.split.clean)
	end)
end)
