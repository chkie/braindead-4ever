-- SPDX-License-Identifier: GPL-3.0-or-later
-- Optional automation (requirement A74, UI/Auto.lua, module "auto"): off by default; one switch accepts
-- the quests of the current part of the route, goes on to the reward page and hands them in with a reward
-- only when there is no choice or exactly one. Foreign quests, quests beyond the next steps and skipped
-- quests stay untouched; gossip only ever gets the line of such a quest. Nothing in a fight or during a
-- loading screen, Shift pauses the dialog, the hardcore-safe mode takes no quest the route warns about,
-- the module turns itself off without the client's API, and a call the server ignores leaves the dialog
-- as it was (requirement A40, gamepad). The route is a small one of our own, so changes of the real route
-- data do not touch these tests.
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

local A, B, C, LATER, HIGH, FOREIGN = 900101, 900102, 900103, 900105, 900106, 900999

-- Steps of the test route (compiled layout, docs/ROUTE-FORMAT.md): accept A and B at one giver, the
-- objectives of A, hand in A and take C, hand in B, then a later quest and a high one.
local STEPS = {
	{ id = "s1", lv = 1, { 1, A, 1, 0 }, { 1, B, 1, 0 } },
	{ id = "s2", lv = 1, { 2, A, 1, 0 } },
	{ id = "s3", lv = 1, { 3, A, 1, 0 }, { 1, C, 1, 0 } },
	{ id = "s4", lv = 1, { 3, B, 1, 0 } },
	{ id = "s5", lv = 1, { 1, LATER, 1, 0 } },
	{ id = "s6", lv = 1, { 1, HIGH, 1, 0 } },
}

-- A session with the test route as the human warrior's speed route. opts as in S.login, plus auto
-- (the switch, default on here) and before(world).
local function login(opts)
	opts = opts or {}
	local saved = opts.saved or { ui = {} }
	saved.ui = saved.ui or {}
	if opts.auto ~= false and saved.ui.auto == nil then
		saved.ui.auto = true
	end
	return S.login({
		saved = saved,
		locale = opts.locale,
		before = opts.before,
		loaded = function(ns)
			local build = ns.RouteData.Alliance
			ns.RouteData.Alliance = function()
				local d = build()
				d.modules["t-auto"] = {
					kind = "start",
					mode = "speed",
					levels = { 1, 10 },
					label = "stabil",
					steps = STEPS,
					optional = opts.optional,
				}
				d.compose.speed = { starts = { { key = "t-auto" } }, core = {}, inserts = {} }
				for _, q in ipairs({ A, B, C, LATER, HIGH }) do
					d.quests[q] = { 1, 100, {} }
				end
				return d
			end
		end,
	})
end

local function calls()
	return wow.world.dialog.calls
end

-- The NPC lists these quests to take (gossip and greeting) and these to hand in.
local function offers(available, active)
	wow.world.offers = available or {}
	wow.world.dialog.active = active or {}
end

local function detail(q, startItem)
	wow.world.questID = q
	wow.fire("QUEST_DETAIL", startItem or 0)
end

-- The dialog closes (the server's answer to an accept or a hand-in, or the player's Esc).
local function finish()
	wow.fire("QUEST_FINISHED")
	wow.fire("GOSSIP_CLOSED", false)
	wow.world.dialog.calls = {}
end

-- The quest is in the log with its objectives done; the route moves on.
local function done(q)
	local log = wow.world.questLog
	log[#log + 1] = { questID = q, complete = true }
	wow.fire("QUEST_ACCEPTED", q)
	wow.fire("QUEST_LOG_UPDATE")
	wow.advance(0.5)
end

-- Every call that would close, decline or leave a dialog, or pick a gossip option that is no quest.
local CLOSING = {
	CloseQuest = true,
	DeclineQuest = true,
	["C_GossipInfo.CloseGossip"] = true,
	["C_GossipInfo.SelectOption"] = true,
}

local function noClosing()
	for _, c in ipairs(calls()) do
		assert.is_nil(CLOSING[c[1]], "the addon called " .. c[1])
	end
end

describe("Optional automation", function()
	it("is off by default: the switch starts unchecked and no dialog step runs", function()
		local ns = login({ auto = false })
		assert.is_false(ns.UI.Get("auto"))
		assert.are.equal("on", ns.Modules.state.auto)
		assert.is_false(wow.world.settings.settings.BRAINDEADFOREVER_AUTO:GetValue())
		offers({ A }, {})
		wow.fire("GOSSIP_SHOW")
		detail(A)
		assert.are.same({}, calls())
	end)

	it("leaves an optional quest alone until the player says to fit it in (Camping 101)", function()
		local ns = login({ optional = { beruf = { B } } })
		local dq = ns.Route.DialogQuests()
		assert.is_true(dq.accept[A])
		assert.is_nil(dq.accept[B], "unanswered: not taken")
		local o = ns.Route.Offer()
		assert.are.equal("opt", o.kind)
		assert.is_true(ns.Route.AnswerOffer(true))
		assert.is_true(ns.Route.DialogQuests().accept[B], "fit in: taken like any route quest")
	end)

	describe("accept", function()
		it("selects the route quest in the gossip list and accepts it", function()
			login()
			offers({ FOREIGN, A }, {})
			wow.fire("GOSSIP_SHOW")
			assert.are.same({ { "C_GossipInfo.SelectAvailableQuest", A } }, calls())
			wow.fire("GOSSIP_CLOSED", true) -- the interaction goes on in the quest dialog
			detail(A)
			assert.are.same({ { "C_GossipInfo.SelectAvailableQuest", A }, { "AcceptQuest" } }, calls())
		end)

		it("takes the quest of the next steps too (hand in A, take C), but not one further ahead", function()
			login()
			detail(C)
			assert.are.same({ { "AcceptQuest" } }, calls())
			finish()
			detail(LATER)
			assert.are.same({}, calls(), "the quest of the fifth step waits")
		end)

		it("leaves a foreign quest alone, in the dialog and in the lists", function()
			login()
			offers({ FOREIGN }, { { questID = FOREIGN, isComplete = true } })
			wow.fire("GOSSIP_SHOW")
			wow.fire("QUEST_GREETING")
			detail(FOREIGN)
			wow.fire("QUEST_PROGRESS")
			wow.fire("QUEST_COMPLETE")
			assert.are.same({}, calls())
		end)

		it("leaves a quest the player skipped alone", function()
			local ns = login()
			assert.is_true(ns.Route.Skip("t-auto/s4")) -- skips B with its hand-in step
			detail(B)
			assert.are.same({}, calls())
			detail(A)
			assert.are.same({ { "AcceptQuest" } }, calls())
		end)

		it("acknowledges a quest the server put into the log, not one from an item, an area or PvP", function()
			login()
			wow.world.dialog.autoAccept = true
			detail(A)
			assert.are.same({ { "AcknowledgeAutoAcceptQuest" } }, calls())
			finish()
			wow.world.dialog.areaTrigger = true -- Blizzard makes a pop-up and closes the dialog itself
			detail(B)
			wow.world.dialog.autoAccept, wow.world.dialog.areaTrigger = false, false
			detail(C, 6948) -- started from an item
			assert.are.same({}, calls())
			wow.world.dialog.pvp = true -- Blizzard asks first
			detail(C)
			assert.are.same({}, calls())
		end)

		it("works in the greeting list of an NPC without gossip, by index", function()
			login()
			offers({ FOREIGN, A }, {})
			wow.fire("QUEST_GREETING")
			assert.are.same({ { "SelectAvailableQuest", 2 } }, calls())
		end)
	end)

	describe("hand in and reward", function()
		it("selects the finished quest, goes on to the reward page and takes the only reward", function()
			login()
			done(A)
			offers({}, { { questID = FOREIGN, isComplete = true }, { questID = A, isComplete = true } })
			wow.fire("GOSSIP_SHOW")
			assert.are.same({ { "C_GossipInfo.SelectActiveQuest", A } }, calls())
			wow.fire("GOSSIP_CLOSED", true)
			wow.world.questID = A
			wow.fire("QUEST_PROGRESS")
			wow.world.dialog.choices = 1
			wow.fire("QUEST_COMPLETE")
			assert.are.same({
				{ "C_GossipInfo.SelectActiveQuest", A },
				{ "CompleteQuest" },
				{ "GetQuestReward", 1 },
			}, calls())
		end)

		it("hands in without a reward choice like Blizzard's button (choice 0)", function()
			login()
			done(A)
			wow.world.questID = A
			wow.world.dialog.choices = 0
			wow.fire("QUEST_COMPLETE")
			assert.are.same({ { "GetQuestReward", 0 } }, calls())
		end)

		it("takes nothing when there are several rewards: the player chooses", function()
			login()
			done(A)
			wow.world.questID = A
			wow.world.dialog.choices = 3
			wow.fire("QUEST_PROGRESS")
			wow.fire("QUEST_COMPLETE")
			assert.are.same({ { "CompleteQuest" } }, calls(), "the reward page opens, the choice stays open")
		end)

		it("leaves quests that are not finished or cost money", function()
			login()
			done(A)
			offers({}, { { questID = A, isComplete = false } })
			wow.fire("GOSSIP_SHOW")
			wow.world.questID = A
			wow.world.dialog.completable = false
			wow.fire("QUEST_PROGRESS")
			wow.world.dialog.completable, wow.world.dialog.money = true, 500
			wow.fire("QUEST_PROGRESS")
			wow.fire("QUEST_COMPLETE")
			assert.are.same({}, calls())
		end)

		it("hands in by index in the greeting list", function()
			login()
			done(A)
			offers({}, { { questID = FOREIGN, isComplete = true }, { questID = A, isComplete = true } })
			wow.fire("QUEST_GREETING")
			assert.are.same({ { "SelectActiveQuest", 2 } }, calls())
		end)
	end)

	describe("pauses", function()
		it("for the whole dialog while Shift is held at one of its steps", function()
			login()
			offers({ A }, {})
			wow.world.shift = true
			wow.fire("GOSSIP_SHOW")
			wow.world.shift = false -- the player picks the quest himself and lets go of Shift
			wow.fire("GOSSIP_CLOSED", true)
			detail(A)
			assert.are.same({}, calls())
			finish()
			wow.fire("GOSSIP_SHOW") -- a new dialog
			assert.are.same({ { "C_GossipInfo.SelectAvailableQuest", A } }, calls())
		end)

		it("in a fight, and acts again after it", function()
			login()
			S.combat(true)
			offers({ A }, {})
			wow.fire("GOSSIP_SHOW")
			detail(A)
			assert.are.same({}, calls())
			assert.are.same({}, wow.blocked)
			S.combat(false)
			detail(A)
			assert.are.same({ { "AcceptQuest" } }, calls())
		end)

		it("during a loading screen", function()
			login()
			wow.fire("LOADING_SCREEN_ENABLED")
			detail(A)
			assert.are.same({}, calls())
			wow.fire("LOADING_SCREEN_DISABLED")
			detail(A)
			assert.are.same({ { "AcceptQuest" } }, calls())
		end)
	end)

	describe("hardcore-safe mode", function()
		local function high(ns)
			ns.Route.Runtime().quests[B][1] = 9 -- 8 levels above the character
		end

		it("takes no quest too far above the character, like the route's warning", function()
			local ns = login({ saved = { ui = { hardcore = "on" } } })
			high(ns)
			offers({ B, A }, {})
			wow.fire("GOSSIP_SHOW")
			assert.are.same({ { "C_GossipInfo.SelectAvailableQuest", A } }, calls())
			finish()
			detail(B)
			assert.are.same({}, calls())
		end)

		it("takes no quest the client marks elite", function()
			login({
				saved = { ui = { hardcore = "on" } },
				before = function()
					_G.C_QuestLog.IsEliteQuest = function(q)
						return q == A
					end
				end,
			})
			detail(A)
			assert.are.same({}, calls())
			detail(B)
			assert.are.same({ { "AcceptQuest" } }, calls())
		end)

		it("takes such a quest when the mode is off", function()
			local ns = login({ saved = { ui = { hardcore = "off" } } })
			high(ns)
			detail(B)
			assert.are.same({ { "AcceptQuest" } }, calls())
		end)
	end)

	describe("dialog stays usable (A40)", function()
		it("tries a call the server ignores once, never closes the dialog, with a gamepad as well", function()
			login({
				before = function(W)
					W.inputStyle = 1 -- Forever's gamepad interface
				end,
			})
			-- the server ignores the accept: the dialog stays and the client sends its events again
			for _ = 1, 5 do
				detail(A)
				wow.advance(1)
			end
			assert.are.same({ { "AcceptQuest" } }, calls())
			offers({ A }, {})
			for _ = 1, 5 do
				wow.fire("GOSSIP_SHOW")
			end
			assert.are.same({ { "AcceptQuest" }, { "C_GossipInfo.SelectAvailableQuest", A } }, calls())
			noClosing()
			-- the player's own click still goes through: nothing hid or replaced Blizzard's functions
			_G.AcceptQuest()
			assert.are.equal(3, #calls())
			-- after RETRY seconds one more try, never a loop
			wow.advance(10)
			detail(A)
			detail(A)
			assert.are.equal(4, #calls())
			noClosing()
		end)

		it("never picks a gossip option and touches nothing when the NPC has no route quest", function()
			login()
			offers({ FOREIGN }, { { questID = FOREIGN, isComplete = true } })
			for _ = 1, 3 do
				wow.fire("GOSSIP_SHOW")
			end
			assert.are.same({}, calls())
		end)

		it("turns itself off when the game blocks one of its calls", function()
			local ns = login()
			detail(A)
			wow.fire("ADDON_ACTION_BLOCKED", "Braindead4Ever", "AcceptQuest()")
			assert.are.equal("disabled", ns.Modules.state.auto)
			finish()
			detail(B)
			assert.are.same({}, calls())
		end)
	end)

	describe("setting", function()
		it("sits on the main page as the fifth option with a one-sentence tooltip that names Shift", function()
			for _, locale in ipairs({ "enUS", "deDE" }) do
				local ns = login({ locale = locale, auto = false })
				local s = wow.world.settings.settings.BRAINDEADFOREVER_AUTO
				assert.are.equal(ns.L.OPT_AUTO, s.name)
				local main
				for _, c in ipairs(wow.world.settings.categories) do
					if c.name == "Braindead 4ever" then
						main = c
					end
				end
				local tip
				for _, i in ipairs(main.inits) do
					if i.setting == s then
						tip = i.tooltip
					end
				end
				assert.are.equal(ns.L.TIP_AUTO, tip)
				assert.matches(locale == "deDE" and "Umschalt" or "Shift", tip)
				ns.UI.Set("auto", true)
				assert.is_true(s:GetValue())
			end
		end)

		it("is not offered when the client lacks the API, and the module stays off", function()
			local ns = login({
				before = function()
					_G.AcknowledgeAutoAcceptQuest = nil
				end,
			})
			assert.are.equal("off", ns.Modules.state.auto)
			assert.matches("AcknowledgeAutoAcceptQuest", ns.Modules.why.auto, 1, true)
			assert.is_nil(wow.world.settings.settings.BRAINDEADFOREVER_AUTO)
			detail(A)
			assert.are.same({}, calls())
			assert.are.same({}, wow.errors)
		end)
	end)
end)
