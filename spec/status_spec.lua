-- SPDX-License-Identifier: GPL-3.0-or-later
-- docs/STATUS.md and the probe: every probe check belongs to a feature in STATUS.md, every id named
-- there exists, and every MVP item of the release concept (M1 to M14) has a row (AP 3 acceptance:
-- "every planned feature has a status in docs/STATUS.md").
local wow = require("spec.helpers.wow")

local function statusText()
	local fh = assert(io.open("docs/STATUS.md", "rb"))
	local text = fh:read("*a")
	fh:close()
	return text
end

describe("docs/STATUS.md", function()
	local ns = wow.session({ probe = true })
	local text = statusText()
	local groups = {}
	for _, c in ipairs(ns.Probe.CHECKS) do
		groups[c.id:match("^(%a+)%.")] = true
	end

	it("names every explicit probe check", function()
		for _, c in ipairs(ns.Probe.CHECKS) do
			assert.is_truthy(text:find("`" .. c.id .. "`", 1, true), "missing in STATUS.md: " .. c.id)
		end
	end)

	it("covers the checks derived from every module", function()
		for _, name in ipairs(ns.Modules.order) do
			assert.is_truthy(text:find("`mod." .. name .. ".*`", 1, true), "missing in STATUS.md: mod." .. name .. ".*")
		end
	end)

	it("names no probe check that does not exist", function()
		local ids = {}
		for _, c in ipairs(ns.Probe.All()) do
			ids[c.id] = true
		end
		for token in text:gmatch("`([%w%.%*]+)`") do
			local group = token:match("^(%l+)%.")
			if group == "mod" then
				local module = token:match("^mod%.(%w+)%.%*$")
				assert.is_table(ns.Modules.defs[module], "unknown module in STATUS.md: " .. token)
			elseif group and groups[group] and not token:find("%u") then
				assert.is_true(ids[token] == true, "unknown probe check in STATUS.md: " .. token)
			end
		end
	end)

	it("has a row with a status for every MVP item M1 to M14", function()
		for i = 1, 14 do
			local row = text:match("\n| M" .. i .. " [^\n]+")
			assert.is_string(row, "no row for M" .. i)
			assert.is_truthy(
				row:find("| planned |", 1, true) or row:find("| built", 1, true) or row:find("| blocked |", 1, true)
			)
		end
	end)
end)
