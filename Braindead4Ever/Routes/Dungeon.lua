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

-- Routes/Dungeon.lua: dungeon hint (owner wish 11, Welle 4 task 2). Pure Lua, no WoW API: reads the
-- route runtime and the compiled dungeon tables (docs/ROUTE-FORMAT.md §Compiled form). Interface and
-- rules: docs/ROUTE-RUNTIME.md §Dungeon hint.
--
-- A dungeon is suggested as an optional step when the character's level lies in its band and givers
-- of its quests are on the way: within ON_WAY_YARDS of a goto point of the route from the current step
-- on, as long as the route stays in the band. In speed mode only when the XP balance justifies it. The
-- hint never changes the route: skipping it only hides it.
--
-- XP (brain chapter 14 §4.3, Forever beta notes #4/#5): the compiled quest XP already has the Forever
-- rule (the part above a normal quest of the same level is halved, tools/routekit/compiler.py); here
-- the Classic reduction by level difference is applied (Routes/XP.lua). Kill XP inside the dungeon
-- (about +20 % in Forever) is not counted: the number of creatures per run is not measured.
-- Balance in speed mode: need = XP the route lacks up to the next zone (Runtime:Balance, shortfall);
-- covers = min(gain, need); surplus = gain beyond need; balance = covers - surplus. The time a run
-- costs only pays when the route needs the XP (else the player would be faster on the route): a
-- dungeon is justified when balance > 0.
local _, ns = ...
local R, XP = ns.Routes, ns.XP
local V = R.VERB

local DG = {}
ns.Dungeon = DG

-- Chosen value, measured against the route data (docs/ROUTE-RUNTIME.md §Dungeon hint): givers on the
-- route lie within 310 yards of a goto point, the capitals next to a route 306 to 1084 yards away,
-- Stormwind from Westfall 1443 yards and more.
DG.ON_WAY_YARDS = 1200

-- Quests the route hands in, step index of the turn-in (from the current step on, not skipped).
local function Turnins(rt, blocked)
	local at = {}
	for i = rt.cur or 1, #rt.steps do
		for _, el in ipairs(rt.steps[i].els) do
			local q = el[1] == V.TURNIN and el[2]
			if q and not at[q] and not blocked[q] then
				at[q] = i
			end
		end
	end
	return at
end

-- Groups of a dungeon quest are met at step index i when one quest per group is handed in already,
-- or the route hands it in at or before i.
local function Met(rt, pre, i, turnins)
	for _, group in ipairs(pre or {}) do
		local ok = false
		for _, m in ipairs(group) do
			if rt.world.IsFlagged(m) or (turnins[m] and turnins[m] <= i) then
				ok = true
				break
			end
		end
		if not ok then
			return false
		end
	end
	return true
end

-- Where the route passes a giver closest, from the current step on while the planned level stays in
-- the band: the goto point (same continent) nearest to the giver at which the quest can be taken,
-- within ON_WAY_YARDS. Returns yards and step index, or nil.
local function Pass(rt, maps, dq, hi, turnins)
	local inst = maps[dq[4]]
	if inst == nil then
		return nil
	end
	local best, at
	for i = rt.cur or 1, #rt.steps do
		local s = rt.steps[i]
		if s.lv and s.lv > hi then
			break
		end
		for _, el in ipairs(s.els) do
			if el[1] == V.GOTO and maps[el[2]] == inst then
				local d = math.sqrt((el[3] - dq[5]) ^ 2 + (el[4] - dq[6]) ^ 2)
				if d <= DG.ON_WAY_YARDS and (not best or d < best) and Met(rt, dq.pre, i, turnins) then
					best, at = d, i
				end
			end
		end
	end
	return best, at
end

-- Hints for the current state. opts: mode ("speed" | "explorer"), level, race, class, balance
-- (Runtime:Balance()), skipped ({ [instanceID] = true }). Returns a list sorted by the first pickup.
function DG.Hints(rt, data, opts)
	local out = {}
	if not (rt and data and data.dungeons and data.dquests and rt.cur and rt.cur <= #rt.steps) then
		return out
	end
	local level, maps = opts.level or 1, data.maps or {}
	local blocked = rt:Blocked()
	local turnins = Turnins(rt, blocked)
	local zone = opts.balance and opts.balance.zone
	local need = zone and zone.shortfall or 0
	for id, d in pairs(data.dungeons) do
		if not (opts.skipped and opts.skipped[id]) and level >= d.lo and level <= d.hi then
			local quests, gain, first = {}, 0, nil
			for _, q in ipairs(d.quests) do
				local dq = data.dquests[q]
				local applies = dq and (not opts.race or R.Applies(dq, opts.race, opts.class))
				if applies and not rt.world.IsFlagged(q) and (dq[2] or 1) <= level then
					local inLog = rt.world.InLog(q)
					local yards, at
					if not inLog then
						yards, at = Pass(rt, maps, dq, d.hi, turnins)
					end
					if inLog or yards then
						local xp = XP.QuestXP(dq[3], dq[1], level)
						gain = gain + xp
						quests[#quests + 1] = {
							q = q,
							level = dq[1],
							xp = xp,
							map = dq[4],
							wx = dq[5],
							wy = dq[6],
							state = inLog and "log" or "take",
							step = at and rt.steps[at].key or nil,
							yards = yards and math.floor(yards + 0.5) or nil,
						}
						if at and (not first or at < first) then
							first = at
						end
					end
				end
			end
			local takes = false
			for _, e in ipairs(quests) do
				takes = takes or e.state == "take"
			end
			if takes then
				local covers = math.min(gain, need)
				local surplus = math.max(0, gain - need)
				local balance = covers - surplus
				local justified = balance > 0
				if opts.mode ~= "speed" or justified then
					table.sort(quests, function(a, b)
						return a.q < b.q
					end)
					out[#out + 1] = {
						id = id,
						area = d.area,
						min = d.min,
						lo = d.lo,
						hi = d.hi,
						entrance = d.entrance,
						quests = quests,
						first = first,
						gain = gain,
						need = need,
						balance = balance,
						justified = justified,
					}
				end
			end
		end
	end
	table.sort(out, function(a, b)
		if (a.first or 0) ~= (b.first or 0) then
			return (a.first or 0) < (b.first or 0)
		end
		return a.id < b.id
	end)
	return out
end
