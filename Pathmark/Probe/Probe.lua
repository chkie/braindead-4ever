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

-- Probe/Probe.lua: developer API probe (AP 3). Checks in the client whether the functions, events,
-- values, atlases and CVars the plan needs exist and what they return, before anything is built on them.
-- Developer build only: the TOC lists the probe inside #@do-not-package@ and .pkgmeta ignores the
-- folder, so players never get it.
-- Pattern after JourneyProbe (JourneyTracker, MIT), own code. Golden rule: every game value goes through
-- Show() BEFORE it is compared, concatenated, indexed or used in math.
-- Results are measurements only (OK, MISSING, ERROR, SECRET, FAILED, ARGERROR). The plan status
-- "verified" is set by a person after the game test (/pathmark probe status <id> verified), never here.
local ADDON, ns = ...
local U = ns.Util
local L = ns.L

local Probe = { CHECKS = {}, seen = {}, mem = { results = {}, plan = {}, blocked = {} } }
ns.Probe = Probe

Probe.PLANS = { planned = true, built = true, verified = true, blocked = true }
Probe.PREFIX = "PathmarkProbe" -- own addon message prefix for the burst and loopback test

local MAX_BLOCKED = 20

-- "C_Map.GetBestMapForUnit", "SOUNDKIT.IG_QUEST_LIST_COMPLETE", "Constants.LegacyConsts" -> value or nil.
-- Indexing goes through pcall: some client tables have __index handlers.
local function Lookup(path)
	local v = _G
	for part in path:gmatch("[^%.]+") do
		if type(v) ~= "table" then
			return nil
		end
		local ok, nxt = pcall(function()
			return v[part]
		end)
		if not ok then
			return nil
		end
		v = nxt
	end
	return v
end
Probe.Lookup = Lookup

-- Display a value without ever comparing or indexing a secret.
local function Show(v)
	if U.IsSecret(v) then
		return "SECRET", true
	end
	local t = type(v)
	if t == "table" then
		local keys, n = {}, 0
		for k in pairs(v) do
			n = n + 1
			if #keys < 8 then
				keys[#keys + 1] = U.IsSecret(k) and "SECRET" or tostring(k)
			end
		end
		table.sort(keys)
		return ("table[%d]{%s}"):format(n, table.concat(keys, ","))
	end
	if t == "string" then
		if #v > 60 then
			return ("%q..."):format(v:sub(1, 60))
		end
		return ("%q"):format(v)
	end
	return tostring(v)
end
Probe.Show = Show

local Pack = U.Pack

-- Call name(...) protected. Returns result and the shown return values.
local function CallCheck(name, ...)
	local fn = Lookup(name)
	if type(fn) ~= "function" then
		return "MISSING", ""
	end
	local res = Pack(pcall(fn, ...))
	if not res[1] then
		return "ERROR", Show(res[2])
	end
	local out, secret = {}, false
	for i = 2, math.max(2, res.n) do
		local s, sec = Show(res[i])
		out[#out + 1] = s
		secret = secret or sec == true
	end
	return secret and "SECRET" or "OK", table.concat(out, ", ")
end

local function DB()
	local db = ns.db
	if type(db) ~= "table" then
		return Probe.mem
	end
	db.probe = type(db.probe) == "table" and db.probe or {}
	local p = db.probe
	p.results = type(p.results) == "table" and p.results or {}
	p.plan = type(p.plan) == "table" and p.plan or {}
	p.blocked = type(p.blocked) == "table" and p.blocked or {}
	return p
end
Probe.DB = DB

-- Checks derived from the module definitions: every required and optional function and event.
-- Explicit checks with the same name and kind are not repeated.
function Probe.ModuleChecks()
	local out, explicit = {}, {}
	for _, c in ipairs(Probe.CHECKS) do
		explicit[c.kind .. ":" .. (c.name or "")] = true
	end
	local M = ns.Modules
	for _, name in ipairs(M.order) do
		local spec = M.defs[name]
		for _, group in ipairs({ "requires", "optional" }) do
			local g = spec[group] or {}
			for _, path in ipairs(g.funcs or {}) do
				if not explicit["exists:" .. path] and not explicit["func:" .. path] then
					out[#out + 1] =
						{ id = ("mod.%s.%s"):format(name, path), kind = "exists", name = path, group = group }
				end
			end
			for _, ev in ipairs(g.events or {}) do
				if not explicit["event:" .. ev] then
					out[#out + 1] = { id = ("mod.%s.%s"):format(name, ev), kind = "event", name = ev, group = group }
				end
			end
		end
	end
	return out
end

function Probe.All()
	local all = {}
	for _, c in ipairs(Probe.CHECKS) do
		all[#all + 1] = c
	end
	for _, c in ipairs(Probe.ModuleChecks()) do
		all[#all + 1] = c
	end
	return all
end

local function Evaluate(c)
	local kind = c.kind
	if kind == "func" then
		local ok, args = pcall(function()
			return Pack((c.args or function() end)())
		end)
		if not ok then
			return "ARGERROR", Show(args)
		end
		return CallCheck(c.name, unpack(args, 1, args.n))
	elseif kind == "exists" then
		return type(Lookup(c.name)) == "function" and "OK" or "MISSING", ""
	elseif kind == "value" then
		local v = Lookup(c.name)
		if v == nil then
			return "MISSING", ""
		end
		local s, secret = Show(v)
		return secret and "SECRET" or "OK", s
	elseif kind == "atlas" then
		return CallCheck("C_Texture.GetAtlasInfo", c.name)
	elseif kind == "cvar" then
		local result, detail = CallCheck("C_CVar.GetCVar", c.name)
		if result == "OK" and detail == "nil" then
			return "MISSING", ""
		end
		return result, detail
	elseif kind == "test" then
		local ok, pass, detail = pcall(c.run)
		if not ok then
			return "ERROR", Show(pass)
		end
		return pass and "OK" or "FAILED", detail and tostring(detail) or ""
	elseif kind == "event" then
		local valid = C_EventUtils.IsEventValid(c.name) == true
		local s = Probe.seen[c.name]
		local detail = s and ("fired %dx, first payload: %s"):format(s.n, s.first) or "not fired yet"
		if c.noRegister then
			detail = "not registered on purpose"
		end
		return valid and "OK" or "MISSING", detail
	end
	return "ERROR", "unknown kind " .. tostring(kind)
end
Probe.Evaluate = Evaluate

local function Context(label)
	return label or (InCombatLockdown() and "combat" or "free")
end

local function Store(c, context)
	local r = DB().results
	local result, detail = Evaluate(c)
	local _, build = GetBuildInfo()
	r[c.id] = { result = result, detail = detail, context = context, build = tonumber(build), at = GetServerTime() }
	return r[c.id]
end

-- One pass over every check that does not wait for a context event and is not manual.
function Probe.Run(label)
	local context = Context(label)
	local n = 0
	for _, c in ipairs(Probe.All()) do
		if not c.when and not c.manual then
			Store(c, context)
			n = n + 1
		end
	end
	return n
end

-- A single check by id (also manual ones).
function Probe.Check(id, label)
	for _, c in ipairs(Probe.All()) do
		if c.id == id then
			return Store(c, Context(label))
		end
	end
end

-- Context checks run when their event fires (quest giver open, loot window, flight map, ...).
function Probe.OnContext(event)
	local label = event .. (InCombatLockdown() and "/combat" or "")
	for _, c in ipairs(Probe.CHECKS) do
		if c.when == event then
			Store(c, label)
		end
	end
end

function Probe.SetPlan(id, plan)
	if not Probe.PLANS[plan] then
		return false
	end
	for _, c in ipairs(Probe.All()) do
		if c.id == id then
			DB().plan[id] = plan
			return true
		end
	end
	return false
end

-- Copyable report: one tab-separated line per check.
function Probe.Report()
	local db = DB()
	local _, build, _, toc = GetBuildInfo()
	local lines = {
		("# Pathmark probe addon=%s build=%s toc=%s project=%s locale=%s"):format(
			tostring(ns.version),
			tostring(build),
			tostring(toc),
			tostring(WOW_PROJECT_ID),
			GetLocale()
		),
		"# id\tkind\tname\tplan\tresult\tcontext\tdetail",
	}
	for _, c in ipairs(Probe.All()) do
		local r = db.results[c.id]
		lines[#lines + 1] = table.concat({
			c.id,
			c.kind,
			c.name or "",
			db.plan[c.id] or "-",
			r and r.result or "NOT RUN",
			r and r.context or (c.when and ("waits for " .. c.when) or (c.manual and "manual" or "")),
			r and r.detail or "",
		}, "\t")
	end
	for _, b in ipairs(db.blocked) do
		lines[#lines + 1] = table.concat({ "blocked", b.event, b.addon, b.func, b.combat and "combat" or "" }, "\t")
	end
	return table.concat(lines, "\n")
end

-- Events ------------------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
Probe.frame = frame
local contextEvents = {}

local function Record(event, ...)
	local s = Probe.seen[event]
	if not s then
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = (Show((select(i, ...))))
		end
		s = { n = 0, first = table.concat(parts, ", ") }
		Probe.seen[event] = s
	end
	s.n = s.n + 1
end

local function Blocked(event, addon, func)
	local list = DB().blocked
	list[#list + 1] = { event = event, addon = Show(addon), func = Show(func), combat = InCombatLockdown() or nil }
	if #list > MAX_BLOCKED then
		table.remove(list, 1) -- short list
	end
end

frame:SetScript("OnEvent", function(_, event, ...)
	ns.Guard.Call("probe", function(...)
		Record(event, ...)
		if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
			Blocked(event, ...)
		end
		local prefix = ...
		if event == "CHAT_MSG_ADDON" and not U.IsSecret(prefix) and prefix == Probe.PREFIX then
			Probe.loopback = (Probe.loopback or 0) + 1
		end
		if contextEvents[event] then
			Probe.OnContext(event)
		end
	end, ...)
end)

local function Subscribe(event)
	if C_EventUtils.IsEventValid(event) then
		pcall(frame.RegisterEvent, frame, event)
	end
end

-- Subscribe after all files are loaded (Checks.lua and the modules define their lists first).
function Probe.Subscribe()
	for _, c in ipairs(Probe.All()) do
		if c.kind == "event" and not c.noRegister then
			Subscribe(c.name)
		end
		if c.when then
			contextEvents[c.when] = true
			Subscribe(c.when)
		end
	end
	for _, ev in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "CHAT_MSG_ADDON" }) do
		Subscribe(ev)
	end
end

-- Slash: /pathmark probe run [label] | report | check <id> | status <id> <plan> --------------------

ns.Commands.probe = function(rest)
	local sub, a, b = rest:match("^(%S*)%s*(%S*)%s*(%S*)")
	sub = sub:lower()
	if sub == "run" or sub == "" then
		local n = Probe.Run(a ~= "" and a or nil)
		print(L.PROBE_RUN_DONE:format(ADDON, n))
	elseif sub == "check" and a ~= "" then
		local r = Probe.Check(a, b ~= "" and b or nil)
		print(r and ("%s %s: %s %s"):format(ADDON, a, r.result, r.detail) or L.PROBE_UNKNOWN:format(ADDON))
	elseif sub == "status" then
		print(Probe.SetPlan(a, b:lower()) and L.PROBE_STATUS_SET:format(ADDON) or L.PROBE_UNKNOWN:format(ADDON))
	elseif sub == "report" then
		ns.ShowCopy(L.PROBE_TITLE, Probe.Report())
	else
		print(L.PROBE_USAGE:format(ADDON))
	end
end
