-- SPDX-License-Identifier: GPL-3.0-or-later
-- Collector/Store.lua: ring buffer of text chunks with a fixed upper limit.
local wow = require("spec.helpers.wow")

local function load()
	wow.reset()
	return wow.loadFiles({ "Pathmark/Locales/enUS.lua", "Pathmark/Core/Util.lua", "Pathmark/Collector/Store.lua" })
end

local function clock()
	return wow.clock
end

local function epoch()
	return 1793836800 + 3600 * 7 -- 2026-11-05 07:00 UTC
end

local function lines(text)
	local out = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		out[#out + 1] = line
	end
	return out
end

-- Size of a SavedVariables file holding the table, written like the client (no indentation).
local function serialize(v)
	local t = type(v)
	if t == "string" then
		return ("%q"):format(v)
	elseif t == "number" or t == "boolean" then
		return tostring(v)
	end
	local parts = {}
	for k, x in pairs(v) do
		parts[#parts + 1] = "[" .. serialize(k) .. "]=" .. serialize(x)
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

describe("Store", function()
	it("encodes fields without breaking the record", function()
		local ns = load()
		local F = ns.Store.Field
		assert.are.equal("", F(nil))
		assert.are.equal("42", F(42))
		assert.are.equal("1.5", F(1.5))
		assert.are.equal("2", F(2.0))
		assert.are.equal("1", F(true))
		assert.are.equal("0", F(false))
		assert.are.equal("a b c", F("a\tb\nc"))
		assert.are.equal("", F(0 / 0))
		assert.are.equal("", F({}))
	end)

	it("starts every chunk with seq and day, then dropped and session, and keeps empty fields", function()
		local ns = load()
		local db = {}
		local s = ns.Store.New(db, clock, epoch)
		s:Open({ n = 3, "k3j9x0q2m7", nil, "WARRIOR" })
		wow.advance(1.25)
		s:Write(nil, "xp", 120, 400, nil)
		s:Flush()
		local l = lines(db.chunks[1])
		assert.are.equal("chunk\t0\t1\t20762", l[1])
		assert.are.equal("session\t0\tk3j9x0q2m7\t\tWARRIOR", l[2])
		assert.are.equal("xp\t13\t120\t400\t", l[3]) -- tenths of a second since chunk start
	end)

	it("never writes the time of day, only the day number", function()
		local ns = load()
		local db = {}
		local s = ns.Store.New(db, clock, epoch)
		s:Open({ n = 0 })
		s:Flush()
		assert.is_nil(db.chunks[1]:find(tostring(epoch()), 1, true))
		assert.are.equal(math.floor(epoch() / 86400), tonumber(db.chunks[1]:match("^chunk\t0\t1\t(%d+)")))
	end)

	it("returns false without an open chunk", function()
		local ns = load()
		local s = ns.Store.New({}, clock, epoch)
		assert.is_false(s:Write(nil, "xp", 1))
	end)

	it("closes a chunk at the byte limit and repeats the session header", function()
		local ns = load()
		local db = {}
		local s = ns.Store.New(db, clock, epoch, { CHUNK_BYTES = 200 })
		s:Open({ n = 1, "char1" })
		for i = 1, 30 do
			s:Write(nil, "pos", 1429, i, i)
		end
		s:Close()
		assert.is_true(db.seq > 1)
		for seq = 1, db.seq do
			local l = lines(db.chunks[seq])
			assert.are.equal("chunk", l[1]:match("^(%a+)"))
			assert.are.equal("session\t0\tchar1", l[2])
		end
	end)

	it("closes a chunk after five minutes", function()
		local ns = load()
		local db = {}
		local s = ns.Store.New(db, clock, epoch)
		s:Open({ n = 0 })
		s:Write(nil, "pos", 1)
		wow.advance(300)
		s:Write(nil, "pos", 2)
		assert.are.equal(2, db.seq)
	end)

	it("keeps the stored bytes under the upper limit and counts dropped chunks", function()
		local ns = load()
		local db = {}
		local s = ns.Store.New(db, clock, epoch, { CHUNK_BYTES = 1024, STORE_BYTES = 8 * 1024 })
		s:Open({ n = 1, "char1" })
		for i = 1, 5000 do
			s:Write(nil, "pos", 1429, i % 10000, (i * 7) % 10000)
			local st = s:Stats()
			-- closed chunks stay under the limit; the open one may add at most one chunk
			assert.is_true(st.bytes <= 8 * 1024 + 1024 + 64, "over the limit at record " .. i)
		end
		s:Close()
		local st = s:Stats()
		assert.is_true(st.dropped > 0)
		assert.is_true(st.bytes <= 8 * 1024)
		-- the oldest chunk still present tells how many were dropped
		local first = lines(db.chunks[db.first])
		assert.are.equal("dropped", first[2]:match("^(%a+)"))
		-- no gaps between first and seq
		for seq = db.first, db.seq do
			assert.is_string(db.chunks[seq])
		end
	end)

	it("holds the default 2 MiB limit with few SavedVariables constants", function()
		local ns = load()
		local db = {}
		local s = ns.Store.New(db, clock, epoch)
		s:Open({ n = 2, "char1", "WARRIOR" })
		for i = 1, 120000 do
			if i % 50 == 0 then
				wow.advance(2)
			end
			s:Write(nil, "pos", 1429, i % 10000, (i * 13) % 10000)
		end
		s:Close()
		local st = s:Stats()
		assert.is_true(st.bytes <= ns.Store.STORE_BYTES)
		assert.is_true(st.bytes > ns.Store.STORE_BYTES - ns.Store.CHUNK_BYTES - 64)
		-- Write the table like a SavedVariables file and count its constants with luac (chapter 12 §5.1).
		local path = os.tmpname()
		local fh = assert(io.open(path, "wb"))
		fh:write("PathmarkCollectDB = { own = " .. serialize(db) .. " }\n")
		fh:close()
		local luac = io.open(".tools/lua51/bin/luac", "rb") and ".tools/lua51/bin/luac" or "luac"
		local p = assert(io.popen(luac .. " -p -l -l " .. path .. " 2>&1"))
		local listing = p:read("*a")
		p:close()
		os.remove(path)
		local constants = tonumber(listing:match("constants %((%d+)%)"))
		assert.is_number(constants, listing:sub(1, 200))
		-- one string per chunk plus keys: far below the 65,535 the project allows (a quarter of the limit)
		assert.is_true(constants < 1000, "constants: " .. tostring(constants))
	end)

	it("rebinds to a replaced SavedVariables table and keeps the live state", function()
		local ns = load()
		local db = {}
		local s = ns.Store.New(db, clock, epoch)
		s:Open({ n = 0 })
		s:Write(nil, "zone", 1429)
		s:Flush()
		local fresh = {}
		assert.are.equal(fresh, s:Rebind(fresh))
		assert.are.equal(db.seq, fresh.seq)
		assert.are.equal(db.chunks, fresh.chunks)
		assert.are.equal(s.db, fresh)
		local made = s:Rebind(nil)
		assert.is_table(made)
		assert.are.equal(1, made.seq)
	end)

	it("drops broken entries when loading old data", function()
		local ns = load()
		local db = { seq = 3, first = 1, chunks = { "a", [2] = 5, x = "y", [3] = "ccc" } }
		local s = ns.Store.New(db, clock, epoch)
		assert.are.equal(4, s:Stats().bytes)
		assert.is_nil(db.chunks[2])
		assert.is_nil(db.chunks.x)
	end)

	it("lists closed chunks after the acknowledged one, oldest first, within a byte budget", function()
		local ns = load()
		local db = {}
		local s = ns.Store.New(db, clock, epoch, { CHUNK_BYTES = 100 })
		s:Open({ n = 0 })
		for i = 1, 40 do
			s:Write(nil, "pos", 1429, i, i)
		end
		local all, last = s:Chunks(0)
		assert.are.equal(db.seq - 1, last) -- the open chunk is not listed
		assert.are.equal(last, #all)
		local part, upto = s:Chunks(0, 250)
		assert.is_true(#part >= 1 and #part < #all)
		s:Ack(upto)
		local rest = s:Chunks(db.acked)
		assert.are.equal(#all - #part, #rest)
		s:Rotate()
		local after, lastAfter = s:Chunks(0)
		assert.are.equal(#all + 1, #after)
		assert.are.equal(db.seq - 1, lastAfter)
	end)
end)
