-- SPDX-License-Identifier: GPL-3.0-or-later
-- Version notice (Welle 9, K3; requirement A47, concept §1.5, brain chapter 17 §5 and pattern F): the
-- addon version travels through the existing exchange (message "a"), once per group, once per session
-- to guild and channel, on the channel inside the channel budget. The notice comes only when two
-- different players report a newer version, once per session, quietly in the status line, never in a
-- fight; pre-releases only for players who run one.
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

local function sent(dist)
	local out = {}
	for _, m in ipairs(wow.world.sent) do
		if m.prefix == "BDF" and m.msg:sub(1, 2) == "a;" and (not dist or m.dist == dist) then
			out[#out + 1] = m
		end
	end
	return out
end

-- A version message of another player arrives (party by default) and the exchange reads its inbox.
local function hear(ns, who, msg, dist)
	wow.fire("CHAT_MSG_ADDON", "BDF", msg, dist or "PARTY", who)
	wow.readInbox(ns)
end

describe("Version notice", function()
	describe("versions", function()
		local V = require("spec.helpers.wow").loadFiles({ "BraindeadForever/Collector/Version.lua" }).Version

		it("reads release tags and leaves development builds out", function()
			assert.are.same({ 0, 1, 10, pre = false }, V.Parse("v0.1.10"))
			assert.are.same({ 1, 2, 3, pre = true }, V.Parse("1.2.3-beta.2"))
			assert.is_nil(V.Parse("dev"))
			assert.is_nil(V.Parse("7a60beb"))
			assert.is_nil(V.Parse("v1.2"))
		end)

		it("compares by number, and a release is newer than its pre-release", function()
			assert.is_true(V.Newer(V.Parse("v0.1.10"), V.Parse("v0.1.9")))
			assert.is_true(V.Newer(V.Parse("v0.2.0"), V.Parse("v0.1.99")))
			assert.is_false(V.Newer(V.Parse("v0.1.0"), V.Parse("v0.1.0")))
			assert.is_true(V.Newer(V.Parse("v0.1.0"), V.Parse("v0.1.0-beta.3")))
			assert.is_false(V.Newer(V.Parse("v0.1.0-beta.3"), V.Parse("v0.1.0")))
		end)
	end)

	describe("receiving", function()
		it("needs two different players with a newer version", function()
			local ns = S.login({ version = "v0.1.0" })
			hear(ns, "Anna Sommer", "a;1;0;1;1;0")
			hear(ns, "Anna Sommer", "a;1;0;1;2;0")
			assert.is_nil(ns.newerVersion, "one player alone could fake it")
			hear(ns, "Carl Ostwind", "a;1;0;1;0;0") -- the same version: no vote
			assert.is_nil(ns.newerVersion)
			hear(ns, "Ben Winter", "a;1;0;1;1;0", "GUILD")
			assert.are.equal("0.1.2", ns.newerVersion)
			wow.advance(1)
			assert.are.equal("New version 0.1.2 available", ns.StepFrame.frame.status.text)
			assert.are.equal("", wow.output(), "no chat line while the step window runs")
		end)

		it("once per session: shown until the next completed step, then gone", function()
			local ns = S.login({ version = "v0.1.0" })
			hear(ns, "Anna Sommer", "a;1;0;1;1;0")
			hear(ns, "Ben Winter", "a;1;0;1;1;0")
			wow.advance(1)
			assert.are.equal("New version 0.1.1 available", ns.StepFrame.frame.status.text)
			hear(ns, "Carl Ostwind", "a;1;0;2;0;0")
			hear(ns, "Dora Fels", "a;1;0;2;0;0")
			assert.are.equal("0.1.1", ns.newerVersion, "no second notice in the session")
			ns.StepFrame.frame.box:Click()
			wow.advance(2)
			assert.is_nil(ns.StepFrame.frame.status.text:find("New version", 1, true))
		end)

		it("pre-releases only for players who run one", function()
			local ns = S.login({ version = "v0.1.0" })
			hear(ns, "Anna Sommer", "a;1;0;2;0;1")
			hear(ns, "Ben Winter", "a;1;0;2;0;1")
			assert.is_nil(ns.newerVersion)
			ns = S.login({ version = "v0.2.0-beta.1" })
			hear(ns, "Anna Sommer", "a;1;0;2;0;0")
			hear(ns, "Ben Winter", "a;1;0;2;0;0")
			assert.are.equal("0.2.0", ns.newerVersion)
		end)

		it("is never read in a fight: the notice comes after it", function()
			local ns = S.login({ version = "v0.1.0" })
			S.combat(true)
			wow.fire("CHAT_MSG_ADDON", "BDF", "a;1;0;1;1;0", "PARTY", "Anna Sommer")
			wow.fire("CHAT_MSG_ADDON", "BDF", "a;1;0;1;1;0", "PARTY", "Ben Winter")
			wow.advance(5)
			assert.is_nil(ns.newerVersion)
			S.combat(false)
			wow.advance(1)
			assert.are.equal("0.1.1", ns.newerVersion)
		end)

		it("with the step window down: one chat line", function()
			local ns = S.login({ version = "v0.1.0", saved = { flags = { window = false } } })
			hear(ns, "Anna Sommer", "a;1;0;1;1;0")
			hear(ns, "Ben Winter", "a;1;0;1;1;0")
			assert.are.equal(
				"|cffff8800Braindead Forever|r: version 0.1.1 is available, you have v0.1.0.",
				wow.output()
			)
		end)
	end)

	describe("sending", function()
		it("a release build: once to the group, once per session to guild and channel", function()
			local ns = S.login({ version = "v0.1.0" })
			wow.freeChannel(ns)
			wow.world.group.party, wow.world.guild = true, true
			wow.advance(1)
			assert.are.equal(1, #sent("PARTY"))
			assert.are.equal("a;1;0;1;0;0", sent("PARTY")[1].msg)
			wow.advance(100) -- channel joined after 8 s, guild and channel 30 to 90 s later
			assert.are.equal(1, #sent("GUILD"))
			assert.are.equal(1, #sent("CHANNEL"))
			wow.advance(600)
			assert.are.equal(1, #sent("PARTY"), "once per group")
			assert.are.equal(1, #sent("GUILD"))
			assert.are.equal(1, #sent("CHANNEL"))
			-- a new group gets it again
			wow.world.group.party = false
			wow.advance(1)
			wow.world.group.party = true
			wow.advance(1)
			assert.are.equal(2, #sent("PARTY"))
		end)

		it("on the channel only with a finds credit of the channel budget", function()
			local ns = S.login({ version = "v0.1.0" })
			local spent, asked = {}, {}
			ns.Exchange.budget = {
				Has = function(_, pool)
					asked[#asked + 1] = pool
					return false
				end,
				Spend = function(_, pool)
					spent[#spent + 1] = pool
				end,
				Heard = function() end,
			}
			wow.advance(200)
			assert.are.equal(0, #sent("CHANNEL"), "no credit, no message")
			local askedFinds = false
			for _, pool in ipairs(asked) do
				askedFinds = askedFinds or pool == "finds"
			end
			assert.is_true(askedFinds, "the version message asks the finds pool")
			assert.are.equal(0, #ns.Exchange.queue, "dropped after waiting like a find")
			-- with a credit it goes and takes it
			ns.Exchange.budget.Has = function()
				return true
			end
			ns.Exchange.announced.channel = false
			wow.advance(100)
			assert.are.equal(1, #sent("CHANNEL"))
			assert.are.same({ "finds" }, spent)
		end)

		it("a development build announces nothing", function()
			local ns = S.login()
			wow.freeChannel(ns)
			wow.world.group.party, wow.world.guild = true, true
			wow.advance(200)
			assert.are.equal(0, #sent())
		end)
	end)
end)
