-- SPDX-License-Identifier: GPL-3.0-or-later
-- Collector/Exchange.lua: sharing finds in the game. Targets, delay, throttling, chat lockdown,
-- trial accounts, the hidden channel, receiving with validation, confirmation and abuse protection.
local wow = require("spec.helpers.wow")

local BOX = { guid = "GameObject-0-1465-0-2105-2843-0000ABC124", name = "Wanted Poster" }

local function start(opts)
	local ns = wow.session(opts)
	return ns, ns.Exchange
end

-- Messages sent with the addon prefix, optionally only on one distribution.
local function sent(dist)
	local out = {}
	for _, m in ipairs(wow.world.sent) do
		if m.prefix == "Pathmark" and (not dist or m.dist == dist) then
			out[#out + 1] = m
		end
	end
	return out
end

local function loot()
	wow.world.loot = { { link = "|Hitem:2589:::|h[x]|h", sources = { BOX.guid, 1 } } }
	wow.fire("LOOT_OPENED", false, false)
end

local function netRecords(ns, kind)
	local store = ns.Collector.net
	store:Flush()
	local out = {}
	for seq = store.db.first, store.db.seq do
		for line in ((store.db.chunks[seq] or "") .. "\n"):gmatch("(.-)\n") do
			if line:match("^" .. kind .. "\t") then
				out[#out + 1] = line
			end
		end
	end
	return out
end

describe("Exchange: sending", function()
	it("registers its prefix and joins the hidden channel 8 s after the first loading screen", function()
		local ns, X = start()
		assert.are.equal("on", ns.Modules.state.exchange)
		assert.is_true(wow.world.prefixes.Pathmark)
		assert.are.equal("waiting", X.channel.state)
		wow.advance(8)
		wow.advance(2)
		assert.are.equal("on", X.channel.state)
		assert.are.equal(5, wow.world.channels.PathmarkShare)
		assert.is_true(wow.world.removedFromChat.PathmarkShare)
		-- chat filter hides every line of the channel, others pass
		local filter = wow.world.chatFilters.CHAT_MSG_CHANNEL
		assert.is_true(filter(nil, "CHAT_MSG_CHANNEL", "hi", "x", "", "", "", "", 0, 5, "PathmarkShare"))
		assert.is_nil(filter(nil, "CHAT_MSG_CHANNEL", "hi", "x", "", "", "", "", 0, 1, "General"))
	end)

	it("sends a find at once to the group and after 30 to 90 s to guild and channel", function()
		local _, X = start()
		wow.advance(10) -- channel joined
		wow.world.group.party, wow.world.guild = true, true
		loot()
		local party = sent("PARTY")
		assert.are.equal(1, #party)
		assert.are.equal("o;1;2843;1429;4231;6512", party[1].msg)
		assert.are.equal(0, #sent("GUILD"))
		assert.are.equal(0, #sent("CHANNEL"))
		wow.advance(29)
		assert.are.equal(0, #sent("GUILD"))
		wow.advance(62)
		assert.are.equal(1, #sent("GUILD"))
		local channel = sent("CHANNEL")
		assert.are.equal(1, #channel)
		assert.are.equal("5", channel[1].target)
		assert.are.equal(1, X.stats.offered)
	end)

	it("offers the same find only once per session", function()
		local _, X = start()
		wow.world.group.party = true
		loot()
		loot()
		assert.are.equal(1, #sent("PARTY"))
		assert.are.equal(1, X.stats.offered)
	end)

	it("sends quest givers, turn-ins, rares and flight masters as IDs and numbers only", function()
		start()
		wow.world.group.party = true
		wow.world.npc, wow.world.questID =
			{ guid = "Creature-0-1465-0-2105-823-0000ABC123", name = "Marshal McBride" }, 783
		wow.fire("QUEST_DETAIL", 0)
		wow.fire("QUEST_ACCEPTED", 783)
		wow.fire("QUEST_COMPLETE")
		wow.fire("QUEST_TURNED_IN", 783, 10, 0)
		wow.world.units.target =
			{ guid = "Creature-0-1465-0-2105-61-0000ABC125", name = "Thuros", classification = "rare" }
		wow.fire("PLAYER_TARGET_CHANGED")
		wow.world.npc = { guid = "Creature-0-1465-0-2105-352-0000ABC127", name = "Dungar" }
		wow.world.taxi.nodes = { { nodeID = 2, state = Enum.FlightPathState.Current } }
		wow.fire("TAXIMAP_OPENED", 0)
		local msgs = {}
		for _, m in ipairs(sent("PARTY")) do
			msgs[#msgs + 1] = m.msg
			assert.matches("^[%w;]+$", m.msg)
			assert.is_true(#m.msg <= 255)
		end
		assert.are.same({
			"q;1;783;c;823;1429;4231;6512",
			"t;1;783;c;823;1429;4231;6512",
			"r;1;61;r;1429;4231;6512",
			"f;1;352;2;1429;4231;6512",
		}, msgs)
	end)

	it("holds to the burst of 10 and refills one message per second", function()
		local _, X = start()
		wow.world.group.party = true
		for i = 1, 15 do
			wow.world.player.x = i / 20 -- 15 different chests
			loot()
		end
		assert.are.equal(10, #sent("PARTY"))
		assert.are.equal(5, #X.queue)
		wow.advance(1)
		assert.are.equal(11, #sent("PARTY"))
		wow.advance(4)
		assert.are.equal(15, #sent("PARTY"))
		assert.are.equal(0, #X.queue)
		-- a long pause refills the bucket to 10, not more
		wow.advance(60)
		for i = 1, 15 do
			wow.world.player.y = i / 20
			loot()
		end
		assert.are.equal(25, #sent("PARTY"))
	end)

	it("keeps the message when the server throttles and sends it later", function()
		local _, X = start()
		wow.world.group.party = true
		local throttle = true
		wow.world.sendResult = function()
			return throttle and Enum.SendAddonMessageResult.AddonMessageThrottle or 0
		end
		loot()
		assert.are.equal(1, #X.queue)
		assert.are.equal(0, X.tokens)
		throttle = false
		wow.advance(1)
		assert.are.equal(0, #X.queue)
		assert.are.equal(0, X.stats.results["3"] - 1) -- exactly one throttled attempt
	end)

	it("sends nothing during the chat lockdown and catches up afterwards", function()
		local _, X = start()
		wow.world.group.party = true
		wow.world.lockdown = true
		loot()
		wow.advance(5)
		assert.are.equal(0, #sent())
		assert.are.equal(1, #X.queue)
		wow.world.lockdown = false
		wow.fire("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Chat, Enum.AddOnRestrictionState.Inactive)
		assert.are.equal(1, #sent("PARTY"))
	end)

	it("never sends from a trial or veteran account", function()
		for _, field in ipairs({ "trial", "veteran" }) do
			start()
			wow.world[field] = true
			wow.world.group.party = true
			loot()
			wow.advance(120)
			assert.are.equal(0, #sent(), field)
		end
	end)

	it("drops the oldest queued message when the queue is full", function()
		local _, X = start()
		wow.world.group.party = true
		wow.world.lockdown = true
		for i = 1, 35 do
			wow.world.player.x = i / 40
			loot()
		end
		assert.are.equal(X.QUEUE_MAX, #X.queue)
		assert.are.equal(5, X.stats.dropped)
	end)

	it("moves to the next channel name when the password is refused", function()
		local _, X = start()
		wow.world.refuse.PathmarkShare = "WRONG_PASSWORD"
		wow.advance(8)
		wow.advance(2)
		wow.advance(1)
		wow.advance(2)
		assert.are.equal(2, X.channel.slot)
		assert.are.equal("on", X.channel.state)
		assert.are.equal(5, wow.world.channels.PathmarkShare2)
	end)

	it("leaves a channel that someone takes over", function()
		local _, X = start()
		wow.advance(10)
		wow.fire("CHAT_MSG_CHANNEL_NOTICE", "PASSWORD_CHANGED", "Griefer", "", "", "", "", 0, 5, "PathmarkShare")
		assert.is_nil(wow.world.channels.PathmarkShare)
		wow.advance(4)
		assert.are.equal("on", X.channel.state)
		assert.are.equal(5, wow.world.channels.PathmarkShare2)
	end)

	it("works without a channel when every name is locked", function()
		local _, X = start()
		for _, name in ipairs(X.CHANNELS) do
			wow.world.refuse[name] = "BANNED"
		end
		wow.advance(60)
		assert.are.equal("nochannel", X.channel.state)
		wow.world.group.party = true
		loot()
		assert.are.equal(1, #sent("PARTY"))
	end)
end)

describe("Exchange: receiving", function()
	local function receive(msg, sender, dist)
		wow.fire("CHAT_MSG_ADDON", "Pathmark", msg, dist or "CHANNEL", sender, "", 0, 5, "PathmarkShare", 0)
	end

	it("stores a find from another player as unconfirmed, without the sender", function()
		local ns, X = start()
		receive("o;1;2843;1429;4231;6512", "Anna Sommer")
		local rx = netRecords(ns, "rx")
		assert.are.equal(1, #rx)
		assert.matches("^rx\t%d+\to\t2843\t1429\t4231\t6512$", rx[1])
		assert.are.equal(1, X.stats.received)
		for seq = 1, ns.Collector.net.db.seq do
			assert.is_nil((ns.Collector.net.db.chunks[seq] or ""):find("Anna", 1, true))
		end
		assert.is_nil(PathmarkCollectDB.net.senders)
	end)

	it("confirms a find when a second player reports it, not when the same one repeats it", function()
		local ns, X = start()
		receive("o;1;2843;1429;4231;6512", "Anna Sommer")
		receive("o;1;2843;1429;4235;6515", "Anna Sommer")
		assert.are.equal(0, #netRecords(ns, "rx2"))
		receive("o;1;2843;1429;4260;6530", "Ben Winter")
		receive("o;1;2843;1429;4260;6530", "Cleo Herbst")
		assert.are.equal(1, #netRecords(ns, "rx"))
		assert.are.equal(1, #netRecords(ns, "rx2"))
		assert.is_true(X.recent[1].confirmed)
	end)

	it("ignores its own echo, other prefixes and secret values", function()
		local ns = start()
		receive("o;1;2843;1429;4231;6512", "Testchar Brightwood")
		wow.fire("CHAT_MSG_ADDON", "Questie", "o;1;2843;1429;4231;6512", "PARTY", "Anna Sommer")
		wow.fire("CHAT_MSG_ADDON", "Pathmark", wow.SECRET, "PARTY", "Anna Sommer")
		wow.fire("CHAT_MSG_ADDON", "Pathmark", "o;1;2843;1429;4231;6512", "PARTY", wow.SECRET)
		assert.are.equal(0, #netRecords(ns, "rx"))
		assert.are.same({}, wow.errors)
	end)

	it("mutes a sender after five broken messages but lets newer versions pass", function()
		local ns, X = start()
		for _ = 1, 4 do
			receive("o;1;broken", "Mallory")
		end
		receive("o;2;2843;1429;4231;6512", "Mallory") -- newer protocol: skipped, not counted
		receive("z;1;1;2;3", "Mallory") -- unknown kind: skipped, not counted
		assert.is_nil(X.muted.Mallory)
		receive("o;1;also broken", "Mallory")
		assert.is_true(X.muted.Mallory)
		receive("o;1;2843;1429;4231;6512", "Mallory")
		assert.are.equal(0, #netRecords(ns, "rx"))
	end)

	it("mutes a sender who reports more than 40 finds in five minutes", function()
		local ns, X = start()
		for i = 1, 45 do
			receive(("o;1;%d;1429;100;100"):format(i), "Spammer")
		end
		assert.is_true(X.muted.Spammer)
		assert.are.equal(40, #netRecords(ns, "rx"))
	end)

	it("keeps received finds in their own buffer so they never push out own data", function()
		local ns = start()
		assert.are_not.equal(ns.Collector.own, ns.Collector.net)
		assert.are.equal(1024 * 1024, ns.Collector.net.STORE_BYTES)
		assert.are.equal(2 * 1024 * 1024, ns.Collector.own.STORE_BYTES)
	end)
end)
