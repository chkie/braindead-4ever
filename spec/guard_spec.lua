-- SPDX-License-Identifier: GPL-3.0-or-later
-- Core/Guard.lua: error buffer, dedup, first occurrence to the handler, error burst.
local wow = require("spec.helpers.wow")

local CORE =
	{ "BraindeadForever/Locales/enUS.lua", "BraindeadForever/Core/Guard.lua", "BraindeadForever/Core/Modules.lua" }

local function setup(opts)
	wow.reset(opts)
	local ns = wow.loadFiles(CORE)
	ns.db = { flags = {}, safeMode = false }
	return ns
end

describe("Guard", function()
	it("passes arguments through and returns the results", function()
		local ns = setup()
		local add = ns.Guard.Wrap("calc", function(a, b)
			return a + b, "ok"
		end)
		local sum, tag = add(2, 3)
		assert.are.equal(5, sum)
		assert.are.equal("ok", tag)
		assert.are.equal(
			7,
			ns.Guard.Call("calc", function(a, b)
				return a + b
			end, 3, 4)
		)
	end)

	it("catches an error and returns nothing instead of throwing", function()
		local ns = setup()
		local boom = ns.Guard.Wrap("calc", function()
			error("broken")
		end)
		assert.has_no.errors(function()
			assert.is_nil(boom())
		end)
		assert.are.equal(1, #ns.Guard.list)
		assert.matches("broken", ns.Guard.list[1].msg)
	end)

	it("reports only the first occurrence to the error handler and counts repeats", function()
		local ns = setup()
		local boom = ns.Guard.Wrap("calc", function()
			error("same failure", 0)
		end)
		boom()
		boom()
		boom()
		assert.are.same({ "Braindead Forever [calc] same failure" }, wow.errors)
		assert.are.equal(3, ns.Guard.list[1].count)
	end)

	it("stays quiet towards the handler when quietErrors is set", function()
		local ns = setup()
		ns.db.flags.quietErrors = true
		ns.Guard.Call("calc", function()
			error("hidden", 0)
		end)
		assert.are.same({}, wow.errors)
		assert.are.equal(1, #ns.Guard.list)
	end)

	it("stores a secret error value as <secret>", function()
		local ns = setup()
		ns.Guard.Call("combat", function()
			error(wow.SECRET)
		end)
		assert.are.equal("<secret>", ns.Guard.list[1].msg)
		assert.are.same({ "Braindead Forever [combat] <secret>" }, wow.errors)
	end)

	it("overwrites the oldest entry when the ring is full", function()
		local ns = setup()
		ns.Guard.MAX = 3
		for i = 1, 4 do
			wow.advance(120) -- keep the burst window empty
			ns.Guard.Call("m" .. i, function()
				error("e" .. i, 0)
			end)
		end
		assert.are.equal(3, #ns.Guard.list)
		assert.is_nil(ns.Guard.byKey["m1|e1"])
		assert.is_table(ns.Guard.byKey["m4|e4"])
	end)

	it("turns a module off after 5 errors within 60 s and skips further calls", function()
		local ns = setup()
		local calls = 0
		ns.Modules.Define("arrow", {})
		ns.Modules.Boot(ns.db)
		local tick = ns.Guard.Wrap("arrow", function()
			calls = calls + 1
			error("arrow failed", 0)
		end)
		for _ = 1, 6 do
			wow.advance(5)
			tick()
		end
		assert.are.equal(5, calls)
		assert.are.equal("disabled", ns.Modules.state.arrow)
		assert.are.equal("5 errors in 60 s", ns.Modules.why.arrow)
		assert.are.equal(1, #wow.errors)
		assert.matches("module arrow turned off", wow.output(), 1, true)
	end)

	it("keeps a module on when the errors are spread over more than 60 s", function()
		local ns = setup()
		ns.Modules.Define("arrow", {})
		ns.Modules.Boot(ns.db)
		local tick = ns.Guard.Wrap("arrow", function()
			error("slow failure", 0)
		end)
		for _ = 1, 8 do
			wow.advance(20)
			tick()
		end
		assert.are.equal("on", ns.Modules.state.arrow)
	end)

	it("builds a sorted report", function()
		local ns = setup()
		ns.Guard.Call("b", function()
			error("second", 0)
		end)
		ns.Guard.Call("a", function()
			error("first", 0)
		end)
		assert.are.equal("1x [a] first\n1x [b] second", ns.Guard:Report())
	end)
end)
