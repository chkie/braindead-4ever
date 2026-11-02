-- SPDX-License-Identifier: GPL-3.0-or-later
-- Spread simulation of the hidden channel (plan "Laufzeiten im Austausch", tasks 3 and 7 with the
-- owner's tightening of 2026-11-02): many clients with the real Collector/Proto.lua,
-- Collector/Runs.lua and Collector/Budget.lua in one channel. Every message a client sends reaches
-- every client online at that moment. Plain Lua, no WoW API, deterministic for a seed. Event-driven,
-- so 20,000 clients run in seconds. Model values are chosen, not measured (docs/RUN-TIMES.md):
--   rounds    ROUND seconds each; in every round a client starts one session with probability
--             ONLINE at a random moment, lasting SESSION_MIN..SESSION_MAX seconds (it may run on into
--             the next round: players log in around the clock)
--   own runs  one section per RUN_EVERY seconds of play, due 30 to 90 s later (as Exchange.Offer);
--             it waits for a credit of the run pool
--   relaying  with a credit of the run pool and no own section due, a client relays the next
--             section of its vault (Runs:NextRelay, one per Runs.RELAY_GAP at most)
--   finds     every client always has a find waiting (one per minute of play, each waits a minute
--             for a credit): a credit of the find pool is spent at once. Finds are only counted
--   channel   one message per client and CHANNEL_GAP seconds (Exchange.CHANNEL_GAP)
--   budget    budget = false sends without one (the counter-check): own sections, a find per
--             FIND_EVERY seconds of play and relays go out as soon as the channel gap allows
--   reach     for EXPORTERS clients: when each section of another player first reached them (heard
--             on the channel). reach[n] is the share of sections that reached an exporter within n
--             rounds after the end of the round they were produced in
-- Simplifications (said in docs/RUN-TIMES.md), all exact for the traffic, which is what the budget
-- guards:
--   estimate  every client older than Budget.WINDOW hears the same channel, so they share one Budget
--             (fed with every message, the client's own ones too: one sender more than the real
--             client counts). Younger clients share one Budget per login minute (COHORT seconds),
--             started at the first login of that minute. Clients that share a Budget send at the same
--             rate, so their credits are one Poisson process of the summed rate, given to a member
--             at random; the rate is taken anew at every Budget.REFRESH and when members come or go.
--   vaults    up to FULL clients every client's vault hears every run message on the channel. Above,
--             only the exporters' vaults do; the others hold their own sections only, so they relay
--             only those. Credits are so rare there that an own section is almost always waiting
--             when one comes. Checked against every vault hearing (seed 20261102): 1,000 clients reach
--             after 9 rounds 0.366 against 0.370, 5,000 clients 0.075 against 0.073; one Budget per
--             login second instead of per minute at 1,000 clients: 0.379 against 0.370.
local M = {}

M.DEFAULTS = {
	clients = 200,
	rounds = 10,
	round = 4 * 3600,
	online = 0.5,
	sessionMin = 3600,
	sessionMax = 3 * 3600,
	runEvery = 1800,
	budget = true,
	exporters = 10,
	cohort = 60,
	full = 100,
	seed = 20261102,
}

M.CHANNEL_GAP = 2 -- as Exchange.CHANNEL_GAP
M.FIND_EVERY = 60 -- budget = false: a find per minute of play
M.FIND_WAIT = 60 -- as Exchange.FIND_WAIT

-- Small deterministic generator (Park-Miller), so the result does not depend on math.random.
local function Rng(seed)
	local s = seed % 2147483647
	return function(m, n)
		s = (s * 16807) % 2147483647
		if not m then
			return s / 2147483647
		end
		return m + s % (n - m + 1)
	end
end
M.Rng = Rng

local ALPHA = "0123456789abcdefghijklmnopqrstuvwxyz"

local function Options(opts)
	local o = {}
	for k, v in pairs(M.DEFAULTS) do
		o[k] = v
	end
	for k, v in pairs(opts or {}) do
		o[k] = v
	end
	return o
end
M.Options = Options

-- Binary heap of events ordered by time, then by insertion.
local function Heap()
	local h, n, seq = {}, 0, 0
	local function less(a, b)
		return a.t < b.t or (a.t == b.t and a.seq < b.seq)
	end
	local q = {}
	function q.push(e)
		seq = seq + 1
		e.seq = seq
		n = n + 1
		local i = n
		h[i] = e
		while i > 1 do
			local p = math.floor(i / 2)
			if less(h[i], h[p]) then
				h[i], h[p] = h[p], h[i]
				i = p
			else
				break
			end
		end
	end
	function q.pop()
		if n == 0 then
			return nil
		end
		local top = h[1]
		h[1] = h[n]
		h[n] = nil
		n = n - 1
		local i = 1
		while true do
			local l, r, m = 2 * i, 2 * i + 1, i
			if l <= n and less(h[l], h[m]) then
				m = l
			end
			if r <= n and less(h[r], h[m]) then
				m = r
			end
			if m == i then
				break
			end
			h[i], h[m] = h[m], h[i]
			i = m
		end
		return top
	end
	return q
end

-- Reach of the exporters: { [n] = { mean, min } } over production rounds r with r + n - 1 <= rounds.
-- exporters: list of { reach = key -> time, own = key -> true }; born: key -> production time.
local function Reach(o, exporters, born)
	local out = {}
	for n = 1, o.rounds do
		local shares = {}
		for _, e in ipairs(exporters) do
			local total, hit = 0, 0
			for key, t in pairs(born) do
				local r = math.floor(t / o.round) + 1
				if r + n - 1 <= o.rounds and not e.own[key] then
					total = total + 1
					local at = e.reach[key]
					if at and at < (r + n - 1) * o.round then
						hit = hit + 1
					end
				end
			end
			if total > 0 then
				shares[#shares + 1] = hit / total
			end
		end
		local sum, min = 0, 1
		for _, x in ipairs(shares) do
			sum, min = sum + x, math.min(min, x)
		end
		out[n] = { mean = #shares > 0 and sum / #shares or 0, min = min }
	end
	return out
end
M.Reach = Reach

-- ns: namespace with Proto, Runs, Budget and XP loaded; opts overrides M.DEFAULTS. Returns
-- { receivedPerSec, maxReceivedPerSec, maxWindow, channelPerSec, sentPerHour, relayedPerHour,
--   reach = { [n] = { mean, min } }, collected, produced, sentOwn, online, estimate = { mean, p05, p95 },
--   peakNew, peakRate, messages }.
function M.Run(ns, opts)
	local o = Options(opts)
	local rnd = Rng(o.seed)
	local now = 0
	local function clock()
		return now
	end
	local function epoch()
		return 20762 * 86400 + 43200
	end
	local Proto, Runs, Budget = ns.Proto, ns.Runs, ns.Budget
	local finish = o.rounds * o.round
	local q = Heap()
	local function at(t, kind, a, b, c)
		q.push({ t = t, kind = kind, a = a, b = b, c = c })
	end
	local function exp(rate)
		return -math.log(1 - rnd()) / rate
	end

	local clients = {}
	for i = 1, o.clients do
		local tok = {}
		for j = 1, 6 do
			local k = rnd(1, 36)
			tok[j] = ALPHA:sub(k, k)
		end
		clients[i] = {
			i = i,
			name = "Player" .. i,
			token = table.concat(tok),
			race = rnd(1, 10),
			class = rnd(1, 11),
			level = 1,
			runs = Runs.New({}, { clock = clock, epoch = epoch, curve = ns.XP.TO_LEVEL }),
			hears = o.clients <= o.full or i <= o.exporters,
			sent = 0,
			received = 0,
			relayed = 0,
			online = 0,
			sid = 0,
		}
		if i <= o.exporters then
			clients[i].reach, clients[i].own = {}, {}
		end
	end
	-- session plan
	for round = 1, o.rounds do
		for i = 1, o.clients do
			if rnd() < o.online then
				local t = (round - 1) * o.round + rnd(0, o.round - 1)
				at(t, "login", clients[i], t + rnd(o.sessionMin, o.sessionMax))
			end
		end
	end

	local online, nonline = {}, 0 -- client -> true
	local listeners = {} -- online clients whose vault hears the channel
	local parsed = {}
	local born, produced, sentOwn = {}, 0, 0
	local chan, times, head = 0, {}, 1 -- channel messages, their times (sliding 60 s window, times[chan])
	local out = { maxWindow = 0, peakNew = 0, peakRate = 0 }
	local ratios = {}

	-- Estimators: one shared Budget for clients older than WINDOW, one per login minute for younger.
	local estimators = {}
	local function NewEstimator(start)
		local e = { start = start, members = {}, version = 0 }
		if o.budget then
			e.budget = Budget.New({ clock = clock, random = rnd })
		end
		estimators[e] = true
		return e
	end
	local shared = NewEstimator(0)
	local cohorts = {} -- minute -> estimator
	local function Resample(e)
		e.version = e.version + 1
		local n = #e.members
		if not o.budget or n == 0 then
			return
		end
		local senders = e.budget:Senders()
		for pool, share in pairs(Budget.SHARE) do
			at(now + exp(n * share / senders), "credit", e, pool, e.version)
		end
	end
	local function Join(e, c)
		local m = e.members
		m[#m + 1] = c
		c.est, c.slot = e, #m
		Resample(e)
	end
	local function Leave(c)
		local e = c.est
		local m = e.members
		local last = m[#m]
		m[c.slot], last.slot = last, c.slot
		m[#m] = nil
		c.est, c.slot = nil, nil
		Resample(e)
	end
	if o.budget then
		at(0, "refresh", shared)
	end

	local function Window()
		times[chan] = now
		while times[head] <= now - 60 do
			times[head] = nil
			head = head + 1
		end
		out.maxWindow = math.max(out.maxWindow, chan - head + 1)
	end

	-- msg = nil: a find (counted only)
	local function Broadcast(from, msg)
		from.sent = from.sent + 1
		chan = chan + 1
		Window()
		for e in pairs(estimators) do
			if e.budget then
				e.budget:Heard(from.name)
			end
		end
		if not msg then
			return
		end
		local f = parsed[msg]
		if not f then
			f = assert(Proto.Parse(msg))
			parsed[msg] = f
		end
		local key = Runs.KeyOf(msg)
		for c in pairs(listeners) do
			if c ~= from then
				c.runs:Hear(f, msg, from.name, true)
				if c.reach and not c.reach[key] then
					c.reach[key] = now
				end
			end
		end
	end

	local TrySend
	local function Retry(c, t)
		if not c.retry or c.retry > t then
			c.retry = t
			at(t, "retry", c, c.sid)
		end
	end

	-- One message on the channel if the client may and has one. Order as Exchange.Pump and
	-- Exchange.Relay: an own section that is due, a find, then a relay.
	function TrySend(c)
		if not c.on then
			return
		end
		if now < c.nextChannelAt then
			Retry(c, c.nextChannelAt)
			return
		end
		local B = c.est and c.est.budget
		if B and B:Busy() then
			c.credit.runs, c.credit.finds = false, false -- Budget:Has drops a held credit
			return
		end
		local sent
		local runs = not o.budget or c.credit.runs
		if runs and #c.pending > 0 and c.pending[1].at <= now then
			Broadcast(c, table.remove(c.pending, 1).msg)
			sentOwn = sentOwn + 1
			c.credit.runs, sent = false, true
		end
		if not sent and o.budget and c.credit.finds then
			Broadcast(c, nil)
			c.credit.finds, sent = false, true
		end
		if not sent and not o.budget then
			while #c.finds > 0 and now - c.finds[1] >= M.FIND_WAIT do
				table.remove(c.finds, 1)
			end
			if #c.finds > 0 and c.finds[1] <= now then
				table.remove(c.finds, 1)
				Broadcast(c, nil)
				sent = true
			end
		end
		local ownDue = #c.pending > 0 and c.pending[1].at <= now
		if not sent and runs and not ownDue then
			local msg = c.runs:NextRelay()
			if msg then
				c.relayed = c.relayed + 1
				Broadcast(c, msg)
				c.credit.runs, sent = false, true
			elseif now < c.runs.nextRelay then
				Retry(c, c.runs.nextRelay)
			end
		end
		if sent then
			c.nextChannelAt = now + M.CHANNEL_GAP
			if not o.budget or c.credit.runs or c.credit.finds then
				Retry(c, c.nextChannelAt)
			end
		end
	end

	local function Login(c, until_)
		if c.on then
			return -- one session at a time
		end
		c.on, c.since, c.until_ = true, now, until_
		c.sid = c.sid + 1
		c.pending, c.finds, c.credit, c.retry = {}, {}, {}, nil
		c.nextChannelAt, c.chan0, c.sent0 = 0, chan, c.sent
		c.runs:StartSession()
		online[c], nonline = true, nonline + 1
		if c.hears then
			listeners[c] = true
		end
		if o.budget then
			local minute = math.floor(now / o.cohort)
			local e = cohorts[minute]
			if not e then
				e = NewEstimator(now)
				cohorts[minute] = e
				at(now + Budget.REFRESH, "refresh", e, minute)
			end
			Join(e, c)
		else
			at(now + M.FIND_EVERY, "find", c, c.sid)
		end
		at(now + o.runEvery, "own", c, c.sid)
		at(until_, "logout", c, c.sid)
		TrySend(c)
	end

	local function Logout(c)
		c.online = c.online + (now - c.since)
		c.received = c.received + (chan - c.chan0) - (c.sent - c.sent0)
		c.on = false
		online[c], nonline = nil, nonline - 1
		listeners[c] = nil
		if c.est then
			Leave(c)
		end
		for _, b in pairs(c.runs.senders) do
			out.peakNew = math.max(out.peakNew, b.new)
			out.peakRate = math.max(out.peakRate, b.n)
		end
	end

	while true do
		local ev = q.pop()
		if not ev or ev.t >= finish then
			break
		end
		now = ev.t
		local kind, c = ev.kind, ev.a
		if kind == "login" then
			Login(c, ev.b)
		elseif kind == "logout" then
			if c.on and c.sid == ev.b then
				Logout(c)
			end
		elseif kind == "own" then
			if c.on and c.sid == ev.b then
				-- own section of a plausible pace, due 30 to 90 s later
				at(now + o.runEvery, "own", c, c.sid)
				local secs, xp = o.runEvery + rnd(-300, 300), 9000 + rnd(0, 3000)
				local msg =
					Proto.Format("s", c.token, c.race, c.class, "s", "l", c.level, 0, secs, xp, 100, c.level + 1, 20762)
				c.level = c.level + 1
				if msg and c.runs:AddOwn(msg) then
					produced = produced + 1
					local key = Runs.KeyOf(msg)
					born[key] = now
					if c.own then
						c.own[key] = true
					end
					local due = now + rnd(30, 90)
					c.pending[#c.pending + 1] = { at = due, msg = msg }
					at(due, "retry", c, c.sid)
				end
			end
		elseif kind == "find" then
			if c.on and c.sid == ev.b then
				at(now + M.FIND_EVERY, "find", c, c.sid)
				local due = now + rnd(30, 90)
				c.finds[#c.finds + 1] = due
				at(due, "retry", c, c.sid)
			end
		elseif kind == "retry" then
			if c.on and c.sid == ev.b then
				if c.retry == now then
					c.retry = nil
				end
				TrySend(c)
			end
		elseif kind == "credit" then
			local e, pool = c, ev.b
			if ev.c == e.version and #e.members > 0 then
				local n = #e.members
				at(now + exp(n * Budget.SHARE[pool] / e.budget:Senders()), "credit", e, pool, e.version)
				if not e.budget:Busy() then
					local m = e.members[rnd(1, n)]
					m.credit[pool] = true
					TrySend(m)
				end
			end
		elseif kind == "refresh" then
			local e, minute = c, ev.b
			if e ~= shared and now - e.start >= Budget.WINDOW then
				-- old enough: its members hear the same window as everybody else
				cohorts[minute], estimators[e] = nil, nil
				e.version = e.version + 1
				for _, m in ipairs(e.members) do
					local s = shared.members
					s[#s + 1] = m
					m.est, m.slot = shared, #s
				end
				Resample(shared)
			elseif e ~= shared and #e.members == 0 then
				cohorts[minute], estimators[e] = nil, nil
			else
				Resample(e)
				at(now + Budget.REFRESH, "refresh", e, minute)
				if e == shared and nonline > 0 and now >= Budget.WINDOW then
					ratios[#ratios + 1] = e.budget:Senders() / nonline
				end
			end
		end
	end
	now = finish
	for c in pairs(online) do
		Logout(c)
	end

	local secs, received, sent, relayed = 0, 0, 0, 0
	out.maxReceivedPerSec = 0
	for _, c in ipairs(clients) do
		secs = secs + c.online
		received, sent, relayed = received + c.received, sent + c.sent, relayed + c.relayed
		if c.online >= 3600 then
			out.maxReceivedPerSec = math.max(out.maxReceivedPerSec, c.received / c.online)
		end
	end
	out.receivedPerSec = received / secs
	out.sentPerHour, out.relayedPerHour = sent / secs * 3600, relayed / secs * 3600
	out.channelPerSec = chan / finish
	out.messages = chan
	out.online = secs / finish
	out.produced, out.sentOwn = produced, sentOwn
	local exporters = {}
	for i = 1, math.min(o.exporters, o.clients) do
		exporters[i] = clients[i]
	end
	out.reach = Reach(o, exporters, born)
	out.collected = 0 -- sections of other players an exporter heard, mean over the exporters
	for _, e in ipairs(exporters) do
		for _ in pairs(e.reach) do
			out.collected = out.collected + 1 / #exporters
		end
	end
	table.sort(ratios)
	if #ratios > 0 then
		local sum = 0
		for _, x in ipairs(ratios) do
			sum = sum + x
		end
		out.estimate = {
			mean = sum / #ratios,
			p05 = ratios[math.max(1, math.floor(#ratios * 0.05))],
			p95 = ratios[math.max(1, math.floor(#ratios * 0.95))],
		}
	end
	return out
end

return M
