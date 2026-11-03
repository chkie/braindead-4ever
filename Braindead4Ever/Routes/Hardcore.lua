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

-- Routes/Hardcore.lua: the rule of the hardcore-safe mode (requirement A18, plan "Spielmodi"). Plain
-- Lua, no WoW API. It uses only data that exists: the quest level of the route data (`quests`, Polestar
-- and EG Link) and the elite mark of the client (C_QuestLog.IsEliteQuest, Forever only). It invents no
-- danger values: no enemy levels, no damage, no death rates. The routes hold no quest that Polestar types
-- as elite or group, dungeon, raid or PvP (data/facts "type"; checked in spec/route_hardcore_spec.lua);
-- the mode warns where the client still marks a route quest elite or a quest lies too far above the
-- character, and the step window hides the optional dungeon step (UI/Connect.lua).
local _, ns = ...

local H = {
	-- Chosen value, not measured: a quest more than GAP levels above the character is too high. Blizzard
	-- colors a quest orange ("very difficult") from 3 levels above the player and red from 5
	-- (DifficultyUtil.GetRelativeDifficultyColor, wow-ui-source forever aff0d8c); the mode warns from
	-- orange on.
	GAP = 2,
}
ns.Hardcore = H

-- The quests a step sends the player to: accept and complete, not the turn-in. els: the step's
-- elements for this character (Routes/Runtime.lua s.els), V: verb codes (ns.Routes.VERB).
function H.Quests(els, V)
	local out, seen = {}, {}
	for _, el in ipairs(els or {}) do
		local v, q = el[1], el[2]
		if (v == V.ACCEPT or v == V.COMPLETE) and not seen[q] then
			seen[q] = true
			out[#out + 1] = q
		end
	end
	return out
end

-- Danger of a step: { quest = q, elite = true } for a quest the client marks elite, else
-- { quest = q, gap = n, level = l } for the quest furthest above the character beyond GAP, else nil.
-- quests: quest IDs; facts: { [q] = { level, ... } } (0 = unknown level, never a warning);
-- isElite(q): the client's mark or nil.
function H.Check(quests, facts, level, isElite)
	local worst
	for _, q in ipairs(quests) do
		if isElite and isElite(q) == true then
			return { quest = q, elite = true }
		end
		local f = facts and facts[q]
		local ql = f and tonumber(f[1]) or 0
		local gap = ql > 0 and ql - (level or 1) or 0
		if gap > H.GAP and (not worst or gap > worst.gap) then
			worst = { quest = q, gap = gap, level = ql }
		end
	end
	return worst
end
