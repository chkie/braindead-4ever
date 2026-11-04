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

-- UI/QuestItem.lua: module "questitem" (M8), the quest item button of the step window. When a quest of
-- the current step has a quest item (GetQuestLogSpecialItemInfo; shown like Blizzard's quest tracker:
-- an item, and the quest not complete or the item kept for complete quests, QuestUtil.
-- QuestShowsItemByIndex), the window shows a button with its icon, charges, cooldown and the range dot
-- of Blizzard's tracker (QuestObjectiveItemButtonTemplate and QuestObjectiveItemButtonMixin,
-- Blizzard_ObjectiveTrackerShared.xml/.lua, wow-ui-source forever 1.60.1). A click or the key binding
-- "Use quest item" (Bindings.xml, CLICK binding) uses the item through a secure action button with
-- type "item" (brain chapter 05 §5 and §9, Muster B); UseQuestLogSpecialItem stays Blizzard's.
-- Combat rule (brain chapter 05 §3): the button is protected, so its attribute, place, size and
-- visibility change only out of combat (UI.OutOfCombat, one job, the last state wins); in a fight the
-- item set last stays usable. It hangs on UIParent, never on the step window: out of combat it is
-- anchored to the window, and when a fight starts (PLAYER_REGEN_DISABLED, before the lockdown) it is
-- pinned to the same spot on UIParent. Otherwise the window would become protected with it (a frame a
-- protected frame is anchored to may not move, size or hide in a fight) and could not lay out its text.
-- Icon, count, cooldown and range dot are no protected changes and follow at any time.
local _, ns = ...
local L, UI, T, U, R = ns.L, ns.UI, ns.Theme, ns.Util, ns.Routes
local M, Guard = ns.Modules, ns.Guard
local V = R.VERB

local QI = {
	NAME = "BraindeadForeverQuestItemButton",
	SIZE = 26, -- QuestObjectiveItemButtonTemplate
	RING = 42, -- the frame atlas as Blizzard draws it (NormalTexture 42x42)
	GAP = 4, -- between the ring and the step text
	RANGE_EVERY = 0.2, -- TOOLTIP_UPDATE_TIME (Blizzard_SharedXML/SharedConstants.lua forever)
	DARK = 0.4, -- icon while the item cools down (QuestObjectiveItemButtonMixin:UpdateCooldown)
}
QI.BINDING = "CLICK " .. QI.NAME .. ":LeftButton"
-- Room the step text leaves at the right: button, the ring's overhang, gap.
QI.ROOM = QI.SIZE + (QI.RING - QI.SIZE) / 2 + QI.GAP
ns.QuestItem = QI

-- Name on Blizzard's key binding page, set when the file loads (UI/Bindings.lua does the same).
_G["BINDING_NAME_" .. QI.BINDING] = L.BINDING_QUESTITEM

local B -- the button
local applied -- the item the button holds: { quest, id, link, icon, charges }
local attached = false -- anchored to the step window (only out of combat)
local anchor = {} -- last anchor: top, scale
local demo -- developer preview: a fixed item, no attribute

local function Window()
	local sf = ns.StepFrame
	return sf and sf.frame and M.IsActive("window") and sf or nil
end

-- Is the step window up? Paused or switched off by key, the button goes too.
local function Visible()
	local sf = Window()
	return sf ~= nil and not UI.Paused() and not sf.hidden
end

-- The quest item of a step: the first quest of the step in the log with an item Blizzard's tracker
-- would show. Nil without one.
function QI.Find(info)
	local step = info and info.step
	if not step then
		return nil
	end
	for _, el in ipairs(step) do
		local v = el[1]
		if v == V.ACCEPT or v == V.COMPLETE or v == V.TURNIN then
			local q = el[2]
			local idx = U.Num(C_QuestLog.GetLogIndexForQuestID(q))
			if idx then
				local link, icon, charges, always = GetQuestLogSpecialItemInfo(idx)
				link = U.Str(link)
				local id = link and tonumber(link:match("item:(%d+)"))
				if id and (always == true or not C_QuestLog.IsComplete(q)) then
					return { quest = q, id = id, link = link, icon = icon, charges = U.Num(charges) }
				end
			end
		end
	end
	return nil
end

-- What the button should hold now.
local function Want()
	if not Visible() then
		return nil
	end
	if demo then
		return demo
	end
	return QI.Find(ns.Connect.Current())
end

-- Room the step text leaves for the button (UI/StepFrame.lua lays out with it): when the button is
-- wanted or still stands there (in a fight it stays until the fight ends).
function QI.Room()
	if not B or not M.IsActive("questitem") then
		return 0
	end
	QI.want = Want()
	return (QI.want or B:IsShown()) and QI.ROOM or 0
end

-- Log index of the quest the button holds, nil when it left the log.
local function Index()
	local q = applied and applied.quest
	return q and U.Num(C_QuestLog.GetLogIndexForQuestID(q)) or nil
end

local function SetRGB(region, color, r, g, b)
	if color and color.GetRGB then
		region:SetVertexColor(color:GetRGB())
	else
		region:SetVertexColor(r, g, b)
	end
end

-- Key text of the binding, or Blizzard's range dot (ActionButtonMixin:UpdateHotkeys).
function QI.HotKey()
	local key = GetBindingKey(QI.BINDING)
	-- (key, 1) as Blizzard's action buttons call it (Blizzard_ActionBar/Shared/ActionButton.lua forever);
	-- the pinned annotations know only (key, prefix, abbreviate)
	---@diagnostic disable-next-line: param-type-mismatch
	local text = key and U.Str(GetBindingText(key, 1)) or nil
	QI.keyText = text
	B.hotkey:SetText(text or RANGE_INDICATOR or L.BULLET)
end

-- Range like Blizzard's tracker: IsQuestLogSpecialItemInRange 0 = too far (red), 1 = in range, nil =
-- the item has no range. Asked only out of combat: whether addon code may call it in a fight is open
-- (probe check qitem.range, brain chapter 05 §4 for C_Item.IsItemInRange); in a fight the dot goes and
-- a key text stays in its normal color. Colorblind mode adds a second channel: the icon turns gray
-- while too far (design rule B3).
function QI.Range()
	if not B or not applied then
		return
	end
	local idx = Index()
	local valid
	if idx and not demo and not InCombatLockdown() then
		valid = U.Num(IsQuestLogSpecialItemInRange(idx))
	elseif demo then
		valid = demo.range
	end
	QI.range = valid
	local far = valid == 0
	if QI.keyText then
		B.hotkey:Show()
		if far then
			SetRGB(B.hotkey, RED_FONT_COLOR, 1, 0.1, 0.1)
		else
			SetRGB(B.hotkey, ACTIONBAR_HOTKEY_FONT_COLOR, 0.6, 0.6, 0.6)
		end
	elseif valid == nil then
		B.hotkey:Hide()
	else
		B.hotkey:Show()
		if far then
			SetRGB(B.hotkey, RED_FONT_COLOR, 1, 0.1, 0.1)
		else
			B.hotkey:SetVertexColor(0.6, 0.6, 0.6)
		end
	end
	B.icon:SetDesaturated(far and T.Colorblind() or false)
end

-- Cooldown (QuestObjectiveItemButtonMixin:UpdateCooldown).
function QI.Cooldown()
	if not B or not applied then
		return
	end
	local idx = Index()
	local start, duration, enable
	if idx and not demo then
		start, duration, enable = GetQuestLogSpecialItemCooldown(idx)
	end
	start, duration, enable = U.Num(start), U.Num(duration), U.Num(enable) or enable
	if start and duration then
		if type(CooldownFrame_Set) == "function" then
			CooldownFrame_Set(B.cooldown, start, duration, enable)
		else
			B.cooldown:SetCooldown(start, duration)
		end
		local dark = duration > 0 and (enable == 0 or enable == false)
		local v = dark and QI.DARK or 1
		B.icon:SetVertexColor(v, v, v)
	else
		B.cooldown:Clear()
		B.icon:SetVertexColor(1, 1, 1)
	end
end

-- Icon, charges, key text, cooldown and range of the item the button holds. No protected call.
function QI.Paint()
	if not B or not applied then
		return
	end
	B.icon:SetTexture(applied.icon)
	local n = applied.charges
	if n and n > 1 then
		B.count:SetText(n)
		B.count:Show()
	else
		B.count:Hide()
	end
	QI.HotKey()
	QI.Cooldown()
	QI.Range()
end

-- Out of combat only (UI.OutOfCombat): item attribute, place at the current step, scale, visibility.
function QI.Apply()
	if not B or not QI.ready then
		return
	end
	local w = Want()
	local item = (w and w.id and not w.demo) and ("item:" .. w.id) or nil
	if B:GetAttribute("item") ~= item then
		B:SetAttribute("item", item) -- nil when empty: no click uses an old item
	end
	applied = w
	local sf = Window()
	if not (w and sf) then
		B:Hide()
		B:ClearAllPoints() -- a hidden button anchored to the window would still bind it in a fight
		attached, anchor = false, {}
		return
	end
	local W = sf.frame
	local scale = W:GetScale() or 1
	local top = (QI.top or (sf.HEADER + 10)) + 1
	if not attached or anchor.top ~= top or anchor.scale ~= scale then
		B:SetScale(scale)
		B:ClearAllPoints()
		B:SetPoint("TOPRIGHT", W, "TOPRIGHT", -sf.RIGHT, -top)
		anchor.top, anchor.scale = top, scale
		attached = true
	end
	B:Show()
	QI.Paint()
end

-- A fight starts (PLAYER_REGEN_DISABLED, before the lockdown): the button keeps its spot but is
-- pinned to UIParent, so the step window stays free to lay out in the fight.
function QI.Detach()
	if not B or not attached then
		return
	end
	attached = false
	local l, r, t = UI.Rect(B)
	local k = (B:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
	B:ClearAllPoints()
	if l and r and t and k > 0 then
		B:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", r / k, t / k)
	else
		B:Hide() -- no rectangle yet: better gone than at a wrong place for the whole fight
	end
end

-- Called by the step window after every layout and refresh; top = top of the current step.
function QI.Follow(top)
	if not B then
		return
	end
	if top then
		QI.top = top
	end
	local w = QI.want
	if w == nil then
		w = Want()
	end
	QI.want = nil
	local id = w and w.id
	local held = applied and applied.id
	local top1 = (QI.top or 0) + 1
	local moved = attached and (anchor.top ~= top1 or anchor.scale ~= (Window() and Window().frame:GetScale()))
	if id ~= held or (w ~= nil) ~= B:IsShown() or moved or (w and not attached) then
		UI.OutOfCombat("questitem", QI.Apply)
	end
	if applied then
		QI.Paint()
	end
end

-- Developer preview (Probe/Preview.lua): a fixed icon without an item attribute; nil ends it.
function QI.SetDemo(d)
	demo = d and {
		demo = true,
		id = 0,
		icon = d.icon,
		charges = d.charges,
		range = d.range,
	} or nil
	UI.OutOfCombat("questitem", QI.Apply)
end

local function Build()
	B = CreateFrame("Button", QI.NAME, UIParent, "SecureActionButtonTemplate")
	QI.button = B
	B:SetFrameStrata("MEDIUM")
	B.icon = B:CreateTexture(nil, "BORDER")
	B.icon:SetAllPoints()
	B.ring = B:CreateTexture(nil, "OVERLAY")
	B.ring:SetSize(QI.RING, QI.RING)
	B.ring:SetPoint("CENTER")
	T.SetAtlas(B.ring, "questitem")
	B.hotkey = B:CreateFontString(nil, "ARTWORK", "NumberFontNormalSmallGray")
	B.hotkey:SetJustifyH("LEFT")
	B.hotkey:SetSize(29, 10)
	B.hotkey:SetPoint("TOPRIGHT", B, "TOPRIGHT", 16, -2)
	B.count = B:CreateFontString(nil, "ARTWORK", "NumberFontNormal")
	B.count:SetJustifyH("RIGHT")
	B.count:SetPoint("BOTTOMRIGHT", B, "BOTTOMRIGHT", -3, 2)
	B.count:Hide()
	B.cooldown = CreateFrame("Cooldown", nil, B, "CooldownFrameTemplate")
	B.cooldown:SetAllPoints()
	B:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	B:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		local idx = Index()
		if idx and GameTooltip.SetQuestLogSpecialItem then
			GameTooltip:SetQuestLogSpecialItem(idx)
		elseif applied and applied.link then
			GameTooltip:SetHyperlink(applied.link)
		end
		GameTooltip:Show()
	end)
	B:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	local acc = 0
	B:SetScript("OnUpdate", function(_, elapsed) -- only while shown
		acc = acc + elapsed
		if acc >= QI.RANGE_EVERY then
			acc = 0
			Guard.Call("questitem", QI.Range)
		end
	end)
	QI.Poke = function() -- next frame asks the range again (new target)
		acc = QI.RANGE_EVERY
	end
end

-- Protected set-up of the button, out of combat (a login in a fight waits for its end).
local function Setup()
	B:SetSize(QI.SIZE, QI.SIZE)
	B:RegisterForClicks("AnyUp", "AnyDown") -- a key binding fires on key down (ActionButtonUseKeyDown)
	B:SetAttribute("type", "item")
	B:Hide()
	QI.ready = true
	QI.Apply()
end

local function Init()
	applied, attached, anchor, demo = nil, false, {}, nil
	Build()
	UI.OutOfCombat("questitemSetup", Setup)
	UI.OnChange("combat", QI, function(_, _, fighting)
		if fighting then
			QI.Detach()
		else
			UI.OutOfCombat("questitem", QI.Apply)
		end
	end)
	for _, key in ipairs({ "paused", "scale" }) do
		UI.OnChange(key, QI, function()
			UI.OutOfCombat("questitem", QI.Apply)
		end)
	end
end

M.Define("questitem", {
	requires = {
		funcs = {
			"GetQuestLogSpecialItemInfo",
			"GetQuestLogSpecialItemCooldown",
			"IsQuestLogSpecialItemInRange",
			"C_QuestLog.GetLogIndexForQuestID",
			"C_QuestLog.IsComplete",
			"InCombatLockdown",
			"GetBindingKey",
			"GetBindingText",
		},
		events = { "BAG_UPDATE_COOLDOWN", "PLAYER_TARGET_CHANGED", "UPDATE_BINDINGS" },
	},
	optional = { funcs = { "CooldownFrame_Set" } },
	init = Init,
	disable = function()
		UI.OutOfCombat("questitem", function()
			if B then
				B:SetAttribute("item", nil)
				B:Hide()
			end
			applied = nil
		end)
	end,
	events = {
		BAG_UPDATE_COOLDOWN = function()
			QI.Cooldown()
		end,
		PLAYER_TARGET_CHANGED = function()
			if QI.Poke then
				QI.Poke()
			end
		end,
		UPDATE_BINDINGS = function()
			if applied then
				QI.HotKey()
				QI.Range()
			end
		end,
	},
})
