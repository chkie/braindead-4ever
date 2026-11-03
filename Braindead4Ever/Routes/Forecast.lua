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

-- Routes/Forecast.lua: time forecast (Welle 4, task 4). Pure Lua, no WoW API. Two parts:
--   route  time to the end of the route from the measured module times (compiled `times`, median of
--          real runs, tools/routekit/observe.py) and the comparison with the median of the current
--          module ("4 minutes ahead of plan")
--   level  time to the next level from the player's own XP rate (active play only)
-- Each part shows values only with enough real data; until then its state is "collecting" and the
-- window shows L.STATUS_COLLECTING ("collecting data"), never an invented number (owner principle
-- "Mehrwert statt Placebo"). Interface and rules: docs/ROUTE-RUNTIME.md §Time forecast.
local _, ns = ...

local F = {}
ns.Forecast = F

-- Chosen values, not measured. MIN_RUNS: real runs per module before its median counts (the plan's
-- validation uses 5 test runs; a module is "stable" from 20). IDLE_CAP: a longer gap between two game
-- events counts as this much play (AFK is not play). RATE_MIN: seconds of active play before the own
-- XP rate counts. RATE_WINDOW: the rate follows the recent pace; older play fades out beyond it.
F.MIN_RUNS = 5
F.IDLE_CAP = 300
F.RATE_MIN = 600
F.RATE_WINDOW = 7200

-- Step index range of every module in the route: { [module] = { first, last } }.
function F.Ranges(rt)
	local r = {}
	for i, s in ipairs(rt.steps) do
		local m = r[s.module]
		if not m then
			r[s.module] = { first = i, last = i }
		else
			m.last = i
		end
	end
	return r
end

-- Route part. times: { [module] = { runs, medianSeconds } }; split: the current module run
-- { m = module, secs, clean } or nil. Returns { state, seconds, level, runs, plan } where plan is
-- { module, delta } (delta > 0: ahead of the median) or nil.
function F.Route(rt, times, split)
	local i = rt.cur
	if not i or i > #rt.steps then
		return { state = "done" }
	end
	local ranges = F.Ranges(rt)
	local seen, order = {}, {}
	for j = i, #rt.steps do
		local m = rt.steps[j].module
		if not seen[m] then
			seen[m] = true
			order[#order + 1] = m
		end
	end
	local total, runs, last = 0, nil, nil
	for k, m in ipairs(order) do
		local t = times and times[m]
		if not t or (t[1] or 0) < F.MIN_RUNS or not t[2] then
			return { state = "collecting" }
		end
		local r = ranges[m]
		local share = 1
		if k == 1 then
			share = (r.last - i + 1) / (r.last - r.first + 1)
		end
		total = total + t[2] * share
		runs = math.min(runs or t[1], t[1])
		last = m
	end
	local out = { state = "ready", seconds = math.floor(total + 0.5), runs = runs }
	for j = #rt.steps, 1, -1 do
		if rt.steps[j].module == last and rt.steps[j].lv then
			out.level = rt.steps[j].lv
			break
		end
	end
	local cur = rt.steps[i].module
	if split and split.m == cur and split.clean then
		local r, t = ranges[cur], times[cur]
		local expected = t[2] * (i - r.first) / (r.last - r.first + 1)
		out.plan = { module = cur, delta = math.floor(expected - split.secs + 0.5) }
	end
	return out
end

-- Level part. rate: { secs, xp } of active play; toLevel: XP to the next level.
function F.Level(rate, toLevel)
	local secs, xp = rate and rate.secs or 0, rate and rate.xp or 0
	if secs < F.RATE_MIN or xp <= 0 or not toLevel then
		return { state = "collecting" }
	end
	local perSecond = xp / secs
	return {
		state = "ready",
		seconds = math.floor(toLevel / perSecond + 0.5),
		perHour = math.floor(perSecond * 3600 + 0.5),
	}
end

-- Adds active play time and XP to a rate, keeping it to the recent window.
function F.Add(rate, secs, xp)
	rate.secs = (rate.secs or 0) + (secs or 0)
	rate.xp = (rate.xp or 0) + (xp or 0)
	if rate.secs > F.RATE_WINDOW then
		local k = F.RATE_WINDOW / rate.secs
		rate.secs, rate.xp = F.RATE_WINDOW, rate.xp * k
	end
end
