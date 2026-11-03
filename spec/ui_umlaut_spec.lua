-- SPDX-License-Identifier: GPL-3.0-or-later
-- Umlauts in every window (Welle 9, K7; release gate T19, concept §2.3 "Pfeilziel 1"): German texts are
-- limited by width and line count (SetMaxLines), never cut in the code. The step window has its test in
-- spec/ui_size_spec.lua; this one covers the arrow and the first start.
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

-- A string cut in the middle of a UTF-8 character ends in a lead byte without its continuation bytes.
local function wholeUTF8(t)
	t = t or ""
	return t:find("[\194-\244]%f[^\128-\191]") == nil
end

local LONG = "Bei der Hütte am Südufer des Kristallsees die Überreste der Gnolle untersuchen und zurückkehren"

describe("Umlauts (T19)", function()
	it("arrow: the German goal stays whole in one line of fixed width", function()
		local ns = S.login({ locale = "deDE" })
		local F = ns.Arrow.frame
		assert.are.equal("„Wölfe an der Grenze“ annehmen", F.title.text)
		assert.are.equal(1, F.title.maxLines)
		assert.are.equal(220, F.title.w)
		assert.is_true(wholeUTF8(F.title.text))
		-- a goal longer than the line: the text stays whole, the client cuts the line at the edge
		ns.Arrow.SetExtra({ map = 1429, wx = 0, wy = 0, title = LONG })
		assert.are.equal(LONG, F.title.text)
		assert.are.equal(1, F.title.maxLines)
		ns.Arrow.Demo(170, 40)
		assert.are.equal("hinter dir", F.hint.text)
		assert.is_true(wholeUTF8(F.hint.text) and wholeUTF8(F.dist.text))
	end)

	it("first start: German card texts stay whole inside their cards", function()
		local ns = S.login({ locale = "deDE", setup = false })
		wow.advance(3)
		local d = _G.BraindeadForeverSetupFrame
		assert.is_true(rawget(d, "shown"))
		local L, Setup = ns.L, ns.Setup
		local inner = Setup.CARD_W - 20
		for i, style in ipairs(ns.Connect.STYLE_ORDER) do
			local card = d.cards[i]
			assert.are.equal(L["STYLE_" .. style], card.title.text)
			assert.are.equal(L["STYLE_SUB_" .. style], card.sub.text)
			assert.are.equal(L["STYLE_TEXT_" .. style], card.text.text)
			assert.are.equal(Setup.SUB_LINES, card.sub.maxLines) -- "Entdecker-Route ohne Hinweise" wraps
			for _, fs in ipairs({ card.title, card.sub, card.text, card.level }) do
				assert.are.equal(inner, fs.w)
				assert.is_true(wholeUTF8(fs.text), "cut character in " .. tostring(fs.text))
			end
		end
		for _, fs in ipairs({ d.question, d.data, d.foot, d.detected }) do
			assert.is_true((fs.w or 0) > 0 and fs.w <= Setup.W - 32, "text inside the window")
			assert.is_true(wholeUTF8(fs.text))
		end
		assert.matches("Spielweise", d.foot.text, 1, true)
	end)
end)
