-- SPDX-License-Identifier: GPL-3.0-or-later
-- Compiled route data (Braindead4Ever/Routes/Data_*.lua) and the composer (Routes/Routes.lua):
-- a route for every one of the 56 race and class combinations, in both modes, and a run
-- through the Elwynn Forest start route with quest-log bookkeeping.
local wow = require("spec.helpers.wow")

local FILES = {
	"Braindead4Ever/Routes/Routes.lua",
	"Braindead4Ever/Routes/Data_Alliance.lua",
	"Braindead4Ever/Routes/Data_Horde.lua",
}

-- 56 combinations from the client table CharBaseInfo (wowf 1.60.1.70707), brain chapter 14 §1.
-- Kept here on purpose, independent of the route data under test.
local COMBOS = {
	Alliance = {
		[1] = { 1, 2, 3, 4, 5, 8, 9 }, -- Human
		[3] = { 1, 2, 3, 4, 5, 7 }, -- Dwarf
		[7] = { 1, 4, 5, 8, 9 }, -- Gnome
		[4] = { 1, 3, 4, 5, 11 }, -- Night Elf
		[95] = { 1, 3, 4, 8, 11 }, -- Skyborne (High Order)
	},
	Horde = {
		[2] = { 1, 3, 4, 7, 8, 9 }, -- Orc
		[5] = { 1, 2, 4, 5, 8, 9 }, -- Undead
		[8] = { 1, 3, 4, 5, 7, 8, 9 }, -- Troll
		[6] = { 1, 3, 7, 11 }, -- Tauren
		[96] = { 1, 3, 4, 7, 11 }, -- Skyborne (Windshaper)
	},
}
-- Start zone (uiMapID) of the first step with a position, per race.
local START_MAP = {
	[1] = 1429,
	[3] = 1426,
	[7] = 1426,
	[4] = 1438,
	[95] = 2521,
	[2] = 1411,
	[8] = 1411,
	[6] = 1412,
	[5] = 1420,
	[96] = 2521,
}
local ZEPHRAS = { [2521] = true, [2665] = true }

local function load()
	wow.reset({})
	return wow.loadFiles(FILES, "Braindead4Ever", {})
end

-- Elements with their own filter count only for their races and classes, as in Routes/Runtime.lua.
local function mine(R, el, race, class)
	return not (el.r or el.c) or R.Applies(el, race, class)
end

local function eachCombo(fn)
	for faction, races in pairs(COMBOS) do
		for race, classes in pairs(races) do
			for _, class in ipairs(classes) do
				fn(faction, race, class)
			end
		end
	end
end

describe("Route data", function()
	local ns = load()
	local R = ns.Routes
	local V = R.VERB

	it("covers 56 combinations", function()
		local n = 0
		eachCombo(function()
			n = n + 1
		end)
		assert.are.equal(56, n)
	end)

	for _, mode in ipairs({ "speed", "explorer" }) do
		it("gives every combination a route that starts in its start zone (" .. mode .. ")", function()
			eachCombo(function(faction, race, class)
				local steps = R.Steps(faction, mode, race, class)
				local label = ("%s %s %d/%d"):format(mode, faction, race, class)
				assert.is_table(steps, label)
				assert.is_true(#steps > 50, label .. " has only " .. #steps .. " steps")
				local first
				for _, s in ipairs(steps) do
					for _, el in ipairs(s.step) do
						if el[1] == V.GOTO then
							first = el[2]
							break
						end
					end
					if first then
						break
					end
				end
				if ZEPHRAS[START_MAP[race]] then
					assert.is_true(ZEPHRAS[first] == true, label .. " starts on " .. tostring(first))
				else
					assert.are.equal(START_MAP[race], first, label)
				end
			end)
		end)
	end

	it("keeps loaded data after releasing the builders", function()
		local fresh = load()
		local data = fresh.Routes.Load("Alliance")
		fresh.Routes.Release()
		assert.is_nil(fresh.RouteData.Horde)
		assert.are.equal(data, fresh.Routes.Load("Alliance"))
		assert.is_nil(fresh.Routes.Load("Horde"))
	end)

	it("gives no route to a combination of the other faction", function()
		assert.is_nil(R.Steps("Alliance", "speed", 2, 1))
		assert.is_nil(R.Steps("Horde", "speed", 1, 1))
	end)

	it("marks every element with sources and the status unconfirmed", function()
		for _, faction in ipairs({ "Alliance", "Horde" }) do
			local data = R.Load(faction)
			assert.are.equal(1, data.format)
			for key, m in pairs(data.modules) do
				assert.are.equal("vorläufig", m.label, key)
				for _, step in ipairs(m.steps) do
					for _, el in ipairs(step) do
						local n = #el
						local src, status = el[n - 1], el[n]
						if el[1] == V.GOTO then
							src, status = el[n - 2], el[n - 1]
						end
						assert.is_true(src > 0, key .. " " .. step.id)
						assert.are.equal(R.STATUS.UNCONFIRMED, status, key .. " " .. step.id)
					end
				end
			end
		end
	end)

	it("runs through every route: accept before turn-in, each quest once", function()
		for _, mode in ipairs({ "speed", "explorer" }) do
			eachCombo(function(faction, race, class)
				local accepted, turned = {}, {}
				for _, s in ipairs(R.Steps(faction, mode, race, class)) do
					for _, el in ipairs(s.step) do
						local v, q = el[1], el[2]
						if not mine(R, el, race, class) then
							v = nil -- an element with its own filter for other races or classes (as Runtime.lua)
						end
						if v == V.ACCEPT then
							assert.is_nil(accepted[q], ("%s accepted twice in %s"):format(q, s.module))
							accepted[q] = true
						elseif v == V.COMPLETE or v == V.TURNIN then
							assert.is_true(
								accepted[q] == true,
								("%s not accepted before %s (%s %s %s/%s)"):format(
									q,
									s.step.id,
									mode,
									faction,
									race,
									class
								)
							)
							if v == V.TURNIN then
								assert.is_nil(turned[q])
								turned[q] = true
							end
						end
					end
				end
			end)
		end
	end)
end)

describe("Example route Elwynn Forest", function()
	local ns = load()
	local R = ns.Routes
	local V = R.VERB

	it("runs through for a human warrior from level 1 to 10", function()
		local steps = R.Steps("Alliance", "speed", 1, 1)
		local log, done, first, last = {}, {}, nil, nil
		local inElwynn = 0
		for _, s in ipairs(steps) do
			if s.module ~= "a-speed-start-elwynn" then
				break
			end
			first = first or s.step.lv
			last = s.step.lv
			assert.is_true(s.step.lv >= (first or 1), s.step.id)
			for _, el in ipairs(s.step) do
				if not mine(R, el, 1, 1) then
					el = { 0 } -- an element for other classes (as Runtime.lua)
				end
				if el[1] == V.ACCEPT then
					log[el[2]] = true
				elseif el[1] == V.TURNIN then
					assert.is_true(log[el[2]], s.step.id)
					log[el[2]] = nil
					done[#done + 1] = el[2]
				elseif el[1] == V.GOTO then
					-- since the quest data of 2026-11-11 one turn-in (t61) is in Stormwind, with walk steps
					if el[2] ~= 1453 then
						assert.are.equal(1429, el[2], s.step.id)
						inElwynn = inElwynn + 1
					end
				end
			end
		end
		assert.are.equal(1, first)
		assert.is_true(last >= 8, "ends at planned level " .. tostring(last))
		assert.is_true(#done >= 20, "only " .. #done .. " quests handed in")
		assert.is_true(inElwynn >= 40)
		assert.is_nil(next(log), "quests left in the log at the end of Elwynn")
	end)
end)
