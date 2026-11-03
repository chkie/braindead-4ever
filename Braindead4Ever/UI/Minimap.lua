--[[
Braindead 4ever
Copyright (C) 2026 Braindead 4ever contributors (see Git history)

This program is free software: you can redistribute it and/or modify it under the
terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

Additional permission under GNU GPL version 3 section 7

If you modify this Program, or any covered work, by linking or combining it with
the Ace3 libraries (or a modified version of that library), containing parts
covered by the terms of the Ace3 license, the licensors of this Program grant you
additional permission to convey the resulting work. Corresponding Source for a
non-source form of such a combination shall include the source code for the parts
of the Ace3 libraries used as well as that of the covered work.
]]
-- SPDX-License-Identifier: GPL-3.0-or-later WITH AdditionRef-Braindead4Ever-Ace3-Exception

-- UI/Minimap.lua: module "minimap" (concept §2.7): a button on the minimap edge and an entry in
-- Blizzard's addon compartment. Left click turns the guidance off and on (rule R5), right click opens
-- the same menu as the step window. No LibDBIcon (release gate T28) and no global compartment function:
-- the entry is registered with AddonCompartmentFrame:RegisterAddon, which takes an atlas or a texture path
-- as icon (Blizzard_Minimap/Mainline/AddonCompartment.lua). Both show the addon icon Media/icon.
local _, ns = ...
local L, UI, T = ns.L, ns.UI, ns.Theme
local M, Guard = ns.Modules, ns.Guard

local MM = {
	SIZE = 31,
	ICON = 20,
	ANGLE = 225, -- degrees, start position on the minimap edge (lower left)
	ICON_FILE = "Interface\\AddOns\\Braindead4Ever\\Media\\icon", -- the addon icon (Media/icon.tga)
}
ns.MinimapButton = MM

local btn

function MM.Click(button)
	if button == "RightButton" then
		ns.Menu.Open(btn)
	else
		UI.SetPaused(not UI.Paused())
	end
end

function MM.Tooltip(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:SetText(L.TITLE, T.RGB(HIGHLIGHT_FONT_COLOR))
	GameTooltip:AddLine(UI.Paused() and L.MM_LEFT_RESUME or L.MM_LEFT_PAUSE, T.RGB(NORMAL_FONT_COLOR))
	GameTooltip:AddLine(L.MM_RIGHT, T.RGB(NORMAL_FONT_COLOR))
	GameTooltip:Show()
end

function MM.Place()
	if not btn then
		return
	end
	local a = math.rad(UI.DB().mmAngle or MM.ANGLE)
	local r = ((Minimap:GetWidth() or 140) / 2) + 5
	btn:ClearAllPoints()
	btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

-- Dragging moves the button along the edge.
local function DragUpdate()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale() or 1
	if mx and cx then
		UI.DB().mmAngle = math.floor(math.deg(math.atan2(cy / scale - my, cx / scale - mx)) + 0.5) % 360
		MM.Place()
	end
end

local function Build()
	btn = CreateFrame("Button", nil, Minimap)
	MM.button = btn
	btn:SetSize(MM.SIZE, MM.SIZE)
	btn:SetFrameStrata("MEDIUM")
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	btn:RegisterForDrag("LeftButton")
	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetSize(MM.ICON, MM.ICON)
	btn.icon:SetPoint("CENTER")
	btn.icon:SetTexture(MM.ICON_FILE)
	btn:SetScript("OnClick", function(_, button)
		Guard.Call("minimap", MM.Click, button)
	end)
	btn:SetScript("OnEnter", MM.Tooltip)
	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	btn:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", DragUpdate)
	end)
	btn:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	MM.Place()
end

function MM.Apply()
	if btn then
		btn:SetShown(UI.Get("mmButton") == true)
	end
end

local function Compartment()
	if not (AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon) then
		return
	end
	MM.compartment = {
		text = L.TITLE,
		icon = MM.ICON_FILE,
		notCheckable = true,
		func = function(_, inputData)
			Guard.Call("minimap", MM.Click, inputData and inputData.buttonName)
		end,
		funcOnEnter = function(button)
			MM.Tooltip(button)
		end,
		funcOnLeave = function()
			GameTooltip:Hide()
		end,
	}
	AddonCompartmentFrame:RegisterAddon(MM.compartment)
end

local function Init()
	if Minimap then
		Build()
		MM.Apply()
		UI.OnChange("mmButton", MM, MM.Apply)
	end
	Compartment()
end

M.Define("minimap", {
	requires = { funcs = { "GetCursorPosition" } },
	init = Init,
})
