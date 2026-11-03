-- SPDX-License-Identifier: GPL-3.0-or-later
-- "Your run" (Welle 8) against the project budget (brain chapter 12 §9: under 0.1 ms per frame on
-- average, at most 10 MB). Offline on stock Lua 5.1 with stand-ins: it shows the order of magnitude;
-- the binding numbers come from C_AddOnProfiler in the client (gate T16). The measured values go to
-- the test output.
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

local function report(fmt, ...)
	io.stdout:write("\n[stats] " .. fmt:format(...))
end

local FPS, OPEN = 60, 10 -- the page or the card stays open 10 s at 60 frames per second

-- A full run vault: 5000 sections of other players, all of the player's class (worst case: every text
-- counts), levels 1 to 30 and route modules, all ways of play.
local function vault()
	local texts, modes = {}, { "s", "e", "f" }
	local i = 0
	while #texts < 5000 do
		i = i + 1
		local tok = ("p%05d"):format(i)
		for l = 1, 30 do
			if #texts >= 5000 then
				break
			end
			local mode = modes[(i % 3) + 1]
			if l % 3 == 0 then
				texts[#texts + 1] = ("s;1;%s;1;1;%s;m;%d;1;%d;900;%d;%d;20762"):format(
					tok,
					mode,
					1000 + l,
					300 + i % 97,
					60 + i % 41,
					l
				)
			else
				texts[#texts + 1] = ("s;1;%s;1;1;%s;l;%d;0;%d;1500;%d;%d;20762"):format(
					tok,
					mode,
					l,
					600 + (i * 7) % 900,
					60 + i % 41,
					l + 1
				)
			end
		end
	end
	return { schema = 1, install = "inst00000000", runs = { list = texts, first = 1, last = #texts, mine = {} } }
end

-- 29 whole levels with every detail and 60 module runs: what a character at level 30 keeps.
local function veteran()
	local lv, mods = {}, {}
	for l = 1, 29 do
		lv[l] = {
			s = 1500 + l * 37.25,
			x = 4000 + l,
			q = 2500,
			k = 1300,
			c = 300.5,
			m = 600.25,
			f = 30,
			p = 120,
			n = 9,
			d = 1,
			b = 2,
			mo = "s",
			o = 95,
			full = true,
			day = 20762,
		}
	end
	for i = 1, 60 do
		mods[i] =
			{ num = 1000 + i, key = "a-speed-m" .. i, v = 1, s = 400 + i, o = 100, mo = "s", l = 2 + math.floor(i / 2) }
	end
	return {
		run = "mine01",
		stats = { schema = 1, lv = lv, mods = mods, recap = {} },
		route = { lvl = { l = 30, full = true, secs = 500, xp = 900, guided = 500, n = 4, d = 4 } },
	}
end

local function login(collect)
	return S.login({
		level = 30,
		char = veteran(),
		before = function()
			_G.PathmarkCollectDB = collect
		end,
	})
end

-- Real time for the time slices of the build (the stand-in clock stands still otherwise).
local function realClock()
	_G.debugprofilestop = function()
		return os.clock() * 1000
	end
end

-- Full collections until the count stands still: Lua 5.1 halves its string table once per full cycle,
-- so a single collect after a big run can show a negative difference.
local function settle()
	local last
	for _ = 1, 20 do
		collectgarbage("collect")
		local now = collectgarbage("count")
		if last and math.abs(now - last) < 1 then
			return now
		end
		last = now
	end
	return collectgarbage("count")
end

-- Runs the build to its end; returns the summed time, the number of slices, the longest slice and the
-- most vault texts one slice read.
local function drain(ns)
	local RS = ns.RunStats
	local d = RS.driver
	local total, frames, worst, most = 0, 0, 0, 0
	while rawget(d, "shown") do
		local job = RS.Job()
		local seq = job and job.seq
		local t0 = os.clock()
		d.scripts.OnUpdate(d, 1 / FPS)
		local ms = (os.clock() - t0) * 1000
		total, frames, worst = total + ms, frames + 1, math.max(worst, ms)
		if seq then
			local after = RS.Job() and RS.Job().seq or (job.last + 1)
			most = math.max(most, after - seq)
		end
	end
	return total, frames, worst, most
end

-- Wall-clock times on a shared CI runner vary by a factor of 3 to 5 (main run of PR #16: longest frame
-- 3.99 ms against 1.2 ms on the development machine). Noise only adds time, so the fastest of three runs
-- stands for the cost; the longest frame is reported, the slice size is what the test holds.
local RUNS = 3

describe("Your run: performance (offline)", function()
	it("closed page: nothing runs per frame; an event of the tally costs microseconds", function()
		local ns = login(vault())
		local RS = ns.RunStats
		assert.is_nil(_G.PathmarkStatsFrame)
		assert.is_false(rawget(RS.driver, "shown") == true) -- no OnUpdate runs while nothing waits
		local t = RS.Tally()
		local N = 200000
		local start = os.clock()
		for i = 1, N do
			t:Flag(i, "move", i % 2 == 0)
			t:Play(i + 0.5, 0.5, 0.5, i % 5 == 0 and 40 or nil)
		end
		local us = (os.clock() - start) * 1e6 / (2 * N)
		-- a busy player: moving on and off once a second, two game events a second
		local perFrame = us * 3 / FPS / 1000
		report(
			"closed page: 0 per frame (no OnUpdate); an event of the tally %.3f µs, at 3 events per second %.5f ms per frame",
			us,
			perFrame
		)
		assert.is_true(perFrame < 0.001)
	end)

	it("open page with a full run vault: build and render under the budget on average", function()
		local ns, best
		for _ = 1, RUNS do
			ns = login(vault())
			realClock()
			collectgarbage("collect")
			local t0 = os.clock()
			SlashCmdList.PATHMARK("stats") -- builds the window, renders own values, starts the comparison
			local open = (os.clock() - t0) * 1000
			local build, frames, worst, most = drain(ns)
			local t1 = os.clock()
			for i = 2, 3 do -- the other two tabs
				_G["PathmarkStatsFrameTab" .. i].scripts.OnClick(_G["PathmarkStatsFrameTab" .. i])
			end
			local tabs = (os.clock() - t1) * 1000 / 2
			if not best or open + build < best.open + best.build then
				best = { open = open, build = build, frames = frames, worst = worst, most = most, tabs = tabs }
			end
		end
		local mean = (best.open + best.build) / (FPS * OPEN)
		report(
			"page open (fastest of %d): window and first render %.2f ms, comparison of 5000 sections %.2f ms in %d frames (longest %.2f ms, at most %d texts per frame), a tab %.2f ms",
			RUNS,
			best.open,
			best.build,
			best.frames,
			best.worst,
			best.most,
			best.tabs
		)
		report("page open for %d s: %.4f ms per frame on average (budget 0.1); afterwards 0 per frame", OPEN, mean)
		assert.is_true(mean < 0.1)
		assert.is_true(best.most <= ns.RunStats.SLICE) -- one frame reads at most SLICE texts
		assert.is_true(best.frames >= math.ceil(5000 / ns.RunStats.SLICE))
		assert.is_false(rawget(ns.RunStats.driver, "shown") == true)
		-- a change of the tally while the page is open (a quest, a death, a level-up): one refresh
		local N = 50
		local t2 = os.clock()
		for _ = 1, N do
			ns.StatsPage.Refresh()
		end
		local refresh = (os.clock() - t2) * 1000 / N
		report("refresh of the open page (on a change of the tally, at most every 0.5 s): %.2f ms", refresh)
		assert.is_true(refresh * 2 / FPS < 0.1) -- even two refreshes a second stay under budget
		assert.are.same({}, wow.errors)
	end)

	it("review card with a full run vault: under the budget on average", function()
		local best
		for _ = 1, RUNS do
			local ns = login(vault())
			realClock()
			ns.RunStats.Char().recap.pending = 30
			local t0 = os.clock()
			ns.StatsPage.TryRecap()
			local start = (os.clock() - t0) * 1000
			local build, frames, worst, most = drain(ns)
			assert.is_true(rawget(_G.PathmarkRecapFrame, "shown"))
			assert.is_true(most <= ns.RunStats.SLICE)
			if not best or start + build < best.start + best.build then
				best = { start = start, build = build, frames = frames, worst = worst }
			end
		end
		local mean = (best.start + best.build) / (FPS * OPEN)
		report(
			"review card (fastest of %d): %.2f ms to start, comparison %.2f ms in %d frames (longest %.2f ms); %.4f ms per frame over %d s",
			RUNS,
			best.start,
			best.build,
			best.frames,
			best.worst,
			mean,
			OPEN
		)
		assert.is_true(mean < 0.1)
	end)

	it("memory: comparison, tally of a level-30 character and the windows", function()
		local ns = login(vault())
		local before = settle()
		ns.RunStats.Request("measure", function() end) -- the comparison alone, without a window
		drain(ns)
		local after = settle()
		local cmp = after - before
		ns.StatsPage.Open()
		drain(ns)
		for i = 1, 3 do
			_G["PathmarkStatsFrameTab" .. i].scripts.OnClick(_G["PathmarkStatsFrameTab" .. i])
		end
		local page = settle() - after
		local index = ns.RunStats.Index()
		local groups, numbers = 0, 0
		for _, list in pairs(index.groups) do
			groups = groups + 1
			numbers = numbers + #list
		end
		-- the saved tally: count the bytes of its SavedVariables text (keys and values)
		local function size(t)
			local n = 0
			for k, v in pairs(t) do
				n = n + #tostring(k) + 4
				n = n + (type(v) == "table" and size(v) or #tostring(v))
			end
			return n
		end
		local sv = size(ns.RunStats.Char()) / 1024
		report("comparison of 5000 sections: +%.0f KB (%d groups, %d values)", cmp, groups, numbers)
		report(
			"page with all three tabs (60 rows): +%.0f KB in the stand-ins (client frames are counted by the client)",
			page
		)
		report("saved tally of a level-30 character with 60 module runs: about %.1f KB of SavedVariables text", sv)
		assert.is_true(cmp < 512)
		assert.is_true(page < 1024)
		assert.is_true(sv < 64)
	end)
end)
