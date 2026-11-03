-- SPDX-License-Identifier: GPL-3.0-or-later
-- Minimal TOC reader for tests: directives, file lines and inline load conditions,
-- following the rules in warcraft.wiki.gg "TOC format".
local M = {}

local GAME_TYPE_FAMILY = { standard = "mainline", camelot = "mainline", vanilla = "classic" }

local function split(list)
	local out = {}
	for v in list:gmatch("[^,%s]+") do
		out[#out + 1] = v:lower()
	end
	return out
end

-- Returns { directives = { [name] = value }, order = { name, ... }, files = { { path, conditions } } }
function M.parse(path)
	local fh = assert(io.open(path, "rb"))
	local text = fh:read("*a")
	fh:close()
	assert(text:sub(1, 3) ~= "\239\187\191", path .. ": TOC must not start with a BOM")
	local toc = { directives = {}, order = {}, files = {} }
	for line in (text .. "\n"):gmatch("(.-)\r?\n") do
		local name, value = line:match("^##%s*([^:]+):%s*(.-)%s*$")
		if name then
			toc.directives[name] = value
			toc.order[#toc.order + 1] = name
		elseif not (line:match("^#") or line:match("^%s*$")) then -- skip comments and empty lines
			local file = line:match("^(.-)%s*%[") or line:match("^(.-)%s*$")
			local conditions = {}
			for cond, values in line:gmatch("%[(%a+)%s*([^%]]*)%]") do
				conditions[cond] = split(values)
			end
			toc.files[#toc.files + 1] = { path = file, conditions = conditions }
		end
	end
	return toc
end

local function contains(list, value)
	for _, v in ipairs(list) do
		if v == value then
			return true
		end
	end
	return false
end

-- Does a file line load in a client with this locale and game type?
function M.loads(entry, client)
	local c = entry.conditions
	local gameType = client.gameType or "camelot"
	local family = GAME_TYPE_FAMILY[gameType]
	if c.AllowLoadTextLocale and not contains(c.AllowLoadTextLocale, (client.locale or "enUS"):lower()) then
		return false
	end
	if
		c.AllowLoadGameType and not (contains(c.AllowLoadGameType, gameType) or contains(c.AllowLoadGameType, family))
	then
		return false
	end
	if
		c.ExcludeLoadGameType and (contains(c.ExcludeLoadGameType, gameType) or contains(c.ExcludeLoadGameType, family))
	then
		return false
	end
	return true
end

-- File path inside the repository for a TOC line ("Core\Guard.lua" -> "Braindead4Ever/Core/Guard.lua").
function M.repoPath(addonDir, tocPath)
	return addonDir .. "/" .. tocPath:gsub("\\", "/")
end

return M
