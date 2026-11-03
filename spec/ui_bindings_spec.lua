-- SPDX-License-Identifier: GPL-3.0-or-later
-- Key bindings (Welle 9, K2; concept §2.7, design rules B5/E9, requirement A57): Bindings.xml lists the
-- actions, unbound by default, each with a name in English and German; every key does what the window
-- does. The combat rule for the keys is part of spec/ui_combat_spec.lua.
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

local function read(path)
	local fh = assert(io.open(path, "rb"))
	local text = fh:read("*a")
	fh:close()
	return text
end

-- { { name = "PATHMARK_X", attrs = "...", body = "..." }, ... } from Bindings.xml
local function bindings()
	local out = {}
	for attrs, body in read("Pathmark/Bindings.xml"):gmatch("<Binding%s([^>]*)>(.-)</Binding>") do
		out[#out + 1] = { name = attrs:match('name="([^"]+)"'), attrs = attrs, body = body }
	end
	return out
end

local function shown(region)
	return rawget(region, "shown") == true
end

describe("Key bindings", function()
	it("Bindings.xml has one binding per action, unbound by default, in the Pathmark section", function()
		local ns = S.login()
		local list = bindings()
		assert.are.equal(#ns.Bindings.ACTIONS, #list)
		for i, b in ipairs(list) do
			local action = ns.Bindings.ACTIONS[i]
			assert.are.equal("PATHMARK_" .. action, b.name)
			assert.matches('category="BINDING_HEADER_PATHMARK"', b.attrs, 1, true)
			assert.is_nil(b.attrs:find("default", 1, true), "a default key would overwrite a binding of the player")
			assert.are.equal('PathmarkBinding("' .. action .. '")', b.body:match("^%s*(.-)%s*$"))
		end
		for _, action in ipairs({ "TOGGLE", "CHECK", "SKIP", "BACK", "WINDOW", "MINI", "STATS" }) do
			assert.is_truthy(read("Pathmark/Bindings.xml"):find('"PATHMARK_' .. action .. '"', 1, true), action)
		end
	end)

	it("every binding has a name on Blizzard's binding page, in English and German", function()
		for locale, names in pairs({
			enUS = { TOGGLE = "Guidance on/off", CHECK = "Check off step", WINDOW = "Step window on/off" },
			deDE = { TOGGLE = "Führung an/aus", CHECK = "Schritt abhaken", WINDOW = "Schrittfenster an/aus" },
		}) do
			local ns = S.login({ locale = locale })
			assert.are.equal("Pathmark", _G.BINDING_HEADER_PATHMARK)
			for _, action in ipairs(ns.Bindings.ACTIONS) do
				local name = _G["BINDING_NAME_PATHMARK_" .. action]
				assert.is_string(name)
				assert.are_not.equal("BINDING_" .. action, name, "untranslated: " .. action)
				assert.is_nil(name:find("\226\128\148"), "no em dash")
			end
			for action, text in pairs(names) do
				assert.are.equal(text, _G["BINDING_NAME_PATHMARK_" .. action])
			end
		end
	end)

	it("check off, step back, skip: the same as the window", function()
		local ns = S.login()
		local first = ns.Route.Current().key
		assert.is_true(_G.PathmarkBinding("CHECK"))
		wow.advance(1)
		local second = ns.Route.Current().key
		assert.are_not.equal(first, second)
		_G.PathmarkBinding("BACK")
		assert.are.equal(first, ns.Route.Current().key)
		wow.popup = nil
		_G.PathmarkBinding("SKIP")
		local popup = wow.popup -- the step has follow-up quests: the same dialog as from the menu
		if popup then
			assert.are.equal("PATHMARK_SKIP_CHAIN", popup.which)
			assert.are.equal(first, ns.Route.Current().key, "nothing moves before the answer")
			popup.dialog.OnAccept(nil, popup.data)
		end
		assert.are.equal("skipped", ns.Route.StepState(first))
		assert.matches("skipped", ns.StepFrame.frame.status.text, 1, true)
	end)

	it("guidance on and off, step window on and off, mini view", function()
		local ns = S.login()
		local W, A = ns.StepFrame.frame, ns.Arrow.frame
		_G.PathmarkBinding("WINDOW")
		assert.is_false(shown(W))
		assert.is_true(shown(A), "the arrow keeps guiding")
		_G.PathmarkBinding("WINDOW")
		assert.is_true(shown(W))
		_G.PathmarkBinding("MINI")
		assert.is_true(ns.UI.DB().mini)
		_G.PathmarkBinding("MINI")
		assert.is_nil(ns.UI.DB().mini)
		_G.PathmarkBinding("TOGGLE")
		assert.is_true(ns.UI.Paused())
		assert.is_false(shown(W))
		local cur = ns.Route.Current().key
		assert.is_false(_G.PathmarkBinding("CHECK"), "while paused only the guidance key works")
		wow.advance(1)
		assert.are.equal(cur, ns.Route.Current().key)
		_G.PathmarkBinding("TOGGLE")
		assert.is_false(ns.UI.Paused())
		assert.is_true(shown(W))
	end)

	it("opens and closes the page “Your run”, after a fight", function()
		S.login()
		local function page()
			return _G.PathmarkStatsFrame ~= nil and shown(_G.PathmarkStatsFrame)
		end
		_G.PathmarkBinding("STATS")
		assert.is_true(page())
		_G.PathmarkBinding("STATS")
		assert.is_false(page())
		S.combat(true)
		_G.PathmarkBinding("STATS")
		assert.is_false(page())
		S.combat(false)
		assert.is_true(page())
	end)

	it("the hidden step window comes back with a /reload", function()
		local ns = S.login()
		_G.PathmarkBinding("WINDOW")
		assert.is_false(shown(ns.StepFrame.frame))
		ns = S.login({ saved = PathmarkDB })
		assert.is_true(shown(ns.StepFrame.frame))
	end)

	it("does nothing while the module is off", function()
		local ns = S.login({ saved = { flags = { bindings = false } } })
		local cur = ns.Route.Current().key
		assert.is_false(_G.PathmarkBinding("CHECK"))
		wow.advance(1)
		assert.are.equal(cur, ns.Route.Current().key)
		assert.is_false(_G.PathmarkBinding("NOPE"))
	end)
end)
