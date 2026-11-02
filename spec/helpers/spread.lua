-- SPDX-License-Identifier: GPL-3.0-or-later
-- Spread simulation of run times in the exchange (plan "Laufzeiten im Austausch", task 3): many
-- clients with the real Collector/Proto.lua and Collector/Runs.lua in one hidden channel. Every
-- message a client sends reaches every client online at that moment. Plain Lua, no WoW API,
-- deterministic for a seed. Model values are chosen, not measured (docs/RUN-TIMES.md):
--   rounds    ROUND seconds each; in every round a client starts one session with probability
--             ONLINE at a random moment, lasting SESSION_MIN..SESSION_MAX seconds (it may run on into
--             the next round: players log in around the clock)
--   own runs  one section per RUN_EVERY seconds of play, sent 30 to 90 s later (as Exchange.Offer)
--   relaying  the exchange ticker asks the vault once per second (Exchange.Relay), but not while an
--             own message waits for the channel
--   coverage  at the end of every session: the share of all sections that existed when the session
--             began which the client now holds
local M = {}

M.DEFAULTS = {
	clients = 200,
	rounds = 10,
	round = 4 * 3600,
	online = 0.5,
	sessionMin = 3600,
	sessionMax = 3 * 3600,
	runEvery = 1800,
	seed = 20261102,
}

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

local ALPHA = "0123456789abcdefghijklmnopqrstuvwxyz"

local function Quantiles(list)
	table.sort(list)
	local over = 0
	for _, x in ipairs(list) do
		if x >= 0.9 then
			over = over + 1
		end
	end
	return {
		n = #list,
		min = list[1] or 1,
		median = list[math.floor((#list + 1) / 2)] or 1,
		share90 = #list > 0 and over / #list or 1,
	}
end

-- ns: namespace with Proto, Runs and XP loaded; opts overrides M.DEFAULTS. Returns
-- { rounds = { [r] = { n, min, median, share90 } }, sentPerHour, relayedPerHour, receivedPerHour,
--   maxSentPerHour, maxReceivedPerHour, peakNew, peakRate, produced }.
function M.Run(ns, opts)
	local o = {}
	for k, v in pairs(M.DEFAULTS) do
		o[k] = v
	end
	for k, v in pairs(opts or {}) do
		o[k] = v
	end
	local rnd = Rng(o.seed)
	local now = 0
	local function clock()
		return now
	end
	local function epoch()
		return 20762 * 86400 + 43200
	end
	local Proto, Runs = ns.Proto, ns.Runs
	local clients = {}
	for i = 1, o.clients do
		local tok = {}
		for j = 1, 6 do
			local k = rnd(1, 36)
			tok[j] = ALPHA:sub(k, k)
		end
		clients[i] = {
			name = "Player" .. i,
			token = table.concat(tok),
			race = rnd(1, 10),
			class = rnd(1, 11),
			level = 1,
			runs = Runs.New({}, { clock = clock, epoch = epoch, curve = ns.XP.TO_LEVEL }),
			sent = 0,
			received = 0,
			relayed = 0,
			online = 0,
		}
	end
	local parsed = {}
	local produced, nproduced = {}, 0 -- keys in the order they were produced
	local out = { rounds = {}, peakNew = 0, peakRate = 0 }
	local onlineList, ends = {}, {}

	local function Broadcast(from, msg)
		from.sent = from.sent + 1
		local f = parsed[msg]
		if not f then
			f = assert(Proto.Parse(msg))
			parsed[msg] = f
		end
		for _, c in ipairs(onlineList) do
			if c ~= from then
				c.received = c.received + 1
				c.runs:Hear(f, msg, from.name, true)
			end
		end
	end

	-- record = false: the simulation ends, the session did not
	local function Logout(c, round, record)
		c.online = c.online + (now - c.since)
		c.on = false
		for _, b in pairs(c.runs.senders) do
			out.peakNew = math.max(out.peakNew, b.new)
			out.peakRate = math.max(out.peakRate, b.n)
		end
		if record == false then
			return
		end
		local have = 0
		for k = 1, c.known do
			if c.runs:Has(produced[k]) then
				have = have + 1
			end
		end
		ends[round] = ends[round] or {}
		table.insert(ends[round], c.known > 0 and have / c.known or 1)
	end

	local starts = {} -- second -> sessions starting then
	for round = 1, o.rounds do
		for _, c in ipairs(clients) do
			if rnd() < o.online then
				local at = (round - 1) * o.round + rnd(0, o.round - 1)
				starts[at] = starts[at] or {}
				table.insert(starts[at], { c = c, to = at + rnd(o.sessionMin, o.sessionMax) })
			end
		end
	end

	local finish = o.rounds * o.round
	for t = 0, finish - 1 do
		now = t
		local round = math.floor(t / o.round) + 1
		for i = #onlineList, 1, -1 do
			local c = onlineList[i]
			if now >= c.until_ then
				table.remove(onlineList, i)
				Logout(c, round)
			end
		end
		for _, s in ipairs(starts[t] or {}) do
			local c = s.c
			if not c.on then -- one session at a time
				c.on, c.since, c.until_, c.known = true, now, s.to, nproduced
				c.nextRun, c.pending = now + o.runEvery, {}
				c.runs:StartSession()
				onlineList[#onlineList + 1] = c
			end
		end
		for _, c in ipairs(onlineList) do
			if now >= c.nextRun then
				-- own section of a plausible pace, sent 30 to 90 s later
				c.nextRun = now + o.runEvery
				local secs, xp = o.runEvery + rnd(-300, 300), 9000 + rnd(0, 3000)
				local msg =
					Proto.Format("s", c.token, c.race, c.class, "s", "l", c.level, 0, secs, xp, 100, c.level + 1, 20762)
				c.level = c.level + 1
				if msg and c.runs:AddOwn(msg) then
					nproduced = nproduced + 1
					produced[nproduced] = Runs.KeyOf(msg)
					c.pending[#c.pending + 1] = { at = now + rnd(30, 90), msg = msg }
				end
			end
			if #c.pending > 0 then
				if now >= c.pending[1].at then
					Broadcast(c, table.remove(c.pending, 1).msg)
				end
			else
				local msg = c.runs:NextRelay()
				if msg then
					c.relayed = c.relayed + 1
					Broadcast(c, msg)
				end
			end
		end
	end
	now = finish
	for _, c in ipairs(onlineList) do
		Logout(c, o.rounds, false)
	end
	for round = 1, o.rounds do
		out.rounds[round] = Quantiles(ends[round] or {})
	end
	local hours, sent, received, relayed = 0, 0, 0, 0
	out.maxSentPerHour, out.maxReceivedPerHour = 0, 0
	for _, c in ipairs(clients) do
		hours = hours + c.online / 3600
		sent, received, relayed = sent + c.sent, received + c.received, relayed + c.relayed
		if c.online >= 3600 then
			out.maxSentPerHour = math.max(out.maxSentPerHour, c.sent / (c.online / 3600))
			out.maxReceivedPerHour = math.max(out.maxReceivedPerHour, c.received / (c.online / 3600))
		end
	end
	out.sentPerHour, out.relayedPerHour, out.receivedPerHour = sent / hours, relayed / hours, received / hours
	out.produced = nproduced
	return out
end

return M
