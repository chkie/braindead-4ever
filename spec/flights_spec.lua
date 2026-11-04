-- SPDX-License-Identifier: GPL-3.0-or-later
-- Flight legs in the exchange (plan "Flugdaten im Austausch", Welle 11, 2026-11-03; docs/ROUTE-FORMAT.md
-- §Flights in the exchange): message kind "h", the flight vault (Collector/Flights.lua) with its
-- checks, saturation and relaying, the legs from the flight master's map and from flights without a
-- stop, the exchange on the find pool of the channel budget, the export with the decoder and
-- tools/routekit/observe.py, and the spread simulation with the counter-checks.
local wow = require("spec.helpers.wow")
local node = require("spec.helpers.node")
local json = require("spec.helpers.json")
local spread = require("spec.helpers.spread")

-- Owner, 2026-11-02 (spec/channel_budget_spec.lua): per client at most 0.5 messages per second on
-- average and at most 1 per second in any 60 s window.
local MEAN_MAX, WINDOW_MAX = 0.5, 60

local function pure()
	wow.reset()
	return wow.loadFiles({
		"Braindead4Ever/Locales/enUS.lua",
		"Braindead4Ever/Core/Util.lua",
		"Braindead4Ever/Collector/Proto.lua",
		"Braindead4Ever/Collector/Runs.lua",
		"Braindead4Ever/Collector/Flights.lua",
		"Braindead4Ever/Collector/Budget.lua",
		"Braindead4Ever/Routes/XP.lua",
		"Braindead4Ever/Routes/Data_Flights.lua",
	})
end

-- A vault on a clock the test moves (t.now), with the real facts unless others are given.
local function vault(ns, db, facts)
	local t = { now = 0 }
	local f = ns.Flights.New(db or {}, {
		clock = function()
			return t.now
		end,
		facts = facts,
	})
	return f, t
end

local function H(ns, a, b, secs)
	return assert(ns.Proto.Format("h", a, b, secs))
end

local function hear(ns, f, msg, who, channel)
	return f:Hear(assert(ns.Proto.Parse(msg)), who, channel ~= false)
end

-- Straight distance between two flight points of the facts, in yards, and the model seconds.
local function model(ns, a, b)
	local F = ns.FlightFacts
	local na, nb = F.nodes[a], F.nodes[b]
	local d = math.sqrt((na[2] - nb[2]) ^ 2 + (na[3] - nb[3]) ^ 2)
	return d, d * F.secondsPerYard
end

describe("Proto: flight legs", function()
	it("formats and parses a leg with flight point IDs and seconds only", function()
		local ns = pure()
		local P = ns.Proto
		local msg = H(ns, 2, 5, 131)
		assert.are.equal("h;1;2;5;131", msg)
		assert.are.same({ kind = "h", n = 3, 2, 5, 131 }, P.Parse(msg))
		assert.are.equal("h;2;5", P.Key(P.Parse(msg)))
		assert.are.equal("h;1;2;5;0", H(ns, 2, 5, 0), "0 = the connection only")
	end)

	it("sends nothing half-valid", function()
		local P = pure().Proto
		assert.is_nil(P.Format("h", 0, 5, 10)) -- no flight point 0
		assert.is_nil(P.Format("h", 2, 5, -1))
		assert.is_nil(P.Format("h", 2, 5, 1.5))
		assert.is_nil(P.Format("h", 2, 5)) -- field missing
		assert.is_nil(P.Format("h", 2, 5, 10, 1429)) -- no room for a map, a position or a name
		assert.is_nil(P.Format("h", 2, "Anna", 10))
		assert.are.same({ nil, "bad" }, { P.Parse("h;1;2;5") })
		assert.are.same({ nil, "bad" }, { P.Parse("h;1;2;5;10;4231") })
	end)

	it("is skipped by a reader that does not know it", function()
		local ns = pure()
		local msg = H(ns, 2, 5, 131)
		ns.Proto.KINDS.h = nil -- an addon version before this kind
		assert.are.same({ nil, "skip" }, { ns.Proto.Parse(msg) })
	end)
end)

describe("Flight vault: checks", function()
	it("drops a 5-s flight over 3 km (counter-check: without the model band it would pass)", function()
		local ns = pure()
		local yards, secs = model(ns, 22, 38)
		assert.is_true(yards * 0.9144 >= 3000, yards) -- 22>38 is a leg of the facts, 3.0 km long
		assert.is_true(secs > 150 and secs < 170, secs)
		local f = vault(ns)
		assert.are.equal("implausible", hear(ns, f, H(ns, 22, 38, 5), "Mallory"))
		assert.is_nil(f.db.legs["22>38"])
		assert.are.equal(0, #(f:Since(0)))
		-- the band is the only thing that stops it: SECONDS_MIN is 5
		assert.are.equal(5, ns.Flights.SECONDS_MIN)
		local low = ns.Flights.MODEL_LOW
		ns.Flights.MODEL_LOW = 0
		local open = vault(ns)
		local result = hear(ns, open, H(ns, 22, 38, 5), "Mallory")
		ns.Flights.MODEL_LOW = low
		assert.are.equal("new", result)
		-- a real flight on the leg passes, also at the edges of the band
		assert.are.equal("new", hear(ns, f, H(ns, 22, 38, 160), "Anna Sommer"))
		assert.are.equal("new", hear(ns, f, H(ns, 22, 38, math.ceil(secs * 0.3)), "Ben Winter"))
		assert.are.equal("new", hear(ns, f, H(ns, 22, 38, math.floor(secs * 3)), "Cleo Herbst"))
		assert.are.equal("implausible", hear(ns, f, H(ns, 22, 38, math.ceil(secs * 3) + 1), "Dana Herbst"))
	end)

	it("needs both flight points in the facts or seen at an own flight master", function()
		local ns = pure()
		local f = vault(ns)
		assert.are.equal("implausible", hear(ns, f, H(ns, 2, 9001, 0), "Mallory"))
		assert.are.equal("implausible", hear(ns, f, H(ns, 9001, 9002, 0), "Mallory"))
		f:SeeNodes({ 9001, 9002 })
		assert.are.equal("new", hear(ns, f, H(ns, 9001, 9002, 0), "Anna Sommer"))
		-- a point without a position: the seconds cannot be checked, the leg counts as a connection
		assert.are.equal("new", hear(ns, f, H(ns, 2, 9001, 120), "Anna Sommer"))
		assert.are.equal(0, f.db.legs["2>9001"].m)
		assert.are.same({ "h;1;9001;9002;0", "h;1;2;9001;0" }, (f:Since(0)))
	end)

	it("drops a leg to itself, across continents and outside 5 to 1800 seconds", function()
		local ns = pure()
		local f = vault(ns)
		assert.are.equal(0, ns.FlightFacts.nodes[2][1])
		assert.are.equal(1, ns.FlightFacts.nodes[22][1])
		assert.are.equal("implausible", hear(ns, f, H(ns, 2, 2, 0), "Mallory"))
		assert.are.equal("implausible", hear(ns, f, H(ns, 2, 22, 0), "Mallory"))
		assert.are.equal("implausible", hear(ns, f, H(ns, 2, 5, 4), "Mallory"))
		assert.are.equal("implausible", hear(ns, f, H(ns, 2, 5, 1801), "Mallory"))
		assert.are.equal(4, f.stats.implausible)
		assert.are.equal(0, f.nlegs)
	end)
end)

describe("Flight vault: saturation", function()
	it("stops sending a connection at three sources and seconds at five measured flights", function()
		local ns = pure()
		local f = vault(ns)
		-- 2>4 is in the facts without a measured flight: one source, no measure
		assert.are.equal(0, ns.FlightFacts.legs["2>4"])
		assert.are.same({ 1, 0 }, { f:Known("2>4") })
		assert.are.equal("h;1;2;4;0", (f:Own(2, 4, 0, false)))
		assert.are.equal("new", hear(ns, f, H(ns, 2, 4, 0), "Anna Sommer"))
		assert.are.same({ 3, 0 }, { f:Known("2>4") })
		assert.is_nil((f:Own(2, 4, 0, false)), "the connection is known from three sources")
		-- seconds still add something until five flights are measured
		for i, who in ipairs({ "Ben Winter", "Cleo Herbst", "Dana Sommer", "Emil Winter" }) do
			assert.are.equal("new", hear(ns, f, H(ns, 2, 4, 90 + i), who))
		end
		assert.are.same({ 7, 4 }, { f:Known("2>4") })
		local msg, secs = f:Own(2, 4, 93, true)
		assert.are.same({ "h;1;2;4;93", 93 }, { msg, secs })
		assert.is_nil((f:Own(2, 4, 95, true)), "five measured flights")
		assert.are.same({ 7, 6 }, { f:Known("2>4") })
		assert.is_false(f:Wants("2>4", 94))
		-- the facts' measured flights count: 22>25 has 11, so its seconds are saturated with the sources
		assert.are.equal(11, ns.FlightFacts.legs["22>25"])
		f:Own(22, 25, 0, false)
		hear(ns, f, H(ns, 22, 25, 0), "Anna Sommer")
		assert.is_false(f:Wants("22>25", 50))
	end)

	it("counts a sender once per leg and session, and keeps no sender name", function()
		local ns = pure()
		local db = {}
		local f = vault(ns, db)
		assert.are.equal("new", hear(ns, f, H(ns, 2, 5, 131), "Anna Sommer"))
		assert.are.equal("dup", hear(ns, f, H(ns, 2, 5, 132), "Anna Sommer"))
		assert.are.equal("new", hear(ns, f, H(ns, 2, 5, 133), "Ben Winter"))
		assert.are.equal(2, db.legs["2>5"].s)
		f:StartSession()
		assert.are.equal("new", hear(ns, f, H(ns, 2, 5, 131), "Anna Sommer"))
		local saved = json.encode(db)
		assert.is_nil(saved:find("Anna", 1, true))
		assert.is_nil(saved:find("Ben", 1, true))
		assert.matches("^[h;%d]+$", table.concat(f:Since(0), ";"))
	end)

	it("keeps its legs over a reload and starts with the table the global holds", function()
		local ns = pure()
		local db = {}
		local f = vault(ns, db)
		f:Own(2, 5, 131, true)
		hear(ns, f, H(ns, 2, 12, 117), "Anna Sommer")
		local again = vault(ns, db)
		assert.are.equal(2, again.nlegs)
		assert.is_true(again.db.legs["2>5"].o)
		assert.are.same({ 131 }, again.db.legs["2>5"].t)
		assert.are.same({ "h;1;2;12;117" }, (again:Since(0)), "only received legs go to the export")
		local fresh = {}
		assert.are.equal(fresh, again:Rebind(fresh))
		assert.are.equal(again.db, fresh)
		assert.is_true(fresh.legs["2>5"].o)
	end)
end)

describe("Flight vault: relaying", function()
	it("relays every leg once per session, own first, then the newest, one per 10 s", function()
		local ns = pure()
		local db = {}
		local f = vault(ns, db)
		hear(ns, f, H(ns, 2, 5, 131), "A")
		hear(ns, f, H(ns, 2, 12, 117), "B")
		f:Own(5, 12, 70, true)
		-- heard on the channel this session, own one offered by the exchange: nothing to relay now
		assert.is_nil(f:NextRelay())
		local t
		f, t = vault(ns, db) -- next session
		local out = {}
		for i = 1, 6 do
			t.now = i * 5
			out[#out + 1] = f:NextRelay() or false
		end
		assert.are.same({ "h;1;5;12;70", false, "h;1;2;12;117", false, "h;1;2;5;131", false }, out)
		t.now = 100
		assert.is_nil(f:NextRelay(), "once per session")
	end)

	it("relays the legs of the flight master's map next, and what came from group or guild", function()
		local ns = pure()
		local f, t = vault(ns)
		f:Own(2, 4, 0, false)
		f:Own(2, 5, 0, false)
		t.now = 1
		local first = f:NextRelay()
		assert.is_true(first == "h;1;2;5;0" or first == "h;1;2;4;0")
		hear(ns, f, H(ns, 2, 12, 117), "Guild Member", false)
		hear(ns, f, H(ns, 5, 12, 70), "Somebody", true) -- the channel just heard it
		local got = {}
		for i = 1, 10 do
			t.now = 1 + i * 10
			got[#got + 1] = f:NextRelay()
		end
		table.sort(got)
		local other = first == "h;1;2;5;0" and "h;1;2;4;0" or "h;1;2;5;0"
		assert.are.same({ "h;1;2;12;117", other }, got)
	end)

	it("relays a leg after a broken message about it, and the median of the measured seconds", function()
		local ns = pure()
		local db = {}
		local f = vault(ns, db)
		f:Own(2, 4, 90, true)
		hear(ns, f, H(ns, 2, 4, 95), "A", false)
		hear(ns, f, H(ns, 2, 4, 85), "B", false)
		local t
		f, t = vault(ns, db)
		assert.are.equal("implausible", hear(ns, f, H(ns, 2, 4, 5), "Mallory"))
		t.now = 1
		assert.are.equal("h;1;2;4;90", f:NextRelay())
	end)

	it("relays nothing the others know already", function()
		local ns = pure()
		local db = {}
		local f = vault(ns, db)
		for i, who in ipairs({ "A", "B", "C", "D", "E" }) do
			hear(ns, f, H(ns, 2, 4, 90 + i), who, false)
		end
		local t
		f, t = vault(ns, db)
		t.now = 1
		assert.is_nil(f:NextRelay())
	end)

	it("exports the legs taken, not exported yet, oldest first", function()
		local ns = pure()
		local f = vault(ns)
		hear(ns, f, H(ns, 2, 5, 131), "A")
		hear(ns, f, H(ns, 2, 5, 3), "B") -- not taken
		local list, last, from = f:Since(f.db.acked)
		assert.are.same({ { "h;1;2;5;131" }, 1, 1 }, { list, last, from })
		f:Ack(last)
		hear(ns, f, H(ns, 2, 12, 117), "C")
		assert.are.same({ { "h;1;2;12;117" }, 2, 2 }, { f:Since(f.db.acked) })
		assert.are.equal(2, #(f:Since(0)))
	end)
end)

-- Messages sent with the addon prefix and kind "h", optionally only on one distribution.
local function sentLegs(dist)
	local out = {}
	for _, m in ipairs(wow.world.sent) do
		if m.prefix == "BDF" and m.msg:sub(1, 2) == "h;" and (not dist or m.dist == dist) then
			out[#out + 1] = m
		end
	end
	return out
end

local function receive(msg, sender, dist)
	wow.fire("CHAT_MSG_ADDON", "BDF", msg, dist or "CHANNEL", sender, "", 0, 5, "BraindeadShare", 0)
	wow.readInbox()
end

-- A flight master at point 2 (slot 1) with direct legs to 5 (slot 2) and 12 (slot 3) and a trip to 71
-- (slot 4) over 5.
local function flightMaster()
	local FP = Enum.FlightPathState
	wow.world.npc = { guid = "Creature-0-1465-0-2105-352-0000ABC127", name = "Dungar Longdrink" }
	wow.world.taxi.nodes = {
		{ nodeID = 2, state = FP.Current, slotIndex = 1 },
		{ nodeID = 5, state = FP.Reachable, slotIndex = 2 },
		{ nodeID = 12, state = FP.Reachable, slotIndex = 3 },
		{ nodeID = 71, state = FP.Reachable, slotIndex = 4 },
	}
	wow.world.taxi.routes = { [2] = { 1, 2 }, [3] = { 1, 3 }, [4] = { 1, 2, 4 } }
	wow.fire("TAXIMAP_OPENED", 0)
end

-- A flight from the open flight master; the landing counts secs from the choice.
local function fly(slot, secs)
	_G.TakeTaxiNode(slot)
	wow.world.onTaxi = true
	wow.fire("PLAYER_CONTROL_LOST")
	wow.advance(secs - 0.2)
	wow.world.onTaxi = false
	wow.fire("PLAYER_CONTROL_GAINED")
	wow.advance(1)
end

describe("Flight legs from play", function()
	it("puts the legs of the flight master's map into the vault and offers a flight without a stop", function()
		local ns = wow.session()
		wow.world.group.party = true
		flightMaster()
		local legs = ns.Collector.flights.db.legs
		for _, key in ipairs({ "2>5", "2>12", "5>71" }) do
			assert.is_true(legs[key] and legs[key].o, key)
		end
		fly(2, 135)
		local party = sentLegs("PARTY")
		assert.are.equal(1, #party)
		assert.are.equal("h;1;2;5;135", party[1].msg)
		assert.are.same({ 135 }, legs["2>5"].t)
		-- a trip with a stop says nothing about one leg: nothing is offered
		flightMaster()
		fly(4, 200)
		assert.are.equal(1, #sentLegs("PARTY"))
		-- a flight with seconds no flight can have: kept as a record, never offered
		flightMaster()
		fly(3, 9)
		assert.are.equal(1, #sentLegs("PARTY"))
		assert.are.same({}, legs["2>12"].t)
	end)

	it("offers nothing the others know already", function()
		local ns = wow.session()
		wow.world.group.party = true
		-- 2>5: facts with three measured flights, and two players who flew it
		receive(H(ns, 2, 5, 131), "Anna Sommer")
		receive(H(ns, 2, 5, 133), "Ben Winter")
		flightMaster()
		fly(2, 134)
		assert.are.equal(0, #sentLegs())
		assert.are.same({ 131, 133, 134 }, ns.Collector.flights.db.legs["2>5"].t)
	end)

	it("never sends a name, a position, a GUID, the installation or a token", function()
		local ns = wow.session()
		wow.freeChannel()
		wow.advance(10)
		wow.world.group.party, wow.world.guild = true, true
		flightMaster()
		fly(2, 135)
		wow.advance(200)
		local all = sentLegs()
		assert.is_true(#all >= 3, #all .. " messages") -- group, guild, channel
		for _, m in ipairs(all) do
			assert.matches("^h;1;%d+;%d+;%d+$", m.msg)
			for _, secret in ipairs({
				"Testchar",
				"Brightwood",
				"Testrealm",
				"Player-",
				"1429",
				BraindeadForeverCollectDB.install,
				BraindeadForeverCharDB.id,
				BraindeadForeverCharDB.run,
			}) do
				assert.is_nil(m.msg:find(secret, 1, true), secret .. " in " .. m.msg)
			end
		end
		assert.is_nil(ns.Collector.flights.db.legs["2>5"].who)
	end)
end)

describe("Flight legs in the exchange", function()
	it("puts a received leg into the flight vault, not into the find buffer, without the sender", function()
		local ns = wow.session()
		receive(H(ns, 2, 5, 131), "Anna Sommer")
		receive(H(ns, 22, 38, 5), "Mallory") -- 5 s over 3 km
		local f = ns.Collector.flights
		assert.are.equal(1, f.db.legs["2>5"].s)
		assert.are.same({ "h;1;2;5;131" }, (f:Since(0)))
		assert.are.equal(1, f.stats.implausible)
		ns.Collector.net:Flush()
		for seq = 1, ns.Collector.net.db.seq do
			assert.is_nil((ns.Collector.net.db.chunks[seq] or ""):find("h;", 1, true))
		end
		wow.fire("PLAYER_LOGOUT")
		local saved = json.encode(BraindeadForeverCollectDB.flights)
		assert.is_nil(saved:find("Anna", 1, true))
		assert.is_nil(saved:find("Mallory", 1, true))
		assert.are.equal(0, ns.Exchange.stats.bad)
	end)

	it("counts received legs towards the sender's limit like finds", function()
		local ns = wow.session()
		local X = ns.Exchange
		for i = 1, X.SENDER_MAX + 5 do
			receive(H(ns, 2, 5, 100 + i), "Mallory")
		end
		assert.is_true(X.muted.Mallory)
	end)

	it("relays on the channel only, one leg per 10 s at most, with a credit of the find pool", function()
		local ns = wow.session()
		local X = ns.Exchange
		wow.freeChannel()
		wow.advance(10)
		wow.world.group.party, wow.world.guild = true, true
		local spent = {}
		X.budget.Spend = function(_, pool)
			spent[pool] = (spent[pool] or 0) + 1
		end
		-- legs from the guild: the channel has not heard them
		local keys = { { 2, 5 }, { 2, 12 }, { 5, 12 }, { 5, 71 }, { 12, 5 }, { 5, 2 } }
		for i, k in ipairs(keys) do
			receive(H(ns, k[1], k[2], 0), "Guild Member " .. i, "GUILD")
		end
		local start = wow.clock
		wow.advance(120)
		local relays = sentLegs("CHANNEL")
		assert.are.equal(0, #sentLegs("PARTY") + #sentLegs("GUILD"), "relays go to the channel only")
		assert.are.equal(#keys, #relays)
		for i = 2, #relays do
			assert.is_true(relays[i].at - relays[i - 1].at >= ns.Flights.RELAY_GAP, "gap at " .. i)
		end
		assert.is_true(relays[1].at >= start)
		assert.are.equal(#keys, spent.finds)
		assert.is_nil(spent.runs)
		wow.advance(600)
		assert.are.equal(#keys, #sentLegs("CHANNEL"), "once per session")
	end)

	it("lets an own find that is due go first and relays nothing without a credit", function()
		local ns = wow.session()
		local X = ns.Exchange
		wow.freeChannel()
		wow.advance(10)
		-- twelve legs of the facts from the guild: two minutes of relays
		local keys = {}
		for key in pairs(ns.FlightFacts.legs) do
			keys[#keys + 1] = key
		end
		table.sort(keys)
		for i = 1, 12 do
			local a, b = keys[i]:match("^(%d+)>(%d+)$")
			receive(H(ns, tonumber(a), tonumber(b), 0), "Guild Member " .. i, "GUILD")
		end
		wow.world.loot =
			{ { link = "|Hitem:2589:::|h[x]|h", sources = { "GameObject-0-1465-0-2105-2843-0000ABC124", 1 } } }
		wow.fire("LOOT_OPENED", false, false)
		local due
		for _, item in ipairs(X.queue) do
			if item.dist == "CHANNEL" then
				due = item.at
			end
		end
		wow.advance(due - wow.clock + X.CHANNEL_GAP + 1)
		local first
		for _, m in ipairs(wow.world.sent) do
			if m.dist == "CHANNEL" and m.at >= due then
				first = first or m
			end
		end
		assert.are.equal("o;1;2843;1429;4231;6512", first.msg)
		assert.is_true(#sentLegs("CHANNEL") >= 2, "relays went before the find was due")
		assert.is_true(#sentLegs("CHANNEL") < 12, "and some still wait")
		-- no credit, no relay
		local before = #sentLegs("CHANNEL")
		X.budget.Has = function()
			return false
		end
		ns.Collector.flights:StartSession()
		wow.advance(120)
		assert.are.equal(before, #sentLegs("CHANNEL"))
	end)
end)

describe("Flight legs from the game to the analysis", function()
	local function useNodeCompression()
		C_EncodingUtil.SerializeJSON = json.encode
		C_EncodingUtil.CompressString = function(s, method)
			return node.compress(s, method)
		end
	end

	local function tmp(content)
		local path = os.tmpname()
		local fh = assert(io.open(path, "wb"))
		fh:write(content or "")
		fh:close()
		return path
	end

	it("goes Lua -> export -> website decoder (CSV) -> tools/routekit/observe.py", function()
		local ns = wow.session()
		useNodeCompression()
		receive(H(ns, 2, 5, 131), "Anna Sommer")
		receive(H(ns, 2, 12, 0), "Ben Winter")
		receive(H(ns, 22, 38, 5), "Mallory") -- never in the export
		local text, _, _, _, _, flightsLast = assert(ns.Collector.BuildExport(false))
		local out = assert(node.decode(text))
		local payload = node.parseJSON(out)
		assert.are.same({ "h;1;2;5;131", "h;1;2;12;0" }, payload.flights)
		assert.are.equal(1, payload.flightsFrom)
		for _, secret in ipairs({ "Anna", "Ben", "Mallory", "Testchar" }) do
			assert.is_nil(out:find(secret, 1, true), secret .. " in the export")
		end
		assert.are.equal("from,to,seconds\n2,5,131\n2,12,0\n", node.flights(text))
		-- the analysis: received legs and seconds next to the own records; the same export twice
		-- counts once
		local path = tmp(text .. "\n" .. text)
		local p = assert(
			io.popen(
				"python3 -c 'import json, sys; from tools.routekit import observe; "
					.. "print(json.dumps(observe.flights(observe.decode(open(sys.argv[1]).read())), sort_keys=True))' "
					.. path
					.. " 2>&1"
			)
		)
		local result = p:read("*a")
		p:close()
		os.remove(path)
		local trips = {}
		for _, t in ipairs(node.parseJSON(result)) do
			trips[t.key] = t
		end
		assert.are.same({ { 2, 5 } }, trips["leg:2>5"].paths)
		assert.are.same({ { 2, 12 } }, trips["leg:2>12"].paths)
		assert.are.same({ ["131"] = 1 }, trips["net:2>5"].seconds)
		assert.is_nil(trips["net:2>12"])
		assert.is_nil(trips["leg:22>38"])
		-- acknowledged after the copy: the next export carries only what came since
		ns.Collector.flights:Ack(flightsLast)
		receive(H(ns, 5, 12, 70), "Cleo Herbst")
		payload = node.parseJSON(assert(node.decode(assert(ns.Collector.BuildExport(false)))))
		assert.are.same({ "h;1;5;12;70" }, payload.flights)
		assert.are.equal(3, payload.flightsFrom)
	end)
end)

-- One line of the simulation table in docs/ROUTE-FORMAT.md §Flights in the exchange.
local function row(n, r, secs)
	local f, reach = r.flights, r.flights.reach
	return ("%d clients (%.0f online, %.1f s): received per client and s mean %.3f, busiest %.3f, most in 60 s %d; flight messages %d (%.3f per online hour, own flights %d, relays %d), finds %d; legs of others that reached an exporter %.3f (at least one of %d exporters %.3f), legs unknown to the facts %.3f (%.3f), legs with seconds %.3f (%.3f); flight messages per round %s"):format(
		n,
		r.online,
		secs,
		r.receivedPerSec,
		r.maxReceivedPerSec,
		r.maxWindow,
		f.messages,
		f.perHour,
		f.offered,
		f.relayed,
		f.finds,
		reach.legs.mean,
		10,
		reach.legs.any,
		reach.hidden.mean,
		reach.hidden.any,
		reach.timed.mean,
		reach.timed.any,
		table.concat(f.byRound, " ")
	)
end

local function sum(list, from, to)
	local s = 0
	for i = from, to do
		s = s + (list[i] or 0)
	end
	return s
end

describe("Spread simulation with flight legs", function()
	it("keeps 1,000 clients under 0.5 messages per second and 60 per minute, legs reach the exporters", function()
		local ns = pure()
		local t = os.clock()
		local r = spread.Run(ns, { clients = 1000, flights = true })
		io.stdout:write("\n[flights] " .. row(1000, r, os.clock() - t) .. "\n")
		assert.is_true(r.receivedPerSec <= MEAN_MAX, r.receivedPerSec)
		assert.is_true(r.maxReceivedPerSec <= MEAN_MAX, r.maxReceivedPerSec)
		assert.is_true(r.maxWindow <= WINDOW_MAX, r.maxWindow)
		local f = r.flights
		assert.is_true(f.messages > 0)
		assert.are.equal(97, f.legs)
		-- most legs other players saw reach an exporter, the ones the facts lack too
		assert.is_true(f.reach.legs.any >= 0.9, f.reach.legs.any)
		assert.is_true(f.reach.hidden.any >= 0.9, f.reach.hidden.any)
		assert.is_true(f.reach.timed.any >= 0.5, f.reach.timed.any)
	end)

	it("counter-check: without saturation the flight traffic does not fall as the network becomes known", function()
		local rounds = 30
		local ns = pure()
		local t = os.clock()
		local with = spread.Run(ns, { clients = 100, flights = true, rounds = rounds })
		io.stdout:write("\n[flights] with saturation, " .. row(100, with, os.clock() - t) .. "\n")
		ns = pure()
		ns.Flights.SOURCES_MIN = math.huge -- every leg adds something for others, always
		t = os.clock()
		local without = spread.Run(ns, { clients = 100, flights = true, rounds = rounds })
		io.stdout:write("\n[flights] without saturation, " .. row(100, without, os.clock() - t) .. "\n")
		local early, late = sum(with.flights.byRound, 1, 10), sum(with.flights.byRound, rounds - 9, rounds)
		local lateWithout = sum(without.flights.byRound, rounds - 9, rounds)
		io.stdout:write(
			("[flights] flight messages in rounds 1-10 %d, in rounds %d-%d %d with and %d without saturation\n"):format(
				early,
				rounds - 9,
				rounds,
				late,
				lateWithout
			)
		)
		assert.is_true(late <= 0.75 * early, late .. " of " .. early)
		assert.is_true(lateWithout >= 1.5 * late, lateWithout .. " against " .. late)
		-- the budget holds either way: the legs only use credits of the find pool
		assert.is_true(without.receivedPerSec <= MEAN_MAX, without.receivedPerSec)
	end)
end)
