--[[
Pathmark
Copyright (C) 2026 Pathmark contributors (see Git history)

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
-- SPDX-License-Identifier: GPL-3.0-or-later WITH AdditionRef-Pathmark-Ace3-Exception

-- UI/Bindings.lua: module "bindings", the key bindings of Bindings.xml (concept §2.7, design rules B5
-- and E9, requirement A57): guidance on and off, check off, skip, previous step, step window on and off,
-- mini view, the page "Your run" (UI/StatsPage.lua). Unbound by default. The names for Blizzard's key binding page are set when the file loads,
-- so they show even while the module is off. A key does nothing a click on the window would not do, and
-- in a fight it goes through the same entry points (UI/StepFrame.lua, UI.OutOfCombat for what may be
-- protected), so the combat rule holds (spec/ui_combat_spec.lua).
local ADDON, ns = ...
local L, UI = ns.L, ns.UI
local M, Guard = ns.Modules, ns.Guard

local B = {
	-- Binding name suffix (Bindings.xml: PATHMARK_<ACTION>) in the order of the key binding page.
	ACTIONS = { "TOGGLE", "CHECK", "SKIP", "BACK", "WINDOW", "MINI", "STATS" },
}
ns.Bindings = B

-- Names on Blizzard's key binding page: the client reads BINDING_HEADER_<category> and
-- BINDING_NAME_<binding> (Blizzard_SettingsDefinitions_Frame/Keybindings.lua, forever).
_G.BINDING_HEADER_PATHMARK = ADDON
for _, action in ipairs(B.ACTIONS) do
	_G["BINDING_NAME_PATHMARK_" .. action] = L["BINDING_" .. action]
end

local function Window()
	return M.IsActive("window") and ns.StepFrame or nil
end

local RUN = {
	TOGGLE = function()
		UI.SetPaused(not UI.Paused())
	end,
	CHECK = function(sf)
		return sf and sf.CheckCurrent()
	end,
	SKIP = function(sf)
		return sf and sf.AskSkip()
	end,
	BACK = function(sf)
		return sf and sf.Back()
	end,
	WINDOW = function(sf)
		return sf and sf.ToggleWindow()
	end,
	MINI = function(sf)
		return sf and sf.SetMini(not UI.DB().mini)
	end,
	STATS = function() -- opens and closes like /pathmark stats; never in a fight (it waits)
		local page = M.IsActive("statspage") and ns.StatsPage
		return page and page.Toggle()
	end,
}

-- One key press. While the guidance pauses, only the keys that resume it and that open the page work.
function B.Run(action)
	local fn = RUN[action]
	if not fn or not M.IsActive("bindings") then
		return false
	end
	if UI.Paused() and action ~= "TOGGLE" and action ~= "STATS" then
		return false
	end
	Guard.Call("bindings", fn, Window())
	return true
end

-- Called by the bodies in Bindings.xml.
_G.PathmarkBinding = function(action)
	return B.Run(action)
end

M.Define("bindings", {})
