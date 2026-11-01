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

-- UI/Arrow.lua: module "arrow" (design v2, view 2). Atlas Navigation-Tracked-Arrow at 44x36 with a
-- black outline (same atlas, black, a bit larger), top center at y -140. Color after TomTom: green up to
-- 20 degrees, yellow at 90, red from 135 with the text "behind you" (decision PF-1101); blue, white,
-- orange with Blizzard's colorblind mode. Below: goal in one line (GameFontHighlight, width 220) and the
-- distance with Blizzard's IN_GAME_NAVIGATION_RANGE (GameFontNormal), at most five times per second.
-- Arrival at 12 yd (5..30): check atlas and "Reached destination", hidden after 1 s.
-- Cost: the direction (UnitPosition) is computed at most 20 times per second, the rotation (facing)
-- every frame from the last direction; nothing allocates in OnUpdate (concept §2.3, brain chapter 12).
-- No arrow in instances or on another continent (the step window says so). Not clickable outside Edit
-- Mode (rule P7); always fully opaque, so the minimum alpha 0.3 of P7 holds. With "use Blizzard navigation" and the CVar showInGameNavigation on,
-- Blizzard's own marker shows the way and this arrow hides (rule P8).
local _, ns = ...
local L, UI, T, Nav = ns.L, ns.UI, ns.Theme, ns.Nav
local M, Guard = ns.Modules, ns.Guard

local A = {
	SIZE_W = 44,
	SIZE_H = 36,
	OUTLINE = 4, -- outline atlas this many units larger; the screenshot in the test bed fixes the value
	COMPUTE_EVERY = 0.05, -- 20 per second
	TEXT_EVERY = 0.2, -- 5 per second
	ARRIVED_FOR = 1,
	CLEAR_EXTRA = 10, -- back to the arrow when the player walks this far past the arrival radius (TomTom)
	DEFAULT = { "TOP", 0, -140 },
}
ns.Arrow = A

local F -- frame
local target -- { map, wx, wy, title, inst }
local angle, dist -- last computed world angle and distance
local compAcc, textAcc = 0, 0
local shownYd
local arrivedAt, arrived

local function Build()
	F = CreateFrame("Frame", nil, UIParent)
	A.frame = F
	F:SetSize(A.SIZE_W, A.SIZE_H)
	F:SetFrameStrata("MEDIUM")
	F:EnableMouse(false)

	F.outline = F:CreateTexture(nil, "BACKGROUND")
	F.outline:SetPoint("CENTER")
	F.outline:SetSize(A.SIZE_W + A.OUTLINE, A.SIZE_H + A.OUTLINE)
	T.SetAtlas(F.outline, "arrow")
	F.outline:SetVertexColor(0, 0, 0, 1) -- black outline (concept §2.3)

	F.tex = F:CreateTexture(nil, "ARTWORK")
	F.tex:SetPoint("CENTER")
	F.tex:SetSize(A.SIZE_W, A.SIZE_H)
	T.SetAtlas(F.tex, "arrow")

	F.title = F:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	F.title:SetPoint("TOP", F, "BOTTOM", 0, -4)
	F.title:SetWidth(220)
	F.title:SetWordWrap(false)
	F.title:SetMaxLines(1)
	F.dist = F:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	F.dist:SetPoint("TOP", F.title, "BOTTOM", 0, -2)
	F.hint = F:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	F.hint:SetPoint("TOP", F.dist, "BOTTOM", 0, -2)

	F:SetScript("OnUpdate", function(_, elapsed)
		A.Update(elapsed)
	end)
	F:Hide()
	UI.Mover(F, "arrow", L.EDIT_ARROW, A.DEFAULT, false)
end

-- Should the arrow show at all (option, pause, Blizzard navigation)?
function A.Wanted()
	if not UI.Get("arrow") or UI.Paused() then
		return false
	end
	if UI.Get("blizzNav") and UI.CVar("showInGameNavigation") == "1" then
		return false
	end
	return true
end

local function ShowArrowLook()
	T.SetAtlas(F.tex, "arrow")
	F.outline:Show()
end

local function Visible()
	return target ~= nil and A.Wanted()
end

-- target: { map, wx, wy } from Nav.Target, or nil; info names the goal.
local function SetTargetNow(t, info)
	if A.extra then
		t = A.extra -- a revealed find (rumor "show location") leads until it is reached
	end
	if t and target and t.map == target.map and t.wx == target.wx and t.wy == target.wy then
		return
	end
	target = t
	if t then
		t.title = t.title or (info and ns.StepText.Step(info, false)) or ""
	end
	arrivedAt, arrived, shownYd, angle, dist = nil, false, nil, nil, nil
	compAcc, textAcc = A.COMPUTE_EVERY, A.TEXT_EVERY
	if not F then
		return
	end
	F.title:SetText(t and t.title or "")
	F.dist:SetText("")
	F.hint:SetText("")
	ShowArrowLook()
	A.Apply()
end

-- A target that is not a route step (revealed find); cleared on arrival.
function A.SetExtra(t)
	A.extra = t
	target = nil
	A.SetTarget(t)
end

function A.Apply()
	if not F then
		return
	end
	F:SetScale((UI.Get("scale") or 100) / 100)
	F:SetShown(Visible())
end

local function Arrive()
	arrived, arrivedAt = true, GetTime()
	T.SetAtlas(F.tex, "check")
	F.tex:SetVertexColor(1, 1, 1, 1)
	F.tex:SetRotation(0)
	F.outline:Hide()
	F.dist:SetText(NAVIGATION_DESTINATION_REACHED_MESSAGE or "")
	F.hint:SetText("")
	if A.extra then
		A.extra = nil
	end
end

-- One frame. Returns nothing; the work is in the frame's regions.
function A.Update(elapsed)
	if not target then
		return
	end
	if arrived then
		if arrivedAt and GetTime() - arrivedAt >= A.ARRIVED_FOR then
			arrivedAt = nil
			F.tex:SetAlpha(0)
			F.title:SetAlpha(0)
			F.dist:SetAlpha(0)
		end
	end
	compAcc = compAcc + elapsed
	if compAcc >= A.COMPUTE_EVERY then
		compAcc = 0
		local d, a = Nav.Vector(target)
		dist, angle = d, d and a or nil
		if not d then
			F.tex:SetAlpha(0)
			F.outline:SetAlpha(0)
			F.dist:SetText("")
			F.hint:SetText("")
			return
		end
		local radius = UI.Get("arrival") or 12
		if not arrived and d <= radius then
			Arrive()
			return
		elseif arrived and d > radius + A.CLEAR_EXTRA then
			arrived, arrivedAt = false, nil
			ShowArrowLook()
			F.tex:SetAlpha(1)
			F.title:SetAlpha(1)
			F.dist:SetAlpha(1)
		end
	end
	if arrived or not angle then
		return
	end
	local rel, dev = Nav.Relative(angle)
	if not rel then
		return
	end
	F.tex:SetAlpha(1)
	F.outline:SetAlpha(1)
	F.tex:SetRotation(rel)
	F.outline:SetRotation(rel)
	F.tex:SetVertexColor(T.ArrowColor(dev, A.colorblind))
	textAcc = textAcc + elapsed
	if textAcc >= A.TEXT_EVERY then
		textAcc = 0
		local yd = math.floor(dist + 0.5)
		if yd ~= shownYd then
			shownYd = yd
			F.dist:SetText(T.Distance(yd))
		end
		F.hint:SetText(dev >= T.BEHIND and L.BEHIND or "")
	end
end

-- For tests and the developer preview: a fixed direction and distance without a position.
function A.Demo(deg, yd)
	if not F then
		return
	end
	target = target or { map = 0, wx = 0, wy = 0, title = "" }
	F:Show()
	local rel = math.rad(deg)
	local dev = math.abs(((deg + 180) % 360) - 180)
	if yd and yd <= (UI.Get("arrival") or 12) then
		Arrive()
		return
	end
	ShowArrowLook()
	F.tex:SetAlpha(1)
	F.tex:SetRotation(rel)
	F.outline:SetRotation(rel)
	F.tex:SetVertexColor(T.ArrowColor(dev, A.colorblind))
	F.dist:SetText(T.Distance(yd or 38))
	F.hint:SetText(dev >= T.BEHIND and L.BEHIND or "")
end

local function Init()
	Build()
	A.colorblind = T.Colorblind()
	for _, key in ipairs({ "arrow", "paused", "blizzNav", "scale" }) do
		UI.OnChange(key, A, A.Apply)
	end
end

M.Define("arrow", {
	requires = {
		funcs = { "UnitPosition", "GetPlayerFacing", "C_Map.GetWorldPosFromMapPos", "CreateVector2D" },
	},
	optional = { events = { "CVAR_UPDATE" } },
	init = Init,
	events = {
		CVAR_UPDATE = function(_, _, name)
			name = type(name) == "string" and name:lower() or ""
			if name == "colorblindmode" then
				A.colorblind = T.Colorblind()
			elseif name == "showingamenavigation" then
				A.Apply()
			end
		end,
	},
})

-- The step window calls SetTarget; module off means no arrow.
function A.SetTarget(t, info)
	if M.IsActive("arrow") then
		Guard.Call("arrow", SetTargetNow, t, info)
	end
end
