-- SPDX-License-Identifier: GPL-3.0-or-later
-- Hints on the way and flights in the route runtime: `train` is done when the trainer window opened,
-- `hs` when the hearthstone was cast, `fp` when the flight point was learned or the flight map opened,
-- `travel fly` at the landing (docs/ROUTE-RUNTIME.md §Rules). Part 1 runs Routes/Runtime.lua with a
-- made-up route; part 2 fires the client events at the module "route" and records what it marks.
local wow = require("spec.helpers.wow")

-- Element codes (docs/ROUTE-FORMAT.md): 1 accept, 5 goto, 6 travel (how 1 walk, 2 fly, 8 hearth),
-- 7 hs, 8 sethome, 9 fp, 10 train.
local function go(map)
	return { 5, map, 0, 0, 10, 16, 0, 1 }
end
local function plan(code)
	return { code, 16, 0 }
end
local function travel(how, map)
	return { 6, how, map, 16, 0 }
end
local function step(id, ...)
	return { module = "m-hint", step = { id = id, lv = 5, ... } }
end

local A, Z = 900001, 900002

local function route()
	return {
		step("aA", { 1, A, 1, 0 }, go(1429)),
		step("train", go(1429), plan(10)),
		step("fm", go(1429), plan(9)),
		step("fly", travel(2, 1429), go(1429)), -- a flight inside the zone
		step("bind", go(1429), plan(8)),
		step("hs", plan(7)),
		step("fly2", travel(2, 1436), go(1436)), -- a flight into another zone
		step("walk", travel(1, 1433), go(1433)),
		step("aZ", { 1, Z, 1, 0 }, go(1433)),
	}
end

local function newRuntime()
	wow.reset({})
	local ns = wow.loadFiles({
		"Braindead4Ever/Routes/Routes.lua",
		"Braindead4Ever/Routes/XP.lua",
		"Braindead4Ever/Routes/Runtime.lua",
	})
	local w = { log = {}, map = 1429, level = 5 }
	local world = {
		IsFlagged = function()
			return false
		end,
		InLog = function(q)
			return w.log[q] == true
		end,
		IsComplete = function()
			return false
		end,
		Level = function()
			return w.level
		end,
		Map = function()
			return w.map
		end,
		XP = function()
			return 0, 400, nil
		end,
		MapParent = function()
			return nil
		end,
	}
	local rt = ns.Runtime.New(route(), { [A] = { 1, 100 }, [Z] = { 5, 100 } }, world, {}, {})
	rt:Evaluate()
	return rt, w, ns.Routes.VERB
end

local function id(rt)
	local c = rt:Current()
	return c and c.id
end

describe("hint steps in the runtime", function()
	it("a trainer step is done when the trainer window opened, without a manual check", function()
		local rt, w, V = newRuntime()
		w.log[A] = true
		rt:Evaluate()
		assert.are.equal("train", id(rt))
		rt:Evaluate()
		assert.are.equal("train", id(rt), "standing at the trainer is not enough")
		assert.is_true(rt:MarkEvent(V.TRAIN))
		assert.are.equal("fm", id(rt))
	end)

	it("a flight point step is done by the flight point event", function()
		local rt, w, V = newRuntime()
		w.log[A] = true
		rt:MarkEvent(V.TRAIN)
		assert.are.equal("fm", id(rt))
		assert.is_true(rt:MarkEvent(V.FP))
		assert.are.equal("fly", id(rt))
	end)

	it("a flight inside the zone waits for the landing; a walk is not marked by it", function()
		local rt, w, V = newRuntime()
		w.log[A] = true
		rt:MarkEvent(V.TRAIN)
		rt:MarkEvent(V.FP)
		assert.are.equal("fly", id(rt))
		rt:Evaluate()
		assert.are.equal("fly", id(rt), "the player is in the target zone before the flight already")
		assert.is_true(rt:MarkEvent(V.TRAVEL, 2))
		assert.are.equal("bind", id(rt))
		rt:MarkEvent(V.SETHOME)
		rt:MarkEvent(V.HS)
		assert.are.equal("fly2", id(rt))
		-- the walk three steps ahead is not a flight: a second landing marks only fly2
		assert.is_true(rt:MarkEvent(V.TRAVEL, 2))
		assert.are.equal("walk", id(rt))
		assert.is_false(rt:MarkEvent(V.TRAVEL, 2))
		assert.are.equal("walk", id(rt))
	end)

	it("a flight into another zone is also done when the player is there (landing missed by a reload)", function()
		local rt, w, V = newRuntime()
		w.log[A] = true
		for _, v in ipairs({ V.TRAIN, V.FP }) do
			rt:MarkEvent(v)
		end
		rt:MarkEvent(V.TRAVEL, 2)
		rt:MarkEvent(V.SETHOME)
		rt:MarkEvent(V.HS)
		assert.are.equal("fly2", id(rt))
		w.map = 1436
		rt:Evaluate()
		assert.are.equal("walk", id(rt))
	end)

	it("the hearthstone step is done by the cast, the bind step by the binding", function()
		local rt, w, V = newRuntime()
		w.log[A] = true
		rt:MarkEvent(V.TRAIN)
		rt:MarkEvent(V.FP)
		rt:MarkEvent(V.TRAVEL, 2)
		assert.are.equal("bind", id(rt))
		assert.is_false(rt:MarkEvent(V.TRAIN), "no trainer step within reach")
		assert.is_true(rt:MarkEvent(V.SETHOME))
		assert.are.equal("hs", id(rt))
		assert.is_true(rt:MarkEvent(V.HS))
		assert.are.equal("fly2", id(rt))
	end)
end)

-- Part 2: client events -> marks. The real route data has no hint steps yet, so the runtime's
-- MarkEvent is replaced by a recorder after the login.
local function session(opts)
	opts = opts or {}
	wow.reset({})
	local P = wow.world.player
	P.faction = { "Alliance", "" }
	P.race = { "-", "-", 1 }
	P.class = { "-", "-", 1 }
	P.level = 5
	_G.C_Trainer = { GetTrainerType = opts.trainerType and function()
		return opts.trainerType
	end or nil }
	local ns = wow.loadFiles(wow.addonFiles())
	wow.fire("ADDON_LOADED", "Braindead4Ever")
	wow.fire("PLAYER_LOGIN")
	wow.fire("PLAYER_ENTERING_WORLD", true, false)
	local rt = ns.Route.Runtime()
	local marks = {}
	rt.MarkEvent = function(_, verb, how)
		marks[#marks + 1] = how and (verb .. "/" .. how) or tostring(verb)
		return true
	end
	return ns, marks
end

describe("hint events of the module route", function()
	after_each(function()
		_G.C_Trainer = nil
	end)

	it("the class trainer window marks the trainer step, a profession or pet trainer does not", function()
		local _, marks = session({ trainerType = 0 })
		wow.fire("TRAINER_SHOW")
		assert.are.same({ "10" }, marks)
		for _, kind in ipairs({ 2, 3 }) do
			local _, m = session({ trainerType = kind })
			wow.fire("TRAINER_SHOW")
			assert.are.same({}, m, "trainer type " .. kind)
		end
		local _, m = session({}) -- client without C_Trainer.GetTrainerType: every trainer window counts
		wow.fire("TRAINER_SHOW")
		assert.are.same({ "10" }, m)
	end)

	it("only the player's own hearthstone cast marks the hearthstone step", function()
		local _, marks = session()
		wow.fire("UNIT_SPELLCAST_SUCCEEDED", "target", "Cast-1", 8690)
		wow.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 133)
		wow.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", wow.SECRET)
		assert.are.same({}, marks)
		wow.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-4", 8690)
		assert.are.same({ "7" }, marks)
	end)

	it("the flight map and the new flight path mark the flight point step, the binding the bind step", function()
		local _, marks = session()
		wow.fire("TAXIMAP_OPENED", 0)
		wow.fire("UI_INFO_MESSAGE", 0, _G.ERR_NEWTAXIPATH)
		wow.fire("HEARTHSTONE_BOUND")
		assert.are.same({ "9", "9", "8" }, marks)
	end)

	it("the landing after a flight marks the flight step; control back without a flight does not", function()
		local _, marks = session()
		wow.world.onTaxi = false
		wow.fire("PLAYER_CONTROL_LOST")
		wow.advance(1.5)
		wow.fire("PLAYER_CONTROL_GAINED")
		assert.are.same({}, marks, "stunned or in a cut scene, no taxi")
		wow.world.onTaxi = true
		wow.fire("PLAYER_CONTROL_LOST")
		wow.advance(1.5)
		wow.world.onTaxi = false
		wow.fire("PLAYER_CONTROL_GAINED")
		assert.are.same({ "6/2" }, marks)
	end)
end)

describe("hint steps on the map (A35)", function()
	local S = require("spec.helpers.uisession")

	it("marks trainer, innkeeper and flight master of the next steps with Blizzard's tracking symbols", function()
		local ns = S.login()
		local C, P, T = ns.Connect, ns.MapPins, ns.Theme
		local function info(key, ...)
			return { key = "m-hint/" .. key, step = { id = key, ... } }
		end
		local cur = info("train", { 5, 1429, -9465, 60, 10, 16, 0, 1 }, plan(10))
		local nexts = {
			info("bind", { 5, 1429, -9460, 100, 10, 16, 0, 1 }, plan(8)),
			info("fm", { 5, 1429, -9400, 120, 10, 16, 0, 1 }, plan(9)),
		}
		C.Current = function()
			return cur
		end
		C.Upcoming = function()
			return nexts
		end
		P.Collect()
		local kinds = {}
		for _, p in ipairs(P.Points()) do
			kinds[#kinds + 1] = p.kind
		end
		assert.are.same({ "pin", "trainer", "innkeeper", "flightmaster" }, kinds)
		assert.are.equal("Class", T.ATLAS.trainer)
		assert.are.equal("Innkeeper", T.ATLAS.innkeeper)
		assert.are.equal("FlightMaster", T.ATLAS.flightmaster)
	end)
end)
