--[[
Braindead Forever
Copyright (C) 2026 Braindead Forever contributors (see Git history)

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
-- SPDX-License-Identifier: GPL-3.0-or-later WITH AdditionRef-BraindeadForever-Ace3-Exception

-- UI/TomTom.lua: module "tomtom" (requirement A36, concept §2.3): when TomTom is installed, the current
-- goal of the route goes to it as well, as one waypoint that is replaced at every new goal and removed
-- at the end of the route, on pause and with the option off. TomTom is an optional dependency (TOC
-- OptionalDeps), never part of the package. Its interface, read in TomTom v4.3.13 (CurseForge file
-- 9309599 of 2026-10-24, TomTom.lua lines 874 and 971): TomTom:AddWaypoint(uiMapID, x, y, opts) with x
-- and y from 0 to 1 returns a uid table, TomTom:RemoveWaypoint(uid) takes it back. Options: title, from,
-- persistent = false (the waypoint does not survive the session) and silent = true (TomTom writes no
-- chat line, design rule R2). Whether TomTom shows its own arrow and pins follows the player's TomTom
-- settings. The hand-over waits for the end of a fight (UI.OutOfCombat), because TomTom draws on the
-- world map and the minimap.
local _, ns = ...
local UI, Nav = ns.UI, ns.Nav
local M, Guard = ns.Modules, ns.Guard

local TT = {}
ns.TomTom = TT

local uid, goal -- waypoint handed to TomTom and the goal it stands for
local wanted -- last goal of the step window: { target, title } or false

local function Addon()
	local t = M.Lookup("TomTom")
	return type(t) == "table" and t or nil
end

local function Remove()
	local tt = Addon()
	if uid and tt then
		tt:RemoveWaypoint(uid)
	end
	uid, goal = nil, nil
end

local function Same(a, b)
	return a and b and a.map == b.map and a.wx == b.wx and a.wy == b.wy
end

local function Apply()
	local t = wanted and wanted.target
	if not t or UI.Get("tomtom") ~= true or UI.Paused() then
		Remove()
		return
	end
	if uid and Same(goal, t) then
		return
	end
	Remove()
	local tt = Addon()
	local x, y = Nav.MapXY(t, t.map)
	if not (tt and x) then
		return
	end
	uid = tt:AddWaypoint(t.map, x, y, { title = wanted.title, from = ns.L.TITLE, persistent = false, silent = true })
	goal = { map = t.map, wx = t.wx, wy = t.wy }
end

local function Queue()
	UI.OutOfCombat("tomtom", function()
		Guard.Call("tomtom", Apply)
	end)
end

-- The step window calls this with every goal (same place as the arrow): target from Nav.Target or nil.
function TT.SetTarget(t, info)
	if not M.IsActive("tomtom") then
		return
	end
	local title = t and (t.title or (info and ns.StepText.Step(info, false))) or nil
	wanted = t and { target = t, title = title } or false
	Queue()
end

-- The waypoint Braindead Forever handed to TomTom, or nil (tests, problem report).
function TT.Waypoint()
	return uid
end

M.Define("tomtom", {
	requires = { funcs = { "TomTom.AddWaypoint", "TomTom.RemoveWaypoint" } },
	init = function()
		for _, key in ipairs({ "tomtom", "paused" }) do
			UI.OnChange(key, TT, Queue)
		end
	end,
	disable = Remove,
})
