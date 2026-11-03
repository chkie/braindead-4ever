-- SPDX-License-Identifier: GPL-3.0-or-later
-- TomTom hand-over (Welle 9, K1; requirement A36, concept §2.3) with a stand-in of TomTom's interface as
-- read in v4.3.13 (TomTom:AddWaypoint(uiMapID, x, y, opts) returns a uid table, RemoveWaypoint(uid)).
-- The real TomTom in a client is release gate T20.
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

-- Stand-in: records every call; waypoints holds the uids TomTom still shows.
local function fakeTomTom()
	local tt = { added = {}, removed = {}, waypoints = {} }
	function tt:AddWaypoint(m, x, y, opts)
		local uid = { m, x, y, title = opts and opts.title }
		self.added[#self.added + 1] = { m = m, x = x, y = y, opts = opts }
		self.waypoints[uid] = true
		return uid
	end
	function tt:RemoveWaypoint(uid)
		assert(type(uid) == "table", "TomTom:RemoveWaypoint(uid) UID is not a table.")
		self.removed[#self.removed + 1] = uid
		self.waypoints[uid] = nil
	end
	return tt
end

local function count(set)
	local n = 0
	for _ in pairs(set) do
		n = n + 1
	end
	return n
end

local function login(opts)
	opts = opts or {}
	local tt = fakeTomTom()
	local before = opts.before
	opts.before = function(W)
		_G.TomTom = tt
		if before then
			before(W)
		end
	end
	local ns = S.login(opts)
	return ns, tt
end

describe("TomTom hand-over", function()
	after_each(function()
		_G.TomTom = nil
	end)

	it("hands the current goal to TomTom, quietly and for this session only", function()
		local ns, tt = login()
		assert.are.equal("on", ns.Modules.state.tomtom)
		assert.are.equal(1, #tt.added)
		local w = tt.added[1]
		assert.are.equal(1429, w.m)
		assert.is_true(w.x > 0 and w.x < 1 and w.y > 0 and w.y < 1, "map position 0..1")
		assert.are.equal("Accept “Wolves Across the Border”", w.opts.title)
		assert.is_true(w.opts.silent, "no TomTom chat line (rule R2)")
		assert.is_false(w.opts.persistent)
		assert.are.equal("Braindead 4ever", w.opts.from)
		assert.are.equal(1, count(tt.waypoints))
	end)

	it("replaces the waypoint at every new goal and keeps only one", function()
		local ns, tt = login()
		local first = tt.added[1]
		ns.Route.Check()
		wow.advance(2)
		assert.is_true(#tt.added >= 2)
		assert.is_true(first.x ~= tt.added[#tt.added].x or first.y ~= tt.added[#tt.added].y)
		assert.are.equal(1, count(tt.waypoints))
		assert.are.equal(#tt.added - 1, #tt.removed)
	end)

	it("takes the waypoint back on pause, with the option off and at the end of the route", function()
		local ns, tt = login()
		ns.UI.SetPaused(true)
		assert.are.equal(0, count(tt.waypoints))
		ns.UI.SetPaused(false)
		assert.are.equal(1, count(tt.waypoints))
		_G.Settings.SetValue("BRAINDEADFOREVER_TOMTOM", false)
		assert.are.equal(0, count(tt.waypoints))
		ns.Route.Check()
		wow.advance(2)
		assert.are.equal(0, count(tt.waypoints))
		_G.Settings.SetValue("BRAINDEADFOREVER_TOMTOM", true)
		assert.are.equal(1, count(tt.waypoints))
		local rt = ns.Route.Runtime()
		rt.saved.anchor = "_end"
		rt:Evaluate()
		wow.advance(1)
		assert.are.equal(0, count(tt.waypoints))
	end)

	it("waits for the end of a fight", function()
		local ns, tt = login()
		local n = #tt.added
		S.combat(true)
		ns.Route.Check()
		wow.advance(2)
		assert.are.equal(n, #tt.added)
		S.combat(false)
		assert.are.equal(n + 1, #tt.added)
	end)

	it("has its option on the Arrow and Map page, in English and German", function()
		login()
		local s = wow.world.settings.settings.BRAINDEADFOREVER_TOMTOM
		assert.is_table(s)
		assert.is_true(s:GetValue())
		login({ locale = "deDE" })
		assert.are.equal("Ziel an TomTom übergeben", wow.world.settings.settings.BRAINDEADFOREVER_TOMTOM.name)
	end)

	it("without TomTom: module off, no option, nothing breaks", function()
		local ns = S.login()
		assert.are.equal("off", ns.Modules.state.tomtom)
		assert.matches("TomTom.AddWaypoint", ns.Modules.why.tomtom, 1, true)
		assert.is_nil(wow.world.settings.settings.BRAINDEADFOREVER_TOMTOM)
		ns.Route.Check()
		wow.advance(2)
		assert.are.same({}, wow.errors)
	end)
end)
