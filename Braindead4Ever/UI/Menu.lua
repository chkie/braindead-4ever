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

-- UI/Menu.lua: the right-click menu of the step window, also opened by the minimap button and the
-- addon compartment (concept §2.7, design v2 "Rechtsklickmenü"): undo with the name of the last action
-- on top, then skip, back, arrow, mini view, report, share, your run (Welle 8), settings, pause. Blizzard_Menu
-- (MenuUtil.CreateContextMenu, brain chapter 04 §10). Every entry is also reachable another way (E9).
local _, ns = ...
local L, UI, C, ST = ns.L, ns.UI, ns.Connect, ns.StepText

local Menu = {}
ns.Menu = Menu

-- Settings page: Settings.OpenToCategory has restrictions (brain chapter 04 §9), so never in combat.
function Menu.OpenSettings()
	UI.OutOfCombat("settings", function()
		if ns.settingsCategoryID and Settings and Settings.OpenToCategory then
			Settings.OpenToCategory(ns.settingsCategoryID)
		end
		if ns.StepFrame then -- Blizzard's settings may load only now: watch them, the hint waits (M13)
			ns.StepFrame.WatchSettings()
			if ns.StepFrame.HintBlocked() then
				ns.StepFrame.SuspendHint()
			end
		end
	end)
end

-- The entries as plain data, so tests and the generator share them.
function Menu.Entries()
	local act = C.LastAction()
	return {
		{ kind = "title", text = L.TITLE },
		{
			kind = "button",
			id = "undo",
			text = ST.Undo(act),
			enabled = act ~= nil,
			fn = ns.StepFrame and ns.StepFrame.Undo,
		},
		{
			kind = "button",
			id = "skip",
			text = L.MENU_SKIP,
			enabled = C.Current() ~= nil,
			fn = ns.StepFrame and ns.StepFrame.AskSkip,
		},
		{ kind = "button", id = "back", text = L.MENU_BACK, enabled = true, fn = ns.StepFrame and ns.StepFrame.Back },
		{
			kind = "checkbox",
			id = "arrow",
			text = L.MENU_ARROW,
			get = function()
				return UI.Get("arrow") == true
			end,
			set = function()
				UI.Set("arrow", not UI.Get("arrow"))
			end,
		},
		{
			kind = "checkbox",
			id = "mini",
			text = L.MENU_MINI,
			get = function()
				return UI.DB().mini == true
			end,
			set = function()
				if ns.StepFrame then
					ns.StepFrame.SetMini(not UI.DB().mini)
				end
			end,
		},
		{ kind = "divider" },
		{
			kind = "button",
			id = "report",
			text = L.MENU_REPORT,
			enabled = true,
			fn = function()
				local cmd = ns.Commands and ns.Commands.report
				if cmd then
					cmd("")
				end
			end,
		},
		{
			kind = "button",
			id = "share",
			text = L.MENU_SHARE,
			enabled = true,
			fn = function()
				local cmd = ns.Commands and ns.Commands.export
				if cmd then
					cmd("")
				end
			end,
		},
		{ kind = "button", id = "stats", text = L.MENU_STATS, enabled = true, fn = ns.StatsPage and ns.StatsPage.Open },
		{ kind = "button", id = "settings", text = L.MENU_SETTINGS, enabled = true, fn = Menu.OpenSettings },
		{
			kind = "button",
			id = "pause",
			text = UI.Paused() and L.MENU_RESUME or L.MENU_PAUSE,
			enabled = true,
			fn = function()
				UI.SetPaused(not UI.Paused())
			end,
		},
	}
end

local function Run(fn)
	return function()
		if fn then
			ns.Guard.Call("ui", fn)
		end
	end
end

-- Generator for MenuUtil: fills a root description from the entries.
function Menu.Generate(_, root)
	for _, e in ipairs(Menu.Entries()) do
		if e.kind == "title" then
			root:CreateTitle(e.text)
		elseif e.kind == "divider" then
			root:CreateDivider()
		elseif e.kind == "checkbox" then
			root:CreateCheckbox(e.text, e.get, Run(e.set))
		else
			local b = root:CreateButton(e.text, Run(e.fn))
			if not e.enabled and b and b.SetEnabled then
				b:SetEnabled(false)
			end
		end
	end
end

function Menu.Open(owner)
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, Menu.Generate)
	end
end
