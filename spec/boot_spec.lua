-- SPDX-License-Identifier: GPL-3.0-or-later
-- Core/Boot.lua: SavedVariables defaults, start guard, safe mode, slash command.
local wow = require("spec.helpers.wow")

local FILES = {
	"Pathmark/Locales/enUS.lua",
	"Pathmark/Core/Guard.lua",
	"Pathmark/Core/Modules.lua",
	"Pathmark/Core/Boot.lua",
}

-- One game session: fresh client with the SavedVariables of the last session.
-- clean = true lets the session reach the "started cleanly" timer.
local function session(opts)
	opts = opts or {}
	wow.reset({ saved = opts.saved, version = opts.version })
	local ns = wow.loadFiles(FILES)
	wow.fire("ADDON_LOADED", "Pathmark")
	if opts.clean then
		wow.fire("PLAYER_ENTERING_WORLD", true, false)
		wow.advance(10)
	end
	return ns
end

describe("Boot", function()
	it("creates PathmarkDB with defaults on the first start", function()
		local ns = session()
		assert.are.equal(ns.db, PathmarkDB)
		assert.are.same({}, PathmarkDB.flags)
		assert.is_false(PathmarkDB.safeMode)
		assert.is_true(PathmarkDB.boot.inProgress)
		assert.are.equal("dev", PathmarkDB.boot.version)
	end)

	it("keeps existing settings and fills in missing ones", function()
		session({ saved = { flags = { arrow = false } } })
		assert.is_false(PathmarkDB.flags.arrow)
		assert.are.equal(0, PathmarkDB.boot.fails)
	end)

	it("counts the start as clean 10 s after the first loading screen", function()
		session()
		wow.fire("PLAYER_ENTERING_WORLD", true, false)
		wow.advance(9)
		assert.is_true(PathmarkDB.boot.inProgress)
		wow.advance(1)
		assert.is_false(PathmarkDB.boot.inProgress)
	end)

	it("switches to safe mode after two unclean starts", function()
		session()
		local saved = PathmarkDB
		session({ saved = saved })
		assert.is_false(PathmarkDB.safeMode)
		session({ saved = PathmarkDB })
		assert.is_true(PathmarkDB.safeMode)
		assert.is_true(PathmarkDB.autoSafe)
		assert.matches("did not start cleanly twice", wow.output(), 1, true)
	end)

	it("resets the counter after a clean start", function()
		session()
		session({ saved = PathmarkDB, clean = true })
		assert.are.equal(0, PathmarkDB.boot.fails)
		assert.is_false(PathmarkDB.boot.inProgress)
	end)

	it("lifts an automatic safe mode when a new version arrives", function()
		local saved = { safeMode = true, autoSafe = true, boot = { inProgress = false, fails = 2, version = "v0.1.0" } }
		session({ saved = saved, version = "v0.1.1" })
		assert.is_false(PathmarkDB.safeMode)
		assert.are.equal("v0.1.1", PathmarkDB.boot.version)
	end)

	it("keeps a safe mode the player set by hand across versions", function()
		local saved =
			{ safeMode = true, autoSafe = false, boot = { inProgress = false, fails = 0, version = "v0.1.0" } }
		session({ saved = saved, version = "v0.1.1" })
		assert.is_true(PathmarkDB.safeMode)
	end)

	it("ignores ADDON_LOADED of other addons", function()
		wow.reset()
		local ns = wow.loadFiles(FILES)
		wow.fire("ADDON_LOADED", "Questie")
		assert.is_nil(ns.db)
		assert.is_nil(PathmarkDB)
	end)
end)

describe("/pathmark", function()
	it("answers before the addon has loaded", function()
		wow.reset()
		wow.loadFiles(FILES)
		SlashCmdList.PATHMARK("")
		assert.are.equal("Pathmark: not loaded yet", wow.output())
	end)

	it("registers the slash command", function()
		session()
		assert.are.equal("/pathmark", SLASH_PATHMARK1)
		assert.is_function(SlashCmdList.PATHMARK)
	end)

	it("switches safe mode on and off", function()
		session()
		SlashCmdList.PATHMARK("safe")
		assert.is_true(PathmarkDB.safeMode)
		assert.is_false(PathmarkDB.autoSafe)
		SlashCmdList.PATHMARK("safe off")
		assert.is_false(PathmarkDB.safeMode)
		assert.matches("safe mode off, takes effect after /reload", wow.output(), 1, true)
	end)

	it("sets a module flag off and back to default", function()
		session()
		SlashCmdList.PATHMARK("flag arrow off")
		assert.is_false(PathmarkDB.flags.arrow)
		SlashCmdList.PATHMARK("flag arrow on")
		assert.is_nil(PathmarkDB.flags.arrow)
	end)

	it("prints the error report and the status", function()
		local ns = session()
		ns.Guard.Call("arrow", function()
			error("broken", 0)
		end)
		SlashCmdList.PATHMARK("errors")
		assert.matches("1x [arrow] broken", wow.output(), 1, true)
		SlashCmdList.PATHMARK("status")
		assert.matches("Pathmark dev build=70532 toc=16001 project=18 safe=false", wow.output(), 1, true)
	end)

	it("toggles quiet errors", function()
		session()
		SlashCmdList.PATHMARK("quiet")
		assert.is_true(PathmarkDB.flags.quietErrors)
		SlashCmdList.PATHMARK("quiet off")
		assert.is_nil(PathmarkDB.flags.quietErrors)
	end)
end)
