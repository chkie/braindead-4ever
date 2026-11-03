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

-- UI/MapPins.lua: module "mappins" (design v2, view 2 "Karte"): the second channel next to the arrow.
-- World map: Blizzard's own symbols only (owner reading 7): Waypoint-MapPin-Tracked for the current
-- goal, QuestNormal for quest givers and QuestTurnin for turn-ins of the current and the next steps;
-- discovery items of Welle 4 through ns.Connect (own finds with a check, revealed finds as a pin).
-- Hint level 2 (Welle 5b): the area of a find as a circle in Blizzard's atlases (gold ring of the
-- scouting map over a faint gold disc), sized in map units and scaling with the terrain, tooltip "Area"
-- with one sentence like design v2 view 4; hover only, clicks go through to the map.
-- Minimap: Waypoint-MapPin-Minimap-Tracked for the goal, off by default ("Standard" scope).
-- Pins without an XML template: own pool in WorldMapFrame.pinPools like HereBeDragons-Pins (brain
-- chapter 07 §4, pattern E). Blizzard's user waypoint is only set with "use Blizzard navigation", so
-- the player's own waypoint stays untouched otherwise; setting it waits for the end of a fight
-- (protection of SetSuperTrackedUserWaypoint in Forever unconfirmed, chapter 07 §3).
local ADDON, ns = ...
local UI, T, C, Nav, R = ns.UI, ns.Theme, ns.Connect, ns.Nav, ns.Routes
local M, Guard = ns.Modules, ns.Guard
local V = R.VERB

local P = {
	TEMPLATE = ADDON .. "PinTemplate",
	SIZE = { pin = 30, giver = 28, turnin = 22, check = 19 },
	AREA_ALPHA = 0.18, -- the gold disc under the ring (chosen value)
	MINI_SIZE = 20,
	MINI_EVERY = 0.1,
}
ns.MapPins = P

local points = {} -- world points: { map, wx, wy, kind, title }
local provider
local mini -- minimap pin frame

-- Points ----------------------------------------------------------------------------------------------

local function Goto(info)
	return Nav.Target(info)
end

local function Add(t, kind, title)
	if t then
		points[#points + 1] = { map = t.map, wx = t.wx, wy = t.wy, kind = kind, title = title }
	end
end

-- Current goal, givers and turn-ins of the current and the next steps, a revealed find.
function P.Collect()
	for i = #points, 1, -1 do
		points[i] = nil
	end
	local cur = C.Current()
	if not cur then
		return points
	end
	local list = { cur }
	for _, n in ipairs(C.Upcoming(UI.Get("ahead") or 3)) do
		list[#list + 1] = n
	end
	for i, info in ipairs(list) do
		local t = Goto(info)
		if t then
			local title = (ns.StepText.Step(info, false))
			if i == 1 then
				Add(t, "pin", title)
			end
			for _, el in ipairs(info.step or {}) do
				if el[1] == V.ACCEPT then
					Add(t, "giver", title)
					break
				elseif el[1] == V.TURNIN then
					Add(t, "turnin", title)
					break
				end
			end
		end
	end
	if P.revealed then
		Add(P.revealed, "pin", P.revealed.title)
	end
	return points
end

function P.Points()
	return points
end

-- World map provider -----------------------------------------------------------------------------------

local function PinMixin()
	local Pin = CreateFromMixins(MapCanvasPinMixin)
	function Pin:OnLoad()
		self.Fill = self:CreateTexture(nil, "BACKGROUND")
		self.Fill:SetAllPoints()
		self.Icon = self:CreateTexture(nil, "ARTWORK")
		self.Icon:SetAllPoints()
		self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	end
	-- area = { rx, ry, text } for kind "area" (radii in map units 0..1)
	function Pin:OnAcquired(x, y, kind, title, area)
		self.kind, self.title, self.text = kind, title, area and area.text
		local isArea = kind == "area" and area ~= nil
		if self.SetIgnoreGlobalPinScale then -- an area scales with the terrain, a symbol keeps its size
			self:SetIgnoreGlobalPinScale(isArea)
		end
		if isArea then
			local canvas = self:GetMap():GetCanvas()
			self:SetSize((canvas:GetWidth() or 0) * area.rx * 2, (canvas:GetHeight() or 0) * area.ry * 2)
			self:SetScale(1)
			T.SetAtlas(self.Fill, "areafill")
			self.Fill:SetVertexColor(T.RGB(NORMAL_FONT_COLOR))
			self.Fill:SetAlpha(P.AREA_ALPHA)
			self.Fill:Show()
		else
			local size = P.SIZE[kind] or 24
			self:SetSize(size, size)
			self.Fill:Hide()
		end
		T.SetAtlas(self.Icon, kind)
		self:SetPosition(x, y)
	end
	-- The map wires OnEnter/OnLeave itself to these mixin methods (brain chapter 07 §4).
	function Pin:OnMouseEnter()
		if self.title and self.title ~= "" then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if self.text then
				GameTooltip:SetText(self.title, T.RGB(NORMAL_FONT_COLOR))
				GameTooltip:AddLine(self.text, 1, 1, 1, true)
			else
				GameTooltip:SetText(self.title, T.RGB(HIGHLIGHT_FONT_COLOR))
			end
			GameTooltip:Show()
		end
	end
	function Pin:OnMouseLeave()
		GameTooltip:Hide()
	end
	Pin.SetPassThroughButtons = function() end -- HereBeDragons workaround against a combat error
	return Pin
end

local function SetupMap()
	if provider or not WorldMapFrame then
		return false
	end
	local Pin = PinMixin()
	-- Pool as in HereBeDragons-Pins (brain chapter 07 pattern E): own pool under an own name, so
	-- AcquirePin does not look for an XML template of that name.
	local pool = CreateUnsecuredRegionPoolInstance and CreateUnsecuredRegionPoolInstance(P.TEMPLATE)
		or CreateFramePool("FRAME")
	pool.parent = WorldMapFrame:GetCanvas()
	pool.createFunc = function()
		local f = CreateFrame("Frame", nil, WorldMapFrame:GetCanvas())
		-- The map wires OnEnter/OnLeave to OnMouseEnter/OnMouseLeave only for a new pin that already takes
		-- mouse motion (MapCanvasMixin:AcquirePin, Blizzard_MapCanvas.lua forever); clicks go through.
		f:SetMouseMotionEnabled(true)
		f:SetMouseClickEnabled(false)
		return Mixin(f, Pin)
	end
	pool.resetFunc = function(_, pin)
		pin:Hide()
		pin:ClearAllPoints()
		pin.pinTemplate, pin.owningMap = nil, nil
	end
	pool.creationFunc, pool.resetterFunc = pool.createFunc, pool.resetFunc -- names before 11.x
	WorldMapFrame.pinPools[P.TEMPLATE] = pool

	provider = CreateFromMixins(MapCanvasDataProviderMixin)
	function provider:RemoveAllData()
		self:GetMap():RemoveAllPinsByTemplate(P.TEMPLATE)
	end
	function provider:RefreshAllData()
		Guard.Call("mappins", P.Draw, self:GetMap())
	end
	WorldMapFrame:AddDataProvider(provider)
	P.provider = provider
	return true
end

-- Draws every point that falls on the shown map.
function P.Draw(map)
	map:RemoveAllPinsByTemplate(P.TEMPLATE)
	if not UI.Get("pins") or UI.Paused() then
		return
	end
	local shown = map:GetMapID()
	if not shown then
		return
	end
	for _, p in ipairs(points) do
		local x, y = Nav.MapXY(p, shown)
		if x then
			map:AcquirePin(P.TEMPLATE, x, y, p.kind, p.title)
		end
	end
	local items = C.MapItems(shown)
	for _, item in ipairs(items) do -- areas first, so the symbols lie on top
		if item.kind == "area" and item.x and item.y then
			map:AcquirePin(P.TEMPLATE, item.x, item.y, "area", item.title, item)
		end
	end
	for _, item in ipairs(items) do
		if item.kind ~= "area" and item.x and item.y then
			map:AcquirePin(P.TEMPLATE, item.x, item.y, item.kind == "own" and "check" or "pin", item.title)
		end
	end
end

-- Minimap -----------------------------------------------------------------------------------------------

local function MiniShown()
	return UI.Get("pins") and UI.Get("minipins") and not UI.Paused() and points[1] ~= nil
end

local miniAcc = 0
local function MiniUpdate(_, elapsed)
	miniAcc = miniAcc + elapsed
	if miniAcc < P.MINI_EVERY then
		return
	end
	miniAcc = 0
	local goal = points[1]
	local pw, pn, inst = Nav.Player()
	local cont = goal and (goal.inst or Nav.Continent(goal.map))
	if not goal or not pw or cont ~= inst then
		mini.tex:SetAlpha(0)
		return
	end
	goal.inst = cont
	local radius = (C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()) or 233
	local dx, dy = (pw - goal.wx) / radius, (pn - goal.wy) / radius
	if UI.CVar("rotateMinimap") == "1" then
		local f = GetPlayerFacing() or 0
		local c, s = math.cos(f), math.sin(f)
		dx, dy = dx * c - dy * s, dx * s + dy * c
	end
	local d2 = dx * dx + dy * dy
	if d2 > 0.81 then -- float on the round edge
		local k = 0.9 / math.sqrt(d2)
		dx, dy = dx * k, dy * k
	end
	local w, h = Minimap:GetWidth() or 140, Minimap:GetHeight() or 140
	mini:ClearAllPoints()
	mini:SetPoint("CENTER", Minimap, "CENTER", dx * w / 2, -dy * h / 2)
	mini.tex:SetAlpha(1)
end

local function SetupMini()
	if mini or not Minimap then
		return
	end
	mini = CreateFrame("Frame", nil, Minimap)
	mini:SetSize(P.MINI_SIZE, P.MINI_SIZE)
	mini.tex = mini:CreateTexture(nil, "OVERLAY")
	mini.tex:SetAllPoints()
	T.SetAtlas(mini.tex, "minipin")
	mini:SetScript("OnUpdate", MiniUpdate)
	mini:Hide()
	P.mini = mini
end

-- Blizzard navigation ----------------------------------------------------------------------------------

function P.BlizzardWaypoint()
	local goal = points[1]
	UI.OutOfCombat("waypoint", function()
		if not (UI.Get("blizzNav") and goal and not UI.Paused()) then
			if P.ownWaypoint and C_Map.ClearUserWaypoint then
				C_Map.ClearUserWaypoint()
			end
			P.ownWaypoint = nil
			return
		end
		if not (C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(goal.map)) then
			return
		end
		local x, y = Nav.MapXY(goal, goal.map)
		if not x then
			return
		end
		local point = UiMapPoint.CreateFromCoordinates(goal.map, x, y)
		if C_Map.SetUserWaypoint(point) ~= false then
			P.ownWaypoint = true
			if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
				C_SuperTrack.SetSuperTrackedUserWaypoint(true)
			end
		end
	end)
end

-- Refresh -----------------------------------------------------------------------------------------------

function P.Refresh()
	if not M.IsActive("mappins") then
		return
	end
	Guard.Call("mappins", function()
		P.Collect()
		if provider then
			provider:RefreshAllData()
		end
		if mini then
			mini:SetShown(MiniShown())
		end
		P.BlizzardWaypoint()
	end)
end

-- "Show location" of a rumor: this one find as a pin (design v2, view 4).
function P.Reveal(t)
	P.revealed = t
	P.Refresh()
end

local function Init()
	SetupMap()
	SetupMini()
	for _, key in ipairs({ "pins", "minipins", "paused", "ahead", "blizzNav", "hint", "style" }) do
		UI.OnChange(key, P, P.Refresh)
	end
	C.OnFinds(P, function()
		P.Refresh()
	end)
end

M.Define("mappins", {
	requires = {
		funcs = { "C_Map.GetMapPosFromWorldPos", "C_Map.GetWorldPosFromMapPos", "CreateVector2D", "CreateFromMixins" },
	},
	optional = {
		funcs = {
			"CreateFramePool",
			"CreateUnsecuredRegionPoolInstance",
			"C_Minimap.GetViewRadius",
			"C_Map.CanSetUserWaypointOnMap",
			"C_Map.SetUserWaypoint",
			"C_Map.ClearUserWaypoint",
			"C_SuperTrack.SetSuperTrackedUserWaypoint",
			"UiMapPoint.CreateFromCoordinates",
		},
		events = { "ADDON_LOADED" },
	},
	init = Init,
	events = {
		ADDON_LOADED = function(_, _, name)
			if name == "Blizzard_WorldMap" and SetupMap() then
				P.Refresh()
			end
		end,
	},
})
