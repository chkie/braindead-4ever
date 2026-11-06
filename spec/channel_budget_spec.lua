-- SPDX-License-Identifier: GPL-3.0-or-later
-- Channel budget (plan "Laufzeiten im Austausch", task 7 with the owner's tightening of 2026-11-02;
-- Collector/Budget.lua, Collector/Exchange.lua, docs/RUN-TIMES.md): the estimate of the senders, the
-- credits and the busy stop, receiving into the inbox and reading it in slices only outside fights,
-- instances and low frame rates, sending on the channel only outside fights and instances, the
-- spread simulation from 100 to 20,000 clients against the owner's limits with the counter-check
-- without budget, and the measured cost of a received message. The fight case of reading sits in
-- spec/ui_combat_spec.lua with the other combat rules.
local wow = require("spec.helpers.wow")
local spread = require("spec.helpers.spread")

-- Owner, 2026-11-02: per client at most 0.5 messages per second on average and at most 1 per second
-- in any 60 s window.
local MEAN_MAX, WINDOW_MAX = 1, 120 -- owner 2026-11-06: no disturbance, measured cost (Budget.lua)

local function pure()
	wow.reset()
	return wow.loadFiles({
		"Braindead4Ever/Locales/enUS.lua",
		"Braindead4Ever/Core/Util.lua",
		"Braindead4Ever/Collector/Proto.lua",
		"Braindead4Ever/Collector/Runs.lua",
		"Braindead4Ever/Collector/Budget.lua",
		"Braindead4Ever/Routes/XP.lua",
	})
end

-- A Budget on a clock the test moves (t.now), with a deterministic random.
local function budget(ns, seed)
	local t = { now = 0 }
	local b = ns.Budget.New({
		clock = function()
			return t.now
		end,
		random = spread.Rng(seed or 7),
	})
	return b, t
end

local function find(i)
	return ("o;1;%d;1429;4231;6512"):format(2000 + i)
end

local function fire(msg, sender, dist)
	wow.fire("CHAT_MSG_ADDON", "BDF", msg, dist or "CHANNEL", sender, "", 0, 5, "BraindeadShare", 0)
end

local function sent(dist, kind)
	local out = {}
	for _, m in ipairs(wow.world.sent) do
		if m.prefix == "BDF" and m.dist == dist and (not kind or m.msg:sub(1, 2) == kind .. ";") then
			out[#out + 1] = m
		end
	end
	return out
end

describe("Channel budget: estimate", function()
	it("bounds the number of uniform senders from above", function()
		local ns = pure()
		local B, rnd = ns.Budget, spread.Rng(11)
		for _, n in ipairs({ 20, 100, 1000, 5000, 20000 }) do
			for _, m in ipairs({ 30, 150, 900 }) do
				local sum, draws = 0, 100
				for _ = 1, draws do
					local counts, heard, twice = {}, 0, 0
					for _ = 1, m do
						local w = rnd(1, n)
						counts[w] = (counts[w] or 0) + 1
						if counts[w] == 1 then
							heard = heard + 1
						elseif counts[w] == 2 then
							twice = twice + 1
						end
					end
					local e = B.Estimate(heard, twice)
					assert.is_true(e >= heard and e <= B.SENDERS_MAX)
					sum = sum + math.min(n, B.SENDERS_MAX) / e
				end
				-- n / estimate is the factor by which a client oversends; on average about 1 or less.
				-- Above SENDERS_MAX the estimate stops there by design and BUSY bounds the channel
				-- (spread simulation below).
				assert.is_true(sum / draws <= 1.15, ("n %d, m %d: %.3f"):format(n, m, sum / draws))
			end
		end
	end)

	it("assumes SENDERS_MAX until someone is heard twice, less when the channel is quiet", function()
		local B = pure().Budget
		assert.are.equal(B.SENDERS_MAX, B.Estimate(0, 0))
		assert.are.equal(B.SENDERS_MAX, B.Estimate(40, 0))
		-- nothing heard in an hour: every sender sends at least SHARE / SENDERS_MAX per second, so
		-- silence means few senders (the 90 % bound of a Poisson count 0 is about 2.3 messages)
		local quiet = B.Estimate(0, 0, 0, 3600)
		assert.is_true(quiet > 2.5 and quiet < 4, quiet)
		assert.is_true(B.Estimate(0, 0, 0, 10) > 200) -- ten seconds say little
		-- a sender heard twice among three bounds the count far below the maximum
		assert.is_true(B.Estimate(3, 1) < 100)
	end)

	it("counts a flooding sender once", function()
		local ns = pure()
		local calm, t1 = budget(ns)
		local flood, t2 = budget(ns)
		for i = 1, 200 do
			t1.now, t2.now = i, i
			calm:Heard("Player" .. i)
			flood:Heard("Player" .. i)
		end
		calm:Heard("Mallory")
		calm:Heard("Mallory")
		for _ = 1, 1000 do
			flood:Heard("Mallory")
		end
		assert.are.equal(calm.twice, flood.twice)
		assert.is_true(flood:Senders() >= calm:Senders())
		assert.is_true(flood:Senders() > 200)
	end)

	it("forgets what is older than the window and keeps names in memory only", function()
		local ns = pure()
		local b, t = budget(ns)
		b:Heard("Anna Sommer")
		b:Heard("Anna Sommer")
		assert.are.equal(1, b.heard)
		assert.are.equal(1, b.twice)
		t.now = ns.Budget.WINDOW + 1
		assert.is_true(b:Senders() > 1)
		assert.are.equal(0, b.heard)
		assert.is_nil(b.count["Anna Sommer"])
	end)
end)

describe("Channel budget: credits", function()
	it("grants credits at its share of the estimate and holds at most one", function()
		local ns = pure()
		local b, t = budget(ns, 3)
		-- 100 players heard twice each in the first half hour: the estimate is about 100
		for round = 1, 2 do
			for i = 1, 100 do
				t.now = (round - 1) * 900 + i
				b:Heard("Player" .. i)
			end
		end
		t.now = 1800
		local senders = b:Senders()
		assert.is_true(senders > 100 and senders < 130, senders)
		-- the rate: with an estimate of 10 players held fixed, 20,000 s give 300 credits on average
		b.estimate, b.until_ = 10, math.huge
		local spent = 0
		for s = 1801, 1800 + 20000 do
			t.now = s
			if b:Has("runs") then
				spent = spent + 1
				b:Spend("runs")
			end
		end
		local expected = 20000 * ns.Budget.SHARE.runs / 10
		assert.is_true(
			math.abs(spent - expected) <= 0.2 * expected,
			("%d credits, %.1f expected"):format(spent, expected)
		)
		-- a credit not spent stays one credit, however long it waits
		t.now = 20000
		b.credit.finds = 1
		assert.is_true(b:Has("finds"))
		assert.are.equal(1, b.credit.finds)
	end)

	it("grants none while the channel is busy and drops a held one", function()
		local ns = pure()
		local b, t = budget(ns)
		b.credit.runs = 1
		for i = 1, ns.Budget.BUSY do
			t.now = i * 50 / ns.Budget.BUSY -- all of them within 50 s
			b:Heard("Player" .. i)
		end
		assert.is_true(b:Busy())
		assert.is_false(b:Has("runs"))
		assert.are.equal(0, b.credit.runs)
		t.now = ns.Budget.BUSY + 60
		assert.is_false(b:Busy())
	end)
end)

describe("Exchange: receiving into the inbox", function()
	it("only queues on the event; the ticker reads ten messages a second", function()
		local ns = wow.session()
		local X = ns.Exchange
		for i = 1, 25 do
			fire(find(i), "Player" .. i)
		end
		assert.are.equal(0, X.stats.received)
		assert.are.equal(25, X.Waiting(X.inbox.channel))
		wow.advance(1)
		assert.are.equal(X.SLICE, X.stats.received)
		wow.advance(2)
		assert.are.equal(25, X.stats.received)
		assert.are.equal(0, X.Waiting(X.inbox.channel))
	end)

	it("lets the oldest give way in a full inbox", function()
		local ns = wow.session()
		local X = ns.Exchange
		for i = 1, X.INBOX_MAX + 5 do
			fire(find(i), "Player" .. i)
		end
		fire(find(1), "Anna Sommer", "PARTY") -- group and guild have their own inbox
		assert.are.equal(5, X.stats.inbox)
		assert.are.equal(X.INBOX_MAX, X.Waiting(X.inbox.channel))
		assert.are.equal(1, X.Waiting(X.inbox.other))
		assert.are.equal(find(6), X.inbox.channel.text[X.inbox.channel.head])
	end)

	it("reads nothing in an instance or below the frame rate floor and catches up afterwards", function()
		local ns = wow.session()
		local X = ns.Exchange
		local t0 = wow.clock
		wow.world.instance = true
		fire(find(1), "Anna Sommer")
		fire(find(2), "Ben Winter", "PARTY")
		wow.advance(100)
		assert.are.equal(0, X.stats.received)
		wow.world.instance = false
		wow.world.fps = X.MIN_FPS - 1
		wow.advance(10)
		assert.are.equal(0, X.stats.received)
		wow.world.fps = 60
		wow.advance(1)
		assert.are.equal(2, X.stats.received)
		-- the estimate takes the message at the time it arrived, not when it was read
		assert.are.equal(t0, X.budget.at[X.budget.tail])
	end)
end)

describe("Exchange: sending on the hidden channel", function()
	for _, case in ipairs({ "combat", "instance" }) do
		it("sends no find on the channel in " .. case .. ", group and guild still get it", function()
			local ns = wow.session()
			local X = ns.Exchange
			wow.freeChannel()
			wow.advance(10) -- channel joined
			wow.world.group.party, wow.world.guild = true, true
			wow.world[case] = true
			wow.world.loot =
				{ { link = "|Hitem:2589:::|h[x]|h", sources = { "GameObject-0-1465-0-2105-2843-0000ABC124", 1 } } }
			wow.fire("LOOT_OPENED", false, false)
			assert.are.equal(1, #sent("PARTY"))
			wow.advance(91 + X.FIND_WAIT)
			assert.are.equal(1, #sent("GUILD"))
			assert.are.equal(0, #sent("CHANNEL"))
			assert.are.equal(1, X.stats.budget) -- the find waited its minute and left the channel
		end)

		it("relays no run section in " .. case .. " and goes on afterwards", function()
			local ns = wow.session()
			wow.freeChannel()
			wow.advance(10)
			for i = 1, 20 do
				local msg = ns.Proto.Format("s", ("gu%04d"):format(i), 1, 1, "s", "l", 5, 0, 600, 2800, 100, 6, 20762)
				fire(msg, "Sender " .. i, "GUILD")
			end
			wow.readInbox()
			assert.are.equal(20, ns.Collector.runs:Count())
			wow.world[case] = true
			wow.advance(120)
			assert.are.equal(0, #sent("CHANNEL", "s"))
			wow.world[case] = false
			wow.advance(30)
			assert.is_true(#sent("CHANNEL", "s") >= 2)
		end)
	end

	it("keeps a fresh client in a quiet channel to its share and starts it within minutes", function()
		local ns = wow.session()
		local X = ns.Exchange
		wow.advance(10)
		-- nothing heard in the first seconds says little: the estimate stays at the upper bound
		assert.is_true(X.budget:Senders() > 200 and X.budget:Senders() <= ns.Budget.SENDERS_MAX + 1)
		-- an hour of silence bounds the players by a few: a find gets its credit within its wait
		wow.advance(3600)
		wow.world.loot =
			{ { link = "|Hitem:2589:::|h[x]|h", sources = { "GameObject-0-1465-0-2105-2843-0000ABC124", 1 } } }
		wow.fire("LOOT_OPENED", false, false)
		assert.is_true(X.budget:Senders() < 6, X.budget:Senders())
		wow.advance(91 + X.FIND_WAIT)
		assert.are.equal(1, #sent("CHANNEL"))
		assert.are.equal(0, X.stats.budget)
	end)
end)

-- Rows of the simulation table in docs/RUN-TIMES.md.
local function row(n, r, secs)
	local reach = {}
	for _, k in ipairs({ 1, 2, 5, 9 }) do
		reach[#reach + 1] = ("%d: %.3f"):format(k, r.reach[k].mean)
	end
	return ("%6d clients (%.0f online, %4.1f s): received per client and s mean %.3f, busiest %.3f, most in 60 s %d; sent per online hour %.2f (relayed %.2f); own sections on the channel %d of %d; estimate / online %.2f [%.2f..%.2f]; reach after n rounds %s; one exporter collected %.0f sections"):format(
		n,
		r.online,
		secs,
		r.receivedPerSec,
		r.maxReceivedPerSec,
		r.maxWindow,
		r.sentPerHour,
		r.relayedPerHour,
		r.sentOwn,
		r.produced,
		r.estimate.mean,
		r.estimate.p05,
		r.estimate.p95,
		table.concat(reach, ", "),
		r.collected
	)
end

describe("Spread simulation under the channel budget", function()
	for _, n in ipairs({ 100, 1000, 5000, 20000 }) do
		it(("keeps %d clients under 0.5 messages per second and 60 per minute"):format(n), function()
			local ns = pure()
			local t = os.clock()
			local r = spread.Run(ns, { clients = n })
			io.stdout:write("\n[budget] " .. row(n, r, os.clock() - t) .. "\n")
			assert.is_true(r.receivedPerSec <= MEAN_MAX, r.receivedPerSec)
			assert.is_true(r.maxReceivedPerSec <= MEAN_MAX, r.maxReceivedPerSec)
			assert.is_true(r.maxWindow <= WINDOW_MAX, r.maxWindow)
			-- the sender limits of the vault leave honest senders alone
			assert.is_true(r.peakNew < ns.Runs.NEW_TOKENS_MAX)
			assert.is_true(r.peakRate <= ns.Runs.SENDER_MAX)
			-- the channel still carries runs to an exporter; with 100 players almost all of them
			assert.is_true(r.reach[9].mean > 0)
			if n == 100 then
				assert.is_true(r.reach[9].mean >= 0.9, r.reach[9].mean)
			end
		end)
	end

	it("counter-check: without the budget 1,000 clients go over both limits in the first round", function()
		local ns = pure()
		local r = spread.Run(ns, { clients = 1000, budget = false, rounds = 1 })
		io.stdout:write(
			("\n[budget] without budget, 1000 clients, 1 round: received per client and s mean %.3f, busiest %.3f, most in 60 s %d\n"):format(
				r.receivedPerSec,
				r.maxReceivedPerSec,
				r.maxWindow
			)
		)
		assert.is_true(r.receivedPerSec > MEAN_MAX)
		assert.is_true(r.maxWindow > WINDOW_MAX)
	end)
end)

describe("Cost of a received message (Lua 5.1 offline)", function()
	it("measures the event, the reading and the memory against the addon budget", function()
		local ns = wow.session()
		local X = ns.Exchange
		local rounds, batch = 50, 100
		-- realistic mix: half run sections, half finds, every one new and from another player
		local msgs, senders = {}, {}
		for i = 1, rounds * batch do
			if i % 2 == 0 then
				msgs[i] = ns.Proto.Format("s", ("%06d"):format(i), 1, 1, "s", "l", 5, 0, 600, 2800, 100, 6, 20762)
			else
				msgs[i] = ("o;1;%d;1429;%d;%d"):format(2000 + i, 1000 + i % 8000, 2000 + i % 7000)
			end
			senders[i] = "Player" .. i .. " Surname"
		end
		local event, read = 0, 0
		for r = 0, rounds - 1 do
			local t = os.clock()
			for i = r * batch + 1, (r + 1) * batch do
				X.Receive("BDF", msgs[i], "CHANNEL", senders[i])
			end
			event = event + os.clock() - t
			t = os.clock()
			wow.readInbox()
			read = read + os.clock() - t
		end
		local n = rounds * batch
		assert.are.equal(n, X.stats.received)
		local eventUs, readUs = event / n * 1e6, read / n * 1e6
		-- share of the addon's budget of 0.1 ms per frame at 60 frames per second, at the owner's limit
		-- of 0.5 messages per second
		local perFrameUs = 0.5 * (eventUs + readUs) / 60
		-- memory: a full vault, full inboxes and a full estimate window, each with distinct strings
		-- Lua 5.1 halves its string table once per full cycle, so after the simulation a single
		-- collect does not settle the count: collect until it stands still.
		local function settle()
			local last
			for _ = 1, 20 do
				collectgarbage("collect")
				local now = collectgarbage("count")
				if last and math.abs(now - last) < 1 then
					return now
				end
				last = now
			end
			return last
		end
		local function kb(build)
			local before = settle()
			local keep = build()
			local used = settle() - before
			return used, keep
		end
		-- the vault as a login finds it: VAULT_MAX sections of other players in the SavedVariables
		local saved = 0
		local vault = kb(function()
			local list = {}
			for i = 1, ns.Runs.VAULT_MAX do
				list[i] = ns.Proto.Format("s", ("v%05d"):format(i), 1, 1, "s", "l", 5, 0, 600, 2800, 100, 6, 20762)
				saved = saved + #list[i] + 1
			end
			return ns.Runs.New({ list = list, first = 1, last = #list }, {
				clock = function()
					return 0
				end,
			})
		end)
		saved = saved / 1024
		local inbox = kb(function()
			for i = 1, X.INBOX_MAX do
				X.Receive("BDF", find(i) .. ";" .. i, "CHANNEL", "Inbox Sender" .. i)
				X.Receive("BDF", find(i) .. ";" .. i, "GUILD", "Guild Sender" .. i)
			end
			return X.inbox
		end)
		local window = kb(function()
			local b = budget(ns)
			for i = 1, ns.Budget.EVENTS_MAX do
				b:Heard("Window Sender" .. i)
			end
			return b
		end)
		io.stdout:write(
			("\n[cost] per received message: event %.2f us, reading %.1f us; at 0.5 per second %.4f us per frame = %.2f %% of 100 us\n[cost] memory: vault of %d sections %.0f KB (the texts alone %.0f KB), two full inboxes %.0f KB, estimate window of %d messages %.0f KB, together %.2f %% of 10 MB\n"):format(
				eventUs,
				readUs,
				perFrameUs,
				perFrameUs,
				ns.Runs.VAULT_MAX,
				vault,
				saved,
				inbox,
				ns.Budget.EVENTS_MAX,
				window,
				(vault + inbox + window) / 10240 * 100
			)
		)
		-- generous bounds, only against a slip by an order of magnitude
		assert.is_true(eventUs < 20, eventUs)
		assert.is_true(perFrameUs < 5, perFrameUs)
		assert.is_true(vault + inbox + window < 4096)
	end)
end)
