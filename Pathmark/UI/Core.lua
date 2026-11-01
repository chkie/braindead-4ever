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

-- UI/Core.lua: shared state of the interface (Welle 5): options in PathmarkDB.ui, change listeners,
-- the out-of-combat queue and the guidance pause. No frame of its own except the event frame.
-- Combat rule (brain chapter 05 §3, chapter 18 R1/R3): nothing that may be protected or that opens a
-- window runs while InCombatLockdown() is true. Such calls go through UI.OutOfCombat, which runs them
-- at once out of combat and otherwise after PLAYER_REGEN_ENABLED (one job per key, the last wins).
local _, ns = ...
local Guard = ns.Guard

local UI = {
	-- Options (the settings page registers them under PATHMARK_<KEY>); values as in the design v2.
	DEFAULTS = {
		scope = "standard", -- Anzeigeumfang: minimal | standard | full
		arrow = true,
		scale = 100, -- percent, 75..200, step 5
		sound = true,
		ahead = 3, -- steps ahead 0..10, synchronous with the height of the step window (owner reading 14)
		width = 300, -- width of the step window, 260..500 (owner reading 14)
		bgAlpha = 35, -- percent, 0..80
		dim = true, -- dim the step window to 60 % in combat
		arrival = 12, -- yards, 5..30
		pins = true,
		minipins = false,
		blizzNav = false,
		mmButton = true,
		textSize = true, -- follow Blizzard's text size (userFontScale)
		style = "hints", -- play style: arrow | hints | self (closing the setup picks "hints")
		hint = 1, -- hint level 0..3
		tracker = "route", -- Blizzard's quest tracker: keep | route | hide (owner reading 15)
	},
	-- Presets of the "Anzeigeumfang" dropdown: each sets these options (brain chapter 18 pattern D).
	SCOPES = {
		minimal = { ahead = 0, pins = false, minipins = false, sound = false },
		standard = { ahead = 3, pins = true, minipins = false, sound = true },
		full = { ahead = 3, pins = true, minipins = true, sound = true },
	},
	COMBAT_ALPHA = 0.6,
	-- Size of the step window (owner reading 14): reset together with the positions.
	SIZE_KEYS = { "width", "ahead" },
	settings = {}, -- key -> Blizzard setting object, filled by UI/Settings.lua
}
ns.UI = UI

local listeners = {} -- key -> { { owner, fn }, ... }
local filled -- PathmarkDB.ui table that got its defaults this session
local queue, keyed = {}, {}
local frame = CreateFrame("Frame")

-- PathmarkDB.ui with defaults filled in. Before ADDON_LOADED a plain table (tests, early calls).
function UI.DB()
	local db = ns.db
	if not db then
		UI.early = UI.early or {}
		return UI.early
	end
	if type(db.ui) ~= "table" then
		db.ui = {}
	end
	local t = db.ui
	if filled ~= t then -- once per table and session; the flag is not saved
		for k, v in pairs(UI.DEFAULTS) do
			if t[k] == nil then
				t[k] = v
			end
		end
		filled = t
	end
	return t
end

function UI.Get(key)
	local v = UI.DB()[key]
	if v == nil then
		return UI.DEFAULTS[key]
	end
	return v
end

-- Listeners: fn(owner, key, value). One per owner and key.
function UI.OnChange(key, owner, fn)
	local list = listeners[key] or {}
	listeners[key] = list
	for _, l in ipairs(list) do
		if l.owner == owner then
			l.fn = fn
			return
		end
	end
	list[#list + 1] = { owner = owner, fn = fn }
end

-- Called after a value changed (by the settings page or by UI.Set).
function UI.Changed(key)
	local value = UI.Get(key)
	for _, l in ipairs(listeners[key] or {}) do
		Guard.Call("ui", l.fn, l.owner, key, value)
	end
	for _, l in ipairs(listeners["*"] or {}) do
		Guard.Call("ui", l.fn, l.owner, key, value)
	end
end

-- Writes an option. With a registered setting the settings page stays in sync (brain chapter 04 §9);
-- the setting's change callback then calls UI.Changed.
function UI.Set(key, value)
	local setting = UI.settings[key]
	if setting then
		setting:SetValue(value)
		return
	end
	UI.DB()[key] = value
	UI.Changed(key)
end

-- Out-of-combat queue (brain chapter 05 pattern A) -------------------------------------------------

local function Flush()
	frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
	local jobs, byKey = queue, keyed
	queue, keyed = {}, {}
	for _, job in ipairs(jobs) do
		Guard.Call("ui", job.fn, unpack(job.args, 1, job.n))
	end
	for _, job in pairs(byKey) do
		Guard.Call("ui", job.fn, unpack(job.args, 1, job.n))
	end
end

-- Lockdown: protected calls wait (Blizzard: lockdown starts after PLAYER_REGEN_DISABLED).
function UI.InCombat()
	return InCombatLockdown() == true
end

-- Fight for the looks (dimming, no glow, no sound, no new hints): already true inside the
-- PLAYER_REGEN_DISABLED handler, before the lockdown starts.
function UI.Fighting()
	return UI.fighting == true or InCombatLockdown() == true
end

-- Runs fn now out of combat, else after the fight. Returns true if it ran now.
function UI.OutOfCombat(key, fn, ...)
	if not UI.InCombat() then
		fn(...)
		return true
	end
	local job = { fn = fn, args = { ... }, n = select("#", ...) }
	if key then
		keyed[key] = job
	else
		queue[#queue + 1] = job
	end
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	return false
end

-- Number of jobs waiting for the end of the fight (tests, diagnostics).
function UI.Waiting()
	local n = #queue
	for _ in pairs(keyed) do
		n = n + 1
	end
	return n
end

-- Combat state for the windows: listeners of the pseudo key "combat" get true or false.
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then
		UI.fighting = false
		for _, l in ipairs(listeners.combat or {}) do
			Guard.Call("ui", l.fn, l.owner, "combat", false)
		end
		Flush()
	else
		UI.fighting = true
		frame:RegisterEvent("PLAYER_REGEN_ENABLED")
		for _, l in ipairs(listeners.combat or {}) do
			Guard.Call("ui", l.fn, l.owner, "combat", true)
		end
	end
end)

-- Guidance pause (right-click menu, minimap button): hides step window, arrow and map pins.
function UI.Paused()
	return UI.DB().paused == true
end

function UI.SetPaused(paused)
	UI.DB().paused = paused and true or nil
	UI.Changed("paused")
end

-- A CVar as string, nil if the client does not know it.
function UI.CVar(name)
	local v = C_CVar.GetCVar(name)
	if v ~= nil and not ns.Util.IsSecret(v) then
		return v
	end
end

-- Event name the running client knows (unknown names throw since 8.0.1).
function UI.Listen(f, event)
	if C_EventUtils.IsEventValid(event) then
		f:RegisterEvent(event)
		return true
	end
	return false
end

-- Positions ---------------------------------------------------------------------------------------
-- Windows hang on UIParent (rule N6). They move in Blizzard's Edit Mode: Blizzard fires
-- "EditMode.Enter" and "EditMode.Exit" through EventRegistry (wow-ui-source forever,
-- Blizzard_EditMode/Shared/EditModeManager.lua); while it is open the windows can be dragged and show
-- a frame with their name. Positions are saved in PathmarkDB.ui.pos.

UI.movers = {}

function UI.Place(key)
	local m = UI.movers[key]
	if not m then
		return
	end
	local pos = (UI.DB().pos or {})[key]
	local f = m.frame
	f:ClearAllPoints()
	if type(pos) == "table" and pos[1] then
		f:SetPoint(pos[1], UIParent, pos[2] or pos[1], pos[3] or 0, pos[4] or 0)
	else
		f:SetPoint(m.default[1], UIParent, m.default[1], m.default[2], m.default[3])
	end
end

local function Save(key)
	local m = UI.movers[key]
	if not m then
		return
	end
	local point, _, relPoint, x, y = m.frame:GetPoint(1)
	if point then
		local db = UI.DB()
		db.pos = type(db.pos) == "table" and db.pos or {}
		db.pos[key] = { point, relPoint, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) }
	end
end

-- win, key, label shown in Edit Mode, default { point, x, y }, mouse = mouse on outside Edit Mode.
function UI.Mover(win, key, label, default, mouse)
	local overlay = CreateFrame("Frame", nil, win)
	overlay:SetAllPoints()
	overlay:Hide()
	overlay.bg = overlay:CreateTexture(nil, "OVERLAY")
	overlay.bg:SetAllPoints()
	overlay.bg:SetColorTexture(ns.Theme.RGB(NORMAL_FONT_COLOR))
	overlay.bg:SetAlpha(0.25)
	overlay.label = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	overlay.label:SetPoint("CENTER")
	overlay.label:SetText(label)
	UI.movers[key] = { frame = win, overlay = overlay, default = default, mouse = mouse }
	win:SetClampedToScreen(true)
	win:SetScript("OnDragStart", function(self)
		if UI.editing and not UI.InCombat() then
			self:StartMoving()
			self:SetUserPlaced(false) -- own saving (brain chapter 04 §4)
		end
	end)
	win:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		Save(key)
	end)
	UI.Place(key)
end

function UI.SetEditing(on)
	UI.editing = on and true or false
	for _, m in pairs(UI.movers) do
		local f = m.frame
		f:SetMovable(UI.editing)
		f:EnableMouse(UI.editing or m.mouse == true)
		if UI.editing then
			f:RegisterForDrag("LeftButton")
		end
		m.overlay:SetShown(UI.editing)
	end
	UI.Changed("editing")
end

UI.SavePosition = Save

-- "Reset" on the Display page: positions and the size of the step window (owner reading 14).
function UI.ResetPositions()
	UI.DB().pos = nil
	for _, key in ipairs(UI.SIZE_KEYS) do
		UI.Set(key, UI.DEFAULTS[key])
	end
	for key in pairs(UI.movers) do
		UI.Place(key)
	end
end

if EventRegistry and EventRegistry.RegisterCallback then
	EventRegistry:RegisterCallback("EditMode.Enter", function()
		Guard.Call("ui", UI.SetEditing, true)
	end, UI)
	EventRegistry:RegisterCallback("EditMode.Exit", function()
		Guard.Call("ui", UI.SetEditing, false)
	end, UI)
end

-- "Fenster positionieren": Blizzard's Edit Mode is opened by the player (game menu). Whether
-- ShowUIPanel(EditModeManagerFrame) from addon code taints is unconfirmed (brain chapter 18 §7), so
-- the addon only says where to find it.
function UI.EditModeHint()
	if UIErrorsFrame and UIErrorsFrame.AddMessage then
		UIErrorsFrame:AddMessage(
			ns.L.EDITMODE_HINT:format(HUD_EDIT_MODE_MENU or "Edit Mode"),
			ns.Theme.RGB(NORMAL_FONT_COLOR)
		)
	end
end
