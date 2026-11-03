-- SPDX-License-Identifier: GPL-3.0-or-later
-- Hardcore-safe mode (Welle 9, M3; requirement A18): a mode with three settings (on Hardcore realms,
-- always, never). It warns only from data that exists: the quest level of the route data against the
-- character's level (chosen gap Routes/Hardcore.lua GAP) and the client's elite mark. It leaves the
-- optional dungeon step out. No invented danger values.
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

local function shown(region)
	return rawget(region, "shown") == true
end

-- Sets the level of quest q in the route data the runtime uses and refreshes the window.
local function questLevel(ns, q, level)
	ns.Route.Runtime().quests[q][1] = level
	ns.StepFrame.Refresh()
end

local function warn(ns)
	local W = ns.StepFrame.frame
	return shown(W.warn) and W.warn.text or nil
end

describe("Hardcore-safe mode", function()
	describe("rule", function()
		local H = wow.loadFiles({ "Pathmark/Routes/Hardcore.lua" }).Hardcore
		local V = { ACCEPT = 1, COMPLETE = 2, TURNIN = 3 }

		it("counts the quests a step sends the player to, not the turn-in", function()
			assert.are.same({ 5, 6 }, H.Quests({ { 1, 5 }, { 2, 5 }, { 2, 6 }, { 3, 7 }, { 5, 1429, 0, 0 } }, V))
			assert.are.same({}, H.Quests({ { 3, 7 } }, V))
		end)

		it("warns from GAP + 1 levels above, never for an unknown level, elite first", function()
			assert.are.equal(2, H.GAP)
			local facts = { [1] = { 12 }, [2] = { 13 }, [3] = { 0 }, [4] = { 30 } }
			assert.is_nil(H.Check({ 1 }, facts, 10))
			assert.are.same({ quest = 2, gap = 3, level = 13 }, H.Check({ 1, 2 }, facts, 10))
			assert.is_nil(H.Check({ 3 }, facts, 1), "level 0 = unknown")
			assert.are.same({ quest = 4, gap = 20, level = 30 }, H.Check({ 2, 4 }, facts, 10))
			local elite = function(q)
				return q == 1
			end
			assert.are.same({ quest = 1, elite = true }, H.Check({ 2, 1 }, facts, 10, elite))
		end)
	end)

	it("the routes hold no quest Polestar types as elite or group, dungeon, raid or PvP", function()
		local json = require("spec.helpers.json")
		local EXCLUDED = { [1] = "elite or group", [41] = "PvP", [62] = "raid", [81] = "dungeon" }
		local types = {}
		for line in io.lines("data/facts/quests.jsonl") do
			local r = json.decode(line)
			types[r.q] = r.type
		end
		local n = 0
		for _, faction in ipairs({ "Alliance", "Horde" }) do
			local data = {}
			assert(loadfile("Pathmark/Routes/Data_" .. faction .. ".lua"))("Pathmark", data)
			for q in pairs(data.RouteData[faction]().quests) do
				n = n + 1
				assert.is_nil(
					EXCLUDED[types[q]],
					("quest %d (%s) in the %s routes"):format(q, tostring(EXCLUDED[types[q]]), faction)
				)
			end
		end
		assert.is_true(n > 900, "route quests checked: " .. n)
	end)

	describe("step window", function()
		it("is off on a normal realm by default and on with “Always”", function()
			local ns = S.login()
			assert.are.equal("auto", ns.UI.Get("hardcore"))
			assert.is_false(ns.Connect.Hardcore())
			questLevel(ns, 33, 9)
			assert.is_nil(warn(ns))
			ns.UI.Set("hardcore", "on")
			assert.are.equal("Careful: quest 8 levels above you", warn(ns))
		end)

		it("warns from three levels above the character, not at two", function()
			local ns = S.login({ saved = { ui = { hardcore = "on" } } })
			questLevel(ns, 33, 3)
			assert.is_nil(warn(ns))
			questLevel(ns, 33, 4)
			assert.are.equal("Careful: quest 3 levels above you", warn(ns))
			wow.world.player.level = 2
			ns.StepFrame.Refresh()
			assert.is_nil(warn(ns), "the warning follows the character's level")
		end)

		it("follows the rules of a Hardcore realm with “On Hardcore realms”, and “Never” wins", function()
			local ns = S.login({
				before = function()
					_G.C_GameRules.IsHardcoreActive = function()
						return true
					end
				end,
			})
			assert.is_true(ns.Connect.Hardcore())
			questLevel(ns, 33, 9)
			assert.is_truthy(warn(ns))
			ns.UI.Set("hardcore", "off")
			assert.is_nil(warn(ns))
		end)

		it("names an elite quest the client marks", function()
			local ns = S.login({
				saved = { ui = { hardcore = "on" } },
				before = function()
					_G.C_QuestLog.IsEliteQuest = function(q)
						return q == 33
					end
				end,
			})
			assert.are.equal("Careful: elite quest", warn(ns))
		end)

		it("stays in the mini view and speaks German", function()
			local ns = S.login({ locale = "deDE", saved = { ui = { hardcore = "on" } } })
			questLevel(ns, 33, 6)
			ns.StepFrame.SetMini(true)
			assert.are.equal("Vorsicht: Quest 5 Stufen über dir", warn(ns))
			assert.is_nil(warn(ns):find("\226\128\148"), "no em dash")
		end)

		it("leaves the optional dungeon step out", function()
			local ns = S.login()
			local first = ns.Route.Upcoming(1)[1].index
			ns.Route.DungeonHint = function()
				return {
					{ id = 63, area = 1581, lo = 18, hi = 24, first = first, quests = { { q = 7, state = "take" } } },
				}
			end
			ns.StepFrame.Invalidate()
			ns.StepFrame.Refresh()
			local W = ns.StepFrame.frame
			assert.is_true(shown(W.next[2].tag))
			ns.UI.Set("hardcore", "on")
			assert.is_nil(ns.Connect.Dungeon())
			assert.is_false(shown(W.next[2].tag))
			assert.is_false(shown(W.next[1].tag))
		end)

		it("has its setting on the Play style page with three values", function()
			local ns = S.login({ locale = "deDE" })
			local s = wow.world.settings.settings.PATHMARK_HARDCORE
			assert.are.equal("Hardcore-sicher", s.name)
			assert.are.equal("auto", s:GetValue())
			assert.are.same({ "auto", "on", "off" }, ns.Connect.HARDCORE)
		end)
	end)
end)
