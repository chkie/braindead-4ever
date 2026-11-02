--[[
Pathmark
Copyright (C) 2026 Pathmark contributors (see Git history)

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
-- SPDX-License-Identifier: GPL-3.0-or-later WITH AdditionRef-Pathmark-Ace3-Exception

-- Collector/Runs.lua: run times in the exchange (plan "Laufzeiten im Austausch", 2026-11-02,
-- docs/RUN-TIMES.md). Every installation keeps the run sections it hears ("s" messages, Proto.lua)
-- in a vault of its own beside the received finds and passes them on, so one export brings the runs
-- of many players. Plain Lua 5.1 without WoW API: clock, server time, random and the XP table are
-- passed in, so the tests and the spread simulation (spec/runs_spec.lua) run this exact code.
-- Rules:
--   vault    PathmarkCollectDB.runs, at most VAULT_MAX sections; the oldest give way first
--   dedup    one section per (token, section); the same text again is a duplicate
--   conflict a different text for the same (token, section) drops both and blocks the key
--   band     seconds against the speedrun record pace (brain chapter 21 §3.4) and a chosen ceiling
--   senders  at most SENDER_MAX run messages per sender and SENDER_WINDOW, at most NEW_TOKENS_MAX
--            tokens a sender introduces per session (its "originals"); above that it is muted for runs
--   relay    per session every section goes out at most once, only on the hidden channel, own
--            sections first, then the newest, one message per RELAY_GAP; a section heard on the
--            channel in this session is not relayed (someone just told everybody online)
-- Sender names are keys in session tables only and never reach the vault.
local _, ns = ...

local Runs = {}
Runs.__index = Runs
ns.Runs = Runs

-- Chosen values, not measured (docs/RUN-TIMES.md lists them; the in-game measurement after
-- 2026-11-05 decides whether they stay).
Runs.VAULT_MAX = 5000 -- sections; about 60 bytes each, 300 KB in the SavedVariables
Runs.RELAY_GAP = 10 -- seconds between two relayed messages of one client (plan: 1 per 10 s)
Runs.SENDER_WINDOW = 300 -- seconds
Runs.SENDER_MAX = 40 -- run messages per sender and window: relay pace 30 plus own sections and margin
Runs.NEW_TOKENS_MAX = 150 -- tokens one sender may introduce per session (simulation peak 66, spec/runs_spec.lua)
Runs.BLOCKED_MAX = 2000 -- conflicting keys remembered; beyond that the list starts over
Runs.MIN_LEVEL_SECS = 60 -- no level takes less than a minute
Runs.MIN_MODULE_SECS = 20 -- the shortest route modules are a travel step and a turn-in
Runs.MAX_SECS = 48 * 3600 -- active play in one section; more is a stuck clock, not a run
Runs.RECORD_MARGIN = 1.5 -- allowed pace over the record pace (rested XP, groups, a fast record split)

-- Solo self-found records in Classic Era (speedrun.com API, read 2026-11-01; brain chapter 21 §3.4):
-- 1-20 in 5:02:59 (167,200 XP), 1-60 in 44:39:29 (4,084,700 XP). Levels below 20 use the first pace,
-- the others the second.
Runs.RECORDS = {
	{ below = 20, xp = 167200, secs = 5 * 3600 + 2 * 60 + 59 },
	{ below = 101, xp = 4084700, secs = 44 * 3600 + 39 * 60 + 29 },
}

local floor, concat = math.floor, table.concat

-- (token, section) of a stored message text, as Proto.Key builds it.
local function KeyOf(msg)
	local tok, kind, sec = msg:match("^s;%d+;([0-9a-z]+);[^;]*;[^;]*;[^;]*;([lm]);(%d+);")
	if tok then
		return concat({ "s", tok, kind, sec }, ";"), tok
	end
end
Runs.KeyOf = KeyOf

-- Highest XP per hour the band allows at a level.
function Runs.MaxRate(level)
	for _, r in ipairs(Runs.RECORDS) do
		if level < r.below then
			return r.xp * 3600 / r.secs * Runs.RECORD_MARGIN
		end
	end
	return 0
end

-- db: table in SavedVariables, changed in place. opts: clock() seconds (required), epoch() server time,
-- curve = XP from level n to n + 1 (ns.XP.TO_LEVEL) or a function returning it.
function Runs.New(db, opts)
	opts = opts or {}
	local r = setmetatable({
		db = db,
		clock = assert(opts.clock, "Runs.New: clock required"),
		epoch = opts.epoch,
		curve = opts.curve,
		index = {}, -- key -> seq
		tokens = {}, -- tokens this client knows (vault and this session)
		n = 0,
	}, Runs)
	db.list = type(db.list) == "table" and db.list or {}
	db.first = type(db.first) == "number" and db.first or 1
	db.last = type(db.last) == "number" and db.last or 0
	db.acked = type(db.acked) == "number" and db.acked or 0
	db.mine = type(db.mine) == "table" and db.mine or {} -- tokens of this installation's characters
	db.blocked = type(db.blocked) == "table" and db.blocked or {}
	db.nblocked = type(db.nblocked) == "number" and db.nblocked or 0
	for seq = db.first, db.last do
		local msg = db.list[seq]
		local key, tok
		if type(msg) == "string" then
			key, tok = KeyOf(msg)
		end
		if key and not r.index[key] then
			r.index[key] = seq
			r.tokens[tok] = true
			r.n = r.n + 1
		else
			db.list[seq] = nil
		end
	end
	r:StartSession()
	return r
end

-- Forever beta trap (chapter 15 §7): continue with the table the global holds now.
function Runs:Rebind(tbl)
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

-- A new session (login or /reload): every section may go out once more, own sections first, then
-- the newest first: a player who was away lacks the recent ones (spread simulation: a higher minimum
-- than random order, spec/runs_spec.lua).
function Runs:StartSession()
	self.heard, self.senders, self.muted = {}, {}, {}
	self.nextRelay, self.qi = 0, 1
	local mine, rest = {}, {}
	local db = self.db
	for seq = db.first, db.last do
		local msg = db.list[seq]
		if msg then
			local _, tok = KeyOf(msg)
			local list = db.mine[tok] and mine or rest
			list[#list + 1] = seq
		end
	end
	for i = #rest, 1, -1 do
		mine[#mine + 1] = rest[i]
	end
	self.queue = mine
	self.stats = { heard = 0, new = 0, dup = 0, conflict = 0, implausible = 0, muted = 0, limit = 0, relayed = 0 }
end

function Runs:Count()
	return self.n
end

function Runs:Has(key)
	return self.index[key] ~= nil
end

local function Remove(self, seq)
	local key = KeyOf(self.db.list[seq])
	self.db.list[seq] = nil
	self.index[key] = nil
	self.n = self.n - 1
end

local function Add(self, msg, key, tok)
	local db = self.db
	db.last = db.last + 1
	db.list[db.last] = msg
	self.index[key] = db.last
	self.tokens[tok] = true
	self.n = self.n + 1
	while self.n > Runs.VAULT_MAX and db.first <= db.last do
		if db.list[db.first] then
			Remove(self, db.first)
		end
		db.first = db.first + 1
	end
	return db.last
end

local function Block(self, key)
	local db = self.db
	if not db.blocked[key] then
		if db.nblocked >= Runs.BLOCKED_MAX then
			db.blocked, db.nblocked = {}, 0
		end
		db.blocked[key] = true
		db.nblocked = db.nblocked + 1
	end
end

-- Plausibility band of a parsed "s" message (fields as in Proto.lua).
function Runs:Plausible(f)
	local kind, sec, secs, xp, level, day = f[5], f[6], f[8], f[9], f[11], f[12]
	if secs > Runs.MAX_SECS then
		return false
	end
	local at
	if kind == "l" then
		if secs < Runs.MIN_LEVEL_SECS or sec >= level then
			return false -- a level section ends on a higher level
		end
		local curve = type(self.curve) == "function" and self.curve() or self.curve
		local need = type(curve) == "table" and curve[sec] or 0
		xp, at = math.max(xp, need), sec -- a level takes at least its XP, whatever the message says
	else
		if secs < Runs.MIN_MODULE_SECS then
			return false
		end
		at = level
	end
	if xp * 3600 / secs > Runs.MaxRate(at) then
		return false
	end
	if self.epoch and day > floor(self.epoch() / 86400) + 1 then
		return false -- a day in the future
	end
	return true
end

-- Sender limits for this session. Returns the sender's bucket or nil when it is muted for runs.
local function Bucket(self, who)
	if self.muted[who] then
		return nil
	end
	local now = self.clock()
	local b = self.senders[who]
	if not b then
		b = { start = now, n = 0, new = 0 }
		self.senders[who] = b
	elseif now - b.start > Runs.SENDER_WINDOW then
		b.start, b.n = now, 0
	end
	b.n = b.n + 1
	if b.n > Runs.SENDER_MAX then
		self.muted[who] = true
		return nil
	end
	return b
end

-- A run message from another player. find = Proto.Parse(msg); who = sender key (session only);
-- channel = it came over the hidden channel, so everybody online heard it.
-- Returns "new", "dup", "conflict", "blocked", "implausible", "muted" or "limit".
function Runs:Hear(find, msg, who, channel)
	local key, tok = KeyOf(msg)
	if not key then
		return "implausible"
	end
	local st = self.stats
	st.heard = st.heard + 1
	if channel then
		self.heard[key] = true
	end
	local b = who and Bucket(self, who)
	if who and not b then
		st.muted = st.muted + 1
		return "muted"
	end
	if self.db.blocked[key] then
		return "blocked"
	end
	local seq = self.index[key]
	if seq then
		if self.db.list[seq] == msg then
			st.dup = st.dup + 1
			return "dup"
		end
		st.conflict = st.conflict + 1
		if not self.db.mine[tok] then -- own data stays with its owner
			Remove(self, seq)
			Block(self, key)
		end
		return "conflict"
	end
	if not self:Plausible(find) then
		st.implausible = st.implausible + 1
		return "implausible"
	end
	if b and not self.tokens[tok] then
		b.new = b.new + 1
		if b.new > Runs.NEW_TOKENS_MAX then
			st.limit = st.limit + 1
			return "limit"
		end
	end
	seq = Add(self, msg, key, tok)
	if not channel then
		self.queue[#self.queue + 1] = seq -- from the group or the guild: the channel has not heard it
	end
	st.new = st.new + 1
	return "new"
end

-- An own section. The exchange sends it now; later sessions relay it first. False when the section
-- is already stored (never twice).
function Runs:AddOwn(msg)
	local key, tok = KeyOf(msg)
	if not key or self.index[key] or self.db.blocked[key] then
		return false
	end
	self.db.mine[tok] = true
	Add(self, msg, key, tok)
	self.heard[key] = true
	return true
end

-- The next message to relay on the channel, or nil (gap not over, nothing left this session).
function Runs:NextRelay()
	local now = self.clock()
	if now < self.nextRelay then
		return nil
	end
	local q, list = self.queue, self.db.list
	while self.qi <= #q do
		local msg = list[q[self.qi]]
		self.qi = self.qi + 1
		local key = msg and KeyOf(msg)
		if key and not self.heard[key] then
			self.heard[key] = true
			self.nextRelay = now + Runs.RELAY_GAP
			self.stats.relayed = self.stats.relayed + 1
			return msg
		end
	end
	return nil
end

-- Sections stored after seq `after` (0 = all), oldest first, and the last seq included.
function Runs:Since(after)
	local out, db = {}, self.db
	local last = after or 0
	for seq = math.max(db.first, last + 1), db.last do
		if db.list[seq] then
			out[#out + 1] = db.list[seq]
		end
		last = seq
	end
	return out, last
end

-- The player copied an export up to this seq.
function Runs:Ack(seq)
	if type(seq) == "number" and seq > self.db.acked then
		self.db.acked = seq
	end
end
