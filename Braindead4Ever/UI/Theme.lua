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

-- UI/Theme.lua: Blizzard look for every window (design v2, brain chapter 18 §1, rules N1 to N7).
-- Graphics only from atlases, each checked with C_Texture.GetAtlasInfo (a missing one gets a neutral
-- surface and a line in the problem report). Fonts are copies of Blizzard font objects, so they keep
-- Friz Quadrata and the alphabet members for Cyrillic, Korean and Chinese; the addon ships no font.
-- Colors come from Blizzard's constants at runtime; the arrow gradient is the only own color set
-- (owner reading point 5, decision PF-1101).
local _, ns = ...
local UI = ns.UI

local T = { missing = {}, fonts = {} }
ns.Theme = T

-- Every name is in the Forever atlas inventory (Ketho BlizzardInterfaceResources, branch forever,
-- 1.60.1/70532, checked 2026-11-01).
T.ATLAS = {
	header = "UI-QuestTracker-Primary-Objective-Header", -- 300x40
	nub = "UI-QuestTracker-Objective-Nub", -- 19x19
	check = "UI-QuestTracker-Tracker-Check", -- 19x19
	fail = "UI-QuestTracker-Objective-Fail", -- 19x19
	collapse = "UI-QuestTrackerButton-Collapse-All", -- 18x19
	expand = "UI-QuestTrackerButton-Expand-All",
	glow = "OBJFX_LineGlow", -- 230x22
	box = "checkbox-minimal", -- 30x29, shown at 19x19 in place of the nub
	tick = "checkmark-minimal",
	clock = "auctionhouse-icon-clock", -- "provisional" symbol, candidate of concept §2.2
	pin = "Waypoint-MapPin-Tracked", -- 30x30
	minipin = "Waypoint-MapPin-Minimap-Tracked", -- 32x32
	giver = "QuestNormal", -- 64x64
	turnin = "QuestTurnin", -- 32x32
	-- hint steps (A35): the minimap tracking symbols, 32x32 each (AtlasInfo forever)
	trainer = "Class",
	innkeeper = "Innkeeper",
	flightmaster = "FlightMaster",
	-- hint level 2 on the map (Welle 5b): gold ring of Blizzard's scouting map and a white disc tinted gold
	area = "UI-prey-Scoutingmap-ring", -- 37x37 (74x74 high resolution)
	areafill = "common-mask-circle", -- 256x256
}

-- Sets an atlas after checking it; without it a neutral surface. Returns true if the atlas exists.
function T.SetAtlas(tex, key, useAtlasSize)
	local name = T.ATLAS[key] or key
	if C_Texture.GetAtlasInfo(name) then
		tex:SetAtlas(name, useAtlasSize)
		return true
	end
	T.missing[name] = true
	tex:SetColorTexture(1, 1, 1, 0.15)
	return false
end

-- Lines for the problem report (Core/Report.lua).
function T.ReportLines()
	local names = {}
	for name in pairs(T.missing) do
		names[#names + 1] = name
	end
	table.sort(names)
	if #names == 0 then
		return {}
	end
	return { "Missing atlases: " .. table.concat(names, ", ") }
end

-- Fonts -------------------------------------------------------------------------------------------

-- Own font objects as copies (CreateFont + CopyFontObject). Sizes at 100 %: header 14, current step
-- 15, details and next steps 13, smallest 12 (owner reading point 2). Fallbacks as in concept §2.1.
-- The global font names keep the internal prefix, not the folder name (CONTRIBUTING.md, no new globals).
local FONT_PREFIX = "BraindeadForever"
T.FONT_DEFS = {
	header = {
		name = FONT_PREFIX .. "FontHeader",
		base = "ObjectiveTrackerHeaderFont",
		fallback = "GameFontNormalMed3",
		size = 14,
	},
	step = {
		name = FONT_PREFIX .. "FontStep",
		base = "ObjectiveTrackerFont15",
		fallback = "GameFontHighlight",
		size = 15,
	},
	line = {
		name = FONT_PREFIX .. "FontLine",
		base = "ObjectiveTrackerFont13",
		fallback = "GameFontHighlight",
		size = 13,
	},
	small = {
		name = FONT_PREFIX .. "FontSmall",
		base = "ObjectiveTrackerFont12",
		fallback = "GameFontHighlight",
		size = 12,
	},
	status = { name = FONT_PREFIX .. "FontStatus", base = "GameFontNormal", fallback = "GameFontHighlight", size = 12 },
}

function T.BuildFonts()
	for key, def in pairs(T.FONT_DEFS) do
		if not T.fonts[key] then
			local obj = _G[def.name] or CreateFont(def.name)
			local base = _G[def.base] or _G[def.fallback]
			if base then
				obj:CopyFontObject(base)
			end
			T.fonts[key] = obj
		end
	end
	T.ApplyFontScale()
end

-- Blizzard's text size (userFontScale, minimum 0.8 like TextSizeManager) or 1. The window size slider
-- scales the frames with SetScale, so the fonts only take the text size: no double scaling
-- (brain chapter 18 §5.2).
function T.TextScale()
	if not UI.Get("textSize") then
		return 1
	end
	local v = tonumber(UI.CVar("userFontScale") or "")
	return math.max(v or 1, 0.8)
end

function T.ApplyFontScale()
	local s = T.TextScale()
	for key, obj in pairs(T.fonts) do
		obj:SetFontHeight(math.floor(T.FONT_DEFS[key].size * s + 0.5))
	end
	T.fontScale = s
end

function T.Font(key)
	return T.fonts[key] or _G[T.FONT_DEFS[key].fallback]
end

-- Colors ------------------------------------------------------------------------------------------

-- r, g, b of a Blizzard color; white when the constant is missing in a client.
function T.RGB(color)
	if color and color.GetRGB then
		return color:GetRGB()
	end
	return 1, 1, 1
end

function T.Tracker(which)
	local c = OBJECTIVE_TRACKER_COLOR and OBJECTIVE_TRACKER_COLOR[which]
	if c then
		return c.r, c.g, c.b
	end
	if which == "Failed" then
		return T.RGB(DIM_RED_FONT_COLOR)
	end
	local v = which == "Complete" and 0.6 or 0.8
	return v, v, v
end

-- Text in a Blizzard color via the color's own escape (no RGB literal in the code, rule N4).
function T.Wrap(color, text)
	if color and color.WrapTextInColorCode then
		return color:WrapTextInColorCode(text)
	end
	return text
end

-- Arrow gradient after TomTom v4.3.13 (goodcolor 0/1/0, middlecolor 1/1/0, badcolor 1/0/0): green up to
-- 20 degrees, to yellow at 90, to red at 135, red beyond. Colorblind mode: blue, white, orange
-- (concept §2.3, GAG). Returns r, g, b without creating a table.
local PAL = {
	normal = { 0, 1, 0, 1, 1, 0, 1, 0, 0 },
	colorblind = { 0.2, 0.6, 1, 1, 1, 1, 1, 0.5, 0 },
}
T.ARROW_PALETTE = PAL
T.ON_COURSE = 20
T.MIDDLE = 90
T.BEHIND = 135

local function mix(p, a, b, k)
	return p[a] + (p[b] - p[a]) * k, p[a + 1] + (p[b + 1] - p[a + 1]) * k, p[a + 2] + (p[b + 2] - p[a + 2]) * k
end

-- deviation in degrees, 0..180
function T.ArrowColor(deviation, colorblind)
	local p = colorblind and PAL.colorblind or PAL.normal
	if deviation <= T.ON_COURSE then
		return p[1], p[2], p[3]
	elseif deviation <= T.MIDDLE then
		return mix(p, 1, 4, (deviation - T.ON_COURSE) / (T.MIDDLE - T.ON_COURSE))
	elseif deviation < T.BEHIND then
		return mix(p, 4, 7, (deviation - T.MIDDLE) / (T.BEHIND - T.MIDDLE))
	end
	return p[7], p[8], p[9]
end

function T.Colorblind()
	return UI.CVar("colorblindMode") == "1"
end

-- Numbers and distances ---------------------------------------------------------------------------

-- 12345 -> "12.345" (deDE) or "12,345" with Blizzard's own grouping when the client has it.
function T.Number(n)
	n = math.floor((n or 0) + 0.5)
	if BreakUpLargeNumbers then
		return BreakUpLargeNumbers(n)
	end
	local s = tostring(math.abs(n))
	local sep = GetLocale() == "deDE" and "." or ","
	local out = s:reverse():gsub("(%d%d%d)", "%1" .. sep):reverse():gsub("^%" .. sep, "")
	return (n < 0 and "-" or "") .. out
end

-- Yards with Blizzard's own format: deDE "%s |4m" (the value stays yards), enUS "%s |4yd:yds". A |4
-- code without a colon lost its word in the client: "48" without "m" in every German screenshot of
-- design stage 2 (Welle 5d, Q2). Such a code becomes the plain word; "|4yd:yds" stays for the client.
local rangeFormat, rangeSource
local function RangeFormat()
	local fmt = IN_GAME_NAVIGATION_RANGE or "%s yd"
	if fmt ~= rangeSource then
		rangeSource = fmt
		rangeFormat = fmt:find("|4[^:;]*$") and fmt:gsub("|4([^:;]*)$", "%1") or fmt
	end
	return rangeFormat
end

function T.Distance(yd)
	yd = math.floor(yd + 0.5)
	local s = tostring(yd)
	if yd >= 1000 and AbbreviateNumbers then
		s = AbbreviateNumbers(yd)
	end
	return RangeFormat():format(s)
end

-- Sound ---------------------------------------------------------------------------------------------

-- One game sound; never in combat, and the "sound on completed step" option decides for kit "done".
function T.Play(kit, isOption)
	if UI.Fighting() or not SOUNDKIT or not PlaySound then
		return false
	end
	if not isOption and not UI.Get("sound") then
		return false
	end
	local id = SOUNDKIT[kit]
	if not id then
		return false
	end
	PlaySound(id)
	return true
end
