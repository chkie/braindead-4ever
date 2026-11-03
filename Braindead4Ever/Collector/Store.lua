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

-- Collector/Store.lua: ring buffer of text chunks in SavedVariables (pattern after Polestar Recorder, own code).
-- Plain Lua 5.1 without WoW API: clock, server time and table are passed in, so the tests run this exact code.
-- One record = one line "kind\tdt\tfield\tfield...". One chunk = one string, i.e. ONE constant in the
-- SavedVariables file (hard limit 262,143 constants per file).
local _, ns = ...

local Store = {}
Store.__index = Store
ns.Store = Store

Store.CHUNK_BYTES = 16 * 1024 -- a chunk closes at 16 KiB ...
Store.CHUNK_SECONDS = 300 -- ... or after 5 minutes (both as in Polestar)
Store.STORE_BYTES = 2 * 1024 * 1024 -- upper limit over closed chunks

local concat, format, floor, gsub = table.concat, string.format, math.floor, string.gsub

-- Encode one field: nil -> "", whole numbers as integers, others with one decimal, bool -> 1/0,
-- text without tab and line breaks (they would split the record).
local function Field(v)
	local t = type(v)
	if v == nil then
		return ""
	end
	if t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return ""
		end
		if v == floor(v) then
			return format("%d", v)
		end
		return (gsub(format("%.1f", v), "%.0$", ""))
	elseif t == "boolean" then
		return v and "1" or "0"
	elseif t == "string" then
		return (gsub(v, "[\t\r\n]", " "))
	end
	return ""
end
Store.Field = Field

-- Kept when the SavedVariables table is replaced at runtime (Rebind).
local FIELDS = { "seq", "first", "chunks", "dropped", "acked" }

-- db: table inside SavedVariables; clock(): seconds (GetTime in game); epoch(): server time (GetServerTime).
-- limits: optional overrides of CHUNK_BYTES, CHUNK_SECONDS, STORE_BYTES for this instance.
function Store.New(db, clock, epoch, limits)
	local s = setmetatable({ db = db, clock = clock, epoch = epoch, open = nil, buf = {}, stored = 0 }, Store)
	for k, v in pairs(limits or {}) do
		s[k] = v
	end
	db.seq = type(db.seq) == "number" and db.seq or 0
	db.first = type(db.first) == "number" and db.first or (db.seq + 1) -- oldest chunk still present
	db.chunks = type(db.chunks) == "table" and db.chunks or {}
	db.dropped = type(db.dropped) == "number" and db.dropped or 0
	db.acked = type(db.acked) == "number" and db.acked or 0 -- last chunk the player has exported
	for seq, text in pairs(db.chunks) do
		if type(seq) ~= "number" or type(text) ~= "string" then
			db.chunks[seq] = nil
		else
			s.stored = s.stored + #text
		end
	end
	s:Enforce()
	return s
end

-- Forever beta trap (Polestar, Mapzeroth): the SavedVariables table can be nil or replaced.
-- Rebind writes the live state into the table the global holds now and continues with it.
function Store:Rebind(tbl)
	if tbl == self.db then
		return tbl
	end
	if type(tbl) ~= "table" then
		tbl = {}
	end
	for _, k in ipairs(FIELDS) do
		tbl[k] = self.db[k]
	end
	self.db = tbl
	return tbl
end

-- Drop the oldest closed chunks until everything fits under STORE_BYTES. O(1) per chunk via db.first
-- instead of table.remove(t, 1), which shifts every element of a large array.
function Store:Enforce()
	local db, openBytes = self.db, self.open and self.open.bytes or 0
	local limit = self.open and self.open.seq or db.seq + 1
	while self.stored + openBytes > self.STORE_BYTES and db.first < limit do
		local text = db.chunks[db.first]
		if text then
			self.stored = self.stored - #text
			db.chunks[db.first] = nil
			db.dropped = db.dropped + 1
		end
		db.first = db.first + 1
	end
end

-- Write the open chunk into the SavedVariables table (refresh or close).
function Store:Flush()
	local c = self.open
	if c and c.dirty then
		self.db.chunks[c.seq] = concat(c.lines, "\n", 1, c.n)
		c.dirty = false
	end
end

function Store:Close()
	local c = self.open
	if not c then
		return
	end
	self:Flush()
	self.open = nil
	self.stored = self.stored + #(self.db.chunks[c.seq] or "")
	self:Enforce()
end

local function Append(self, line)
	local c = self.open
	c.n = c.n + 1
	c.lines[c.n] = line
	c.bytes = c.bytes + #line + 1
	c.dirty = true
end

-- header: fields of the session context (list with n, may have holes). Every following chunk
-- starts with it again, so a single chunk stays readable.
function Store:Open(header)
	local db = self.db
	self.header = header
	db.seq = db.seq + 1
	local c = { seq = db.seq, t0 = self.clock(), lines = {}, n = 0, bytes = 0, dirty = true }
	self.open = c
	-- Only the day of the server time, never the time of day (anonymity); order comes from seq.
	Append(self, format("chunk\t0\t%d\t%d", c.seq, floor(self.epoch() / 86400)))
	if db.dropped > 0 then
		self:Write(nil, "dropped", db.dropped)
	end
	if header then
		self:Write(nil, "session", unpack(header, 1, header.n or #header))
	end
	c.base = c.n -- lines before the first real record
	self:Flush()
end

function Store:IsOpen()
	return self.open ~= nil
end

-- Write one record. t = time on the clock or nil = now. Returns false without an open chunk.
function Store:Write(t, kind, ...)
	local c = self.open
	if not c then
		return false
	end
	local now = self.clock()
	if c.bytes >= self.CHUNK_BYTES or now - c.t0 >= self.CHUNK_SECONDS then
		local header = self.header
		self:Close()
		self:Open(header)
		c = self.open
	end
	local buf, n = self.buf, select("#", ...)
	buf[1] = kind
	buf[2] = format("%d", floor(((t or now) - c.t0) * 10 + 0.5)) -- tenths of a second since chunk start
	for i = 1, n do
		buf[i + 2] = Field((select(i, ...)))
	end
	Append(self, concat(buf, "\t", 1, n + 2))
	return true
end

-- Close the open chunk and start a new one with the same header (before an export).
-- A chunk that holds nothing but its header stays open.
function Store:Rotate()
	if self.open and self.open.n > (self.open.base or 0) then
		local header = self.header
		self:Close()
		self:Open(header)
	end
end

function Store:Stats()
	local n = 0
	for _ in pairs(self.db.chunks) do
		n = n + 1
	end
	return {
		chunks = n,
		bytes = self.stored + (self.open and self.open.bytes or 0),
		dropped = self.db.dropped,
		first = self.db.first,
		seq = self.db.seq,
		acked = self.db.acked,
	}
end

-- Closed chunks after seq `after`, oldest first, until maxBytes is reached (at least one chunk).
-- Returns the list of texts and the last seq included (or `after` when there is nothing).
function Store:Chunks(after, maxBytes)
	local out, db, last, size = {}, self.db, after or 0, 0
	local openSeq = self.open and self.open.seq
	for seq = math.max(db.first, last + 1), db.seq do
		local text = db.chunks[seq]
		if seq ~= openSeq and text then
			if maxBytes and size > 0 and size + #text > maxBytes then
				break
			end
			out[#out + 1] = text
			size = size + #text
		end
		if seq ~= openSeq then
			last = seq
		end
	end
	return out, last
end

-- The player has copied an export up to this chunk.
function Store:Ack(seq)
	if type(seq) == "number" and seq > self.db.acked then
		self.db.acked = seq
	end
end
