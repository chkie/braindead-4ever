-- SPDX-License-Identifier: GPL-3.0-or-later
-- Minimap button and addon compartment entry: both show the addon icon (Media/icon.tga), not a
-- Blizzard stand-in atlas, and the file the TOC names for IconTexture exists.
local S = require("spec.helpers.uisession")

local ICON = "Interface\\AddOns\\Braindead4Ever\\Media\\icon"

describe("minimap icon", function()
	it("is the addon icon in the compartment entry and on the button", function()
		local ns = S.login()
		assert.are.equal(ICON, ns.MinimapButton.ICON_FILE)
		assert.are.equal(ICON, _G.AddonCompartmentFrame.registered[1].icon)
	end)

	it("is the file the TOC names for IconTexture, and the file exists", function()
		local f = assert(io.open("Braindead4Ever/Braindead4Ever.toc", "rb"))
		local toc = f:read("*a")
		f:close()
		assert.is_truthy(toc:find("## IconTexture: " .. ICON .. "\n", 1, true))
		local icon = assert(io.open("Braindead4Ever/Media/icon.tga", "rb"))
		icon:close()
	end)
end)
