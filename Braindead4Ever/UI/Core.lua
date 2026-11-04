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

-- UI/Core.lua: shared state of the interface (Welle 5): options in BraindeadForeverDB.ui, change listeners,
-- the out-of-combat queue and the guidance pause. No frame of its own except the event frame.
-- Combat rule (brain chapter 05 §3, chapter 18 R1/R3): nothing that may be protected or that opens a
-- window runs while InCombatLockdown() is true. Such calls go through UI.OutOfCombat, which runs them
-- at once out of combat and otherwise after PLAYER_REGEN_ENABLED (one job per key, the last wins).
local _, ns = ...
local Guard = ns.Guard

local UI = {
	-- Options (the settings page registers them under BRAINDEADFOREVER_<KEY>); values as in the design v2.
	DEFAULTS = {
		scope = "standard", -- Anzeigeumfang: minimal | standard | full
		arrow = true,
		scale = 100, -- percent, 75..200, step 5
		sound = true,
		ahead = 3, -- steps ahead 0..10, synchronous with the height of the step window (owner reading 14)
		width = 300, -- width of the step window, 260..500 (owner reading 14)
		bgAlpha = 70, -- percent, 0..80; 70 keeps every text of the window at 4.5:1 on white ground (Welle 5d)
		dim = true, -- dim the step window to 60 % in combat
		arrival = 12, -- yards, 5..30
		pins = true,
		minipins = false,
		blizzNav = false,
		mmButton = true,
		tomtom = true, -- hand the current goal to TomTom when it is installed (UI/TomTom.lua)
		hardcore = "auto", -- hardcore-safe mode: auto (the realm's rule set) | on | off (UI/Connect.lua)
		textSize = true, -- follow Blizzard's text size (userFontScale)
		style = "hints", -- play style: arrow | hints | self (closing the setup picks "hints")
		hint = 1, -- hint level 0..3
		tracker = "hide", -- Blizzard's quest tracker: keep | route | hide (owner readings 15 and 16)
		lock = false, -- "Lock window": the header band no longer drags the step window (owner reading 16)
		recap = true, -- review card at level 10, 20 and 30 (Welle 8, UI/StatsPage.lua)
		auto = false, -- optional automation of route quest dialogs, off by default (UI/Auto.lua, A74)
	},
	-- Revision of the defaults in BraindeadForeverDB.ui.rev. UI.DB fills every default into the saved table, so
	-- a value equal to an old default was never chosen: it takes the new default, any other value is the
	-- player's choice and stays. REVISIONS[n] lists the defaults that revision n replaced.
	REV = 2,
	REVISIONS = {
		[1] = { tracker = "route" }, -- Welle 5c: Blizzard's quest tracker hidden while Braindead 4ever guides
		-- Welle 5d, M1: 35 % left white text at 3.2:1 and gold at 3.0:1 over the bright sky of Orgrimmar
		[2] = { bgAlpha = 35 },
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
local filled -- BraindeadForeverDB.ui table that got its defaults this session
local queue, keyed = {}, {}
local frame = CreateFrame("Frame")

-- BraindeadForeverDB.ui with defaults filled in. Before ADDON_LOADED a plain table (tests, early calls).
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
		UI.Migrate(t)
		for k, v in pairs(UI.DEFAULTS) do
			if t[k] == nil then
				t[k] = v
			end
		end
		filled = t
	end
	return t
end

-- Lifts a saved option table to UI.REV (see UI.REVISIONS). A saved position is never touched.
function UI.Migrate(t)
	local from = tonumber(t.rev) or 0
	for rev = from + 1, UI.REV do
		for key, old in pairs(UI.REVISIONS[rev] or {}) do
			if t[key] == old then
				t[key] = nil -- the default fills in
			end
		end
	end
	if from < UI.REV then
		t.rev = UI.REV
	end
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
frame:SetScript("OnEvent", function(_, event, key)
	if event == "INPUT_DEVICE_INTERFACE_TRANSITION" then
		-- the player switched between mouse and keyboard and the gamepad UI: their places (K8)
		UI.OutOfCombat("placeAll", function()
			Guard.Call("ui", UI.PlaceAll)
		end)
	elseif event == "MODIFIER_STATE_CHANGED" then
		if (key == "LSHIFT" or key == "RSHIFT") and IsShiftKeyDown then
			Guard.Call("ui", UI.OnShift, IsShiftKeyDown() == true)
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		UI.fighting = false
		for _, l in ipairs(listeners.combat or {}) do
			Guard.Call("ui", l.fn, l.owner, "combat", false)
		end
		Guard.Call("ui", UI.OnShift, UI.shift == true)
		Flush()
	else
		UI.fighting = true
		frame:RegisterEvent("PLAYER_REGEN_ENABLED")
		for name in pairs(UI.movers or {}) do -- a drag ends where the fight starts
			Guard.Call("ui", UI.StopMove, name)
		end
		for _, l in ipairs(listeners.combat or {}) do
			Guard.Call("ui", l.fn, l.owner, "combat", true)
		end
		Guard.Call("ui", UI.OnShift, UI.shift == true) -- the arrow lets go of the mouse
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

UI.Listen(frame, "INPUT_DEVICE_INTERFACE_TRANSITION") -- Forever only: switch to and from the gamepad UI

-- Positions ---------------------------------------------------------------------------------------
-- Windows hang on UIParent (rule N6). They move three ways (owner reading 16): the step window by
-- dragging its header band, the arrow while Shift is held (it stays click-free otherwise, rule P7), and
-- both in Blizzard's Edit Mode. Blizzard fires "EditMode.Enter" and "EditMode.Exit" through
-- EventRegistry in EditModeManagerFrameMixin:EnterEditMode and :ExitEditMode (wow-ui-source
-- Blizzard_EditMode/Shared/EditModeManager.lua: live 12.1.5 lines 100 and 119, forever 1.60.1 lines 105
-- and 124); while it is open the windows show a frame with their name. Nothing moves in a fight.
-- Positions are saved in BraindeadForeverDB.ui.pos; a window without one stands at its default, and a default
-- given as a function is computed again at every placement.

UI.movers = {}

-- Rectangle of a frame in UIParent units (left, right, top, bottom), nil when the frame has none yet
-- or a value is secret. GetLeft and the others count in the frame's own scale.
function UI.Rect(f)
	if not (f and f.GetLeft and f.GetEffectiveScale and UIParent) then
		return nil
	end
	local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
	local s, p = f:GetEffectiveScale(), UIParent:GetEffectiveScale()
	-- every value on its own: ipairs would stop at the first nil and let it through
	local values = { l, r, t, b, s, p }
	for i = 1, 6 do
		local v = values[i]
		if type(v) ~= "number" or ns.Util.IsSecret(v) then
			return nil
		end
	end
	if p <= 0 then
		return nil
	end
	local k = s / p
	return l * k, r * k, t * k, b * k
end

-- UI type (Welle 9, K8; requirement A40): Forever saves Edit Mode layouts per UI type, mouse and
-- keyboard apart from gamepad (patch 1.60.1 beta 4, brain chapter 18 §1.6), and the windows follow:
-- BraindeadForeverDB.ui.pos holds their places for mouse and keyboard, BraindeadForeverDB.ui.posPad for the gamepad UI.
-- The type comes from C_InputInterfaceStyle.GetCurrentStyle (InputInterfaceStyleDocumentation.lua,
-- wow-ui-source forever); Retail 12.1.5 has no gamepad UI and no such function, so there it is always
-- mouse and keyboard. INPUT_DEVICE_INTERFACE_TRANSITION places the windows again, after a fight.
function UI.Pad()
	local style = ns.Modules.Optional("C_InputInterfaceStyle.GetCurrentStyle")
	if not style then
		return false
	end
	---@diagnostic disable-next-line: undefined-field
	local types = Enum.InputDeviceInterfaceType -- not in the pinned annotations (12.0.1)
	local pad = types and types.Gamepad or 1 -- InputConstantsDocumentation.lua forever: Gamepad = 1
	local ok, value = pcall(style)
	return ok and value == pad
end

-- Name of the table in BraindeadForeverDB.ui that holds the places for the current UI type.
function UI.PosKey()
	return UI.Pad() and "posPad" or "pos"
end

-- Saved position of a window, nil while it stands at its default.
function UI.Position(key)
	local pos = UI.DB()[UI.PosKey()]
	pos = type(pos) == "table" and pos[key]
	if type(pos) == "table" and pos[1] then
		return pos
	end
end

function UI.Place(key)
	local m = UI.movers[key]
	if not m then
		return
	end
	local pos = UI.Position(key)
	local f = m.frame
	f:ClearAllPoints()
	if pos then
		f:SetPoint(pos[1], UIParent, pos[2] or pos[1], pos[3] or 0, pos[4] or 0)
		if m.top and not tostring(pos[1]):find("^TOP") then
			UI.SavePosition(key) -- a place saved before Welle 5d: the same spot, now held at the top edge
		end
	else
		local d = m.default
		if type(d) == "function" then
			d = d()
		end
		f:SetPoint(d[1], UIParent, d[1], d[2], d[3])
	end
end

-- Anchors a window at its top edge where it stands: TOPLEFT or TOPRIGHT of UIParent, whichever side
-- of the screen its middle is on. The client anchors a dropped frame at the point closest to a UIParent
-- point (Frame:StopMovingOrSizing, warcraft.wiki.gg), in the middle of the screen height that is LEFT,
-- CENTER or RIGHT, and a window anchored there grows up and down when a line comes or goes (Welle 5d,
-- M4). Returns true when it anchored.
function UI.AnchorTop(f)
	local l, r, t = f:GetLeft(), f:GetRight(), f:GetTop()
	local pr, pt = UIParent:GetRight(), UIParent:GetTop()
	local fs, ps = f:GetEffectiveScale(), UIParent:GetEffectiveScale()
	for _, v in ipairs({ l, r, t, pr, pt, fs, ps }) do
		if type(v) ~= "number" or ns.Util.IsSecret(v) then
			return false
		end
	end
	if fs <= 0 or ps <= 0 then
		return false
	end
	local k = ps / fs -- UIParent units to the window's units
	local screenR, screenT = pr * k, pt * k
	local right = (l + r) / 2 > screenR / 2
	local point = right and "TOPRIGHT" or "TOPLEFT"
	f:ClearAllPoints()
	f:SetPoint(point, UIParent, point, right and (r - screenR) or l, t - screenT)
	return true
end

local function Save(key)
	local m = UI.movers[key]
	if not m then
		return
	end
	if m.top then
		UI.AnchorTop(m.frame)
	end
	local point, _, relPoint, x, y = m.frame:GetPoint(1)
	if point then
		local db, which = UI.DB(), UI.PosKey()
		db[which] = type(db[which]) == "table" and db[which] or {}
		db[which][key] = { point, relPoint, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) }
	end
end

-- Mouse of a window: always (step window), in Edit Mode, while Shift is held outside a fight (arrow),
-- and as long as a drag runs.
local function Mouse(m)
	local shift = m.shift and UI.shift and not UI.Fighting()
	m.frame:EnableMouse(UI.editing or m.mouse == true or shift or m.moving == true)
end

-- May the window be dragged now? Never in a fight; in Edit Mode always; otherwise when its own rule
-- says so (header band and not locked, Shift held).
function UI.CanMove(key)
	local m = UI.movers[key]
	if not m or UI.Fighting() then
		return false
	end
	if UI.editing then
		return true
	end
	return m.drag ~= nil and m.drag(m.frame) == true
end

function UI.StartMove(key)
	local m = UI.movers[key]
	if not m or m.moving or not UI.CanMove(key) then
		return false
	end
	m.frame:StartMoving()
	m.frame:SetUserPlaced(false) -- own saving (brain chapter 04 §4)
	m.moving = true
	return true
end

-- Drag released (or a fight starts): the place is saved. Without a running drag nothing is saved, so a
-- refused drag never turns the default into a saved position.
function UI.StopMove(key)
	local m = UI.movers[key]
	if not (m and m.moving) then
		return false
	end
	m.moving = false
	m.frame:StopMovingOrSizing()
	Save(key)
	Mouse(m)
	return true
end

function UI.OnShift(down)
	UI.shift = down
	for _, m in pairs(UI.movers) do
		if m.shift then
			Mouse(m)
		end
	end
end

-- win, key, label shown in Edit Mode, default { point, x, y } or a function returning one; opts:
-- mouse = takes the mouse outside Edit Mode, drag(frame) = true when a drag may start outside Edit
-- Mode, shift = takes the mouse only while Shift is held, top = the saved place holds the top edge (a
-- window whose height changes grows downwards only).
function UI.Mover(win, key, label, default, opts)
	opts = opts or {}
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
	local m = {
		frame = win,
		overlay = overlay,
		default = default,
		mouse = opts.mouse == true,
		drag = opts.drag,
		shift = opts.shift == true,
		top = opts.top == true,
	}
	UI.movers[key] = m
	win:SetClampedToScreen(true)
	win:SetMovable(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", function()
		UI.StartMove(key)
	end)
	win:SetScript("OnDragStop", function()
		UI.StopMove(key)
	end)
	if m.shift and not UI.listensShift then
		UI.listensShift = UI.Listen(frame, "MODIFIER_STATE_CHANGED")
	end
	Mouse(m)
	UI.Place(key)
end

function UI.SetEditing(on)
	UI.editing = on and true or false
	for _, m in pairs(UI.movers) do
		Mouse(m)
		m.overlay:SetShown(UI.editing)
	end
	UI.Changed("editing")
end

UI.SavePosition = Save

-- Every window at its place for the current UI type.
function UI.PlaceAll()
	for key in pairs(UI.movers) do
		UI.Place(key)
	end
end

-- "Reset" on the Display page: positions of the current UI type and the size of the step window (owner
-- reading 14).
function UI.ResetPositions()
	UI.DB()[UI.PosKey()] = nil
	for _, key in ipairs(UI.SIZE_KEYS) do
		UI.Set(key, UI.DEFAULTS[key])
	end
	UI.PlaceAll()
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
