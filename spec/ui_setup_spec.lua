-- SPDX-License-Identifier: GPL-3.0-or-later
-- Design v2, view 3 "Erststart": one window two seconds after the first login, once per account,
-- never in combat; detected race, class, level and start zone without a question; exactly one question
-- with three cards, nothing preselected; a card sets play style and hint level (3, 1, 0) and closes;
-- closing picks "With hints"; reopened from the settings and with /pathmark setup.
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

local function dialog()
	return _G.PathmarkSetupFrame
end

local function first(opts)
	opts = opts or {}
	opts.setup = false
	return S.login(opts)
end

describe("First start", function()
	it("opens two seconds after the first login, centered, with one question and three cards", function()
		local ns = first()
		assert.is_nil(dialog())
		wow.advance(1.6)
		local d = dialog()
		assert.is_true(rawget(d, "shown"))
		assert.are.equal("BasicFrameTemplateWithInset", d.template)
		assert.are.same({ 560, 330 }, { d.w, d.h })
		assert.are.equal("CENTER", d.points[1][1])
		assert.are.equal("Set up Pathmark", d.TitleText.text)
		assert.are.equal("Detected", d.detectedLabel.text)
		assert.are.equal("Mensch • Krieger • Level 1 • Route starts in Elwynn Forest", d.detected.text)
		assert.are.equal("How do you want to play?", d.question.text)
		local titles = {}
		for i, card in ipairs(d.cards) do
			titles[i] = card.title.text .. " / " .. card.level.text
		end
		assert.are.same({
			"Just follow the arrow / Hint level 3",
			"With hints / Hint level 1",
			"Discover on my own / Hint level 0",
		}, titles)
		assert.matches("^Pathmark shares what you discover", d.data.text)
		assert.matches("Closing picks “With hints”%.$", d.foot.text)
		-- the route has not switched before the player chose
		assert.are.equal("speed", ns.Route.Mode())
		local found = false
		for _, name in ipairs(_G.UISpecialFrames) do
			found = found or name == "PathmarkSetupFrame"
		end
		assert.is_true(found, "Escape does not close the setup")
	end)

	it("a card picks style and hint level, plays Blizzard's preset click and leads at once", function()
		for _, c in ipairs({ { 1, "arrow", 3, "speed" }, { 2, "hints", 1, "explorer" }, { 3, "self", 0, "explorer" } }) do
			local ns = first()
			wow.advance(2)
			dialog().cards[c[1]]:Click()
			assert.are.equal(c[2], ns.UI.Get("style"))
			assert.are.equal(c[3], ns.UI.Get("hint"))
			assert.are.equal(c[4], ns.Route.Mode())
			assert.are.same({ 366430 }, wow.world.sounds)
			assert.is_false(rawget(dialog(), "shown"))
			assert.is_true(ns.UI.DB().setupDone)
			assert.are.equal(1, #wow.world.helptips) -- the one usage hint follows
			assert.is_true(rawget(ns.StepFrame.frame, "shown"))
		end
	end)

	it("closing with the cross picks “With hints”", function()
		local ns = first()
		wow.advance(2)
		dialog().CloseButton:Click()
		assert.are.equal("hints", ns.UI.Get("style"))
		assert.are.equal(1, ns.UI.Get("hint"))
		assert.are.equal("explorer", ns.Route.Mode())
		assert.is_true(ns.UI.DB().setupDone)
	end)

	it("comes once per account: the next login does not open it", function()
		local ns = first()
		wow.advance(2)
		dialog().cards[1]:Click()
		local saved = ns.db
		S.login({ saved = { ui = saved.ui }, setup = false })
		wow.advance(5)
		assert.is_nil(dialog())
	end)

	it("never opens in combat: it waits for the end of the fight", function()
		first({ combat = true })
		wow.advance(5)
		assert.is_nil(dialog())
		S.combat(false)
		assert.is_true(rawget(dialog(), "shown"))
		assert.are.same({}, wow.blocked)
	end)

	it("reopens from /pathmark setup; closing it then changes nothing", function()
		local ns = S.login({ style = "self" })
		SlashCmdList.PATHMARK("setup")
		local d = dialog()
		assert.is_true(rawget(d, "shown"))
		assert.are.equal("You can change this any time under “Play style” in the settings.", d.foot.text)
		d.CloseButton:Click()
		assert.are.equal("self", ns.UI.Get("style"))
		SlashCmdList.PATHMARK("setup")
		d.cards[1]:Click()
		assert.are.equal("arrow", ns.UI.Get("style"))
		assert.are.equal(0, #wow.world.helptips) -- the usage hint belongs to the first start only
	end)

	-- Welle 5d, S7: "Entdecker-Route ohne Hinweise" wrapped and pushed the third card's text a line down.
	it("gives every card subtitle two lines, so the three texts start on one line (S7)", function()
		first({ locale = "deDE" })
		wow.advance(2)
		local d = dialog()
		local h = d.cards[1].sub.h
		assert.is_true(h ~= nil and h >= 24)
		for _, card in ipairs(d.cards) do
			assert.are.equal(h, card.sub.h)
			assert.are.equal(2, card.sub.maxLines)
			assert.are.same(
				{ "TOPLEFT", card.sub, "BOTTOMLEFT" },
				{ card.text.points[1][1], card.text.points[1][2], card.text.points[1][3] }
			)
		end
	end)

	it("speaks German in the German client", function()
		first({ locale = "deDE" })
		wow.advance(2)
		local d = dialog()
		assert.are.equal("Pathmark einrichten", d.TitleText.text)
		assert.are.equal("Mensch • Krieger • Stufe 1 • Route ab Wald von Elwynn", d.detected.text)
		assert.are.equal("Wie willst du spielen?", d.question.text)
		assert.are.equal("Einfach dem Pfeil folgen", d.cards[1].title.text)
		assert.are.equal(
			"Jederzeit in den Einstellungen unter „Spielweise“ änderbar. Schließen wählt „Mit Hinweisen“.",
			d.foot.text
		)
	end)
end)
