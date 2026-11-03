-- SPDX-License-Identifier: GPL-3.0-or-later
-- Design v2, view 4 "Entdecker-Modus", the parts the interface owns, against the real discovery logic
-- of Welle 4 (ns.Explore, docs/ROUTE-RUNTIME.md §Explorer mode): rumor line with "Show location" in the
-- step window, the revealed find as pin and arrow goal, own finds with a check on the map, play style
-- and hint level handed to ns.Explore.
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

-- A rare creature another player reported in Elwynn Forest (exchange message kind "r").
local function hear(ns)
	ns.Explore.Heard({ kind = "r", n = 5, 62, "r", 1429, 4231, 6512 }, false)
	wow.advance(0.3)
end

local function banner(ns)
	local W = ns.StepFrame.frame
	return rawget(W.banner, "shown") and W.banner.text or nil
end

local function pinsByTitle()
	local out = {}
	for _, p in ipairs(_G.WorldMapFrame.pins) do
		out[#out + 1] = { title = p.title, atlas = p.Icon.atlas }
	end
	return out
end

describe("Discovery in the interface", function()
	it("hands play style and hint level to the discovery logic", function()
		local ns = S.login({ style = "hints" })
		assert.are.equal("hints", ns.Explore.Style())
		assert.are.equal(1, ns.Explore.Level())
		_G.Settings.SetValue("BRAINDEADFOREVER_HINT", 2)
		assert.are.equal(2, ns.Explore.Level())
		_G.Settings.SetValue("BRAINDEADFOREVER_STYLE", "self")
		assert.are.equal("self", ns.Explore.Style())
		assert.are.equal(0, ns.Explore.Level())
		assert.are.equal("explorer", ns.Route.Mode())
	end)

	it("shows a rumor with the zone only, the exact place only on request", function()
		local ns = S.login({ style = "hints" })
		hear(ns)
		assert.are.equal("Rumor: Other players saw a rare creature in Elwynn Forest.", banner(ns))
		local W = ns.StepFrame.frame
		assert.is_true(rawget(W.btnShow, "shown"))
		assert.are.equal("Show location", W.btnShow.text)
		local before = #pinsByTitle()
		W.btnShow:Click()
		assert.are.equal("Rare creature", ns.Arrow.frame.title.text) -- the arrow leads there
		local found = false
		for _, p in ipairs(pinsByTitle()) do
			found = found or (p.title == "Rare creature" and p.atlas == "Waypoint-MapPin-Tracked")
		end
		assert.is_true(found, "revealed find has no pin")
		assert.is_true(#pinsByTitle() > before)
	end)

	it("speaks German in the German client", function()
		local ns = S.login({ style = "hints", locale = "deDE" })
		hear(ns)
		assert.matches("^Gerücht: ", banner(ns))
		assert.matches("Wald von Elwynn", banner(ns), 1, true)
	end)

	it("never shows rumors to “just follow the arrow”: the find is a point on the map", function()
		local ns = S.login({ style = "arrow" })
		hear(ns)
		assert.is_nil(banner(ns))
		local found = false
		for _, p in ipairs(pinsByTitle()) do
			found = found or (p.title == "Rare creature" and p.atlas == "Waypoint-MapPin-Tracked")
		end
		assert.is_true(found)
	end)

	it("never brings a new rumor in combat", function()
		local ns = S.login({ style = "self" })
		_G.Settings.SetValue("BRAINDEADFOREVER_HINT", 1)
		S.combat(true)
		hear(ns)
		assert.is_nil(banner(ns))
		S.combat(false)
		ns.StepFrame.Refresh()
		assert.is_string(banner(ns))
	end)

	it("drops the rumor after the next completed step, once per find", function()
		local ns = S.login({ style = "hints" })
		hear(ns)
		assert.is_string(banner(ns))
		ns.StepFrame.frame.box:Click()
		wow.advance(1)
		assert.is_nil(banner(ns))
		ns.Explore.Heard({ kind = "r", n = 5, 62, "r", 1429, 4231, 6512 }, false) -- the same find again
		wow.advance(0.3)
		assert.is_nil(banner(ns))
	end)

	it("puts own finds on the map with the check, at every hint level", function()
		local ns = S.login({ style = "self" })
		ns.Explore.Own("r", 100, "r", 1429, 2700, 8800)
		wow.advance(0.3)
		local own = false
		for _, p in ipairs(pinsByTitle()) do
			own = own or (p.title == "Rare creature" and p.atlas == "UI-QuestTracker-Tracker-Check")
		end
		assert.is_true(own, "own find not on the map")
	end)

	it("shows nothing of it without the discovery logic", function()
		local ns = S.login({ style = "hints" })
		ns.Explore = nil
		ns.StepFrame.Refresh()
		assert.is_nil(banner(ns))
		assert.are.same({}, ns.Connect.MapItems(1429))
		assert.are.equal(1, ns.Connect.HintLevel())
	end)
end)
