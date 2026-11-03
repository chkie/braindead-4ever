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

-- Collector/Exchange.lua: every installation shares its discoveries with other players who run the
-- addon, through addon messages (Plan: "Teilen im Spiel"; owner decision 2026-11-01: contributing data
-- is part of the addon, not an option). Received finds go into the collector's second buffer marked
-- as unconfirmed ("rx"); a second independent sender confirms them ("rx2").
-- Transport after chapter 13 pattern D and the ForeverItemFinder channel approach (GPL-3.0, read only;
-- own code): group, guild and a hidden custom chat channel, own token bucket (server default 10 per
-- prefix, +1/s), 2 s gap on the channel, nothing sent during chat lockdown or from trial accounts.
-- Privacy: sender names live in memory for this session only and are never saved. Finds for guild
-- and channel wait 30 to 90 s, so a message does not tell where a player is right now.
-- Run times ("s", Collector/Runs.lua): received ones go into the run vault, not into the find buffer;
-- the vault's sections are passed on over the hidden channel only, one message per 10 s at most, and
-- only while no own message is due there (own messages first).
-- Channel budget (Collector/Budget.lua, owner 2026-11-02: "so rare that there are really no
-- performance problems"): on the hidden channel every message needs a credit of its pool, so the
-- channel carries about the same small traffic for 100 or 20,000 players. Run messages wait for one,
-- finds wait FIND_WAIT seconds for one and are then dropped from the channel (group and guild still
-- get them). Nothing goes on the channel in combat or in an instance.
-- Version notice ("a", Collector/Version.lua): the addon version goes once to each group the player is
-- in, once per session to the guild and once per session on the channel. On the channel it needs a
-- credit of the finds pool like a find, so it stays inside the channel budget and adds no traffic.
-- Receiving costs next to nothing: the event checks the prefix and puts the raw text into a small
-- inbox (INBOX_MAX, the oldest give way). The ticker reads the inbox in slices (SLICE messages,
-- SLICE_MS), never in combat, never in an instance and never below MIN_FPS frames per second.
local _, ns = ...
local U, Proto, Version = ns.Util, ns.Proto, ns.Version
local M, Guard = ns.Modules, ns.Guard
local Num, Str = U.Num, U.Str

local X = {
	TOKENS = 10, -- burst per prefix (server default, can change at any time)
	QUEUE_MAX = 30, -- oldest queued message gives way
	CHANNEL_GAP = 2, -- seconds between channel messages (FIF)
	DELAY_MIN = 30, -- delay for guild and channel, seconds
	DELAY_MAX = 90,
	FIND_WAIT = 60, -- seconds a due find waits for the channel (credit, no fight, no instance), then it is dropped
	-- Chosen values for the inbox (docs/RUN-TIMES.md): the channel brings about 0.2 messages a second,
	-- so 100 hold a fight of several minutes; a slice of 10 empties a full inbox in 10 s.
	INBOX_MAX = 100, -- per inbox (channel, group and guild); the oldest give way
	SLICE = 10, -- messages read per second at most
	SLICE_MS = 1, -- and milliseconds per slice at most
	MIN_FPS = 20, -- no reading below this frame rate (ChatThrottleLib's MIN_FPS, brain chapter 13 §6)
	SENDER_WINDOW = 300, -- abuse protection per sender (FIF)
	SENDER_MAX = 40, -- finds per window before a sender is muted
	BAD_MAX = 5, -- broken messages before a sender is muted
	SEEN_MAX = 5000, -- remembered find keys per session
	RECENT_MAX = 100, -- received finds kept for the interface
	JOIN_DELAY = 8, -- the game's own channels join first, ours waits so it never takes their numbers
	CHANNELS = { "BraindeadShare", "BraindeadShare2", "BraindeadShare3", "BraindeadShare4", "BraindeadShare5" },
	PASSWORD = "pm1",
	queue = {},
	tokens = 10,
	nextChannelAt = 0,
	offered = {}, -- own find keys already offered this session
	seen = {}, -- received key -> { first = sender, confirmed = bool }
	nseen = 0,
	senders = {}, -- sender -> { start, finds, bad }
	pseen = {}, -- "sender;questID" of received prerequisite observations (session only)
	muted = {},
	recent = {}, -- received finds, newest last (session only)
	stats = {
		offered = 0,
		sent = 0,
		received = 0,
		confirmed = 0,
		dropped = 0,
		bad = 0,
		relayed = 0,
		budget = 0, -- finds left off the channel for lack of a credit or in a fight or instance
		inbox = 0, -- received messages that gave way in a full inbox
		results = {},
	},
	channel = { slot = 1, state = "waiting", tries = 0 },
}
ns.Exchange = X

-- Inboxes: rings of raw received messages, read later by X.Drain. Parallel arrays, so receiving a
-- message creates no table.
local function Inbox()
	return { text = {}, sender = {}, dist = {}, at = {}, head = 1, tail = 0 }
end
X.inbox = { channel = Inbox(), other = Inbox() }

local api = {}
local ticker

local function Call(fn, ...)
	if not fn then
		return
	end
	local ok, a, b = pcall(fn, ...)
	if ok then
		return a, b
	end
end

local function ChannelName()
	return X.CHANNELS[X.channel.slot]
end

local function ChannelNumber()
	local id = Num((Call(GetChannelName, ChannelName())))
	if id and id > 0 then
		return id
	end
end

-- Own name as the game writes it in CHAT_MSG_ADDON (Forever: "Firstname Lastname", Retail: name without
-- realm). Used only to drop our own echo, never stored.
local function Me()
	return Str((Call(api.GetUnitName, "player"))) or Str((Call(UnitName, "player")))
end

local function SenderKey(sender)
	return Str((Call(api.Ambiguate, sender, "none"))) or sender
end

function X.CanSend()
	if Call(api.IsTrialAccount) or Call(api.IsVeteranTrialAccount) then
		return false -- Forever 1.60.1: trial accounts cannot send addon messages (Beta 4, 70291)
	end
	if Call(api.InChatMessagingLockdown) then
		return false -- encounter, M+ run or PvP match: keep the queue for later
	end
	if Call(api.AreOutgoingAddonChatMessagesRestricted) then
		return false
	end
	return true
end

-- No fight and no instance: only then a message goes on the hidden channel (owner 2026-11-02).
function X.Quiet()
	return not Call(InCombatLockdown) and not Call(IsInInstance)
end

-- Received messages are read only when the player is not fighting, not in an instance and the frame
-- rate is not low.
function X.CanRead()
	if not X.Quiet() then
		return false
	end
	local fps = Call(GetFramerate)
	return not (type(fps) == "number" and fps < X.MIN_FPS)
end

local function Waiting(box)
	return box.tail - box.head + 1
end
X.Waiting = Waiting

-- A channel message may go now: no fight, no instance, the estimate has read everything heard, and
-- the budget gives a credit of its pool.
local function ChannelReady(item)
	return X.Quiet() and Waiting(X.inbox.channel) == 0 and X.budget:Has(item.pool)
end

-- Where a find goes right now. Group without delay, guild and channel later.
local function Targets()
	local list = {}
	if Call(IsInGroup, LE_PARTY_CATEGORY_INSTANCE) then
		list[#list + 1] = { dist = "INSTANCE_CHAT", delay = false }
	elseif Call(IsInRaid) then
		list[#list + 1] = { dist = "RAID", delay = false }
	elseif Call(IsInGroup) then
		list[#list + 1] = { dist = "PARTY", delay = false }
	end
	if Call(IsInGuild) then
		list[#list + 1] = { dist = "GUILD", delay = true }
	end
	if X.channel.state == "on" then
		list[#list + 1] = { dist = "CHANNEL", delay = true }
	end
	return list
end

local R -- Enum.SendAddonMessageResult, resolved at init
local RETRY = {}

function X.Pump()
	if not M.IsActive("exchange") or not X.CanSend() then
		return
	end
	local now, q = GetTime(), X.queue
	local i = 1
	while i <= #q and X.tokens >= 1 do
		local item = q[i]
		if item.at > now or (item.dist == "CHANNEL" and now < X.nextChannelAt) then
			i = i + 1
		elseif item.pool and not ChannelReady(item) then
			if item.pool == "runs" or now - item.at < X.FIND_WAIT then
				i = i + 1 -- a run time waits for its share of the channel, a find for a while
			else
				table.remove(q, i) -- a find without its chance stays off the channel
				X.stats.budget = X.stats.budget + 1
			end
		else
			local target = item.target
			local result
			if item.dist == "CHANNEL" then
				target = ChannelNumber()
				target = target and tostring(target)
			end
			if item.dist == "CHANNEL" and not target then
				result = "nochannel"
			else
				result = C_ChatInfo.SendAddonMessage(Proto.PREFIX, item.msg, item.dist, target)
			end
			X.stats.results[tostring(result)] = (X.stats.results[tostring(result)] or 0) + 1
			if RETRY[result] then
				X.tokens = 0 -- the server says no: the message stays, next try after the bucket refills
				return
			end
			table.remove(q, i) -- sent or a final error (not in group, no channel, ...)
			if result == R.Success then
				X.tokens = X.tokens - 1
				X.stats.sent = X.stats.sent + 1
				if item.dist == "CHANNEL" then
					X.nextChannelAt = now + X.CHANNEL_GAP
					X.budget:Spend(item.pool)
				end
			end
		end
	end
end

-- Budget pool of a channel message: run times ("s") or finds (every other kind).
local function Pool(msg, dist)
	if dist == "CHANNEL" then
		return msg:sub(1, 2) == "s;" and "runs" or "finds"
	end
end

local function Enqueue(msg, dist, delay)
	local q = X.queue
	if #q >= X.QUEUE_MAX then
		table.remove(q, 1)
		X.stats.dropped = X.stats.dropped + 1
	end
	local at = GetTime()
	if delay then
		at = at + math.random(X.DELAY_MIN, X.DELAY_MAX)
	end
	q[#q + 1] = { msg = msg, dist = dist, at = at, pool = Pool(msg, dist) }
end

-- Passes one section of the run vault on (Collector/Runs.lua): only over the hidden channel, only
-- while no own message is due there (own messages first) and the queue has room, so a relay never
-- pushes an own message out. Runs.RELAY_GAP keeps it to one message per 10 s at most; the channel
-- budget keeps it to the client's share of the run pool, and nothing is relayed in a fight or an
-- instance.
function X.Relay()
	local C = ns.Collector
	local runs = C and C.runs
	if not runs or X.channel.state ~= "on" or not X.CanSend() then
		return false
	end
	if not X.Quiet() or Waiting(X.inbox.channel) > 0 then
		return false
	end
	local q = X.queue
	if #q >= X.QUEUE_MAX / 2 then
		return false
	end
	local now, budget = GetTime(), X.budget
	for _, item in ipairs(q) do
		-- an own message is due: it goes first (a find only while it has a credit, else it is dropped)
		if item.dist == "CHANNEL" and item.at <= now and (item.pool == "runs" or budget:Has(item.pool)) then
			return false
		end
	end
	if not budget:Has("runs") then
		return false
	end
	local msg = runs:NextRelay()
	if not msg then
		return false
	end
	X.stats.relayed = X.stats.relayed + 1
	Enqueue(msg, "CHANNEL", false)
	X.Pump()
	return true
end

-- Version notice: the own version once per group membership, once per session to guild and channel
-- (on the channel with a finds credit like a find; Pump drops it after FIND_WAIT without one). Called
-- by the ticker; a build without a release version ("dev", untagged) announces nothing.
function X.Announce()
	local msg, a = X.versionMsg, X.announced
	if not msg then
		return false
	end
	local group
	if Call(IsInGroup, LE_PARTY_CATEGORY_INSTANCE) then
		group = "INSTANCE_CHAT"
	elseif Call(IsInRaid) then
		group = "RAID"
	elseif Call(IsInGroup) then
		group = "PARTY"
	end
	local any = false
	if group and not a.group then
		Enqueue(msg, group, false)
		any = true
	end
	a.group = group ~= nil
	if not a.guild and Call(IsInGuild) then
		a.guild = true
		Enqueue(msg, "GUILD", true)
		any = true
	end
	if not a.channel and X.channel.state == "on" then
		a.channel = true
		Enqueue(msg, "CHANNEL", true)
		any = true
	end
	if any then
		X.Pump()
	end
	return any
end

-- A version reported by another player: the notice once per session when enough players report a
-- newer one (Collector/Version.lua). The step window shows it in its status line.
local function HeardVersion(who, find)
	local newest = X.versions and X.versions:Heard(who, { find[1], find[2], find[3], pre = find[4] == 1 })
	if newest then
		ns.newerVersion = Version.Text(newest)
		M.Tell(ns.L.MSG_NEW_VERSION:format("|cffff8800Braindead 4ever|r", ns.newerVersion, tostring(ns.version)))
	end
end

-- Called by the collector for each discovery. Fields as in Proto.lua; invalid ones are not sent.
function X.Offer(kind, ...)
	if not M.IsActive("exchange") then
		return false
	end
	local msg = Proto.Format(kind, ...)
	if not msg then
		return false
	end
	local key = Proto.Key(Proto.Parse(msg))
	if X.offered[key] then
		return false
	end
	X.offered[key] = true
	X.stats.offered = X.stats.offered + 1
	for _, t in ipairs(Targets()) do
		Enqueue(msg, t.dist, t.delay)
	end
	X.Pump()
	return true
end

local function Bucket(who)
	local now = GetTime()
	local b = X.senders[who]
	if not b or now - b.start > X.SENDER_WINDOW then
		b = { start = now, finds = 0, bad = 0 }
		X.senders[who] = b
	end
	return b
end

-- A find of another player for the explorer mode (Routes/Explore.lua): rumor, or confirmed.
local function Heard(find, confirmed)
	local E = ns.Explore
	if E and E.Heard and find.kind ~= "t" and find.kind ~= "v" then
		Guard.Call("explore", E.Heard, find, confirmed)
	end
end

-- One received message, read from the inbox. at = when it arrived.
local function Evaluate(text, dist, sender, at)
	local who = SenderKey(sender)
	if who == Me() then
		return
	end
	if dist == "CHANNEL" then
		X.budget:Heard(who, at) -- every message on the channel loads it, also a broken or muted one
	end
	if X.muted[who] then
		return
	end
	local b = Bucket(who)
	local find, err = Proto.Parse(text)
	if not find then
		if err == "bad" then
			X.stats.bad = X.stats.bad + 1
			b.bad = b.bad + 1
			if b.bad >= X.BAD_MAX then
				X.muted[who] = true
			end
		end
		return
	end
	if find.kind == "a" then
		b.finds = b.finds + 1 -- counts towards the sender's limit like a find
		if b.finds > X.SENDER_MAX then
			X.muted[who] = true
			return
		end
		HeardVersion(who, find)
		return
	end
	if find.kind == "s" then
		-- Run time: own limits per sender in the vault (a relaying player sends many, finds do not count).
		local C = ns.Collector
		if C and C.runs then
			X.stats.received = X.stats.received + 1
			C.runs:Hear(find, text, who, dist == "CHANNEL")
		end
		return
	end
	b.finds = b.finds + 1
	if b.finds > X.SENDER_MAX then
		X.muted[who] = true
		return
	end
	X.stats.received = X.stats.received + 1
	local key = Proto.Key(find)
	local s = X.seen[key]
	local C = ns.Collector
	if find.kind == "p" then
		-- Prerequisite observation: one per sender and quest in a session, so one player cannot pose
		-- as several observers by changing the token. It goes to the route's store, not to the finds.
		local per = who .. ";" .. find[2]
		if s or X.pseen[per] then
			return
		end
		X.pseen[per] = true
		X.seen[key] = { first = who }
		X.nseen = X.nseen + 1
		if C and C.RecordNet then
			C.RecordNet("rx", "p", unpack(find, 1, find.n))
		end
		local Route = ns.Route
		if Route and Route.ObserveFind then
			Guard.Call("route", Route.ObserveFind, find)
		end
		return
	end
	if not s then
		if X.nseen >= X.SEEN_MAX then
			X.seen, X.nseen = {}, 0
		end
		X.seen[key] = { first = who }
		X.nseen = X.nseen + 1
		if C and C.RecordNet then
			C.RecordNet("rx", find.kind, unpack(find, 1, find.n))
		end
		local recent = X.recent
		recent[#recent + 1] = { kind = find.kind, key = key, at = GetTime(), confirmed = false }
		if #recent > X.RECENT_MAX then
			table.remove(recent, 1) -- short list
		end
		Heard(find, false)
	elseif not s.confirmed and s.first ~= who then
		-- A second, independent player reports the same find (Plan: confirmation by two players).
		s.confirmed = true
		X.stats.confirmed = X.stats.confirmed + 1
		if C and C.RecordNet then
			C.RecordNet("rx2", find.kind, unpack(find, 1, find.n))
		end
		for i = #X.recent, 1, -1 do
			if X.recent[i].key == key then
				X.recent[i].confirmed = true
				break
			end
		end
		Heard(find, true)
	end
end

-- CHAT_MSG_ADDON: check the prefix and put the raw text into its inbox, nothing else.
local function Receive(prefix, text, dist, sender)
	if U.IsSecret(prefix) or U.IsSecret(text) or U.IsSecret(sender) then
		return
	end
	if prefix ~= Proto.PREFIX or type(text) ~= "string" or type(sender) ~= "string" then
		return
	end
	local box = dist == "CHANNEL" and X.inbox.channel or X.inbox.other
	local t = box.tail + 1
	box.tail = t
	box.text[t], box.dist[t], box.sender[t], box.at[t] = text, dist, sender, GetTime()
	if t - box.head + 1 > X.INBOX_MAX then
		local h = box.head
		box.text[h], box.dist[h], box.sender[h], box.at[h] = nil, nil, nil, nil
		box.head = h + 1
		X.stats.inbox = X.stats.inbox + 1
	end
end
X.Receive = Receive

-- Reads one slice of the inboxes, oldest message first: at most SLICE messages and SLICE_MS, and
-- only when X.CanRead(). Returns the number read.
function X.Drain()
	if not X.CanRead() then
		return 0
	end
	local stop = debugprofilestop() + X.SLICE_MS
	local c, o = X.inbox.channel, X.inbox.other
	local n = 0
	while n < X.SLICE do
		local box
		if c.head <= c.tail and (o.head > o.tail or c.at[c.head] <= o.at[o.head]) then
			box = c
		elseif o.head <= o.tail then
			box = o
		else
			break
		end
		local h = box.head
		local text, dist, sender, at = box.text[h], box.dist[h], box.sender[h], box.at[h]
		box.text[h], box.dist[h], box.sender[h], box.at[h] = nil, nil, nil, nil
		box.head = h + 1
		n = n + 1
		Evaluate(text, dist, sender, at)
		if debugprofilestop() >= stop then
			break
		end
	end
	return n
end

-- Hidden custom channel ---------------------------------------------------------------------------

local function HideChannel()
	local name = ChannelName()
	for i = 1, tonumber(NUM_CHAT_WINDOWS) or 10 do
		local frame = _G["ChatFrame" .. i]
		if type(frame) == "table" then
			if frame.RemoveChannel then
				pcall(frame.RemoveChannel, frame, name)
			elseif api.ChatFrame_RemoveChannel then
				pcall(api.ChatFrame_RemoveChannel, frame, name)
			end
		end
	end
end

local function Ours(name)
	if type(name) ~= "string" or U.IsSecret(name) then
		return false
	end
	local n = name:lower()
	for _, c in ipairs(X.CHANNELS) do
		if n == c:lower() then
			return true
		end
	end
	return false
end

-- Nothing of the channel reaches a chat window, whatever someone types into it.
-- Chat filter arguments: frame, event, text, author, language, channelString, target, flags,
-- zoneChannelID, channelNumber, channelBaseName.
local function Filter(_, _, _, _, _, _, _, _, _, _, channelName)
	if Ours(channelName) then
		return true
	end
end

local Join
local function Hop()
	local c = X.channel
	local old = ChannelName()
	if ChannelNumber() and api.LeaveChannelByName then
		pcall(api.LeaveChannelByName, old)
	end
	if c.slot >= #X.CHANNELS then
		c.state = "nochannel" -- every name is locked this session: group and guild still work
		return
	end
	c.slot, c.tries, c.refused = c.slot + 1, 0, false
	C_Timer.After(1, Join)
end

function Join()
	local c = X.channel
	if not M.IsActive("exchange") then
		return
	end
	if ChannelNumber() then
		HideChannel()
		c.state = "on"
		X.Pump()
		return
	end
	local join = api.JoinTemporaryChannel or api.JoinChannelByName
	if not join then
		c.state = "nochannel"
		return
	end
	c.tries, c.refused, c.state = c.tries + 1, false, "joining"
	local slot = c.slot
	pcall(join, ChannelName(), X.PASSWORD)
	C_Timer.After(
		2,
		Guard.Wrap("exchange", function()
			if c.slot ~= slot then
				return
			end
			if ChannelNumber() then
				HideChannel()
				c.state = "on"
				X.Pump()
			elseif c.refused then
				Hop()
			elseif c.tries < 3 then
				c.state = "waiting"
				C_Timer.After(30, Guard.Wrap("exchange", Join))
			else
				c.state = "nochannel"
			end
		end)
	)
end
X.Join = Join

-- Only the channel's owner or a moderator can do these; copies of the addon never do.
local TAKEOVER = {
	PASSWORD_CHANGED = true,
	MODERATION_ON = true,
	PLAYER_KICKED = true,
	PLAYER_BANNED = true,
	UNSET_VOICE = true,
	MUTED = true,
}

local function Notice(kind, name)
	if U.IsSecret(kind) or type(kind) ~= "string" or not Ours(name) then
		return
	end
	if name:lower() ~= ChannelName():lower() then
		return
	end
	local c = X.channel
	if kind == "WRONG_PASSWORD" or kind == "BANNED" then
		c.refused = true
	elseif TAKEOVER[kind] and c.state == "on" then
		c.state = "moving"
		Hop()
	elseif kind == "YOU_LEFT" and c.state == "on" then
		c.state, c.tries = "waiting", 0
		C_Timer.After(30, Guard.Wrap("exchange", Join))
	end
end

-- Module ------------------------------------------------------------------------------------------

local function Init()
	for name, path in pairs({
		GetUnitName = "GetUnitName",
		Ambiguate = "Ambiguate",
		IsTrialAccount = "IsTrialAccount",
		IsVeteranTrialAccount = "IsVeteranTrialAccount",
		InChatMessagingLockdown = "C_ChatInfo.InChatMessagingLockdown",
		AreOutgoingAddonChatMessagesRestricted = "C_ChatInfo.AreOutgoingAddonChatMessagesRestricted",
		JoinTemporaryChannel = "JoinTemporaryChannel",
		JoinChannelByName = "JoinChannelByName",
		LeaveChannelByName = "LeaveChannelByName",
		ChatFrame_RemoveChannel = "ChatFrame_RemoveChannel",
		AddMessageEventFilter = "ChatFrameUtil.AddMessageEventFilter",
		ChatFrame_AddMessageEventFilter = "ChatFrame_AddMessageEventFilter",
	}) do
		api[name] = M.Optional(path)
	end
	X.tokens = X.TOKENS
	X.budget = ns.Budget.New({ clock = GetTime })
	local own = Version.Parse(ns.version)
	X.versions = Version.New(own)
	X.versionMsg = own and Proto.Format("a", own[1], own[2], own[3], own.pre and 1 or 0) or nil
	X.announced = { group = false, guild = false, channel = false }
	R = Enum.SendAddonMessageResult
	RETRY = { [R.AddonMessageThrottle] = true, [R.ChannelThrottle] = true, [R.AddOnMessageLockdown] = true }
	local RR = Enum.RegisterAddonMessagePrefixResult
	local res = C_ChatInfo.RegisterAddonMessagePrefix(Proto.PREFIX)
	if res ~= RR.Success and res ~= RR.DuplicatePrefix then
		error("RegisterAddonMessagePrefix: " .. tostring(res), 0)
	end
	local addFilter = api.AddMessageEventFilter or api.ChatFrame_AddMessageEventFilter
	if addFilter then
		for _, event in ipairs({
			"CHAT_MSG_CHANNEL",
			"CHAT_MSG_CHANNEL_NOTICE",
			"CHAT_MSG_CHANNEL_NOTICE_USER",
			"CHAT_MSG_CHANNEL_JOIN",
			"CHAT_MSG_CHANNEL_LEAVE",
		}) do
			pcall(addFilter, event, Filter)
		end
	end
	ticker = C_Timer.NewTicker(
		1,
		Guard.Wrap("exchange", function()
			X.tokens = math.min(X.TOKENS, X.tokens + 1)
			X.Drain()
			X.Announce()
			X.Pump()
			X.Relay()
		end)
	)
end

local function Stop()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	X.queue = {}
	X.inbox = { channel = Inbox(), other = Inbox() }
	if ChannelNumber() and api.LeaveChannelByName then
		pcall(api.LeaveChannelByName, ChannelName())
	end
	X.channel.state = "off"
end

M.Define("exchange", {
	-- Not core (konzept 1.5): it uses addon messages, which can be restricted. Mandatory: no flag and
	-- no manual safe mode turns it off; only the automatic safe mode after failed starts and the error
	-- buffer do, like for every module.
	mandatory = true,
	requires = {
		funcs = { "C_ChatInfo.RegisterAddonMessagePrefix", "C_ChatInfo.SendAddonMessage" },
		events = { "CHAT_MSG_ADDON" },
	},
	optional = {
		funcs = {
			"C_ChatInfo.InChatMessagingLockdown",
			"C_ChatInfo.AreOutgoingAddonChatMessagesRestricted",
			"IsTrialAccount",
			"IsVeteranTrialAccount",
			"GetUnitName",
			"Ambiguate",
			"JoinTemporaryChannel",
			"JoinChannelByName",
			"LeaveChannelByName",
			"GetChannelName",
			"ChatFrame_RemoveChannel",
			"ChatFrameUtil.AddMessageEventFilter",
			"InCombatLockdown",
			"IsInInstance",
			"GetFramerate",
		},
		events = {
			"PLAYER_ENTERING_WORLD",
			"ADDON_RESTRICTION_STATE_CHANGED",
			"CHAT_MSG_CHANNEL_NOTICE",
			"UPDATE_CHAT_WINDOWS",
		},
	},
	init = Init,
	disable = Stop,
	events = {
		CHAT_MSG_ADDON = function(_, _, ...)
			Receive(...)
		end,
		PLAYER_ENTERING_WORLD = function()
			if X.joinPlanned then
				return
			end
			X.joinPlanned = true
			C_Timer.After(X.JOIN_DELAY, Guard.Wrap("exchange", Join))
		end,
		ADDON_RESTRICTION_STATE_CHANGED = function(_, _, rtype, state)
			local T, S = Enum.AddOnRestrictionType, Enum.AddOnRestrictionState
			-- Chat = 5 is in the Forever docs; the pinned annotations (12.0.1) do not list it yet.
			---@diagnostic disable-next-line: undefined-field
			if T and S and rtype == T.Chat and state == S.Inactive then
				X.Pump() -- lockdown over: the ticker would also do it within a second
			end
		end,
		-- Notice arguments: kind, first player, language, channelString, second player, flags,
		-- zoneChannelID, channelNumber, channelBaseName.
		CHAT_MSG_CHANNEL_NOTICE = function(_, _, kind, _, _, _, _, _, _, _, name)
			Notice(kind, name)
		end,
		UPDATE_CHAT_WINDOWS = function()
			if X.channel.state == "on" then
				HideChannel()
			end
		end,
	},
})
