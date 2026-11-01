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
		wow.world.player.level = 20
		wow.fire("PLAYER_LEVEL_UP", 20)
		wow.advance(0.5)
		local cur = ns.Route.Current()
		assert.are.equal("a-speed-core-01-1436/r1436", cur.key, "the zone change waits for the player")
		local o = ns.Route.Offer()
		assert.are.equal("switch", o.kind)
		assert.are.equal("jump", o.choice.kind)
		assert.are.equal(20, o.choice.plan)
		assert.are.equal(o, changed)
		assert.are.equal("Darkshore fits your level better (planned from level 20). Go there next?", W.banner.text)
		assert.are.equal("Go there", W.btnYes.text)
		assert.are.equal("Keep route", W.btnNo.text)
		W.btnYes:Click()
		wow.advance(0.5)
		assert.are.equal(o.choice.to, ns.Route.Current().key)
		assert.is_nil(ns.Route.Offer())
		assert.is_false(shown(W.btnYes))
		assert.are.equal("Undo: zone switched", S.menu(ns).items[2].text)
		ns.Route.Undo()
		assert.are.equal("a-speed-core-01-1436/r1436", ns.Route.Current().key)
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
					levels = { 20, 22 },
					label = "test",
					version = 1,
					steps = {
						{ id = "r1439", lv = 20, { 6, 2, 1439, 16, 0 } },
						{ id = "a1", lv = 20, { 1, 999001, 16, 0 }, { 5, 1439, 6500, 400, 10, 16, 0 } },
					},
				}
				data.quests[999001] = { 20, 1000 }
				data.alts = { ["a-speed-core-01-1436"] = { { key = ALT, plan = 20, map = 1439, gain = 1200 } } }
				return data
			end
		end
		local char = {}
		local ns = S.login({ char = char, loaded = inject })
		local W = ns.StepFrame.frame
		wow.world.mapInfo[1439] = { mapID = 1439, name = "Darkshore" }
		wow.world.player.level = 20
		wow.fire("PLAYER_LEVEL_UP", 20)
		wow.advance(0.5)
		local o = ns.Route.Offer()
		assert.are.equal("module", o.choice.kind, "the module wins the tie with the jump by its time gain")
		assert.are.equal(
			"Darkshore fits your level better (planned from level 20). Go there next? About 20 min faster.",
			W.banner.text
		)
		W.btnYes:Click()
		wow.advance(0.5)
		assert.are.equal(ALT .. "/r1439", ns.Route.Current().key)
		assert.is_nil(ns.Route.Offer())
		-- /reload: the route is put together with the chosen module again
		ns = S.login({ char = char, loaded = inject, level = 20 })
		wow.world.mapInfo[1439] = { mapID = 1439, name = "Darkshore" }
		assert.are.equal(ALT .. "/r1439", ns.Route.Current().key)
	end)

	it("“Keep route” keeps it and does not ask again", function()
		local ns = S.login()
		local W = ns.StepFrame.frame
		wow.world.player.level = 20
		wow.fire("PLAYER_LEVEL_UP", 20)
		wow.advance(0.5)
		assert.is_table(ns.Route.Offer())
		W.btnNo:Click()
		wow.advance(0.5)
		assert.is_nil(ns.Route.Offer())
		assert.are.equal("a-speed-core-01-1436/r1436", ns.Route.Current().key)
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
		assert.are.equal("1 Quest ausgelassen: Ihre Abgabe brächte weniger als 80 % EP.", ST.Adjusted(1))
	end)
end)
