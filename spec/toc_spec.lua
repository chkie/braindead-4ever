-- SPDX-License-Identifier: GPL-3.0-or-later
-- Smoke test: reads both TOC files and loads their files in order, like the client does.
local wow = require("spec.helpers.wow")
local tocReader = require("spec.helpers.toc")

local ADDON = "BraindeadForever"
local DIR = "BraindeadForever"
local TOCS = {
	{ file = DIR .. "/BraindeadForever.toc", gameType = "standard", flavor = "retail" },
	{ file = DIR .. "/BraindeadForever_Camelot.toc", gameType = "camelot", flavor = "forever" },
}
-- Globals the addon may create. Everything else must stay in the namespace.
local ALLOWED_NEW_GLOBALS = {
	BraindeadForeverDB = true,
	BraindeadForeverCollectDB = true,
	BraindeadForeverCharDB = true,
	SLASH_BRAINDEADFOREVER1 = true,
	SLASH_BRAINDEADFOREVER2 = true,
	-- Interface (Welle 5): font copies of Blizzard objects (CreateFont needs a name) and the setup
	-- window (Escape closes frames by name).
	BraindeadForeverFontHeader = true,
	BraindeadForeverFontStep = true,
	BraindeadForeverFontLine = true,
	BraindeadForeverFontSmall = true,
	BraindeadForeverFontStatus = true,
	BraindeadForeverSetupFrame = true,
	-- Key bindings (Welle 9): the handler Bindings.xml calls and the names on Blizzard's binding page.
	BraindeadForeverBinding = true,
	BINDING_HEADER_BRAINDEADFOREVER = true,
	BINDING_NAME_BRAINDEADFOREVER_TOGGLE = true,
	BINDING_NAME_BRAINDEADFOREVER_CHECK = true,
	BINDING_NAME_BRAINDEADFOREVER_SKIP = true,
	BINDING_NAME_BRAINDEADFOREVER_BACK = true,
	BINDING_NAME_BRAINDEADFOREVER_WINDOW = true,
	BINDING_NAME_BRAINDEADFOREVER_MINI = true,
	BINDING_NAME_BRAINDEADFOREVER_STATS = true,
}

local function fileExists(path)
	local fh = io.open(path, "rb")
	if fh then
		fh:close()
		return true
	end
	return false
end

local function interfaces(toc)
	local out = {}
	for v in (toc.directives.Interface or ""):gmatch("%d+") do
		out[#out + 1] = tonumber(v)
	end
	return out
end

-- Loads a TOC like the client and returns the namespace and the loaded file paths.
local function loadToc(entry, client)
	local toc = tocReader.parse(entry.file)
	local ns, loaded = {}, {}
	for _, line in ipairs(toc.files) do
		if tocReader.loads(line, { locale = client.locale, gameType = entry.gameType }) then
			local path = tocReader.repoPath(DIR, line.path)
			wow.loadFile(path, ADDON, ns)
			loaded[#loaded + 1] = path
		end
	end
	return ns, loaded
end

describe("TOC files", function()
	local base = tocReader.parse(TOCS[1].file)
	local camelot = tocReader.parse(TOCS[2].file)

	it("declare the interface versions for Retail 12.1.5 and Forever", function()
		assert.are.same({ 120105, 16001 }, interfaces(base))
		assert.are.same({ 16001 }, interfaces(camelot))
	end)

	it("list the same files with the same conditions", function()
		assert.are.same(base.files, camelot.files)
		assert.is_true(#base.files > 0)
	end)

	it("share the same metadata apart from the interface", function()
		for name, value in pairs(base.directives) do
			if name ~= "Interface" then
				assert.are.equal(value, camelot.directives[name], name)
			end
		end
	end)

	for _, entry in ipairs(TOCS) do
		describe(entry.file, function()
			local toc = tocReader.parse(entry.file)

			it("has the required directives", function()
				assert.are.equal("Braindead Forever", toc.directives.Title)
				assert.are.equal("@project-version@", toc.directives.Version)
				assert.are.equal("BraindeadForeverDB, BraindeadForeverCollectDB", toc.directives.SavedVariables)
				assert.are.equal("BraindeadForeverCharDB", toc.directives.SavedVariablesPerCharacter)
			end)

			it("keeps the developer probe inside the do-not-package block", function()
				local fh = assert(io.open(entry.file, "rb"))
				local text = fh:read("*a")
				fh:close()
				local block = text:match("#@do%-not%-package@\r?\n(.-)#@end%-do%-not%-package@")
				assert.is_string(block, "no #@do-not-package@ block")
				local inside = {}
				for line in block:gmatch("[^\r\n]+") do
					if not line:match("^#") then
						inside[#inside + 1] = line
					end
				end
				assert.are.same({ "Probe\\Probe.lua", "Probe\\Checks.lua", "Probe\\Preview.lua" }, inside)
				for _, line in ipairs(toc.files) do
					if line.path:match("^Probe") then
						assert.is_truthy(block:find(line.path, 1, true), line.path .. " outside the block")
					end
				end
			end)

			it("puts unlocalized Notes before Notes-deDE", function()
				local plain, localized
				for i, name in ipairs(toc.order) do
					if name == "Notes" then
						plain = i
					elseif name == "Notes-deDE" then
						localized = i
					end
				end
				assert.is_truthy(plain)
				assert.is_truthy(localized)
				assert.is_true(plain < localized)
			end)

			it("lists only files that exist", function()
				for _, line in ipairs(toc.files) do
					local path = tocReader.repoPath(DIR, line.path)
					assert.is_true(fileExists(path), "missing file " .. path)
				end
			end)

			it("lists every Lua file of the addon", function()
				local listed = {}
				for _, line in ipairs(toc.files) do
					listed[tocReader.repoPath(DIR, line.path)] = true
				end
				local find = assert(io.popen('find "' .. DIR .. '" -name "*.lua"'))
				for path in find:lines() do
					assert.is_true(listed[path] == true, "not listed in TOC: " .. path)
				end
				find:close()
			end)

			for _, locale in ipairs({ "enUS", "deDE" }) do
				it("loads in order and boots without errors (" .. locale .. ")", function()
					wow.reset({ flavor = entry.flavor, locale = locale })
					local before = {}
					for k in pairs(_G) do
						before[k] = true
					end

					local ns, loaded = loadToc(entry, { locale = locale })
					assert.are.equal(locale == "deDE" and #toc.files or #toc.files - 1, #loaded)

					wow.fire("ADDON_LOADED", "SomeOtherAddon")
					assert.is_nil(ns.db)
					wow.fire("ADDON_LOADED", ADDON)
					wow.fire("PLAYER_LOGIN")
					wow.fire("PLAYER_ENTERING_WORLD", true, false)
					wow.advance(10)

					for _, name in ipairs({ "collector", "exchange", "report" }) do
						assert.are.equal("on", ns.Modules.state[name], name)
					end
					assert.is_table(BraindeadForeverCollectDB)
					assert.is_string(BraindeadForeverCharDB.id)

					assert.are.same({}, wow.errors)
					assert.is_table(BraindeadForeverDB)
					assert.are.equal(BraindeadForeverDB, ns.db)
					assert.is_false(BraindeadForeverDB.boot.inProgress)
					assert.are.equal("dev", ns.version)

					SlashCmdList.BRAINDEADFOREVER("")
					assert.matches("^Braindead Forever dev build=", wow.output())

					for k in pairs(_G) do
						if not before[k] then
							assert.is_true(ALLOWED_NEW_GLOBALS[k] == true, "unexpected global " .. tostring(k))
						end
					end
				end)
			end
		end)
	end
end)

describe(".pkgmeta", function()
	it("leaves the developer probe and the decoder out of the package", function()
		local fh = assert(io.open(".pkgmeta", "rb"))
		local text = fh:read("*a")
		fh:close()
		assert.is_truthy(text:find("\n  %- BraindeadForever/Probe\n"), "BraindeadForever/Probe not ignored")
		assert.is_truthy(text:find("\n  %- decoder\n"), "decoder not ignored")
	end)
end)

describe("Locales", function()
	local function keys(locale)
		wow.reset({ locale = locale })
		local ns = {}
		wow.loadFile(DIR .. "/Locales/enUS.lua", ADDON, ns)
		local english = {}
		for k, v in pairs(ns.L) do
			english[k] = v
		end
		wow.loadFile(DIR .. "/Locales/deDE.lua", ADDON, ns)
		return english, ns.L
	end

	-- Only the keys deDE.lua itself assigns.
	local function germanKeys()
		wow.reset({ locale = "deDE" })
		local assigned = {}
		local ns = {
			L = setmetatable({}, {
				__newindex = function(t, k, v)
					rawset(t, k, v)
					assigned[k] = v
				end,
			}),
		}
		wow.loadFile(DIR .. "/Locales/deDE.lua", ADDON, ns)
		return assigned
	end

	it("translate every English key into German with the same placeholders", function()
		local english = keys("enUS")
		local german = germanKeys()
		for k, v in pairs(english) do
			local translated = german[k]
			assert.is_string(translated, "missing deDE key " .. k)
			local _, a = v:gsub("%%[ds]", "")
			local _, b = translated:gsub("%%[ds]", "")
			assert.are.equal(a, b, "placeholder count differs for " .. k)
		end
		for k in pairs(german) do
			assert.is_string(english[k], "deDE key without English text: " .. k)
		end
	end)

	it("leave English untouched on other clients", function()
		local english, current = keys("frFR")
		for k, v in pairs(english) do
			assert.are.equal(v, current[k])
		end
	end)

	it("fall back to the key for unknown texts", function()
		local _, L = keys("enUS")
		assert.are.equal("NO_SUCH_KEY", L.NO_SUCH_KEY)
	end)
end)
