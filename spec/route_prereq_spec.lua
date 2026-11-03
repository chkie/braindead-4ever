-- SPDX-License-Identifier: GPL-3.0-or-later
-- Prerequisites from player data (Welle 4, task 3): the rule shared with tools/routekit/prereq.py,
-- what the collector records when an NPC offers or a player takes a quest, the exchange message,
-- and how the route uses confirmed prerequisites at once and marks the chain incomplete until then.
-- Simulated runs: three players in three sessions, two of them reach the third through the exchange.
local wow = require("spec.helpers.wow")
local json = require("spec.helpers.json")

local function fixture()
	local fh = assert(io.open("tools/tests/fixtures/prereq_cases.json", "rb"))
	local t = json.decode(fh:read("*a"))
	fh:close()
	return t.cases
end

local NPC = { guid = "Creature-0-1-0-1-197-0000000001", name = "Marshal" }

local function pure()
	wow.reset({})
	return wow.loadFiles({ "BraindeadForever/Routes/Prereq.lua" })
end

-- Records of one kind in the collector's own buffer, split into fields.
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

local function sentPrereq()
	local out = {}
	for _, m in ipairs(wow.world.sent) do
		if m.prefix == "BDF" and m.msg:match("^p;") then
			out[#out + 1] = m.msg
		end
	end
	return out
end

-- The player talks to the NPC, hands in `done` and takes `take`, like the client reports it.
local function visit(done, take)
	local W = wow.world
	W.npc = NPC
	W.offers = { 900099 } -- the NPC lists its offers first; `take` is not among them yet
	wow.fire("GOSSIP_SHOW")
	if done then
		W.questLog = { { questID = done, complete = true } }
		W.questID = done
		wow.fire("QUEST_COMPLETE")
		W.questLog = {}
		W.completed[done] = true
		wow.fire("QUEST_REMOVED", done, false)
		wow.fire("QUEST_TURNED_IN", done, 100, 0)
	end
	if take then
		W.questID = take
		wow.fire("QUEST_DETAIL", 0)
		W.questLog = { { questID = take, objectives = {} } }
		wow.fire("QUEST_ACCEPTED", take)
	end
	wow.advance(1.5)
end

describe("Prerequisite rule", function()
	local P = pure().Prereq

	it("agrees with the Python rule on every shared case", function()
		for _, c in ipairs(fixture()) do
			local store = P.New({})
			for _, o in ipairs(c.obs) do
				store:Add(c.q, o.t, o.l, o.u == 1, o.d, o.n)
			end
			local state, groups = store:Result(c.q)
			assert.are.equal(c.state, state, c.name)
			assert.are.same(c.pre, groups, c.name)
		end
	end)

	it("keeps observations as one string per player and keeps refutations of players over the limit", function()
		local db = {}
		local store = P.New(db)
		for i = 1, P.OBS_MAX + 3 do
			store:Add(900002, ("t%05d"):format(i), 0, false, {}, i == P.OBS_MAX + 2 and { 900001 } or {})
		end
		local n = 0
		for _, v in pairs(db.obs[900002]) do
			n = n + 1
			assert.is_string(v)
		end
		assert.are.equal(P.OBS_MAX, n)
		assert.is_truthy(db.ref[900002]:find("900001", 1, true), "refutation of a player over the limit")
		-- a fresh store reads the saved table back
		local again = P.New(db)
		assert.are.same({ store:Result(900002) }, { again:Result(900002) })
	end)

	it("makes a stable token per install and quest that does not reveal the install", function()
		local a = P.Token("abcdefghijkl", 900002)
		assert.are.equal(a, P.Token("abcdefghijkl", 900002))
		assert.are_not.equal(a, P.Token("abcdefghijkl", 900003))
		assert.are_not.equal(a, P.Token("abcdefghijkm", 900002))
		assert.matches("^[0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z]$", a)
	end)
end)

describe("Exchange message for prerequisite observations", function()
	wow.reset({})
	local Proto = wow.loadFiles({ "BraindeadForever/Collector/Proto.lua" }).Proto

	it("carries token, quest, link, unlock and two short ID lists", function()
		local msg = Proto.Format("p", "a1b2c3", 900002, 900001, 1, "900005.900006", "")
		assert.are.equal("p;1;a1b2c3;900002;900001;1;900005.900006;", msg)
		local f = Proto.Parse(msg)
		assert.are.equal("p", f.kind)
		assert.are.same({ "a1b2c3", 900002, 900001, 1, "900005.900006", "" }, { unpack(f, 1, f.n) })
		assert.are.equal("p;900002;a1b2c3", Proto.Key(f))
	end)

	it("rejects broken tokens and lists", function()
		assert.is_nil(Proto.Format("p", "A1B2C3", 900002, 0, 0, "", ""))
		assert.is_nil(Proto.Format("p", "a1b2c3", 900002, 0, 2, "", ""))
		assert.is_nil(Proto.Format("p", "a1b2c3", 900002, 0, 0, "1.x", ""))
		local eleven = {}
		for i = 1, 11 do
			eleven[i] = 900000 + i
		end
		assert.is_nil(Proto.Format("p", "a1b2c3", 900002, 0, 0, table.concat(eleven, "."), ""))
		local _, err = Proto.Parse("p;1;a1b2c3;900002;0;0;1..2;")
		assert.are.equal("bad", err)
	end)
end)

describe("Collector: prerequisite observations", function()
	it("records link, unlock, recent turn-ins and checks at an accept and offers them to the group", function()
		local ns = wow.session()
		wow.world.group.party = true
		visit(900010, 900011) -- an earlier, unrelated turn-in elsewhere in the session
		visit(900001, 900002)
		local acc = records(ns, "accept")
		local last = acc[#acc]
		-- kind, dt, map, x, y, quest, giverKind, giverID, item, name, level, xp, token, link, unlock, done, missing
		assert.are.equal("900002", last[6])
		assert.matches("^[0-9a-z]+$", last[13])
		assert.are.equal("900001", last[14], "turned in directly before at the giver")
		assert.are.equal("1", last[15], "the NPC did not offer it before the turn-in")
		assert.are.equal("900010", last[16], "recent turn-ins count as done")
		local msgs = sentPrereq()
		assert.are.equal(("p;1;%s;900002;900001;1;900010;"):format(last[13]), msgs[#msgs])
		-- the own observation is in the route's store at once
		assert.are.same({ 900001, 900010 }, ns.Route.Candidates(900002))
	end)

	it("sets no link when the turn-in was at another NPC or too long ago", function()
		local ns = wow.session()
		visit(900001, nil)
		wow.advance(ns.Prereq.LINK_SECONDS + 1)
		visit(nil, 900002)
		local acc = records(ns, "accept")
		assert.are.equal("0", acc[#acc][14])
		assert.are.equal("0", acc[#acc][15])
	end)

	it("sets no unlock when the NPC offered the quest before the turn-in", function()
		local ns = wow.session()
		local W = wow.world
		W.npc = NPC
		W.offers = { 900002 }
		wow.fire("GOSSIP_SHOW")
		W.questLog = { { questID = 900001, complete = true } }
		W.questID = 900001
		wow.fire("QUEST_COMPLETE")
		W.questLog, W.completed[900001] = {}, true
		wow.fire("QUEST_TURNED_IN", 900001, 100, 0)
		W.questID = 900002
		wow.fire("QUEST_DETAIL", 0)
		wow.fire("QUEST_ACCEPTED", 900002)
		local acc = records(ns, "accept")
		assert.are.equal("900001", acc[#acc][14])
		assert.are.equal("0", acc[#acc][15])
	end)

	it("links the turn-in also when Forever sends no QUEST_TURNED_IN", function()
		local ns = wow.session()
		local W = wow.world
		W.npc = NPC
		W.offers = { 900099 }
		wow.fire("GOSSIP_SHOW")
		W.questLog = { { questID = 900001, complete = true } }
		W.questID = 900001
		wow.fire("QUEST_COMPLETE")
		W.questLog, W.completed[900001] = {}, true
		wow.fire("QUEST_REMOVED", 900001, false) -- no QUEST_TURNED_IN follows
		W.questID = 900002
		wow.fire("QUEST_DETAIL", 0)
		wow.fire("QUEST_ACCEPTED", 900002)
		local acc = records(ns, "accept")
		assert.are.equal("900001", acc[#acc][14])
		assert.are.equal("1", acc[#acc][15])
	end)

	it("reads the offer list of a greeting dialog (NPC without gossip)", function()
		local ns = wow.session()
		ns.Route.Observe(900002, "zzzzzz", 900001, true, {}, {})
		wow.world.npc = NPC
		wow.world.offers = { 900005, 900002 }
		wow.fire("QUEST_GREETING")
		local offers = records(ns, "offer")
		assert.are.equal(1, #offers, "only the quest with an open prerequisite question")
		assert.are.equal("900002", offers[1][6])
		assert.are.equal("900001", offers[1][9])
		wow.fire("QUEST_GREETING")
		assert.are.equal(1, #records(ns, "offer"), "once per quest and session")
	end)

	it("refutes known candidates when an NPC offers the quest to a player who has not done them", function()
		local ns = wow.session()
		ns.Route.Observe(900002, "zzzzzz", 900001, true, {}, {})
		wow.world.npc = NPC
		wow.world.offers = { 900002 }
		wow.fire("GOSSIP_SHOW")
		local offers = records(ns, "offer")
		assert.are.equal(1, #offers)
		-- kind, dt, map, x, y, quest, token, done, missing
		assert.are.equal("900002", offers[1][6])
		assert.are.equal("900001", offers[1][9])
		local _, _, n = ns.Prereq.New(ns.db.prereq):Result(900002)
		assert.are.equal(2, n)
		assert.is_truthy(ns.db.prereq.ref[900002]:find("900001", 1, true))
	end)
end)

describe("Route: prerequisites from player data", function()
	-- A quest of the Alliance explorer route whose prerequisites no source states (the only such quest
	-- of its step, so the step's mark depends on it alone), and a quest the route takes before it.
	local function alone(rt, s, q)
		for _, o in ipairs(s.quests) do
			if o ~= q and rt.unsure[o] then
				return false
			end
		end
		return true
	end

	local function pick(ns)
		local rt = ns.Route.Runtime()
		for i, s in ipairs(rt.steps) do
			for _, q in ipairs(s.quests) do
				if rt.unsure[q] and rt.accepts[q] == i and i > 20 and alone(rt, s, q) then
					for j = i - 1, 1, -1 do
						local c = rt.steps[j].quests[1]
						if c and not rt.unsure[c] and rt.accepts[c] == j then
							return q, c, rt
						end
					end
				end
			end
		end
	end

	local function explorer()
		local ns = wow.session()
		assert.is_true(ns.Route.SetMode("explorer"))
		return ns
	end

	it("marks the chain of a quest without known prerequisites as incomplete", function()
		local ns = explorer()
		local q, _, rt = pick(ns)
		assert.is_number(q, "no quest with unknown prerequisites in the explorer route")
		assert.are.equal("incomplete", ns.Route.ChainState(q))
		local info = rt:Info(rt.accepts[q])
		assert.are.equal("incomplete", info.chain)
	end)

	it("uses a confirmed prerequisite at once: skipping it skips the follow-up", function()
		local ns = explorer()
		local q, c, rt = pick(ns)
		local reasons = {}
		ns.Route.RegisterCallback("RouteRecalculated", "test", function(_, why)
			reasons[#reasons + 1] = why
		end)
		ns.Route.Skip(rt.steps[rt.accepts[c]].key)
		assert.is_nil(rt:Blocked()[q], "before: no known link between the two quests")
		ns.Route.Undo()
		for _, t in ipairs({ "aaaaaa", "bbbbbb" }) do
			ns.Route.Observe(q, t, c, true, {}, {})
		end
		assert.are.equal("incomplete", ns.Route.ChainState(q), "two players are not enough")
		ns.Route.Observe(q, "cccccc", 0, false, { c }, {})
		assert.are.equal("observed", ns.Route.ChainState(q))
		assert.are.equal("prereq", reasons[#reasons])
		assert.is_nil(rt:Info(rt.accepts[q]).chain)
		ns.Route.Skip(rt.steps[rt.accepts[c]].key)
		assert.is_true(rt:Blocked()[q], "the follow-up goes with its confirmed prerequisite")
	end)

	it("clears the mark when five players confirm that there is none", function()
		local ns = explorer()
		local q, _, rt = pick(ns)
		for i = 1, 5 do
			ns.Route.Observe(q, ("t%05d"):format(i), 0, false, {}, {})
		end
		assert.are.equal("none", ns.Route.ChainState(q))
		assert.is_nil(rt:Info(rt.accepts[q]).chain)
	end)

	it("keeps observations over /reload (account-wide)", function()
		local ns = explorer()
		local q = pick(ns)
		for _, t in ipairs({ "aaaaaa", "bbbbbb", "cccccc", "dddddd", "eeeeee" }) do
			ns.Route.Observe(q, t, 0, false, {}, {})
		end
		wow.fire("PLAYER_LOGOUT")
		local saved = _G.BraindeadForeverDB
		ns = wow.session({ saved = saved, char = _G.BraindeadForeverCharDB, collect = _G.BraindeadForeverCollectDB })
		ns.Route.SetMode("explorer")
		assert.are.equal("none", ns.Route.ChainState(q))
	end)
end)

describe("Simulated runs: three players, the exchange carries the observations", function()
	it("confirms a prerequisite from two received observations and the player's own", function()
		local messages = {}
		for i, install in ipairs({ "aaaaaaaaaaaa", "bbbbbbbbbbbb", "cccccccccccc" }) do
			local ns = wow.session({ collect = { schema = 1, install = install } })
			wow.world.group.party = true
			wow.world.player.name = "Player" .. i
			for _, m in ipairs(messages) do
				wow.fire("CHAT_MSG_ADDON", "BDF", m.msg, "PARTY", m.from)
			end
			wow.readInbox(ns)
			if i < 3 then
				assert.are.equal("incomplete", ns.Route.ChainState(900002))
			end
			visit(900001, 900002)
			for _, msg in ipairs(sentPrereq()) do
				messages[#messages + 1] = { msg = msg, from = "Player" .. i .. " Testname" }
			end
			if i == 3 then
				assert.are.equal("observed", ns.Route.ChainState(900002))
				local _, groups, n = ns.Prereq.New(ns.db.prereq):Result(900002)
				assert.are.same({ { 900001 } }, groups)
				assert.are.equal(3, n)
			end
		end
	end)
end)
