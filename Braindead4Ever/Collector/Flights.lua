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

-- Collector/Flights.lua: flight legs in the exchange (plan "Flugdaten im Austausch", Welle 11,
-- 2026-11-03; docs/ROUTE-FORMAT.md §Flights in the exchange). Every installation keeps the direct
-- flight legs it knows, from its own flight masters and landings, from other players and from the
-- facts (Routes/Data_Flights.lua), and passes on only what others may still lack, so the traffic
-- falls as the network becomes known. Plain Lua 5.1 without WoW API: clock and facts are passed in,
-- so the tests and the spread simulation (spec/helpers/spread.lua) run this exact code.
-- Rules:
--   message   "h" (Proto.lua): from, to, seconds of a flight without a stop, 0 = connection seen
--   sources   own observation (once), each sender once per session, the facts (once)
--   measures  own and received seconds, plus the flights the facts measured
--   saturated a connection goes out only while the leg has fewer than SOURCES_MIN sources, seconds
--             only while it has fewer than SOURCES_MIN sources or fewer than MEASURES_MIN measures
--   checks    both flight points in the facts or seen at an own flight master; not on two
--             continents; seconds within SECONDS_MIN..SECONDS_MAX and MODEL_LOW..MODEL_HIGH times the
--             model value (straight distance times the facts' seconds per yard). Seconds that cannot
--             be checked (a point without a position in the facts) count as the connection only
--   relay     per session every leg at most once, only on the hidden channel, own legs first, then
--             the newest, one message per RELAY_GAP; a leg heard on the channel in this session is
--             not relayed (someone just told everybody online)
--   export    received messages that were taken, under the export key "flights"
-- Sender names are keys in session tables only and never reach the vault.
local _, ns = ...

local Flights = {}
Flights.__index = Flights
ns.Flights = Flights

-- Chosen values (plan Welle 11, decisions 3 and 4; docs/ROUTE-FORMAT.md lists them).
Flights.SOURCES_MIN = 3 -- independent sources after which a connection is not sent any more
Flights.MEASURES_MIN = 5 -- measured flights after which seconds are not sent any more
Flights.MODEL_LOW = 0.3 -- seconds below this share of the model value are not a flight
Flights.MODEL_HIGH = 3 -- nor above this multiple
Flights.SECONDS_MIN = 5 -- as tools/routekit/observe.py: a landing outside these is a broken pair
Flights.SECONDS_MAX = 1800
Flights.RELAY_GAP = 10 -- seconds between two relayed legs of one client, as Runs.RELAY_GAP
Flights.LEGS_MAX = 1000 -- legs in the vault (the facts know 99 for both factions)
Flights.NODES_MAX = 500 -- flight points seen at own flight masters
Flights.EXPORT_MAX = 2000 -- received messages kept for the export; the oldest give way
Flights.PAIRS_MAX = 5000 -- (sender, leg) pairs remembered per session; beyond that the list starts over

local floor, sqrt = math.floor, math.sqrt
local EMPTY = { nodes = {}, legs = {} }

local function Key(a, b)
	return a .. ">" .. b
end

local function Ends(key)
	local a, b = key:match("^(%d+)>(%d+)$")
	return tonumber(a), tonumber(b)
end

-- Median of a list of seconds, or nil.
local function Median(list)
	if not list or #list == 0 then
		return nil
	end
	local s = {}
	for i, v in ipairs(list) do
		s[i] = v
	end
	table.sort(s)
	return s[floor((#s + 1) / 2)]
end

-- db: table in SavedVariables, changed in place. opts: clock() seconds (required), facts = the table of
-- Routes/Data_Flights.lua (default ns.FlightFacts), proto = Proto.lua (default ns.Proto).
function Flights.New(db, opts)
	opts = opts or {}
	local f = setmetatable({
		db = db,
		clock = assert(opts.clock, "Flights.New: clock required"),
		facts = opts.facts or ns.FlightFacts or EMPTY,
		proto = opts.proto or ns.Proto,
	}, Flights)
	db.legs = type(db.legs) == "table" and db.legs or {} -- "a>b" -> { s, m, o, t, at }
	db.nodes = type(db.nodes) == "table" and db.nodes or {} -- flight point -> true
	db.list = type(db.list) == "table" and db.list or {}
	db.first = type(db.first) == "number" and db.first or 1
	db.last = type(db.last) == "number" and db.last or 0
	db.acked = type(db.acked) == "number" and db.acked or 0
	db.tick = type(db.tick) == "number" and db.tick or 0
	f.nlegs, f.nnodes = 0, 0
	for key, leg in pairs(db.legs) do
		if type(key) == "string" and Ends(key) and type(leg) == "table" then
			leg.s, leg.m = tonumber(leg.s) or 0, tonumber(leg.m) or 0
			leg.t = type(leg.t) == "table" and leg.t or {}
			f.nlegs = f.nlegs + 1
		else
			db.legs[key] = nil
		end
	end
	for _ in pairs(db.nodes) do
		f.nnodes = f.nnodes + 1
	end
	f:StartSession()
	return f
end

-- Forever beta trap (chapter 15 §7): continue with the table the global holds now.
function Flights:Rebind(tbl)
	if tbl == self.db then
		return tbl
	end
	if type(tbl) ~= "table" then
		tbl = {}
	end
	for k, v in pairs(self.db) do
		tbl[k] = v
	end
	self.db = tbl
	return tbl
end

-- A new session (login or /reload): every leg may go out once more, own legs first, then the
-- newest first.
function Flights:StartSession()
	self.heard, self.pairs, self.npairs = {}, {}, 0
	self.nextRelay, self.qi = 0, 1
	local mine, rest = {}, {}
	for key, leg in pairs(self.db.legs) do
		local list = leg.o and mine or rest
		list[#list + 1] = key
	end
	local legs = self.db.legs
	local function newest(a, b)
		return (legs[a].at or 0) > (legs[b].at or 0)
	end
	table.sort(mine, newest)
	table.sort(rest, newest)
	for _, key in ipairs(rest) do
		mine[#mine + 1] = key
	end
	self.queue = mine
	self.stats = { heard = 0, new = 0, dup = 0, implausible = 0, full = 0, relayed = 0 }
end

-- Independent sources and measured flights this client knows for a leg.
function Flights:Known(key)
	local leg, fact = self.db.legs[key], self.facts.legs[key]
	local sources, measures = 0, 0
	if leg then
		sources = leg.s + (leg.o and 1 or 0)
		measures = leg.m
	end
	if fact then
		sources, measures = sources + 1, measures + fact
	end
	return sources, measures
end

-- True while a message about the leg with these seconds adds something for others.
function Flights:Wants(key, secs)
	local sources, measures = self:Known(key)
	if sources < Flights.SOURCES_MIN then
		return true
	end
	return secs > 0 and measures < Flights.MEASURES_MIN
end

-- Checks a leg. Returns the seconds to count (0 = the connection only) or nil when it cannot be a
-- flight leg.
function Flights:Check(a, b, secs)
	if a == b then
		return nil
	end
	local nodes, seen = self.facts.nodes, self.db.nodes
	local na, nb = nodes[a], nodes[b]
	if not ((na or seen[a]) and (nb or seen[b])) then
		return nil
	end
	local placed = na and nb and na[1] and nb[1]
	if placed and na[1] ~= nb[1] then
		return nil -- no flight crosses from one continent to another
	end
	if secs == 0 then
		return 0
	end
	if secs < Flights.SECONDS_MIN or secs > Flights.SECONDS_MAX then
		return nil
	end
	local perYard = self.facts.secondsPerYard
	if not (placed and perYard) then
		return 0
	end
	local dx, dy = na[2] - nb[2], na[3] - nb[3]
	local model = sqrt(dx * dx + dy * dy) * perYard
	if secs < model * Flights.MODEL_LOW or secs > model * Flights.MODEL_HIGH then
		return nil
	end
	return secs
end

local function Leg(self, key)
	local legs = self.db.legs
	local leg = legs[key]
	if not leg then
		if self.nlegs >= Flights.LEGS_MAX then
			return nil
		end
		leg = { s = 0, m = 0, t = {} }
		legs[key] = leg
		self.nlegs = self.nlegs + 1
	end
	self.db.tick = self.db.tick + 1
	leg.at = self.db.tick
	return leg
end

local function Measure(leg, secs)
	leg.m = leg.m + 1
	local t = leg.t
	t[#t + 1] = secs
	while #t > Flights.MEASURES_MIN do
		table.remove(t, 1)
	end
end

local function Keep(self, msg)
	local db = self.db
	db.last = db.last + 1
	db.list[db.last] = msg
	while db.last - db.first + 1 > Flights.EXPORT_MAX do
		db.list[db.first] = nil
		db.first = db.first + 1
	end
end

-- Flight points the open flight master shows as known (TAXIMAP_OPENED): they exist.
function Flights:SeeNodes(list)
	for _, node in ipairs(list) do
		if not self.db.nodes[node] and self.nnodes < Flights.NODES_MAX then
			self.db.nodes[node] = true
			self.nnodes = self.nnodes + 1
		end
	end
end

-- An own observation: a leg of the flight master's map (secs 0) or a flight without a stop. Counted
-- once as an own source; seconds count as a measure. offer = the exchange sends it now (it is not
-- relayed again this session); otherwise the leg is the next one to relay. Returns the message and the
-- seconds it carries when it adds something for others, else nil.
function Flights:Own(a, b, secs, offer)
	local ok = self:Check(a, b, secs)
	if not ok then
		return nil
	end
	local key = Key(a, b)
	local wanted = self:Wants(key, ok)
	local leg = Leg(self, key)
	if not leg then
		return nil
	end
	leg.o = true
	if ok > 0 then
		Measure(leg, ok)
	end
	if not wanted then
		return nil
	end
	if offer then
		self.heard[key] = true
	else
		table.insert(self.queue, self.qi, key)
	end
	return self.proto.Format("h", a, b, ok), ok
end

-- A flight message from another player. find = Proto.Parse(msg); who = sender key (session only);
-- channel = it came over the hidden channel, so everybody online heard it.
-- Returns "new", "dup", "implausible" or "full".
function Flights:Hear(find, who, channel)
	local a, b = find[1], find[2]
	local key, st = Key(a, b), self.stats
	st.heard = st.heard + 1
	local ok = self:Check(a, b, find[3])
	if not ok then
		st.implausible = st.implausible + 1
		return "implausible" -- and it does not stop the relay of the leg: nobody learnt anything
	end
	if channel then
		self.heard[key] = true
	end
	if who then
		local pair = who .. ";" .. key
		if self.pairs[pair] then
			st.dup = st.dup + 1
			return "dup" -- one sender counts once per leg and session
		end
		if self.npairs >= Flights.PAIRS_MAX then
			self.pairs, self.npairs = {}, 0
		end
		self.pairs[pair], self.npairs = true, self.npairs + 1
	end
	local leg = Leg(self, key)
	if not leg then
		st.full = st.full + 1
		return "full"
	end
	leg.s = leg.s + 1
	if ok > 0 then
		Measure(leg, ok)
	end
	Keep(self, self.proto.Format("h", a, b, ok))
	if not channel then
		self.queue[#self.queue + 1] = key -- from the group or the guild: the channel has not heard it
	end
	st.new = st.new + 1
	return "new"
end

-- The next leg to relay on the channel, as a message, or nil (gap not over, nothing left this
-- session). Seconds: the median of the measures kept, 0 when there are none.
function Flights:NextRelay()
	local now = self.clock()
	if now < self.nextRelay then
		return nil
	end
	local q, legs = self.queue, self.db.legs
	while self.qi <= #q do
		local key = q[self.qi]
		self.qi = self.qi + 1
		local leg = legs[key]
		if leg and not self.heard[key] then
			local secs = Median(leg.t) or 0
			if self:Wants(key, secs) then
				self.heard[key] = true
				self.nextRelay = now + Flights.RELAY_GAP
				self.stats.relayed = self.stats.relayed + 1
				local a, b = Ends(key)
				return self.proto.Format("h", a, b, secs)
			end
		end
	end
	return nil
end

-- Received messages kept after seq `after` (0 = all), oldest first, the first and the last seq included.
function Flights:Since(after)
	local out, db = {}, self.db
	local from = math.max(db.first, (after or 0) + 1)
	local last = after or 0
	for seq = from, db.last do
		if db.list[seq] then
			out[#out + 1] = db.list[seq]
		end
		last = seq
	end
	return out, last, from
end

-- The player copied an export up to this seq.
function Flights:Ack(seq)
	if type(seq) == "number" and seq > self.db.acked then
		self.db.acked = seq
	end
end
