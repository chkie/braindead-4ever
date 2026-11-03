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

-- Core/Boot.lua: feature flags and safe mode in SavedVariables, start guard, slash command.
-- Must be the last core file: it boots every module defined before ADDON_LOADED.
local ADDON, ns = ...
local L = ns.L

ns.slash = "bdf"

local version = C_AddOns.GetAddOnMetadata(ADDON, "Version")
-- Unpackaged checkout: the packager has not replaced the keyword yet.
if not version or version:find("^@") then
	version = "dev"
end
ns.version = version

local DEFAULTS = { flags = {}, safeMode = false, autoSafe = false, boot = { inProgress = false, fails = 0 } }

local function Merge(dst, src)
	for k, v in pairs(src) do
		if dst[k] == nil then
			dst[k] = type(v) == "table" and Merge({}, v) or v
		elseif type(v) == "table" and type(dst[k]) == "table" then
			Merge(dst[k], v)
		end
	end
	return dst
end

local function Boot()
	BraindeadForeverDB = type(BraindeadForeverDB) == "table" and BraindeadForeverDB or {}
	local db = Merge(BraindeadForeverDB, DEFAULTS)
	ns.db = db
	local b = db.boot
	-- New version: lift an automatic safe mode (the hotfix must be allowed to run).
	if b.version ~= ns.version then
		b.fails, b.version = 0, ns.version
		if db.autoSafe then
			db.safeMode, db.autoSafe = false, false
		end
	end
	-- Start guard: if inProgress is still true, the last start did not finish (error or abort
	-- during init, then a normal logout). The client writes SavedVariables only on logout,
	-- /reload or disconnect; a client crash leaves nothing here.
	if b.inProgress then
		b.fails = b.fails + 1
	end
	local switched = false
	if b.fails >= 2 and not db.safeMode then
		db.safeMode, db.autoSafe, switched = true, true, true
	end
	b.inProgress = true
	ns.Modules.Boot(db)
	if switched then
		-- The step window names safe mode in its status line; a chat line only if it is down itself.
		ns.Modules.Tell(L.MSG_SAFE_MODE_AUTO:format("|cffff8800" .. L.TITLE .. "|r", ns.slash))
	end
end

local function StartedCleanly()
	if ns.db then
		ns.db.boot.inProgress, ns.db.boot.fails = false, 0
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then
			return
		end
		self:UnregisterEvent("ADDON_LOADED")
		ns.Guard.Call("boot", Boot)
	elseif event == "PLAYER_ENTERING_WORLD" then
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
		-- 10 s after the first loading screen the start counts as clean.
		C_Timer.After(10, StartedCleanly)
	end
end)

local function OnOff(value)
	return value and L.WORD_ON or L.WORD_OFF
end

SLASH_BRAINDEADFOREVER1 = "/bd4"
SLASH_BRAINDEADFOREVER2 = "/braindead4ever"
SLASH_BRAINDEADFOREVER3 = "/bdf" -- the short form of the first release name, kept as an alias
SlashCmdList.BRAINDEADFOREVER = function(msg)
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	local a, b = rest:lower():match("^(%S*)%s*(%S*)")
	local db = ns.db
	if not db then
		print(L.MSG_NOT_LOADED:format(L.TITLE))
		return
	end
	local ext = ns.Commands and ns.Commands[cmd]
	if ext then
		-- Subcommands of other files (export, report, probe) get the rest of the line as typed.
		ns.Guard.Call("slash", ext, rest, cmd)
	elseif cmd == "safe" then
		db.safeMode, db.autoSafe = (a ~= "off"), false
		print(L.MSG_SAFE_MODE_SET:format(L.TITLE, OnOff(db.safeMode)))
	elseif cmd == "flag" and ns.Modules.defs[a] and ns.Modules.defs[a].mandatory then
		print(L.MSG_FLAG_MANDATORY:format(L.TITLE, a))
	elseif cmd == "flag" and a ~= "" then
		-- nil = default (on). Trap: "x and nil or false" is always false in Lua.
		if b == "off" then
			db.flags[a] = false
		else
			db.flags[a] = nil
		end
		print(L.MSG_FLAG_SET:format(L.TITLE, a, OnOff(b ~= "off")))
	elseif cmd == "errors" then
		print(ns.Guard:Report())
	elseif cmd == "quiet" then
		db.flags.quietErrors = (a ~= "off") or nil
	else
		print(ns.Modules.Report())
	end
end
