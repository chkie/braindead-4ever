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

-- Core/CopyWindow.lua: one window that shows a text for copying (export, error report, probe report).
-- CopyToClipboard is restricted for addons in Forever (HasRestrictions): the player copies with Ctrl+C.
-- Pattern after the JourneyTracker export window (MIT), own code. The frame is created on first use.
local _, ns = ...
local L = ns.L

local win

local function CreateWindow()
	local f = CreateFrame("Frame", "BraindeadForeverCopyFrame", UIParent, "BackdropTemplate")
	f:SetSize(560, 380)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 14,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	f:SetBackdropColor(0, 0, 0, 0.92)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	tinsert(UISpecialFrames, "BraindeadForeverCopyFrame") -- Escape closes

	f.title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	f.title:SetPoint("TOPLEFT", 14, -12)

	local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -40)
	scroll:SetPoint("BOTTOMRIGHT", -32, 44)

	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal)
	box:SetWidth(500)
	box:SetScript("OnEscapePressed", function()
		f:Hide()
	end)
	-- Read-only: undo every edit by the player and select the text again.
	box:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(f.text or "")
			self:HighlightText()
		end
	end)
	box:SetScript("OnEditFocusGained", function(self)
		self:HighlightText()
	end)
	-- Ctrl+C (Cmd+C on a Mac) seen: the text is on the clipboard now.
	box:SetScript("OnKeyUp", function(_, key)
		if key == "C" and (IsControlKeyDown() or IsMetaKeyDown()) then
			f.status:SetText(L.COPY_DONE)
			if f.onCopy then
				local fn = f.onCopy
				f.onCopy = nil
				ns.Guard.Call("copy", fn)
			end
		end
	end)
	scroll:SetScrollChild(box)
	f.box = box

	f.status = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	f.status:SetPoint("BOTTOMLEFT", 16, 18)

	local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	close:SetSize(100, 22)
	close:SetPoint("BOTTOMRIGHT", -12, 12)
	close:SetText(CLOSE)
	close:SetScript("OnClick", function()
		f:Hide()
	end)
	return f
end

-- opts: { hint = extra status text, onCopy = fn called once after Ctrl+C }. Not in combat.
function ns.ShowCopy(title, text, opts)
	if InCombatLockdown() then
		print(L.MSG_AFTER_COMBAT)
		return false
	end
	opts = opts or {}
	win = win or CreateWindow()
	win.text, win.onCopy = text, opts.onCopy
	win.title:SetText(title)
	local status = L.COPY_STATUS:format(#text)
	if opts.hint then
		status = status .. " " .. opts.hint
	end
	win.status:SetText(status)
	win.box:SetText(text)
	win:Show()
	win.box:SetFocus()
	win.box:HighlightText()
	return true
end

-- For tests and the probe: the window if it exists.
function ns.CopyWindow()
	return win
end
