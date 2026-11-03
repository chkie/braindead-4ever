-- SPDX-License-Identifier: GPL-3.0-or-later
-- Honest coverage (Welle 9, K5; requirement A32: "it promises nowhere more than it has"): the route
-- data ends at level 30, so the TOC notes, the README and the end of the route say 1 to 30 and that
-- the rest follows with updates. The level comes from the data, not from a constant.
local S = require("spec.helpers.uisession")
local tocReader = require("spec.helpers.toc")

local function read(path)
	local fh = assert(io.open(path, "rb"))
	local text = fh:read("*a")
	fh:close()
	return text
end

-- Highest planned level of any module in the compiled data of a faction (file read on its own: the
-- session drops the other faction's data).
local function topOfData(faction)
	local data = {}
	assert(loadfile("Braindead4Ever/Routes/Data_" .. faction .. ".lua"))("Braindead4Ever", data)
	local top = 0
	for _, m in pairs(data.RouteData[faction]().modules) do
		top = math.max(top, m.levels[2])
	end
	return top
end

describe("Coverage", function()
	it("the route knows how far its data reaches", function()
		local ns = S.login()
		assert.are.equal(30, ns.Route.TopLevel())
		assert.are.equal(30, topOfData("Alliance"))
		assert.are.equal(30, topOfData("Horde"))
	end)

	it("the end of the route says where the routes go on, in English and German", function()
		for locale, text in pairs({
			enUS = "End of the route reached. Routes from level 30 on follow with updates.",
			deDE = "Ende der Route erreicht. Routen ab Stufe 30 folgen mit Updates.",
		}) do
			local ns = S.login({ locale = locale })
			local rt = ns.Route.Runtime()
			rt.saved.anchor = "_end"
			rt:Evaluate()
			assert.are.equal(text, ns.StepFrame.frame.status.text)
		end
	end)

	it("routes that reach the level cap end without the hint", function()
		local ns = S.login()
		ns.Route.TopLevel = function()
			return 60
		end
		local rt = ns.Route.Runtime()
		rt.saved.anchor = "_end"
		rt:Evaluate()
		assert.are.equal("End of the route reached", ns.StepFrame.frame.status.text)
	end)

	it("both TOCs name levels 1 to 30 and promise no 60", function()
		for _, path in ipairs({
			"Braindead4Ever/Braindead4Ever.toc",
			"Braindead4Ever/Braindead4Ever_Camelot.toc",
		}) do
			local d = tocReader.parse(path).directives
			assert.matches("levels 1 to 30", d.Notes, 1, true)
			assert.matches("Stufe 1 bis 30", d["Notes-deDE"], 1, true)
			assert.is_nil(d.Notes:find("60"), path)
			assert.is_nil(d["Notes-deDE"]:find("60"), path)
		end
	end)

	it("the README names 1 to 30 and says that 30 to 60 follow with updates", function()
		local text = read("README.md")
		assert.is_nil(text:find("from level 1 to 60", 1, true))
		assert.is_nil(text:find("levels 1 to 60", 1, true))
		assert.is_nil(text:find("von Stufe 1 bis 60", 1, true))
		assert.is_nil(text:find("Stufe 1 bis 60", 1, true))
		assert.matches("levels 1 to 30; levels 30 to 60 follow with updates", text, 1, true)
	end)
end)
