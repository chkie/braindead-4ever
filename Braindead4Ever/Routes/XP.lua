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

-- Routes/XP.lua: experience rules for the XP balance (owner wish 9, 2026-11-01). Pure Lua, no WoW API.
-- Classic rules with one measured Forever change. WoW: Forever has no level scaling (Blizzard, brain
-- chapter 14 §2) and no announced change of the XP curve (chapter 14 §4.3), so the Classic values
-- are the starting assumption; every number derived here is shown as an estimate ("ca.") until the
-- probe checks xp.curve, xp.kill and xp.quest have measured them in the Forever client
-- (docs/STATUS.md).
-- Forever change: a creature below the character gives (5 * creature level + 45) reduced by the
-- level difference, not (5 * character level + 45) as in Classic. Measured in the beta (level 10
-- against level 5: 40 XP in Forever, 54 in Classic Era, both rested) and closed by a Blizzard
-- developer as "Not A Bug" on 2026-09-28: github.com/ClassicWoWCommunity/forever-bugs/issues/138;
-- confirmed by the Polestar maintainer in github.com/fitzforge/polestar/issues/30 (brain chapter 06
-- §8, report DR 22b). Creatures at or above the character's level are unchanged (none measured).
-- tools/routekit/xp.py computes the same rules; tools/tests/fixtures/xp_cases.json holds the cases
-- both must agree on.
-- Sources (read 2026-11-01): warcraft.wiki.gg "Experience to level" (Vanilla / Classic table),
-- "Mob experience" (zero difference), "Experience point" (quest XP by level difference);
-- cross-checked against cmangos/mangos-classic src/game/Tools/Formulas.h (namespace XP: BaseGain,
-- GetZeroDifference, IsTrivialLevelDifference).
local _, ns = ...

local XP = {}
ns.XP = XP

-- XP from level n to n + 1, levels 1 to 59. Sum 4,084,700 (warcraft.wiki.gg).
XP.TO_LEVEL = {
	400,
	900,
	1400,
	2100,
	2800,
	3600,
	4500,
	5400,
	6500,
	7600, -- 1-10
	8800,
	10100,
	11400,
	12900,
	14400,
	16000,
	17700,
	19400,
	21300,
	23200, -- 11-20
	25200,
	27300,
	29400,
	31700,
	34000,
	36400,
	38900,
	41400,
	44300,
	47400, -- 21-30
	50800,
	54500,
	58600,
	62800,
	67100,
	71600,
	76100,
	80800,
	85700,
	90700, -- 31-40
	95800,
	101000,
	106300,
	111800,
	117500,
	123200,
	129100,
	135100,
	141200,
	147500, -- 41-50
	153900,
	160400,
	167100,
	173900,
	180800,
	187900,
	195000,
	202300,
	209800, -- 51-59
}

local function round(x)
	return math.floor(x + 0.5)
end

-- Levels below the character at which a creature gives no XP any more (green range).
local function Trivial(level, mobLevel)
	if mobLevel >= level then
		return false
	end
	local band = math.floor(level / 5)
	local range = band <= 1 and 4 or band <= 3 and 5 or band <= 5 and 6 or band <= 7 and 7 or math.min(band, 12)
	return level - mobLevel > range
end

-- Zero difference: the level gap at which kill XP would reach zero.
function XP.ZeroDiff(level)
	if level < 8 then
		return 5
	elseif level < 10 then
		return 6
	elseif level < 12 then
		return 7
	elseif level < 16 then
		return 8
	elseif level < 20 then
		return 9
	elseif level < 30 then
		return 11
	elseif level < 40 then
		return 12
	elseif level < 45 then
		return 13
	elseif level < 50 then
		return 14
	elseif level < 55 then
		return 15
	elseif level < 60 then
		return 16
	end
	return 17
end

-- XP for a solo kill. Creature at or above the character: character level * 5 + 45 (Azeroth),
-- +5 % per level above, at most +4 levels. Creature below (Forever, forever-bugs #138): creature
-- level * 5 + 45, linearly down to zero at the zero difference. Elite doubles.
function XP.KillXP(level, mobLevel, elite)
	mobLevel = mobLevel or level
	local xp
	if mobLevel >= level then
		xp = (level * 5 + 45) * (1 + 0.05 * math.min(mobLevel - level, 4))
	elseif Trivial(level, mobLevel) then
		return 0
	else
		xp = (mobLevel * 5 + 45) * (1 - (level - mobLevel) / XP.ZeroDiff(level))
	end
	if elite then
		xp = xp * 2
	end
	return round(xp)
end

-- Quest XP: full up to quest level + 5, then 80, 60, 40, 20 and 10 %, rounded to a multiple of 5.
local REDUCED = { [6] = 0.8, [7] = 0.6, [8] = 0.4, [9] = 0.2 }
function XP.QuestXP(full, questLevel, level)
	if not full or full <= 0 then
		return 0
	end
	local diff = level - (questLevel or level)
	if diff <= 5 then
		return full
	end
	return round(full * (REDUCED[diff] or 0.1) / 5) * 5
end

-- XP from the current state (level, xp of xpMax) to the start of level target. nil when the table
-- has no value for a level in between (level 60 and above).
function XP.Needed(level, xp, xpMax, target)
	if not target or target <= level then
		return 0
	end
	local need = math.max(0, xpMax - xp)
	for l = level + 1, target - 1 do
		local step = XP.TO_LEVEL[l]
		if not step then
			return nil
		end
		need = need + step
	end
	return need
end

-- Kills of creatures at the character's level for need XP. Rested kills give double and use up the
-- rested pool by the XP they give (brain chapter 06 §8). Returns kills and XP per normal kill.
function XP.Kills(need, level, rested)
	local per = XP.KillXP(level, level)
	if not need or need <= 0 or per <= 0 then
		return 0, per
	end
	local restedPart = math.min(need, math.max(0, rested or 0))
	local kills = math.ceil(restedPart / (2 * per))
	return kills + math.ceil((need - restedPart) / per), per
end
