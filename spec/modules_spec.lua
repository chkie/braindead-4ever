-- SPDX-License-Identifier: GPL-3.0-or-later
-- Core/Modules.lua: requirements, API probe, flags, safe mode, event dispatch.
local wow = require("spec.helpers.wow")

local function setup(opts, files)
	wow.reset(opts)
	local ns = wow.loadFiles(files or {
		"Braindead4Ever/Locales/enUS.lua",
		"Braindead4Ever/Core/Guard.lua",
		"Braindead4Ever/Core/Modules.lua",
	})
	ns.db = { flags = {}, safeMode = false }
	return ns
end

describe("Modules", function()
	it("turns a module off when a required function is missing", function()
		local ns = setup({ flavor = "retail" })
		ns.Modules.Define("questcolor", { requires = { funcs = { "C_QuestLog.GetTrivialRange" } } })
		ns.Modules.Boot(ns.db)
		assert.are.equal("off", ns.Modules.state.questcolor)
		assert.are.equal("missing C_QuestLog.GetTrivialRange", ns.Modules.why.questcolor)
	end)

	it("runs the same module in Forever, where the function exists", function()
		local ns = setup({ flavor = "forever" })
		local range
		ns.Modules.Define("questcolor", {
			requires = { funcs = { "C_QuestLog.GetTrivialRange" } },
			init = function()
				range = ns.Modules.Resolve("C_QuestLog.GetTrivialRange")()
			end,
		})
		ns.Modules.Boot(ns.db)
		assert.are.equal("on", ns.Modules.state.questcolor)
		assert.are.equal(5, range)
	end)

	it("does not accept an empty namespace as the function", function()
		local ns = setup({ flavor = "retail" })
		assert.is_table(_G.C_SkillInfo)
		ns.Modules.Define("skills", { requires = { funcs = { "C_SkillInfo.AbandonSkill" } } })
		ns.Modules.Boot(ns.db)
		assert.are.equal("off", ns.Modules.state.skills)
	end)

	it("uses a developer stand-in from ns.shim when the real function is missing", function()
		local ns = setup({ flavor = "retail" })
		ns.shim = {
			["C_QuestLog.GetTrivialRange"] = function()
				return 7
			end,
		}
		local fn, source = ns.Modules.Resolve("C_QuestLog.GetTrivialRange")
		assert.are.equal(7, fn())
		assert.are.equal("shim", source)
		assert.is_nil(rawget(_G.C_QuestLog, "GetTrivialRange"))
	end)

	it("turns a module off when a required event is unknown", function()
		local ns = setup({ flavor = "retail" })
		ns.Modules.Define("rules", { requires = { events = { "GAME_RULES_CHANGED" } } })
		ns.Modules.Boot(ns.db)
		assert.are.equal("off", ns.Modules.state.rules)
		assert.are.equal("missing event GAME_RULES_CHANGED", ns.Modules.why.rules)
	end)

	it("respects flags and the safe mode", function()
		local ns = setup()
		ns.Modules.Define("collector", { core = true })
		ns.Modules.Define("arrow", {})
		ns.Modules.Define("hints", {})
		ns.db.flags.hints = false
		ns.db.safeMode = true
		ns.Modules.Boot(ns.db)
		assert.are.equal("on", ns.Modules.state.collector)
		assert.are.equal("off", ns.Modules.state.arrow)
		assert.are.equal("safe mode", ns.Modules.why.arrow)
		assert.are.equal("off", ns.Modules.state.hints)
		assert.are.equal("turned off", ns.Modules.why.hints)
	end)

	it("marks a module as error when its init throws, and keeps the others running", function()
		local ns = setup()
		ns.Modules.Define("broken", {
			init = function()
				error("init failed", 0)
			end,
		})
		ns.Modules.Define("fine", {})
		ns.Modules.Boot(ns.db)
		assert.are.equal("error", ns.Modules.state.broken)
		assert.are.equal("on", ns.Modules.state.fine)
		assert.are.same({ "Braindead 4ever [broken] init failed" }, wow.errors)
	end)

	it("dispatches events to every active module and registers each event once", function()
		local ns = setup()
		local seen = {}
		ns.Modules.Define("a", {
			events = {
				QUEST_ACCEPTED = function(_, event, questID)
					seen[#seen + 1] = "a:" .. event .. ":" .. questID
				end,
			},
		})
		ns.Modules.Define("b", {
			events = {
				QUEST_ACCEPTED = function(_, _, questID)
					seen[#seen + 1] = "b:" .. questID
				end,
			},
		})
		ns.Modules.Boot(ns.db)
		wow.fire("QUEST_ACCEPTED", 33)
		assert.are.same({ "a:QUEST_ACCEPTED:33", "b:33" }, seen)
		assert.is_true(ns.Modules.frame.events.QUEST_ACCEPTED)
	end)

	it("never registers an unknown event with the frame", function()
		local ns = setup({ flavor = "retail" })
		ns.Modules.Define("rules", { events = { GAME_RULES_CHANGED = function() end } })
		assert.has_no.errors(function()
			ns.Modules.Boot(ns.db)
		end)
		assert.is_nil(ns.Modules.frame.events.GAME_RULES_CHANGED)
	end)

	it("lets stand-in events through the dispatcher", function()
		local ns = setup({ flavor = "retail" })
		ns.shimEvents = { GAME_RULES_CHANGED = true }
		local count = 0
		ns.Modules.Define("rules", {
			events = {
				GAME_RULES_CHANGED = function()
					count = count + 1
				end,
			},
		})
		ns.Modules.Boot(ns.db)
		ns.Modules.Dispatch("GAME_RULES_CHANGED")
		assert.are.equal(1, count)
	end)

	it("calls the disable hook once when a module is turned off", function()
		local ns = setup()
		local stopped = 0
		ns.Modules.Define("arrow", {
			disable = function()
				stopped = stopped + 1
			end,
		})
		ns.Modules.Boot(ns.db)
		ns.Modules.Disable("arrow", "test")
		ns.Modules.Disable("arrow", "test")
		assert.are.equal(1, stopped)
		assert.are.equal("disabled", ns.Modules.state.arrow)
	end)

	it("reports states in the client language", function()
		local ns = setup({ locale = "deDE" }, {
			"Braindead4Ever/Locales/enUS.lua",
			"Braindead4Ever/Locales/deDE.lua",
			"Braindead4Ever/Core/Guard.lua",
			"Braindead4Ever/Core/Modules.lua",
		})
		ns.Modules.Define("collector", { core = true })
		ns.Modules.Define("arrow", {})
		ns.db.safeMode = true
		ns.Modules.Boot(ns.db)
		local report = ns.Modules.Report()
		assert.matches("build=70532 toc=16001 project=18", report, 1, true)
		assert.matches("collector%s+an", report)
		assert.matches("arrow%s+aus%s+sicherer Modus", report)
	end)
end)
