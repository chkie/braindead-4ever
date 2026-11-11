-- SPDX-License-Identifier: GPL-3.0-or-later
-- Replanning in the step window (Welle 7): the question "over the plan" and the switch point as a
-- banner with two buttons, never newly in a fight; the route module with the real Elwynn route.
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

local function shown(region)
	return rawget(region, "shown") == true
end

local OVER =
	{ kind = "over", id = "over:test", key = "a-speed-start-elwynn/a33", gap = 3, plan = 1, drop = { 33, 783 } }

-- Puts a fixed question into the route module, like the developer preview does.
local function stub(ns, offer)
	local answered
	ns.Route.Offer = function()
		return offer
	end
	ns.Route.AnswerOffer = function(yes)
		answered = yes
		offer = nil
		return true
	end
	return function()
		return answered
	end
end

-- Since the quest data of 2026-11-11 the human's Elwynn route walks into Stormwind for one turn-in (t61)
-- and back out. A zone change waits for the player, so these tests let him have done that turn-in and the
-- next quest before he grinds: the first zone change ahead is then the boat to Darkshore again.
local function pastStormwind()
	wow.world.completed[61] = true
	wow.world.completed[11] = true
end

describe("Replanning in the step window", function()
	it("stops at the zone change after grinding and offers the block that fits; undo goes back", function()
		local ns = S.login()
		local W = ns.StepFrame.frame
		wow.world.mapInfo[1439] = { mapID = 1439, name = "Darkshore" }
		local changed
		ns.Route.RegisterCallback("OfferChanged", "test", function(_, offer)
			changed = offer
		end)
		-- twenty levels of grinding in Elwynn Forest without the route
		pastStormwind()
		wow.world.player.level = 20
		wow.fire("PLAYER_LEVEL_UP", 20)
		wow.advance(0.5)
		local cur = ns.Route.Current()
		assert.are.equal("a-speed-core-01-1439/r1453x", cur.key, "the zone change waits for the player")
		local o = ns.Route.Offer()
		assert.are.equal("switch", o.kind)
		assert.are.equal("jump", o.choice.kind)
		-- the block that fits level 20: a-speed-core-04-1439 (Darkshore, levels 18-19); the next block starts at 22
		assert.are.equal("a-speed-core-04-1439/r1439", o.choice.to)
		assert.are.equal(18, o.choice.plan)
		assert.are.equal(o, changed)
		assert.are.equal("Darkshore fits your level better (planned from level 18). Go there next?", W.banner.text)
		assert.are.equal("Go there", W.btnYes.text)
		assert.are.equal("Keep route", W.btnNo.text)
		W.btnYes:Click()
		wow.advance(0.5)
		assert.are.equal(o.choice.to, ns.Route.Current().key)
		-- the level rule passed Elwynn's class quests: the list "later" asks next (KQ-1105), its "no" ends it
		local later = ns.Route.Offer()
		assert.are.equal("later", later and later.kind)
		assert.is_true(ns.Route.AnswerOffer(false))
		assert.is_nil(ns.Route.Offer())
		assert.is_false(shown(W.btnYes))
		assert.are.equal("Undo: zone switched", S.menu(ns).items[2].text)
		ns.Route.Undo()
		assert.are.equal("a-speed-core-01-1439/r1453x", ns.Route.Current().key)
	end)

	it("an alternative module built offline: yes builds the route with it, also after /reload", function()
		local ALT = "a-speed-alt-test"
		local function inject(ns)
			local build = ns.RouteData.Alliance
			ns.RouteData.Alliance = function()
				local data = build()
				data.modules[ALT] = {
					kind = "core",
					mode = "speed",
					levels = { 18, 19 },
					label = "test",
					version = 1,
					steps = {
						{ id = "r1439", lv = 18, { 6, 2, 1439, 16, 0 } },
						{ id = "a1", lv = 18, { 1, 999001, 16, 0 }, { 5, 1439, 6500, 400, 10, 16, 0 } },
					},
				}
				data.quests[999001] = { 20, 1000 }
				-- planned from level 18 like the jump to a-speed-core-04-1439: a tie the time gain decides
				data.alts = { ["a-speed-core-01-1439"] = { { key = ALT, plan = 18, map = 1439, gain = 1200 } } }
				return data
			end
		end
		local char = {}
		local ns = S.login({ char = char, loaded = inject })
		local W = ns.StepFrame.frame
		wow.world.mapInfo[1439] = { mapID = 1439, name = "Darkshore" }
		pastStormwind()
		wow.world.player.level = 20
		wow.fire("PLAYER_LEVEL_UP", 20)
		wow.advance(0.5)
		local o = ns.Route.Offer()
		assert.are.equal("module", o.choice.kind, "the module wins the tie with the jump by its time gain")
		assert.are.equal(
			"Darkshore fits your level better (planned from level 18). Go there next? About 20 min faster.",
			W.banner.text
		)
		W.btnYes:Click()
		wow.advance(0.5)
		assert.are.equal(ALT .. "/r1439", ns.Route.Current().key)
		-- the level rule passed Elwynn's class quests: the list "later" asks next (KQ-1105), its "no" ends it
		local later = ns.Route.Offer()
		assert.are.equal("later", later and later.kind)
		assert.is_true(ns.Route.AnswerOffer(false))
		assert.is_nil(ns.Route.Offer())
		-- /reload: the route is put together with the chosen module again
		ns = S.login({ char = char, loaded = inject, level = 20 })
		wow.world.mapInfo[1439] = { mapID = 1439, name = "Darkshore" }
		assert.are.equal(ALT .. "/r1439", ns.Route.Current().key)
	end)

	-- A core module that returns into a zone left earlier (`!return "neue Quests"`, R09) starts with a
	-- zone change like any other: the switch point offers the block that fits. Only the travel step of a
	-- class insert (`!return "Klassenquest"`, R24) is a detour where the search stops.
	local function returnAt(reason, kind)
		return function(ns)
			local build = ns.RouteData.Alliance
			ns.RouteData.Alliance = function()
				local data = build()
				local m = data.modules["a-speed-core-01-1439"]
				-- every travel step up to the arrival in Darkshore (the ride steps before it carry the
				-- module's !return like the arrival step does)
				for _, st in ipairs(m.steps) do
					st.ret = reason
					if st.id == "r1439" then
						break
					end
				end
				if kind then
					m.kind = kind
				end
				return data
			end
		end
	end

	it("offers the switch at a core module's return into a zone, not at a class detour", function()
		local ns = S.login({ loaded = returnAt("neue Quests") })
		wow.world.mapInfo[1439] = { mapID = 1439, name = "Darkshore" }
		pastStormwind()
		wow.world.player.level = 20
		wow.fire("PLAYER_LEVEL_UP", 20)
		wow.advance(0.5)
		assert.are.equal("a-speed-core-01-1439/r1453x", ns.Route.Current().key)
		local o = ns.Route.Offer()
		assert.is_table(o, "a core return is a zone change: the switch point asks")
		assert.are.equal("switch", o.kind)
		assert.are.equal(18, o.choice.plan)
		-- counter check: the same step as the travel step of a class insert is a detour; it is no switch
		-- point, the level rule passes it like before
		ns = S.login({ loaded = returnAt("Klassenquest", "class") })
		pastStormwind()
		wow.world.player.level = 20
		wow.fire("PLAYER_LEVEL_UP", 20)
		wow.advance(0.5)
		assert.are_not.equal("a-speed-core-01-1439/r1453x", ns.Route.Current().key)
		local again = ns.Route.Offer()
		assert.is_true(again == nil or again.key ~= "a-speed-core-01-1439/r1453x")
	end)

	it("“Keep route” keeps it and does not ask again", function()
		local ns = S.login()
		local W = ns.StepFrame.frame
		pastStormwind()
		wow.world.player.level = 20
		wow.fire("PLAYER_LEVEL_UP", 20)
		wow.advance(0.5)
		assert.is_table(ns.Route.Offer())
		W.btnNo:Click()
		wow.advance(0.5)
		-- the level rule passed Elwynn's class quests: the list "later" asks next (KQ-1105), its "no" ends it
		local later = ns.Route.Offer()
		assert.are.equal("later", later and later.kind)
		assert.is_true(ns.Route.AnswerOffer(false))
		assert.is_nil(ns.Route.Offer())
		assert.are.equal("a-speed-core-01-1439/r1453x", ns.Route.Current().key)
		assert.is_false(shown(W.banner))
	end)

	it("asks “over the plan” with Adjust and Keep route; after Adjust the status line counts", function()
		local ns = S.login()
		local W = ns.StepFrame.frame
		local answered = stub(ns, OVER)
		ns.StepFrame.Refresh()
		assert.are.equal("You are 3 levels above the plan. Adjust the route?", W.banner.text)
		assert.are.equal("Adjust", W.btnYes.text)
		assert.is_true(shown(W.btnNo))
		W.btnYes:Click()
		assert.is_true(answered())
		assert.are.equal("2 quests left out: their turn-in would give less than 80 % XP.", W.status.text)
		assert.is_false(shown(W.btnYes))
	end)

	it("the level hint of a class quest names quest and place and asks Now or Later", function()
		local ns = S.login()
		local W = ns.StepFrame.frame
		wow.world.mapInfo[1454] = { mapID = 1454, name = "Orgrimmar" }
		local answered = stub(ns, { kind = "ready", id = "ready:test", quest = 783, map = 1454, module = "test" })
		ns.StepFrame.Refresh()
		assert.matches("^Your class quest .+ is available now", W.banner.text)
		assert.matches("Orgrimmar%. Do it now or later%?$", W.banner.text)
		assert.are.equal("Now", W.btnYes.text)
		assert.are.equal("Later", W.btnNo.text)
		W.btnNo:Click()
		assert.is_false(answered())
	end)

	it("profession quests ask Fit in or On my own; On my own counts them in the status line", function()
		local ns = S.login()
		local W = ns.StepFrame.frame
		local answered = stub(ns, { kind = "opt", id = "opt:test:beruf", key = "test/tG", quests = { 1, 2, 3 } })
		ns.StepFrame.Refresh()
		assert.are.equal("3 profession quests: fit them in now or do them on your own?", W.banner.text)
		assert.are.equal("Fit in", W.btnYes.text)
		assert.are.equal("On my own", W.btnNo.text)
		W.btnNo:Click()
		assert.is_false(answered())
		assert.are.equal("3 profession quests left out.", W.status.text)
		assert.is_false(shown(W.btnYes))
	end)

	it("profession quests in German, in the owner's words", function()
		local ns = S.login({ locale = "deDE" })
		local W = ns.StepFrame.frame
		stub(ns, { kind = "opt", id = "opt:test:beruf", key = "test/tG", quests = { 1 } })
		ns.StepFrame.Refresh()
		assert.are.equal("Berufsquest: jetzt kurz einschieben oder selbst machen?", W.banner.text)
		assert.are.equal("Einschieben", W.btnYes.text)
		assert.are.equal("Selbst machen", W.btnNo.text)
	end)

	it("shows no new question in a fight, one shown before stays", function()
		local ns = S.login()
		local W = ns.StepFrame.frame
		S.combat(true)
		stub(ns, OVER)
		ns.StepFrame.Refresh()
		assert.is_false(shown(W.btnYes), "no new question in a fight")
		S.combat(false)
		ns.StepFrame.Refresh()
		assert.is_true(shown(W.btnYes))
		S.combat(true)
		ns.StepFrame.Refresh()
		assert.is_true(shown(W.btnYes), "the question shown before stays")
	end)

	it("speaks German", function()
		local ns = S.login({ locale = "deDE" })
		local W = ns.StepFrame.frame
		stub(ns, OVER)
		ns.StepFrame.Refresh()
		assert.are.equal("Du bist 3 Stufen über dem Plan. Route anpassen?", W.banner.text)
		assert.are.equal("Anpassen", W.btnYes.text)
		assert.are.equal("Route behalten", W.btnNo.text)
		local ST = ns.StepText
		local text = ST.Offer({ kind = "switch", choice = { map = 1436, plan = 14, gain = 1800 } })
		assert.are.equal(
			"Westfall passt besser zu deiner Stufe (geplant ab Stufe 14). Als Nächstes dorthin? Etwa 30 Min. schneller.",
			text
		)
		-- "ihre" means the quest's: lower case, so it never reads as the polite "Ihre" (screenshot round 3);
		-- a no-break space keeps "80" and "%" on one line
		assert.are.equal("1 Quest ausgelassen, weil ihre Abgabe weniger als 80\194\160% EP brächte.", ST.Adjusted(1))
	end)
end)
