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

-- Collector/Budget.lua: the channel budget (plan "Laufzeiten im Austausch", task 7 with the owner's
-- tightening of 2026-11-02; docs/RUN-TIMES.md). Every message on the hidden channel reaches every
-- player in it, so without a budget the traffic each player receives grows with the number of
-- players. Each client therefore estimates how many players send on the channel and allows itself
-- only its share of a small fixed total, one pool for run messages (own sections and relays) and one
-- for finds:
--   estimate  an upper bound, not a mean, the smaller of two:
--             repeats  of the players heard in the last WINDOW seconds, how many were heard more than
--                      once. Few repeats among many senders mean many players; no repeat at all means
--                      "as many as SENDERS_MAX". A player counts once however much it sends, so one
--                      flooding sender cannot shrink the estimate by more than one repeat.
--             traffic  every client sends at least SHARE / SENDERS_MAX per second, so the messages per
--                      second on the channel times SENDERS_MAX / SHARE bound the number of senders.
--                      This one gets a quiet channel going: there, repeats would take hours.
--             Both use the far end of a one-sided 90 % interval of a Poisson count (Wilson-Hilferty),
--             so the estimate errs on the side of more players and a smaller share.
--   share     a pool grants a credit at random moments (a Poisson process), on average
--             SHARE[pool] / estimate per second, and holds at most one. One message on the channel
--             takes one credit.
--   busy      while BUSY or more messages were heard in the last 60 s, no credit is granted and a
--             held one is dropped: a hard stop whatever the estimate says.
-- No client API gives the member count of a custom channel without side effects: Forever has
-- GetChannelDisplayInfo (count), GetNumChannelMembers and CHANNEL_COUNT_UPDATE (Ketho
-- BlizzardInterfaceResources, branch forever), but Blizzard's channel pane fills the count only for
-- group channels and only after SetSelectedDisplayChannel asks the server for the roster
-- (wow-ui-source forever, Blizzard_Channels/Mainline/ChannelFrame.lua), and GetNumChannelMembers has
-- no documentation. So the estimate uses the messages themselves. Plain Lua 5.1 without WoW API:
-- clock and random are passed in, so the tests and the spread simulation (spec/helpers/spread.lua)
-- run this exact code. Sender names live in this table for WINDOW seconds and are never saved.
local _, ns = ...

local Budget = {}
Budget.__index = Budget
ns.Budget = Budget

-- Chosen values, not measured in the game (docs/RUN-TIMES.md lists them; the in-game measurement
-- after 2026-11-05 decides whether they stay). Owner, 2026-11-02: a client receives at most 0.5
-- messages per second on average and at most 1 per second in any 60 s, whatever the number of
-- players. The shares add up to half of that, which leaves room for the error of the estimate and
-- for chance (spread simulation, spec/channel_budget_spec.lua).
Budget.SHARE = {
	runs = 0.15, -- run messages per second on the whole channel: own sections first, then relays
	finds = 0.1, -- finds, prerequisite observations, version notices and flight legs per second on the whole channel
}
Budget.WINDOW = 3600 -- seconds of channel traffic the estimate looks at
Budget.SENDERS_MAX = 20000 -- players assumed while no sender was heard twice (largest size simulated)
Budget.Z = 1.2816 -- one-sided 90 % bound for the repeats
Budget.REFRESH = 30 -- seconds an estimate is reused
Budget.BUSY = 30 -- channel messages in the last 60 s that stop all sending (half of 1 per second)
Budget.EVENTS_MAX = 2000 -- channel messages remembered; beyond that the window gets shorter

local exp, sqrt, max, min = math.exp, math.sqrt, math.max, math.min

-- Share of the senders heard at least once that were heard at least twice, when every sender sends
-- a Poisson number of messages with mean lam: 1 - lam / (e^lam - 1).
local function RepeatShare(lam)
	if lam < 1e-4 then
		return lam / 2 - lam * lam / 12
	end
	return 1 - lam / (exp(lam) - 1)
end

-- Ends of the one-sided interval for the mean of a Poisson count k (Wilson-Hilferty).
local function Low(k)
	if k <= 0 then
		return 0
	end
	local c = 1 - 1 / (9 * k) - Budget.Z / (3 * sqrt(k))
	return c > 0 and k * c * c * c or 0
end
local function High(k)
	k = k + 1
	local c = 1 - 1 / (9 * k) + Budget.Z / (3 * sqrt(k))
	return k * c * c * c
end

-- Total of the shares: the least a client sends per second times SENDERS_MAX.
local function Total()
	local t = 0
	for _, share in pairs(Budget.SHARE) do
		t = t + share
	end
	return t
end

-- Upper bound on the number of senders from `heard` senders of which `twice` were heard at least
-- twice, and `messages` heard in `span` seconds (all in the window). Pure, for the tests.
function Budget.Estimate(heard, twice, messages, span)
	local bound = Budget.SENDERS_MAX
	if messages and span and span > 0 then
		bound = min(bound, max(heard, High(messages) / span * Budget.SENDERS_MAX / Total()))
	end
	if twice <= 0 or heard <= 0 then
		return bound
	end
	local share = Low(twice) / heard
	if share <= 0 then
		return bound
	end
	if share >= 1 then
		return min(bound, heard)
	end
	local lo, hi = 0, 50 -- messages per sender in the window; RepeatShare rises with it
	for _ = 1, 40 do
		local mid = (lo + hi) / 2
		if RepeatShare(mid) < share then
			lo = mid
		else
			hi = mid
		end
	end
	local n = heard / (1 - exp(-(lo + hi) / 2))
	return min(bound, max(heard, n))
end

-- opts: clock() seconds (required), random() in [0, 1) (default math.random).
function Budget.New(opts)
	opts = opts or {}
	local b = setmetatable({
		clock = assert(opts.clock, "Budget.New: clock required"),
		random = opts.random or math.random,
		at = {}, -- ring of channel messages: time
		who = {}, -- and sender
		head = 1, -- oldest message in the window
		recent = 1, -- oldest message of the last 60 s
		tail = 0,
		count = {}, -- sender -> messages in the window
		heard = 0, -- senders in the window
		twice = 0, -- of them heard at least twice
		credit = {},
		last = {},
	}, Budget)
	b.start = b.clock()
	for pool in pairs(Budget.SHARE) do
		b.credit[pool], b.last[pool] = 0, b.clock()
	end
	return b
end

local function Expire(self, now)
	local from = now - Budget.WINDOW
	local at, who, count = self.at, self.who, self.count
	local h = self.head
	while h <= self.tail and (at[h] <= from or self.tail - h + 1 > Budget.EVENTS_MAX) do
		if at[h] > from then
			self.cut = at[h] -- the window is shorter than WINDOW from here on
		end
		local w = who[h]
		local c = count[w] - 1
		if c == 1 then
			self.twice = self.twice - 1
		elseif c == 0 then
			self.heard = self.heard - 1
			c = nil
		end
		count[w] = c
		at[h], who[h] = nil, nil
		h = h + 1
	end
	self.head = h
	local r = max(self.recent, h)
	while r <= self.tail and at[r] <= now - 60 do
		r = r + 1
	end
	self.recent = r
end

-- A message of another player on the hidden channel, of any kind (also broken or from a muted
-- sender: it loads the channel all the same). who = sender key, session only; at = when it arrived
-- (default now; the exchange reads its inbox later).
function Budget:Heard(who, at)
	at = at or self.clock()
	local t = self.tail + 1
	self.tail = t
	self.at[t], self.who[t] = at, who
	local c = (self.count[who] or 0) + 1
	self.count[who] = c
	if c == 1 then
		self.heard = self.heard + 1
	elseif c == 2 then
		self.twice = self.twice + 1
	end
	Expire(self, at)
end

-- Estimated number of players who send on the channel, this client included. Reused for REFRESH s.
function Budget:Senders()
	local now = self.clock()
	if not self.estimate or now >= self.until_ then
		Expire(self, now)
		local span = min(Budget.WINDOW, now - self.start, now - (self.cut or self.start))
		self.estimate = Budget.Estimate(self.heard, self.twice, self.tail - self.head + 1, span) + 1
		self.until_ = now + Budget.REFRESH
	end
	return self.estimate
end

-- Channel messages heard in the last 60 s.
function Budget:Recent()
	Expire(self, self.clock())
	return self.tail - self.recent + 1
end

-- True while the channel carries BUSY or more messages a minute: nobody adds one.
function Budget:Busy()
	return self:Recent() >= Budget.BUSY
end

-- Messages per second this client may send in a pool.
function Budget:Rate(pool)
	return Budget.SHARE[pool] / self:Senders()
end

-- True when the pool holds a credit. Grants one with the probability that a Poisson process of the
-- pool's rate fired since the last look. A busy channel grants none and takes a held one back.
function Budget:Has(pool)
	local now = self.clock()
	if self:Busy() then
		self.credit[pool], self.last[pool] = 0, now
		return false
	end
	if self.credit[pool] >= 1 then
		return true
	end
	local dt = now - self.last[pool]
	if dt > 0 then
		self.last[pool] = now
		if self.random() < 1 - exp(-self:Rate(pool) * dt) then
			self.credit[pool] = 1
		end
	end
	return self.credit[pool] >= 1
end

-- A message of the pool went out on the channel.
function Budget:Spend(pool)
	self.credit[pool] = 0
	local now = self.clock()
	if now > self.last[pool] then
		self.last[pool] = now
	end
end
