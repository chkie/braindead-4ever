-- SPDX-License-Identifier: GPL-3.0-or-later
-- Messages the player did not ask for (Welle 9, K4; concept §1.5, design rule R2, requirement A54):
-- automatic safe mode and a module turned off go into the status line of the step window. Only when the
-- step window itself is down does one chat line per session go out instead.
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

-- SavedVariables of a player whose last start did not finish twice (start guard, Core/Boot.lua).
local function twoFailedStarts(extra)
	local saved = extra or {}
	saved.boot = { inProgress = true, fails = 1, version = "dev" }
	return saved
end

describe("Messages without a command", function()
	it("automatic safe mode: status line of the step window, no chat line", function()
		local ns = S.login({ saved = twoFailedStarts() })
		assert.is_true(BraindeadForeverDB.safeMode)
		assert.is_true(BraindeadForeverDB.autoSafe)
		assert.are.equal("Safe mode: only the core is running", ns.StepFrame.frame.status.text)
		assert.are.equal("", wow.output())
	end)

	it("automatic safe mode with the step window down: one chat line", function()
		S.login({ saved = twoFailedStarts({ flags = { window = false } }) })
		assert.is_true(BraindeadForeverDB.safeMode)
		assert.matches("did not start cleanly twice, safe mode is on", wow.output(), 1, true)
		assert.are.equal(1, #wow.printed)
	end)

	it("a module turned off at runtime: status line, no chat line", function()
		local ns = S.login()
		local tick = ns.Guard.Wrap("arrow", function()
			error("arrow failed", 0)
		end)
		for _ = 1, 5 do
			wow.advance(1)
			tick()
		end
		wow.advance(1)
		assert.are.equal("disabled", ns.Modules.state.arrow)
		assert.are.equal("Module arrow turned off, see /bd4 status", ns.StepFrame.frame.status.text)
		assert.are.equal("", wow.output())
	end)

	it("at most one chat line per session while the step window is down", function()
		local ns = S.login({ saved = { flags = { window = false } } })
		for _, name in ipairs({ "arrow", "mappins" }) do
			local tick = ns.Guard.Wrap(name, function()
				error(name .. " failed", 0)
			end)
			for _ = 1, 5 do
				wow.advance(1)
				tick()
			end
		end
		assert.are.equal("disabled", ns.Modules.state.mappins)
		assert.are.equal(1, #wow.printed)
		assert.matches("module arrow turned off", wow.output(), 1, true)
	end)
end)
