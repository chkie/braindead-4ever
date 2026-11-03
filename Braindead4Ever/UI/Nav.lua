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

-- UI/Nav.lua: positions, distance and direction for the arrow, the step window and the map pins.
-- Brain chapter 07 §2 and pattern C: UnitPosition gives north, west in yards (nil in instances);
-- GetPlayerFacing is radians, 0 = north, counterclockwise. A route "goto" holds world coordinates:
-- wx on the west axis, wy on the north axis (docs/ROUTE-FORMAT.md). The angle formula is the one of
-- HereBeDragons GetWorldVector. Nothing here allocates per frame except the map projection, which only
-- runs when pins are refreshed.
local _, ns = ...
local R = ns.Routes
local V = R.VERB

local Nav = { continents = {} }
ns.Nav = Nav

local PI2, atan2, abs, sqrt = math.pi * 2, math.atan2, math.abs, math.sqrt

-- Continent (instance ID) of a uiMapID, cached; nil if the client cannot place the map.
function Nav.Continent(map)
	local c = Nav.continents[map]
	if c == nil then
		local cont = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(0.5, 0.5))
		c = ns.Util.Num(cont) or false
		Nav.continents[map] = c
	end
	return c or nil
end

-- The step's target: its last "goto" that applies to the character. nil without one.
function Nav.Target(info)
	local step = info and info.step
	if not step then
		return nil
	end
	local _, _, race = UnitRace("player")
	local _, _, class = UnitClass("player")
	local found
	for _, el in ipairs(step) do
		if el[1] == V.GOTO and (not (el.r or el.c) or R.Applies(el, race, class)) then
			found = el
		end
	end
	if not found then
		return nil
	end
	return { map = found[2], wx = found[3], wy = found[4], radius = found[5], key = info.key }
end

-- A map position (0..1) as a world target { map, wx, wy, inst }, or nil when the client cannot place it.
function Nav.FromMap(map, x, y)
	local cont, world = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(x, y))
	if not (cont and world) then
		return nil
	end
	local north, west = world:GetXY()
	return { map = map, wx = west, wy = north, inst = ns.Util.Num(cont) }
end

-- Player world position: west, north, instance ID; nil in instances.
function Nav.Player()
	local north, west, _, inst = UnitPosition("player")
	if not north or not west then
		return nil
	end
	return west, north, inst
end

-- World angle from delta west/north, same convention as GetPlayerFacing (HereBeDragons).
function Nav.WorldAngle(dx, dy)
	local a = atan2(-dx, dy)
	if a > 0 then
		return PI2 - a
	end
	return -a
end

-- Distance (yards) and world angle to a target, or nil and the reason: "instance" (no position) or
-- "continent" (target on another continent or in another instance).
function Nav.Vector(t)
	local pw, pn, inst = Nav.Player()
	if not pw then
		return nil, "instance"
	end
	local cont = t.inst
	if cont == nil then
		cont = Nav.Continent(t.map) or false
		t.inst = cont
	end
	if not cont or cont ~= inst then
		return nil, "continent"
	end
	local dx, dy = t.wx - pw, t.wy - pn
	return sqrt(dx * dx + dy * dy), Nav.WorldAngle(dx, dy)
end

-- Rotation of the arrow texture and the deviation from the course in degrees (0..180).
function Nav.Relative(angle)
	local facing = GetPlayerFacing()
	if not facing or ns.Util.IsSecret(facing) then
		return nil
	end
	local rel = angle - facing
	local dev = abs(((rel + math.pi) % PI2) - math.pi)
	return rel, math.deg(dev)
end

-- Position of a target on a shown map (0..1), or nil when it does not fall on it.
function Nav.MapXY(t, map)
	local cont = t.inst
	if cont == nil then
		cont = Nav.Continent(t.map) or false
		t.inst = cont
	end
	if not cont then
		return nil
	end
	local _, pos = C_Map.GetMapPosFromWorldPos(cont, CreateVector2D(t.wy, t.wx), map)
	if not pos then
		return nil
	end
	local x, y = pos:GetXY()
	if not x or x < 0 or x > 1 or y < 0 or y > 1 then
		return nil
	end
	return x, y
end
