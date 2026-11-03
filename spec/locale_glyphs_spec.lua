-- SPDX-License-Identifier: GPL-3.0-or-later
-- Every text a player can see uses only characters the client font of his language draws (release
-- gate T19, requirement A61: no empty boxes in Russian, Korean or Chinese clients).
--
-- Glyph sets measured on 2026-11-01: the client fonts from wago.tools (CASC file IDs 615960
-- FRIZQT__.TTF, 615971 FRIZQT___CYR.TTF, 615966 2002.TTF, 615974 ARKai_T.ttf, 615963 blei00d.TTF),
-- character maps read with fontTools. Blizzard's Fonts.xml (wow-ui-source forever) assigns them per
-- alphabet: roman FRIZQT__, russian FRIZQT___CYR, korean 2002, simplified Chinese ARKai_T, traditional
-- Chinese blei00d. All five have every printable ASCII character. Of the rest:
--   in all five:        “ ” – • …
--   missing:            · (FRIZQT___CYR), „ (ARKai_T, blei00d), ä ö ü Ä Ö Ü ß (blei00d),
--                       no-break space U+00A0 (ARKai_T; measured again 2026-11-02, Welle 5d)
-- English texts are the fallback for every client language, so they may use only what all five fonts
-- have. German texts load only in the German client (TOC: AllowLoadTextLocale deDE), which uses
-- FRIZQT__.
local wow = require("spec.helpers.wow")

local ALL_FONTS = { ["“"] = true, ["”"] = true, ["–"] = true, ["•"] = true, ["…"] = true }
local LATIN =
	{ ["ä"] = true, ["ö"] = true, ["ü"] = true, ["Ä"] = true, ["Ö"] = true, ["Ü"] = true, ["ß"] = true }
for c in pairs(ALL_FONTS) do
	LATIN[c] = true
end
LATIN["„"] = true
LATIN["\194\160"] = true -- no-break space: FRIZQT__ has it, ARKai_T does not (English must not use it)

-- Characters of a UTF-8 string that are neither printable ASCII nor in the allowed set.
local function bad(text, allowed)
	local out = {}
	for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		local b = ch:byte()
		if #ch == 1 then
			if (b < 32 and ch ~= "\n") or b == 127 then
				out[#out + 1] = ("\\%d"):format(b)
			end
		elseif not allowed[ch] then
			out[#out + 1] = ch
		end
	end
	return out
end

local function locale(code)
	wow.reset({ locale = code })
	local files = { "BraindeadForever/Locales/enUS.lua" }
	if code == "deDE" then
		files[2] = "BraindeadForever/Locales/deDE.lua"
	end
	return wow.loadFiles(files).L
end

local function check(L, allowed)
	local problems = {}
	for key, text in pairs(L) do
		if type(text) == "string" then
			local found = bad(text, allowed)
			if #found > 0 then
				problems[#problems + 1] = key .. ": " .. table.concat(found, " ")
			end
		end
	end
	table.sort(problems)
	return problems
end

-- String literals of a Lua source (comments skipped): what the code itself could put on screen.
local function literals(src)
	local out, i, n = {}, 1, #src
	while i <= n do
		local c = src:sub(i, i)
		if src:sub(i, i + 1) == "--" then
			local eq = src:match("^%-%-%[(=*)%[", i)
			if eq then
				local _, e = src:find("]" .. eq .. "]", i, true)
				i = (e or n) + 1
			else
				i = (src:find("\n", i, true) or n) + 1
			end
		elseif c == '"' or c == "'" then
			local j = i + 1
			while j <= n and src:sub(j, j) ~= c do
				j = j + (src:sub(j, j) == "\\" and 2 or 1)
			end
			out[#out + 1] = src:sub(i + 1, j - 1)
			i = j + 1
		elseif src:match("^%[=*%[", i) then
			local eq = src:match("^%[(=*)%[", i)
			local s = i + #eq + 2
			local _, e = src:find("]" .. eq .. "]", s, true)
			out[#out + 1] = src:sub(s, (e or n) - #eq - 2)
			i = (e or n) + 1
		else
			i = i + 1
		end
	end
	return out
end

describe("Characters of the interface texts", function()
	it("English texts (fallback of every client language) use only glyphs of all client fonts", function()
		assert.are.same({}, check(locale("enUS"), ALL_FONTS))
	end)

	it("German texts use only glyphs of the Latin client font", function()
		assert.are.same({}, check(locale("deDE"), LATIN))
	end)

	it("the separator is not the middle dot the Cyrillic font lacks", function()
		for _, code in ipairs({ "enUS", "deDE" }) do
			local L = locale(code)
			assert.are.equal(" • ", L.SEP)
			assert.are.equal("•", L.BULLET)
			for key, text in pairs(L) do
				assert.is_nil(type(text) == "string" and text:find("·", 1, true) or nil, code .. " " .. key)
			end
		end
	end)

	it("strings in the packaged code are plain ASCII (on-screen text lives in Locales/)", function()
		-- values of the route data that the code compares and never shows
		local DATA = { ["vorläufig"] = true } -- module label (docs/ROUTE-FORMAT.md)
		local problems = {}
		for _, path in ipairs(wow.addonFiles()) do -- without the developer probe and preview
			if not path:find("/Locales/", 1, true) and not path:find("/Data_", 1, true) then
				local fh = assert(io.open(path, "rb"))
				local src = fh:read("*a")
				fh:close()
				for _, s in ipairs(literals(src)) do
					local found = bad(s, {})
					if #found > 0 and not DATA[s] then
						problems[#problems + 1] = path .. ": " .. s
					end
				end
			end
		end
		assert.are.same({}, problems)
	end)

	it("counter-check: the middle dot in an English text is found", function()
		assert.are.same({ "·" }, bad("Elwynn Forest · 4/48", ALL_FONTS))
		assert.are.same({ "„" }, bad("„Quest“", ALL_FONTS))
		assert.are.same({}, bad("„Quest“", LATIN))
	end)
end)
