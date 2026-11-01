-- SPDX-License-Identifier: GPL-3.0-or-later
-- Option "Blizzard's quest tracker" (owner reading point 15, Welle 5b task 8): unchanged | only the
-- quests of the route | hidden (default since Welle 5c, owner reading 16). The check marks of the character are saved first and come
-- back with "unchanged", the pause, a module turned off and at logout; a mark the player sets stays,
-- one he removes stays removed; marks Blizzard sets by itself after an accept are not the player's;
-- nothing happens in a fight; an error turns only this module off.
-- Real route data (human warrior, Elwynn Forest: quests 33, 783 and 7 are on the route).
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

local OTHER = { 90001, 90002, 90003 } -- quests the route does not know

local function log(...)
	local entries = {}
	for i = 1, select("#", ...) do
		entries[i] = { questID = (select(i, ...)) }
	end
	return entries
end

local function sorted(list)
	local out = {}
	for i, q in ipairs(list) do
		out[i] = q
	end
	table.sort(out)
	return out
end

-- Login with quests in the log and marks set before Pathmark changed anything. Without opts.saved the
-- player chose "only quests of the route" after Welle 5c (rev 1), so the choice stays.
local function login(opts)
	opts = opts or {}
	opts.saved = opts.saved or { ui = { tracker = "route", rev = 1 } }
	local quests, marks = opts.log or { 33, 783, OTHER[1] }, opts.marks or { 33, OTHER[1] }
	local race = opts.race
	opts.before = function(W)
		if race then
			W.player.race = { "-", "-", race } -- a race without a start module (new races are announced)
		end
		W.questLog = log(unpack(quests))
		for _, q in ipairs(marks) do
			W.watches[#W.watches + 1] = q
		end
	end
	local ns = S.login(opts)
	wow.advance(1)
	return ns
end

-- A quest accepted in the game: the log, QUEST_ACCEPTED, and Blizzard's own mark (autoQuestWatch).
local function accept(q)
	local W = wow.world
	W.questLog[#W.questLog + 1] = { questID = q }
	wow.fire("QUEST_ACCEPTED", q)
	W.watch(q, true)
end

describe("Blizzard's quest tracker", function()
	it("hides Blizzard's quest tracker by default and brings it back with the pause and at logout", function()
		local ns = login({ saved = {} })
		assert.are.equal("hide", ns.UI.Get("tracker"))
		assert.are.same({}, wow.world.watches)
		assert.are.equal(0, _G.ObjectiveTrackerFrame.alpha)
		assert.are.same({ 33, OTHER[1] }, ns.QuestWatch.State().saved)
		ns.UI.SetPaused(true)
		wow.advance(1)
		assert.are.same({ 33, OTHER[1] }, sorted(wow.world.watches))
		assert.are.equal(1, _G.ObjectiveTrackerFrame.alpha)
		ns.UI.SetPaused(false)
		wow.advance(1)
		assert.are.same({}, wow.world.watches)
		wow.fire("PLAYER_LOGOUT")
		assert.are.same({ 33, OTHER[1] }, sorted(wow.world.watches))
		assert.are.equal(1, _G.ObjectiveTrackerFrame.alpha)
	end)

	it("saves the marks, then follows only the quests of the route (chosen)", function()
		local ns = login()
		assert.is_true(ns.Modules.IsActive("questwatch"))
		assert.are.equal("route", ns.UI.Get("tracker"))
		assert.is_true(ns.Route.Quests()[33] and ns.Route.Quests()[783])
		assert.is_nil(ns.Route.Quests()[OTHER[1]])
		assert.are.same({ 33, 783 }, sorted(wow.world.watches))
		local state = ns.QuestWatch.State()
		assert.are.same({ 33, OTHER[1] }, state.saved)
		assert.are.same(state, _G.PathmarkCharDB.watch)
	end)

	it("takes Blizzard's own mark from a quest off the route, keeps it on a route quest", function()
		local ns = login({ log = { 33 }, marks = { 33 } })
		accept(OTHER[2])
		accept(7)
		wow.advance(1)
		assert.are.same({ 7, 33 }, sorted(wow.world.watches))
		assert.is_nil(ns.QuestWatch.State().kept[OTHER[2]])
	end)

	it("keeps a mark the player sets and leaves a removed one removed", function()
		local ns = login()
		wow.world.watch(OTHER[1], true) -- the player's click in the quest log
		wow.world.watch(783, false)
		wow.advance(1)
		ns.Route.Check() -- next pass after a step change
		wow.advance(2)
		assert.are.same({ 33, OTHER[1] }, sorted(wow.world.watches))
		local state = ns.QuestWatch.State()
		assert.is_true(state.kept[OTHER[1]])
		assert.is_true(state.dropped[783])
	end)

	it("unchanged brings the saved marks back, with the player's own changes", function()
		local ns = login({ log = { 33, 783, OTHER[1], OTHER[3] }, marks = { 33, OTHER[1] } })
		wow.world.watch(OTHER[3], true)
		wow.advance(1)
		_G.Settings.SetValue("PATHMARK_TRACKER", "keep")
		wow.advance(1)
		assert.are.same({ 33, OTHER[1], OTHER[3] }, sorted(wow.world.watches))
		assert.is_nil(ns.QuestWatch.State().saved)
		_G.Settings.SetValue("PATHMARK_TRACKER", "route")
		wow.advance(1)
		assert.are.same({ 33, 783, OTHER[3] }, sorted(wow.world.watches)) -- the player's mark stays
	end)

	it("the pause restores, going on applies again", function()
		local ns = login()
		ns.UI.SetPaused(true)
		wow.advance(1)
		assert.are.same({ 33, OTHER[1] }, sorted(wow.world.watches))
		ns.UI.SetPaused(false)
		wow.advance(1)
		assert.are.same({ 33, 783 }, sorted(wow.world.watches))
	end)

	it("hidden empties the list but the player's marks and sets the tracker's alpha to 0", function()
		local ns = login({ log = { 33, 783, OTHER[1], OTHER[2] } })
		wow.world.watch(OTHER[2], true)
		wow.advance(1)
		_G.Settings.SetValue("PATHMARK_TRACKER", "hide")
		wow.advance(1)
		assert.are.same({ OTHER[2] }, wow.world.watches)
		assert.are.equal(0, _G.ObjectiveTrackerFrame.alpha)
		_G.Settings.SetValue("PATHMARK_TRACKER", "route")
		wow.advance(1)
		assert.are.equal(1, _G.ObjectiveTrackerFrame.alpha)
		assert.are.same({ 33, 783, OTHER[2] }, sorted(wow.world.watches))
		assert.is_nil(ns.QuestWatch.hidden)
	end)

	it("restores at logout and writes the table back; the next login saves and applies again", function()
		local ns = login()
		_G.PathmarkCharDB = {} -- the client replaced the table during the session
		wow.fire("PLAYER_LOGOUT")
		assert.are.same({ 33, OTHER[1] }, sorted(wow.world.watches))
		assert.are.equal(ns.QuestWatch.State(), _G.PathmarkCharDB.watch)
		assert.is_nil(_G.PathmarkCharDB.watch.saved)
	end)

	it("changes nothing before the first start, without a route, or with unchanged", function()
		local first = login({ setup = false })
		assert.are.same({ 33, OTHER[1] }, wow.world.watches)
		wow.advance(3) -- the first start opens
		first.Setup.Closed() -- closed without a card: "With hints", then the option applies
		wow.advance(1)
		assert.is_nil(first.Route.Quests()[OTHER[1]])
		assert.are.same({ 33, 783 }, sorted(wow.world.watches))
		login({ saved = { ui = { tracker = "keep" } } })
		assert.are.same({ 33, OTHER[1] }, wow.world.watches)
		local ns = login({ race = 99 })
		assert.is_truthy(ns.Route.missing)
		assert.are.same({ 33, OTHER[1] }, wow.world.watches)
	end)

	it("never sets more than Blizzard's 25 marks", function()
		local quests, marks = { 33, 783 }, {}
		for i = 1, 30 do
			quests[#quests + 1] = 91000 + i
		end
		for i = 1, 25 do
			marks[i] = 91000 + i
		end
		local ns = login({ log = quests, marks = marks })
		for i = 1, 25 do
			wow.world.watch(91000 + i, false)
		end
		for i = 1, 25 do
			wow.world.watch(91000 + i, true) -- the player marks 25 quests himself
		end
		wow.advance(1)
		ns.Route.Check()
		wow.advance(2)
		assert.are.equal(25, #wow.world.watches)
	end)

	it("waits for the end of a fight", function()
		local ns = login({ log = { 33, 783, OTHER[1], OTHER[2] } })
		S.combat(true)
		accept(OTHER[2])
		_G.Settings.SetValue("PATHMARK_TRACKER", "hide")
		ns.UI.SetPaused(true)
		ns.UI.SetPaused(false)
		wow.advance(2)
		assert.are.same({}, wow.blocked)
		assert.are.same({ 33, 783, OTHER[2] }, sorted(wow.world.watches))
		S.combat(false)
		assert.are.same({}, wow.blocked)
		assert.are.same({}, wow.world.watches)
		assert.are.equal(0, _G.ObjectiveTrackerFrame.alpha)
	end)

	it("a blocked call turns only this module off and the old marks come back", function()
		local ns = login()
		_G.Settings.SetValue("PATHMARK_TRACKER", "hide")
		wow.advance(0.3)
		wow.fire("ADDON_ACTION_BLOCKED", "Pathmark", "C_QuestLog.RemoveQuestWatch()")
		assert.are.equal("disabled", ns.Modules.state.questwatch)
		assert.matches("blocked", ns.Modules.why.questwatch)
		assert.are.equal("on", ns.Modules.state.window)
		assert.are.same({ 33, OTHER[1] }, sorted(wow.world.watches))
		assert.are.equal(1, _G.ObjectiveTrackerFrame.alpha)
	end)

	it("errors turn only this module off", function()
		local ns = login()
		_G.C_QuestLog.RemoveQuestWatch = function()
			error("taint test")
		end
		for _ = 1, 6 do
			wow.world.watch(OTHER[1], true)
			wow.world.watch(OTHER[1], false)
			wow.advance(1)
			ns.QuestWatch.State().kept[OTHER[1]] = nil
			wow.world.watch(OTHER[1], true)
			ns.UI.SetPaused(true)
			wow.advance(1)
			ns.UI.SetPaused(false)
			wow.advance(1)
		end
		assert.are.equal("disabled", ns.Modules.state.questwatch)
		assert.are.equal("on", ns.Modules.state.window)
		assert.are.equal("on", ns.Modules.state.route)
	end)
end)
