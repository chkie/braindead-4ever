-- SPDX-License-Identifier: GPL-3.0-or-later
-- NPC names in the steps (M4, UI/NpcNames.lua): accept and turn-in steps name the quest giver and the
-- turn-in NPC in the client's language. The NPC IDs come from the facts (Routes/Data_Npcs.lua, IDs
-- only), the names from the client's creature cache (tooltip data of a unit link) or from the player
-- meeting the NPC. Without a name the step reads as before. A name learned in another language never
-- shows: the counter-check reads every language and the German client shows the English name, so the
-- test sees the fault it guards against.
-- The NPC names below are test values of the stand-in client, not the game's names.
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

-- Elwynn start of the human warrior (Data_Npcs.lua from data/facts): the route starts with quest 783,
-- given by NPC 823 and taken by 197, which also gives quest 7.
local GIVER_783, TURNIN_783 = 823, 197

local function current(ns)
	return ns.StepFrame.frame.step:GetText()
end

-- Text of the upcoming step with this key part (route keys are "<module>/<step id>").
local function upcoming(ns, id)
	for _, info in ipairs(ns.Route.Upcoming(5)) do
		if info.id == id then
			return (ns.StepText.Step(info, false))
		end
	end
end

local function read(path)
	local fh = assert(io.open(path, "rb"))
	local text = fh:read("*a")
	fh:close()
	return text
end

-- Lines of a compiled data file that hold a string literal outside the header comments: a name in the
-- data would show here (the file must carry NPC IDs only).
local function stringsInData(text)
	local found = {}
	for line in text:gmatch("[^\n]+") do
		if not line:find("^%s*%-%-") and not line:find("^local _, ns = %.%.%.$") and line:find("[\"']") then
			found[#found + 1] = line
		end
	end
	return found
end

describe("NPC names in the steps (M4)", function()
	it("names the quest giver the client knows, in English", function()
		local ns = S.login({
			before = function(W)
				W.creatures[GIVER_783] = "Deputy Willem"
			end,
		})
		assert.are.equal("on", ns.Modules.state.npcnames)
		assert.are.equal("Accept “A Threat Within” from Deputy Willem", current(ns))
	end)

	it("German client: the German name in the German word order", function()
		local ns = S.login({
			locale = "deDE",
			before = function(W)
				W.creatures[GIVER_783] = "Hilfssheriff Willem"
			end,
		})
		assert.are.equal("„Eine Bedrohung von innen“ bei Hilfssheriff Willem annehmen", current(ns))
	end)

	it("names the turn-in NPC, and an NPC that also gives the next quest only once", function()
		local ns = S.login({
			before = function(W)
				W.creatures[TURNIN_783] = "Marshal McBride"
			end,
		})
		assert.are.equal(
			"Turn in “A Threat Within” to Marshal McBride, Accept “Kobold Camp Cleanup”",
			upcoming(ns, "t783")
		)
	end)

	it("without a name the step reads as before", function()
		local named = S.login()
		local plain = current(named)
		assert.are.equal("Accept “A Threat Within”", plain)
		-- the same session without the module (no tooltip API): the same text
		local off = S.login({
			before = function()
				_G.C_TooltipInfo = nil
			end,
		})
		assert.are.equal("off", off.Modules.state.npcnames)
		assert.are.equal(plain, current(off))
		assert.are.equal("Turn in “A Threat Within”, Accept “Kobold Camp Cleanup”", upcoming(off, "t783"))
		assert.are.equal(upcoming(off, "t783"), upcoming(named, "t783"))
		assert.are.same({}, wow.errors)
	end)

	it("learns the name at the quest dialog, keeps it for the client's language and shows it later", function()
		local ns = S.login({ locale = "deDE" })
		assert.are.equal("„Eine Bedrohung von innen“ annehmen", current(ns))
		wow.world.npc = { guid = "Creature-0-1-0-1-823-0000ABCDEF", name = "Hilfssheriff Willem" }
		wow.fire("QUEST_DETAIL")
		wow.advance(1) -- the window redraws once
		assert.are.equal("„Eine Bedrohung von innen“ bei Hilfssheriff Willem annehmen", current(ns))
		local saved = _G.BraindeadForeverDB
		assert.are.equal("Hilfssheriff Willem", saved.npcNames.deDE[GIVER_783])
		assert.is_nil(saved.npcNames.enUS)
		-- next session: the client's cache is empty, the learned name stays
		local again = S.login({ locale = "deDE", saved = saved })
		assert.are.equal("„Eine Bedrohung von innen“ bei Hilfssheriff Willem annehmen", current(again))
	end)

	it("learns only givers and turn-ins of the route's faction, never from a player or a secret", function()
		local ns = S.login()
		local N = ns.NpcNames
		wow.world.units.target = { guid = "Creature-0-1-0-1-299-0000ABCDEF", name = "Young Wolf" }
		assert.is_false(N.Learn("target")) -- NPC 299 gives and takes no quest
		wow.world.units.target = { guid = "Player-1234-0ABCDEF1", name = "Anna" }
		assert.is_false(N.Learn("target"))
		wow.world.units.target = { guid = wow.SECRET, name = wow.SECRET }
		assert.is_false(N.Learn("target"))
		wow.world.units.target = { guid = "Creature-0-1-0-1-196-0000ABCDEF", name = wow.SECRET }
		assert.is_false(N.Learn("target"))
		assert.is_nil(next(_G.BraindeadForeverDB.npcNames.enUS, "n"))
		assert.are.same({}, wow.errors)
	end)

	it("asks the client only on a new step or an event, never per frame", function()
		local ns = S.login()
		local asked = wow.world.tooltipQueries
		assert.is_true(asked > 0) -- the first draw asked for the NPCs of the visible steps
		local W = ns.StepFrame.frame
		for _ = 1, 600 do -- ten seconds of frames
			W.scripts.OnUpdate(W, 1 / 60)
		end
		for _ = 1, 5 do
			wow.fire("QUEST_LOG_UPDATE")
			wow.advance(0.5)
		end
		assert.are.equal(asked, wow.world.tooltipQueries) -- an unknown NPC waits for the next step
		wow.world.creatures[GIVER_783] = "Deputy Willem" -- the player saw him meanwhile
		ns.Connect.Check()
		wow.advance(1)
		ns.Connect.Back() -- the step comes back: asked again, now with a name
		wow.advance(1)
		assert.is_true(wow.world.tooltipQueries > asked)
		assert.are.equal("Accept “A Threat Within” from Deputy Willem", current(ns))
	end)

	it("never shows a name learned in another language", function()
		local ns = S.login({
			locale = "deDE",
			saved = { npcNames = { enUS = { n = 1, [GIVER_783] = "Deputy Willem" } } },
		})
		assert.are.equal("„Eine Bedrohung von innen“ annehmen", current(ns))
	end)

	it("counter-check: reading the names of every language shows the English name in the German client", function()
		local ns = S.login({
			locale = "deDE",
			saved = { npcNames = { enUS = { n = 1, [GIVER_783] = "Deputy Willem" } } },
			loaded = function(ns)
				ns.NpcNames.Saved = function() -- the fault: the language of the client is not checked
					return ns.db.npcNames.enUS
				end
			end,
		})
		assert.are.equal("„Eine Bedrohung von innen“ bei Deputy Willem annehmen", current(ns))
	end)

	it("the compiled data holds NPC IDs only, no names", function()
		local text = read("Braindead4Ever/Routes/Data_Npcs.lua")
		assert.are.same({}, stringsInData(text))
		local ns = {}
		wow.loadFile("Braindead4Ever/Routes/Data_Npcs.lua", "Braindead4Ever", ns)
		for _, faction in ipairs({ "Alliance", "Horde" }) do
			local n = 0
			for q, f in pairs(ns.NpcFacts[faction]()) do
				n = n + 1
				assert.is_number(q)
				assert.are.equal(5, #f)
				for i = 1, 5 do
					assert.is_number(f[i])
				end
			end
			assert.is_true(n > 500, faction)
		end
		assert.are.same({ 196, 3, 196, 1, 0 }, ns.NpcFacts.Alliance()[33]) -- giver and turn-in with sources
	end)

	it("counter-check: a name in the data is found", function()
		local text = read("Braindead4Ever/Routes/Data_Npcs.lua")
		local bad = text:gsub("%[33%] = { 196,", '[33] = { 196, "Eagan Peltskinner",', 1)
		assert.are.equal(1, #stringsInData(bad))
	end)
end)
