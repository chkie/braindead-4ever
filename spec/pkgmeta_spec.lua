-- SPDX-License-Identifier: GPL-3.0-or-later
-- .pkgmeta: the package holds the addon files and the licences, nothing else (no route tools, source
-- data, decoder, tests, docs). Emulates the BigWigs packager's selection on the tracked files: dotfiles
-- and dot folders are always left out, every "ignore" entry drops the path and everything below it.
local tocReader = require("spec.helpers.toc")

local LICENCES = { LICENSE = true, ["LICENSE-EXCEPTION.md"] = true, NOTICE = true }
-- Files beside the licences that travel with the addon: the credits (release gate T13) and the
-- changelog the packager uses as release notes (manual-changelog, release gate T30).
local BESIDE = { ["CREDITS.md"] = true, ["CHANGELOG.md"] = true }

local function ignoreList()
	local fh = assert(io.open(".pkgmeta", "rb"))
	local text = fh:read("*a")
	fh:close()
	local list, inIgnore = {}, false
	for line in text:gmatch("[^\n]+") do
		if line:match("^%S") then
			inIgnore = line:match("^ignore:%s*$") ~= nil
		elseif inIgnore then
			local path = line:match("^%s+%-%s+(%S+)")
			if path then
				list[#list + 1] = path
			end
		end
	end
	return list
end

local function tracked()
	local p = assert(io.popen("git ls-files"))
	local files = {}
	for line in p:lines() do
		files[#files + 1] = line
	end
	p:close()
	return files
end

local function packaged()
	local ignore = ignoreList()
	local out = {}
	for _, f in ipairs(tracked()) do
		local dot = f:match("^%.") or f:match("/%.")
		local skip = dot ~= nil
		for _, path in ipairs(ignore) do
			if f == path or f:sub(1, #path + 1) == path .. "/" then
				skip = true
			end
		end
		if not skip then
			out[#out + 1] = f
		end
	end
	return out, ignore
end

describe(".pkgmeta", function()
	local files, ignore = packaged()

	it("leaves out tools, source data, decoder, tests, docs and the developer probe", function()
		local set = {}
		for _, p in ipairs(ignore) do
			set[p] = true
		end
		for _, p in ipairs({ "tools", "data", "decoder", "spec", "docs", "scripts", "types", "Braindead4Ever/Probe" }) do
			assert.is_true(set[p] == true, "not ignored: " .. p)
		end
	end)

	it("packages only addon files and licences", function()
		assert.is_true(#files > 10)
		for _, f in ipairs(files) do
			assert.is_true(LICENCES[f] or BESIDE[f] or f:match("^Braindead4Ever/") ~= nil, "would be packaged: " .. f)
		end
		local have = {}
		for _, f in ipairs(files) do
			have[f] = true
		end
		for name in pairs(LICENCES) do
			assert.is_true(have[name] == true, "licence missing in the package: " .. name)
		end
		assert.is_true(have["CREDITS.md"] == true, "credits missing in the package")
	end)

	it("packages every file the TOC loads outside the developer block", function()
		local have = {}
		for _, f in ipairs(files) do
			have[f] = true
		end
		for _, toc in ipairs({
			"Braindead4Ever/Braindead4Ever.toc",
			"Braindead4Ever/Braindead4Ever_Camelot.toc",
		}) do
			assert.is_true(have[toc] == true, toc)
			for _, line in ipairs(tocReader.parse(toc).files) do
				local path = tocReader.repoPath("Braindead4Ever", line.path)
				if not path:match("^Braindead4Ever/Probe/") then
					assert.is_true(have[path] == true, "TOC file not packaged: " .. path)
				end
			end
		end
	end)
end)
