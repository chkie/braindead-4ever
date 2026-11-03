-- SPDX-License-Identifier: GPL-3.0-or-later
-- Run times in the exchange (plan "Laufzeiten im Austausch", 2026-11-02, docs/RUN-TIMES.md): message
-- kind "s", the run vault (Collector/Runs.lua) with dedup, conflicts, plausibility band and sender
-- limits, relaying under the channel limit, the sections from the route (Routes/Guide.lua) and the export
-- with the decoder's run table and tools/routekit/runs.py. The spread simulation and the channel budget
-- are in spec/channel_budget_spec.lua.
local wow = require("spec.helpers.wow")
local node = require("spec.helpers.node")
local json = require("spec.helpers.json")

local DAY = 20762 -- 2026-11-05, the server day of the test world

local function pure()
	wow.reset()
	return wow.loadFiles({
		"Braindead4Ever/Locales/enUS.lua",
		"Braindead4Ever/Core/Util.lua",
		"Braindead4Ever/Collector/Proto.lua",
		"Braindead4Ever/Collector/Runs.lua",
		"Braindead4Ever/Routes/XP.lua",
	})
end

-- A run message. o: race, class, mode, version, inOrder, level, day.
local function S(ns, tok, kind, sec, secs, xp, o)
	o = o or {}
	local level = o.level or (kind == "l" and sec + 1 or 10)
	return assert(
		ns.Proto.Format(
			"s",
			tok,
			o.race or 1,
			o.class or 1,
			o.mode or "s",
			kind,
			sec,
			o.version or 0,
			secs,
			xp,
			o.inOrder or 100,
			level,
			o.day or DAY
		)
	)
end

-- A vault on a clock the test moves (t.now).
local function vault(ns, db)
	local t = { now = 0 }
	local runs = ns.Runs.New(db or {}, {
		clock = function()
			return t.now
		end,
		epoch = function()
			return DAY * 86400 + 3600
		end,
		curve = ns.XP.TO_LEVEL,
	})
	return runs, t
end

local function hear(ns, runs, msg, who, channel)
	return runs:Hear(assert(ns.Proto.Parse(msg)), msg, who, channel ~= false)
end

-- Sections 1..9 of a run from level 1 to 10 in `total` seconds: "even" gives every level the same
-- time, "xp" shares the time by the XP each level needs.
local function run1to10(ns, tok, total, split)
	local curve, sum, out = ns.XP.TO_LEVEL, 0, {}
	for l = 1, 9 do
		sum = sum + curve[l]
	end
	for l = 1, 9 do
		local secs = split == "even" and math.floor(total / 9) or math.floor(total * curve[l] / sum)
		out[l] = S(ns, tok, "l", l, secs, curve[l])
	end
	return out
end

describe("Proto: run sections", function()
	it("formats and parses a section with IDs and numbers only", function()
		local ns = pure()
		local P = ns.Proto
		local msg = S(ns, "abc123", "l", 5, 600, 2800, { race = 2, class = 9, mode = "e", inOrder = 87 })
		assert.are.equal("s;1;abc123;2;9;e;l;5;0;600;2800;87;6;20762", msg)
		assert.are.same({ kind = "s", n = 12, "abc123", 2, 9, "e", "l", 5, 0, 600, 2800, 87, 6, 20762 }, P.Parse(msg))
		assert.are.equal("s;abc123;l;5", P.Key(P.Parse(msg)))
		local widest =
			S(ns, "zzzzzz", "m", 9999991, 9999999, 9999999, { race = 9999999, class = 9999999, version = 9999999 })
		assert.is_true(#widest <= 255, "longest message: " .. #widest)
	end)

	it("sends nothing half-valid", function()
		local ns = pure()
		local P = ns.Proto
		local ok = { "abc123", 1, 1, "s", "l", 5, 0, 600, 2800, 100, 6, DAY }
		assert.is_string(P.Format("s", unpack(ok)))
		local function with(i, v)
			local f = { unpack(ok) }
			f[i] = v
			return P.Format("s", unpack(f))
		end
		assert.is_nil(with(1, "abc12")) -- token too short
		assert.is_nil(with(1, "Anna S")) -- a name is no token
		assert.is_nil(with(4, "x")) -- unknown mode
		assert.is_nil(with(5, "q")) -- unknown section kind
		assert.is_nil(with(8, 0)) -- no seconds
		assert.is_nil(with(10, 101)) -- share over 100
		assert.is_nil(with(11, 0)) -- level 0
		assert.is_nil(with(9, 1.5))
		assert.is_nil(P.Format("s", unpack(ok, 1, 11))) -- field missing
		assert.are.same({ nil, "bad" }, { P.Parse("s;1;abc123;1;1;s;l;5;0;600;2800;100;6") })
		assert.are.same({ nil, "bad" }, { P.Parse("s;1;abc123;1;1;s;l;5;0;600;2800;100;6;20762;1") })
	end)

	it("is skipped by a reader that does not know it", function()
		local ns = pure()
		local msg = S(ns, "abc123", "l", 5, 600, 2800)
		ns.Proto.KINDS.s = nil -- an addon version before this kind
		assert.are.same({ nil, "skip" }, { ns.Proto.Parse(msg) })
	end)

	it("numbers route modules like tools/routekit/runs.py", function()
		local ns = pure()
		local fh = assert(io.open("tools/tests/fixtures/module_numbers.json", "rb"))
		local cases = json.decode(fh:read("*a")).cases
		fh:close()
		assert.is_true(#cases >= 3)
		for _, c in ipairs(cases) do
			assert.are.equal(c.number, ns.Proto.ModuleNumber(c.module), c.module)
		end
	end)
end)

describe("Run vault", function()
	it("keeps a section once, from whoever and however often it comes", function()
		local ns = pure()
		local runs = vault(ns)
		local msg = S(ns, "abc123", "l", 5, 600, 2800)
		assert.are.equal("new", hear(ns, runs, msg, "Anna Sommer"))
		assert.are.equal("dup", hear(ns, runs, msg, "Ben Winter"))
		assert.are.equal("dup", hear(ns, runs, msg, "Anna Sommer", false))
		assert.are.equal(1, runs:Count())
		assert.are.same({ msg }, (runs:Since(0)))
	end)

	it("drops both values when the same token reports a section twice with different values", function()
		local ns = pure()
		local runs = vault(ns)
		local a = S(ns, "abc123", "l", 5, 600, 2800)
		local b = S(ns, "abc123", "l", 5, 900, 2800)
		hear(ns, runs, a, "Anna Sommer")
		assert.are.equal("conflict", hear(ns, runs, b, "Ben Winter"))
		assert.are.equal(0, runs:Count())
		assert.are.equal("blocked", hear(ns, runs, a, "Cleo Herbst"), "the key stays blocked")
		assert.are.equal("new", hear(ns, runs, S(ns, "abc123", "l", 6, 700, 3600), "Cleo Herbst"))
	end)

	it("keeps its own section when someone else sends another value for it", function()
		local ns = pure()
		local runs = vault(ns)
		local mine = S(ns, "own111", "l", 5, 600, 2800)
		assert.is_true(runs:AddOwn(mine))
		assert.is_false(runs:AddOwn(mine), "never twice")
		assert.are.equal("conflict", hear(ns, runs, S(ns, "own111", "l", 5, 61, 2800), "Mallory"))
		assert.are.same({ mine }, (runs:Since(0)))
	end)

	it("drops a faked five-minute run from level 1 to 10, keeps a real pace", function()
		local ns = pure()
		local runs = vault(ns)
		for _, split in ipairs({ "even", "xp" }) do
			for _, msg in ipairs(run1to10(ns, "fake" .. (split == "xp" and "01" or "02"), 300, split)) do
				assert.are.equal("implausible", hear(ns, runs, msg, "Mallory " .. split), msg)
			end
		end
		assert.are.equal(0, runs:Count())
		-- the Classic Era record from 1 to 20 took 5:03 h; 1 to 10 in 3 hours is fast but real
		for _, msg in ipairs(run1to10(ns, "real01", 3 * 3600, "xp")) do
			assert.are.equal("new", hear(ns, runs, msg, "Anna Sommer"), msg)
		end
		assert.are.equal(9, runs:Count())
	end)

	it("checks modules by their XP per hour and drops days in the future and stuck clocks", function()
		local ns = pure()
		local runs = vault(ns)
		local maxRate = ns.Runs.MaxRate(10) -- 1.5 times the 1-20 record pace
		assert.are.equal(math.floor(167200 * 3600 / (5 * 3600 + 2 * 60 + 59) * 1.5), math.floor(maxRate))
		local fast = math.ceil(maxRate * 600 / 3600) + 50 -- XP of ten minutes above the band
		assert.are.equal("implausible", hear(ns, runs, S(ns, "mod001", "m", 4711, 600, fast), "A"))
		assert.are.equal("new", hear(ns, runs, S(ns, "mod001", "m", 4712, 600, fast - 100), "A"))
		assert.are.equal("implausible", hear(ns, runs, S(ns, "mod001", "m", 4713, 10, 0), "A"))
		assert.are.equal("implausible", hear(ns, runs, S(ns, "mod001", "l", 7, 4000, 0, { day = DAY + 2 }), "A"))
		assert.are.equal("implausible", hear(ns, runs, S(ns, "mod001", "l", 8, 48 * 3600 + 1, 0), "A"))
		assert.are.equal("implausible", hear(ns, runs, S(ns, "mod001", "l", 9, 4000, 0, { level = 9 }), "A"))
		-- a level section counts at least the XP of its level, whatever xp it claims
		assert.are.equal("implausible", hear(ns, runs, S(ns, "mod001", "l", 9, 60, 10), "A"))
	end)

	it("mutes a sender who floods run messages and limits the tokens one sender brings in", function()
		local ns = pure()
		local runs, t = vault(ns)
		for i = 1, 100 do
			hear(ns, runs, S(ns, ("fl%04d"):format(i), "l", 5, 600, 2800), "Mallory")
		end
		assert.are.equal(ns.Runs.SENDER_MAX, runs:Count())
		assert.are.equal(100 - ns.Runs.SENDER_MAX, runs.stats.muted)
		-- at the honest relay pace of one message per 10 s: the limit of new tokens per session
		for i = 1, 200 do
			t.now = t.now + 10
			hear(ns, runs, S(ns, ("tk%04d"):format(i), "l", 5, 600, 2800), "Ben Winter")
		end
		assert.are.equal(ns.Runs.SENDER_MAX + ns.Runs.NEW_TOKENS_MAX, runs:Count())
		assert.are.equal(200 - ns.Runs.NEW_TOKENS_MAX, runs.stats.limit)
		-- known tokens are no originals: more sections of them pass
		assert.are.equal("new", hear(ns, runs, S(ns, "tk0001", "l", 6, 700, 3600), "Ben Winter"))
		runs:StartSession() -- a new session forgets the limits
		assert.are.equal("new", hear(ns, runs, S(ns, "fl9999", "l", 5, 600, 2800), "Mallory"))
	end)

	it("gives way with the oldest sections first", function()
		local ns = pure()
		local old = ns.Runs.VAULT_MAX
		ns.Runs.VAULT_MAX = 5
		local runs = vault(ns)
		local msgs = {}
		for i = 1, 8 do
			msgs[i] = S(ns, ("rv%04d"):format(i), "l", 5, 600, 2800)
			hear(ns, runs, msgs[i])
		end
		ns.Runs.VAULT_MAX = old
		assert.are.same({ msgs[4], msgs[5], msgs[6], msgs[7], msgs[8] }, (runs:Since(0)))
		assert.is_false(runs:Has(ns.Runs.KeyOf(msgs[1])))
	end)

	it("relays every section once per session, own first, then the newest, one per 10 s", function()
		local ns = pure()
		local db = {}
		local runs = vault(ns, db)
		local a = S(ns, "aaaaaa", "l", 5, 600, 2800)
		local b = S(ns, "bbbbbb", "l", 5, 600, 2800)
		local c = S(ns, "cccccc", "l", 5, 600, 2800)
		local mine = S(ns, "own111", "l", 5, 600, 2800)
		hear(ns, runs, a, "A")
		hear(ns, runs, b, "B")
		runs:AddOwn(mine)
		hear(ns, runs, c, "C")
		-- heard on the channel this session, own one sent by the exchange: nothing to relay now
		assert.is_nil(runs:NextRelay())
		-- next session (the saved table as the client loads it)
		local t
		runs, t = vault(ns, db)
		local out = {}
		for i = 1, 6 do
			t.now = i * 5
			out[#out + 1] = runs:NextRelay() or false
		end
		assert.are.same({ mine, false, c, false, b, false }, out)
		t.now = 100
		hear(ns, runs, a, "D") -- someone else just told the channel
		assert.is_nil(runs:NextRelay())
		-- a section from the group or the guild has not been on the channel: it goes out
		local d = S(ns, "dddddd", "l", 5, 600, 2800)
		hear(ns, runs, d, "E", false)
		assert.are.equal(d, runs:NextRelay())
		t.now = 200
		assert.is_nil(runs:NextRelay(), "once per session")
	end)

	it("exports the sections not exported yet", function()
		local ns = pure()
		local runs = vault(ns)
		hear(ns, runs, S(ns, "aaaaaa", "l", 5, 600, 2800))
		local list, last = runs:Since(runs.db.acked)
		assert.are.equal(1, #list)
		runs:Ack(last)
		hear(ns, runs, S(ns, "bbbbbb", "l", 5, 600, 2800))
		assert.are.equal(1, #(runs:Since(runs.db.acked)))
		assert.are.equal(2, #(runs:Since(0)))
	end)
end)

-- Messages sent with the addon prefix and kind "s", optionally only on one distribution.
local function sentRuns(dist)
	local out = {}
	for _, m in ipairs(wow.world.sent) do
		if m.prefix == "BDF" and m.msg:sub(1, 2) == "s;" and (not dist or m.dist == dist) then
			out[#out + 1] = m
		end
	end
	return out
end

local function receive(msg, sender, dist)
	wow.fire("CHAT_MSG_ADDON", "BDF", msg, dist or "CHANNEL", sender, "", 0, 5, "BraindeadShare", 0)
	wow.readInbox()
end

describe("Run times in the exchange", function()
	it("puts a received section into the run vault, not into the find buffer, without the sender", function()
		local ns = wow.session()
		local msg = S(ns, "abc123", "l", 5, 600, 2800)
		receive(msg, "Anna Sommer")
		assert.are.equal(1, ns.Collector.runs:Count())
		ns.Collector.net:Flush()
		for seq = 1, ns.Collector.net.db.seq do
			assert.is_nil((ns.Collector.net.db.chunks[seq] or ""):find("abc123", 1, true))
		end
		assert.are.same({ msg }, BraindeadForeverCollectDB.runs.list and { BraindeadForeverCollectDB.runs.list[1] })
		for k in pairs(BraindeadForeverCollectDB.runs) do
			assert.is_nil(tostring(k):find("Anna"))
		end
		assert.are.equal(0, ns.Exchange.stats.bad)
	end)

	it("relays at most one message per 10 s, on the channel only, below the channel's own limit", function()
		local ns = wow.session()
		wow.freeChannel()
		wow.advance(10) -- channel joined
		wow.world.group.party, wow.world.guild = true, true
		-- 100 sections from the guild: the channel has not heard them
		for i = 1, 100 do
			receive(S(ns, ("gu%04d"):format(i), "l", 5, 600, 2800), "Sender " .. math.ceil(i / 20), "GUILD")
		end
		assert.are.equal(100, ns.Collector.runs:Count())
		local start = wow.clock
		wow.advance(600)
		local relays = sentRuns("CHANNEL")
		assert.are.equal(0, #sentRuns("PARTY") + #sentRuns("GUILD"), "relays go to the channel only")
		assert.is_true(#relays <= 61, #relays .. " relays in 10 minutes")
		assert.is_true(#relays >= 55, #relays .. " relays in 10 minutes")
		for i = 2, #relays do
			assert.is_true(relays[i].at - relays[i - 1].at >= ns.Runs.RELAY_GAP, "gap at " .. i)
		end
		-- the channel itself takes one message per 2 s (300 in 10 minutes): relays use at most a fifth
		local capacity = 600 / ns.Exchange.CHANNEL_GAP
		assert.is_true(#relays / capacity <= 0.21)
		assert.are.equal(#relays, ns.Exchange.stats.relayed)
		assert.is_true(relays[1].at >= start)
	end)

	it("lets an own message that is due go first", function()
		local ns = wow.session()
		wow.freeChannel()
		wow.advance(10)
		for i = 1, 20 do
			receive(S(ns, ("gu%04d"):format(i), "l", 5, 600, 2800), "Sender " .. i, "GUILD")
		end
		-- an own find waits 30 to 90 s for the channel; while it is due, no relay is queued before it
		wow.world.loot =
			{ { link = "|Hitem:2589:::|h[x]|h", sources = { "GameObject-0-1465-0-2105-2843-0000ABC124", 1 } } }
		wow.fire("LOOT_OPENED", false, false)
		local due
		for _, item in ipairs(ns.Exchange.queue) do
			if item.dist == "CHANNEL" then
				due = item.at
			end
		end
		assert.is_number(due)
		wow.advance(due - wow.clock + ns.Exchange.CHANNEL_GAP + 1) -- a relay just before may hold the channel 2 s
		local first
		for _, m in ipairs(wow.world.sent) do
			if m.dist == "CHANNEL" and m.at >= due then
				first = first or m
			end
		end
		assert.are.equal("o;1;2843;1429;4231;6512", first.msg)
	end)

	it("never names the player, the realm, a GUID or the installation", function()
		local ns = wow.session({ player = { level = 1, xp = 0 } })
		wow.world.group.party = true
		wow.advance(120)
		wow.fire("QUEST_LOG_UPDATE")
		wow.world.player.level = 2
		wow.fire("PLAYER_LEVEL_UP", 2)
		receive(S(ns, "abc123", "l", 5, 600, 2800), "Anna Sommer")
		local all = {}
		for _, m in ipairs(sentRuns()) do
			all[#all + 1] = m.msg
		end
		assert.is_true(#all >= 1)
		for _, msg in ipairs(ns.Collector.runs:Since(0)) do
			all[#all + 1] = msg
		end
		local text = table.concat(all, "\n")
		for _, secret in ipairs({
			"Testchar",
			"Brightwood",
			"Testrealm",
			"Player-",
			"Anna",
			BraindeadForeverCollectDB.install,
			BraindeadForeverCharDB.id,
		}) do
			assert.is_nil(text:find(secret, 1, true), secret .. " in a run message")
		end
		assert.matches("^[%w;]+$", all[1])
		-- the token sent is the character's rolled one, no piece of the character or installation ID
		local tok = all[1]:match("^s;1;(%w+);")
		assert.are.equal(BraindeadForeverCharDB.run, tok)
		assert.is_nil(BraindeadForeverCharDB.id:find(tok, 1, true))
		assert.is_nil(BraindeadForeverCollectDB.install:find(tok, 1, true))
		-- the export as the website reads it: no name, realm or GUID anywhere, run sections without IDs
		C_EncodingUtil.SerializeJSON = json.encode
		C_EncodingUtil.CompressString = function(str, method)
			return node.compress(str, method)
		end
		local out = assert(node.decode(assert(ns.Collector.BuildExport(true))))
		for _, secret in ipairs({ "Testchar", "Brightwood", "Testrealm", "Player-", "Anna" }) do
			assert.is_nil(out:find(secret, 1, true), secret .. " in the export")
		end
		local runs = table.concat(node.parseJSON(out).runs, "\n")
		assert.is_true(#runs > 0)
		for _, id in ipairs({ BraindeadForeverCollectDB.install, BraindeadForeverCharDB.id }) do
			assert.is_nil(runs:find(id, 1, true), id .. " in the exported run sections")
		end
	end)
end)

-- Own records of one kind as field lists.
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

-- Fields of a "run" record from the token on: token, race, class, mode, kind, section, version,
-- seconds, xp, in order, level, day.
local function runFields(r)
	return { unpack(r, 6, 17) }
end

local function play(seconds, step)
	for _ = 1, seconds / (step or 60) do
		wow.advance(step or 60)
		wow.fire("QUEST_LOG_UPDATE")
	end
end

local function levelUp(level)
	wow.world.player.level = level
	wow.fire("PLAYER_LEVEL_UP", level)
end

describe("Run sections from play", function()
	it("reports a level with the route: seconds, XP, steps done in route order, speed mode", function()
		local ns = wow.session({ player = { level = 1, xp = 0 } })
		wow.world.group.party = true
		for _ = 1, 4 do
			play(60)
			ns.Route.Check()
		end
		wow.world.player.xp = 300
		wow.fire("PLAYER_XP_UPDATE", "player")
		levelUp(2)
		local r = records(ns, "run")
		assert.are.equal(1, #r)
		local f = runFields(r[1])
		assert.are.same(
			{ BraindeadForeverCharDB.run, "1", "1", "s", "l", "1", "0", "240", "300", "100", "2", tostring(DAY) },
			f
		)
		local party = sentRuns("PARTY")
		assert.are.equal(1, #party)
		assert.are.equal("s;1;" .. table.concat(f, ";"), party[1].msg)
		assert.is_true(ns.Collector.runs:Has("s;" .. BraindeadForeverCharDB.run .. ";l;1"))
	end)

	it("reports free play without a route, with the window paused, and counts skipped steps", function()
		-- no route for this race
		local ns = wow.session({ player = { level = 1, xp = 0, race = { "X", "X", 99 } } })
		assert.is_nil(ns.Route.Runtime())
		play(300)
		levelUp(2)
		local f = runFields(records(ns, "run")[1])
		assert.are.same({ "f", "l", "1", "300", "0", "2" }, { f[4], f[5], f[6], f[8], f[10], f[11] })
		-- the guidance paused for the whole level
		ns = wow.session({ player = { level = 1, xp = 0 } })
		ns.UI.SetPaused(true)
		play(300)
		levelUp(2)
		f = runFields(records(ns, "run")[1])
		assert.are.same({ "f", "300" }, { f[4], f[8] })
		-- with the route and one skipped step (it takes its follow-up steps with it): the share of the
		-- passed steps that were done
		ns = wow.session({ player = { level = 1, xp = 0 } })
		for i = 1, 4 do
			play(60)
			if i == 2 then
				ns.Route.Skip()
			else
				ns.Route.Check()
			end
		end
		local rt, done = ns.Route.Runtime(), 0
		for j = 1, rt.cur - 1 do
			if rt:StepState(j) == "done" then
				done = done + 1
			end
		end
		assert.are.equal(3, done)
		levelUp(2)
		f = runFields(records(ns, "run")[1])
		assert.are.same({ "s", tostring(math.floor(100 * done / (rt.cur - 1) + 0.5)) }, { f[4], f[10] })
		assert.is_true(rt.cur - 1 > 4, "the skip passed more steps than the four played")
	end)

	it("keeps the seconds over /reload and reports a level only once", function()
		wow.session({ player = { level = 1, xp = 0 } })
		play(180)
		wow.fire("PLAYER_LOGOUT")
		local saved =
			{ char = _G.BraindeadForeverCharDB, saved = _G.BraindeadForeverDB, collect = _G.BraindeadForeverCollectDB }
		local ns = wow.session({
			char = saved.char,
			saved = saved.saved,
			collect = saved.collect,
			player = { level = 1, xp = 40 },
		})
		play(120)
		levelUp(2)
		levelUp(2) -- the same event twice
		local r = records(ns, "run")
		assert.are.equal(1, #r)
		assert.are.equal("300", runFields(r[1])[8])
		-- a /reload right after the level-up starts nothing twice
		wow.fire("PLAYER_LOGOUT")
		ns = wow.session({
			char = _G.BraindeadForeverCharDB,
			saved = _G.BraindeadForeverDB,
			collect = _G.BraindeadForeverCollectDB,
			player = { level = 2, xp = 0 },
		})
		play(240)
		levelUp(3)
		local all = ns.Collector.runs:Since(0)
		assert.are.equal(2, #all)
		assert.matches(";l;1;", all[1])
		assert.matches(";l;2;0;240;", all[2])
	end)

	it("leaves out the level the addon first sees in the middle", function()
		local ns = wow.session() -- level 5 with 120 XP: a partial level
		play(300)
		levelUp(6)
		assert.are.same({}, records(ns, "run"))
		play(600)
		levelUp(7)
		local r = records(ns, "run")
		assert.are.equal(1, #r)
		assert.are.same({ "l", "6", "600" }, { runFields(r[1])[5], runFields(r[1])[6], runFields(r[1])[8] })
	end)

	it("reports a module played from its first step past its last", function()
		local ns = wow.session()
		local first = ns.Route.Current()
		local module, n = first.module, 0
		while ns.Route.Current() and ns.Route.Current().module == module do
			play(60)
			n = n + 1
			ns.Route.Check()
		end
		local r = records(ns, "run")
		assert.are.equal(1, #r)
		local f = runFields(r[1])
		local m = ns.Route.Module(module)
		assert.are.same(
			{ "s", "m", tostring(ns.Proto.ModuleNumber(module)), tostring(m.version), tostring(n * 60), "100" },
			{ f[4], f[5], f[6], f[7], f[8], f[10] }
		)
		assert.are.equal(1, #records(ns, "split"), "the clean split record stays")
	end)
end)

describe("Run times from the game to the analysis", function()
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

	it("goes Lua -> export -> website decoder (CSV) -> tools/routekit/runs.py", function()
		local ns = wow.session({ player = { level = 1, xp = 0 } })
		useNodeCompression()
		play(600)
		levelUp(2) -- own level 1: 600 s in speed mode, no route step passed
		-- three warriors of other players on level 1: two follow the route, one plays free
		receive(S(ns, "aaaaaa", "l", 1, 400, 400, { mode = "s" }), "Anna Sommer")
		receive(S(ns, "bbbbbb", "l", 1, 500, 400, { mode = "s", inOrder = 90 }), "Ben Winter")
		receive(S(ns, "cccccc", "l", 1, 900, 400, { mode = "f", inOrder = 0 }), "Cleo Herbst")
		receive(S(ns, "dddddd", "l", 5, 100, 2800), "Mallory") -- level 5 in 100 s: never in the vault
		local text = assert(ns.Collector.BuildExport(false))
		local payload = node.parseJSON(assert(node.decode(text)))
		assert.are.equal(4, #payload.runs)
		local csv = assert(node.runs(text))
		local lines = {}
		for line in csv:gmatch("[^\n]+") do
			lines[#lines + 1] = line
		end
		assert.are.equal("token,race,class,mode,kind,section,version,seconds,xp,in_order,level,day,source", lines[1])
		assert.are.equal(5, #lines, "own section once (record and vault), three received")
		assert.is_nil(csv:find("Anna", 1, true))
		local inPath, outPath = tmp(csv), tmp()
		local p = assert(io.popen("python3 -m tools.routekit runs " .. inPath .. " --json " .. outPath .. " 2>&1"))
		local log = p:read("*a")
		p:close()
		local fh = assert(io.open(outPath, "rb"))
		local result = node.parseJSON(fh:read("*a"))
		fh:close()
		os.remove(inPath)
		os.remove(outPath)
		assert.matches("'rows': 4", log)
		local groups = {}
		for _, g in ipairs(result) do
			groups[g.mode .. "/" .. g.group] = g
		end
		assert.are.same({ 2, 450 }, { groups["s/follows"].runs, groups["s/follows"].seconds })
		-- the own level passed no route step (none in route order): neither following nor free
		assert.are.same({ 1, 600 }, { groups["s/partial"].runs, groups["s/partial"].seconds })
		assert.are.same({ 1, 900 }, { groups["f/free"].runs, groups["f/free"].seconds })
		assert.are.equal("l", groups["s/follows"].kind)
		assert.are.equal(1, groups["s/follows"].section)
	end)
end)
