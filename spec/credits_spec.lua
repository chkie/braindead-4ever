-- SPDX-License-Identifier: GPL-3.0-or-later
-- CREDITS.md (Welle 9, K6; release gate T13, concept §3.3): one list feeds CREDITS.md and the Credits
-- page in the settings. Every data source of NOTICE and of the Credits page stands in CREDITS.md with
-- its licence, together with the licence line without warranty, the library line and the trademark line.
local wow = require("spec.helpers.wow")

local function read(path)
	local fh = assert(io.open(path, "rb"))
	local text = fh:read("*a")
	fh:close()
	return text
end

-- English texts of the Credits page.
local function strings()
	local ns = wow.loadFiles({ "Braindead4Ever/Locales/enUS.lua" })
	return ns.L
end

-- Sources of NOTICE: lines "  data/sources/<dir>/   <name>   <licence>".
local function noticeSources()
	local out = {}
	for line in read("NOTICE"):gmatch("[^\n]+") do
		local name, licence = line:match("^%s+data/sources/%w+/%s+(.-)%s%s+(%S.-)%s*$")
		if name then
			out[#out + 1] = { name = name, licence = licence }
		end
	end
	return out
end

describe("CREDITS.md", function()
	local text = read("CREDITS.md")
	local L = strings()

	it("names every data source of NOTICE with its licence", function()
		local list = noticeSources()
		assert.are.equal(3, #list)
		local short = { ["Polestar forever-db"] = "Polestar forever-db", ["All The Things"] = "All The Things" }
		for _, s in ipairs(list) do
			local name = short[s.name] or s.name:match("^(EG Link)") or s.name
			local row = text:match("\n| [^\n]*" .. name:gsub("%p", "%%%0") .. "[^\n]*")
			assert.is_string(row, "missing in CREDITS.md: " .. s.name)
			assert.matches(s.licence, row, 1, true)
		end
	end)

	-- The interface names no other addon (owner 04.11.2026): the Credits page points to NOTICE, and
	-- the credits the licences ask for stay in NOTICE and CREDITS.md, which ship in the package.
	it("the Credits page names no source project and points to NOTICE", function()
		for _, name in ipairs({ "Polestar", "EG Link", "All The Things", "ATT" }) do
			assert.is_nil(L.CREDITS_SOURCES:find(name, 1, true), name)
		end
		assert.matches("NOTICE", L.CREDITS_SOURCES, 1, true)
	end)

	it("has the licence line without warranty, the library line and the trademark line", function()
		assert.matches("GPL-3.0-or-later", text, 1, true)
		assert.matches("without any warranty", text, 1, true)
		assert.matches("Braindead 4ever embeds no libraries.", text, 1, true)
		assert.matches(L.CREDITS_LIBS, text, 1, true)
		assert.matches("not affiliated with or endorsed by Blizzard Entertainment", text, 1, true)
	end)
end)
