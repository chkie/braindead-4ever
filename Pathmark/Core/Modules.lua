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

-- Core/Modules.lua: modules with requirements, API probe at boot, orderly shutdown.
-- States: planned -> on | off (flag, safe mode, missing API or event) | error (init threw)
-- | disabled (error burst at runtime). The reason is kept in why[name].
local ADDON, ns = ...
local L = ns.L
local Guard = ns.Guard

local M = { defs = {}, order = {}, state = {}, why = {}, frame = CreateFrame("Frame") }
ns.Modules = M

-- "C_QuestLog.GetInfo" or "UnitXP" -> function or nil. A namespace alone is not enough:
-- C_SkillInfo exists in Retail 12.1.5 as an empty namespace.
local function Lookup(path)
	local space, fn = path:match("^([%w_]+)%.([%w_]+)$")
	if space then
		local t = _G[space]
		return type(t) == "table" and t[fn] or nil
	end
	return _G[path]
end
M.Lookup = Lookup

-- Developer stand-ins (Retail test bed only, never packaged): ns.shim[path] = function ...
local function Resolve(path)
	local f = Lookup(path)
	if type(f) == "function" then
		return f, "real"
	end
	local s = ns.shim and ns.shim[path]
	if type(s) == "function" then
		return s, "shim"
	end
end
M.Resolve = Resolve

local function EventOK(ev)
	if ns.shimEvents and ns.shimEvents[ev] then
		return true, "shim"
	end
	return C_EventUtils.IsEventValid(ev) == true, "real"
end

-- spec = { core = bool, mandatory = bool, requires = { funcs = {...}, events = {...} },
--          optional = { funcs = {...}, events = {...} },
--          init = fn(spec), disable = fn(spec), events = { EVENT = fn(spec, event, ...) } }
-- core: runs in safe mode. mandatory: part of the addon that the player cannot switch off (data
-- contribution, owner decision 2026-11-01): flags and a safe mode set by hand do not stop it; the
-- automatic safe mode after failed starts and the error buffer still do.
-- optional: what the module uses when the client has it; listed for the API probe (Probe/Checks.lua).
function M.Define(name, spec)
	M.defs[name] = spec
	M.order[#M.order + 1] = name
	M.state[name] = "planned"
end

function M.IsActive(name)
	return M.state[name] == "on"
end

-- A message the player did not ask for (module turned off, automatic safe mode): it goes into the
-- status line of the step window (concept §1.5, design rule R2; UI/StepFrame.lua reads the states).
-- Only when the step window itself is not running does a chat line go out, one per session at most.
-- Returns true when it printed.
M.told = false
function M.Tell(text)
	local sf = ns.StepFrame
	if M.IsActive("window") and sf and sf.Queue then
		Guard.Call("window", sf.Queue)
		return false
	end
	if M.told then
		return false
	end
	M.told = true
	print(text)
	return true
end

function M.Disable(name, reason)
	if M.state[name] ~= "on" then
		return
	end
	local spec = M.defs[name]
	M.state[name], M.why[name] = "disabled", reason
	if spec.disable then
		Guard.Call(name, spec.disable, spec)
	end
	-- The module's events stay registered on the frame; Guard.Wrap asks IsActive.
	M.Tell(L.MSG_MODULE_DISABLED:format("|cffff8800" .. ADDON .. "|r", name, reason, ns.slash or "pathmark"))
end

-- Checks requirements; returns nil or the reason.
local function Missing(spec)
	local req = spec.requires or {}
	for _, p in ipairs(req.funcs or {}) do
		if not Resolve(p) then
			return L.WHY_MISSING_API:format(p)
		end
	end
	for _, ev in ipairs(req.events or {}) do
		if not EventOK(ev) then
			return L.WHY_MISSING_EVENT:format(ev)
		end
	end
end

local handlers = {} -- event -> { { name, fn }, ... }

local function Dispatch(_, event, ...)
	local list = handlers[event]
	if not list then
		return
	end
	for i = 1, #list do
		list[i].fn(event, ...) -- fn is protected by Guard.Wrap
	end
end
M.frame:SetScript("OnEvent", Dispatch)
M.Dispatch = function(event, ...) -- for stand-in events
	Dispatch(nil, event, ...)
end

local function Register(name, spec)
	for ev, fn in pairs(spec.events or {}) do
		if EventOK(ev) then
			local list = handlers[ev]
			if not list then
				list = {}
				handlers[ev] = list
				-- Unknown names throw since 8.0.1: IsEventValid first, pcall as second wall.
				if C_EventUtils.IsEventValid(ev) then
					pcall(M.frame.RegisterEvent, M.frame, ev)
				end
			end
			list[#list + 1] = {
				name = name,
				fn = Guard.Wrap(name, function(e, ...)
					return fn(spec, e, ...)
				end),
			}
		end
	end
end

local function InitFailed(name)
	return function(e)
		Guard:Record(name, e)
		return tostring(e)
	end
end

-- Boot: call once after ADDON_LOADED (SavedVariables are available then).
function M.Boot(db)
	for _, name in ipairs(M.order) do
		local spec = M.defs[name]
		if db.flags[name] == false and not spec.mandatory then
			M.state[name], M.why[name] = "off", L.WHY_FLAG
		elseif db.safeMode and not spec.core and not (spec.mandatory and not db.autoSafe) then
			M.state[name], M.why[name] = "off", L.WHY_SAFE_MODE
		else
			local miss = Missing(spec)
			if miss then
				M.state[name], M.why[name] = "off", miss
			else
				M.state[name] = "on" -- before init, so Guard.Wrap lets calls through
				local ok = xpcall(spec.init or function() end, InitFailed(name), spec)
				if ok then
					Register(name, spec)
				else
					M.state[name], M.why[name] = "error", L.WHY_INIT
				end
			end
		end
	end
end

-- Optional capability at runtime (inside a module): function or nil.
function M.Optional(path)
	return (Resolve(path))
end

-- Status lines for /pathmark status and the error report.
function M.Report()
	local _, build, _, toc = GetBuildInfo()
	local lines = {
		("%s %s build=%s toc=%s project=%s safe=%s"):format(
			ADDON,
			tostring(ns.version),
			tostring(build),
			tostring(toc),
			tostring(WOW_PROJECT_ID),
			tostring(ns.db and ns.db.safeMode)
		),
	}
	for _, name in ipairs(M.order) do
		local state = M.state[name]
		lines[#lines + 1] = ("%-12s %-12s %s"):format(name, L["STATE_" .. state], M.why[name] or "")
	end
	return table.concat(lines, "\n")
end
