--[[
Braindead Forever
Copyright (C) 2026 Braindead Forever contributors (see Git history)

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
-- SPDX-License-Identifier: GPL-3.0-or-later WITH AdditionRef-BraindeadForever-Ace3-Exception

-- Routes/Prereq.lua: prerequisites from player observations (Welle 4, task 3). Pure Lua, no WoW API.
-- The same rule runs offline in tools/routekit/prereq.py; tools/tests/fixtures/prereq_cases.json
-- holds the cases both must agree on. Rule and measurements: docs/ROUTE-RUNTIME.md §Prerequisites
-- from player data.
--
-- An observation of quest q is made when a player takes q or an NPC offers it:
--   token   hash of the random install ID and q: one player counts once per quest, observations of
--           different quests cannot be linked to each other
--   link    the quest turned in directly before at the NPC that gives q (0 = none)
--   unlock  that NPC had listed its offers before the turn-in, without q
--   d       quests already done (turned in shortly before, or checked candidates)
--   n       checked candidates not done although q was offered or taken (refutation)
-- Saved account-wide (BraindeadForeverDB.prereq): obs[q][token] = "link;unlock;d1.d2;n1.n2", ref[q] = "c1.c2".
local _, ns = ...

local P = {}
P.__index = P
ns.Prereq = P

-- Chosen values, not measured (same as tools/routekit/prereq.py).
P.MIN_LINKS = 2
P.MIN_SUPPORT = 3
P.MIN_NONE = 5
P.NONE_SHARE = 0.5
P.LIST_MAX = 10
P.LINK_SECONDS = 120
P.OBS_MAX = 20 -- observers kept per quest; later ones still refute

local function ids(s)
	local out = {}
	for x in (s or ""):gmatch("%d+") do
		out[#out + 1] = tonumber(x)
	end
	return out
end
P.Ids = ids

local function list(t, q)
	local out = {}
	for _, x in ipairs(t or {}) do
		x = tonumber(x)
		if x and x ~= q and #out < P.LIST_MAX then
			out[#out + 1] = x
		end
	end
	return out
end

-- db: table in SavedVariables, changed in place.
function P.New(db)
	db.obs = type(db.obs) == "table" and db.obs or {}
	db.ref = type(db.ref) == "table" and db.ref or {}
	return setmetatable({ db = db }, P)
end

-- Stable 6-character token from install ID and quest (djb2 modulo 2^31 - 1, base 36).
local ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyz"
function P.Token(install, q)
	local s = tostring(install) .. ":" .. tostring(q)
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + s:byte(i)) % 2147483647
	end
	local out = {}
	for i = 6, 1, -1 do
		local k = h % 36
		out[i] = ALPHABET:sub(k + 1, k + 1)
		h = math.floor(h / 36)
	end
	return table.concat(out)
end

-- Adds one observation; returns true when the result for q changed.
function P:Add(q, token, link, unlock, d, n)
	q = tonumber(q)
	if not q or type(token) ~= "string" or token == "" then
		return false
	end
	link = tonumber(link) or 0
	if link == q then
		link = 0
	end
	unlock = link ~= 0 and (unlock == true or unlock == 1)
	d, n = list(d, q), list(n, q)
	local before = { self:Result(q) }
	if #n > 0 then
		local ref = {}
		for _, c in ipairs(ids(self.db.ref[q])) do
			ref[c] = true
		end
		for _, c in ipairs(n) do
			ref[c] = true
		end
		local all = {}
		for c in pairs(ref) do
			all[#all + 1] = c
		end
		table.sort(all)
		self.db.ref[q] = table.concat(all, ".")
	end
	local obs = self.db.obs[q] or {}
	local count = 0
	for _ in pairs(obs) do
		count = count + 1
	end
	if obs[token] or count < P.OBS_MAX then
		obs[token] = table.concat({ link, unlock and 1 or 0, table.concat(d, "."), table.concat(n, ".") }, ";")
		self.db.obs[q] = obs
	end
	local after = { self:Result(q) }
	return before[1] ~= after[1] or P.GroupKey(before[2]) ~= P.GroupKey(after[2])
end

function P.GroupKey(groups)
	local parts = {}
	for i, g in ipairs(groups or {}) do
		parts[i] = table.concat(g, ",")
	end
	return table.concat(parts, "|")
end

local function parse(v)
	local link, unlock, d, n = v:match("^(%d+);(%d);([%d%.]*);([%d%.]*)$")
	return tonumber(link) or 0, unlock == "1", ids(d), ids(n)
end

-- links, unlocks, done counts per candidate, refuted set and number of observers.
function P:Counts(q)
	local links, unlocks, done, refuted, observers = {}, {}, {}, {}, 0
	for _, c in ipairs(ids(self.db.ref[q])) do
		refuted[c] = true
	end
	for _, v in pairs(self.db.obs[q] or {}) do
		observers = observers + 1
		local link, unlock, d = parse(v)
		local seen = {}
		for _, c in ipairs(d) do
			seen[c] = true
		end
		if link ~= 0 then
			links[link] = (links[link] or 0) + 1
			unlocks[link] = (unlocks[link] or 0) + (unlock and 1 or 0)
			seen[link] = true
		end
		for c in pairs(seen) do
			done[c] = (done[c] or 0) + 1
		end
	end
	return links, unlocks, done, refuted, observers
end

-- state ("observed" | "observed-none" | "unknown"), groups ({ { id }, ... }), observers.
function P:Result(q)
	local links, unlocks, done, refuted, observers = self:Counts(q)
	local pre = {}
	for c, k in pairs(links) do
		if not refuted[c] and k >= P.MIN_LINKS and (unlocks[c] or 0) >= 1 and (done[c] or 0) >= P.MIN_SUPPORT then
			pre[#pre + 1] = c
		end
	end
	table.sort(pre)
	if #pre > 0 then
		local groups = {}
		for i, c in ipairs(pre) do
			groups[i] = { c }
		end
		return "observed", groups, observers
	end
	if observers >= P.MIN_NONE then
		local block = math.max(P.MIN_SUPPORT, P.NONE_SHARE * observers)
		for c, k in pairs(done) do
			if k >= block and not refuted[c] then
				return "unknown", {}, observers
			end
		end
		for c, k in pairs(links) do
			if k >= P.MIN_LINKS and not refuted[c] then
				return "unknown", {}, observers
			end
		end
		return "observed-none", {}, observers
	end
	return "unknown", {}, observers
end

-- Candidates for q: every quest some observer linked or reported as done, sorted.
function P:Candidates(q)
	local set = {}
	for _, v in pairs(self.db.obs[q] or {}) do
		local link, _, d = parse(v)
		if link ~= 0 then
			set[link] = true
		end
		for _, c in ipairs(d) do
			set[c] = true
		end
	end
	local out = {}
	for c in pairs(set) do
		out[#out + 1] = c
	end
	table.sort(out)
	return out
end

-- Every quest with a result other than "unknown": { [q] = { state, groups } }.
function P:Known()
	local out = {}
	for q in pairs(self.db.obs) do
		local state, groups = self:Result(q)
		if state ~= "unknown" then
			out[q] = { state = state, groups = groups }
		end
	end
	return out
end
