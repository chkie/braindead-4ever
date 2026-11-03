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

-- Core/Guard.lua: own error buffer, module isolation, turning a module off after an error burst.
-- First code file after the locales. NEVER calls seterrorhandler: BugGrabber turns it into a
-- no-op, and Blizzard attaches its error frame, log and crash reporter to that handler.
local _, ns = ...
local L = ns.L

local Guard = {
	MAX = 50, -- entries in the ring buffer; the oldest is overwritten
	DISABLE_AFTER = 5, -- this many errors of one module ...
	WINDOW = 60, -- ... within this many seconds turn the module off
	list = {}, -- ring: { key, module, msg, stack, count, first, last }
	byKey = {}, -- key -> entry (dedup)
	head = 0,
	recent = {}, -- module -> { t1, t2, ... } times of the latest errors
}
ns.Guard = Guard

local issecret = issecretvalue or function()
	return false
end

local function now()
	return GetTime()
end

-- Store error text so that a secret value is never compared, indexed or saved.
local function Clean(v)
	if v == nil then
		return ""
	end
	if issecret(v) then
		return "<secret>"
	end
	return tostring(v)
end

-- Dedup key: module + first line of the message (max. 200 characters). Numbers are kept,
-- so messages with changing IDs become separate entries.
local function KeyOf(module, msg)
	local first = msg:gsub("[\r\n].*", "")
	return module .. "|" .. first:sub(1, 200)
end

function Guard:Record(module, err, stack)
	local msg = Clean(err)
	local key = KeyOf(module, msg)
	local t = now()
	local e = self.byKey[key]
	if e then
		e.count, e.last = e.count + 1, t
	else
		self.head = self.head % self.MAX + 1
		local old = self.list[self.head]
		if old then
			self.byKey[old.key] = nil
		end
		e = {
			key = key,
			module = module,
			msg = msg,
			stack = Clean(stack):sub(1, 1200),
			count = 1,
			first = t,
			last = t,
		}
		self.list[self.head], self.byKey[key] = e, e
		-- Only the FIRST occurrence per session goes to the active handler (BugSack/Blizzard).
		-- Fetch geterrorhandler() now, never cache it (BugGrabber may load later).
		if not (ns.db and ns.db.flags and ns.db.flags.quietErrors) then
			local h = geterrorhandler()
			if h then
				pcall(h, L.TITLE .. " [" .. module .. "] " .. msg)
			end
		end
	end
	ns.LastError = e
	-- Error burst per module: turn it off after DISABLE_AFTER errors within WINDOW.
	local r = self.recent[module] or {}
	self.recent[module] = r
	r[#r + 1] = t
	while r[1] and t - r[1] > self.WINDOW do
		table.remove(r, 1) -- short list
	end
	if #r >= self.DISABLE_AFTER and ns.Modules and ns.Modules.IsActive(module) then
		ns.Modules.Disable(module, L.WHY_ERROR_BURST:format(#r, self.WINDOW))
	end
end

-- Handler for xpcall: keeps the stack and returns a string (WoW replaces anything else).
local function MakeHandler(module)
	return function(err)
		local stack = debugstack and debugstack(2, 12, 0) or nil
		Guard:Record(module, err, stack)
		return Clean(err)
	end
end
local handlers = setmetatable({}, {
	__index = function(t, m)
		local h = MakeHandler(m)
		t[m] = h
		return h
	end,
})

local function After(ok, ...)
	if ok then
		return ...
	end
end

-- Wrap: calls fn protected. WoW's xpcall passes extra arguments through (unlike stock Lua 5.1),
-- so no closure and no table per call. Do not use inside coroutines that yield.
function Guard.Wrap(module, fn)
	local handler = handlers[module]
	return function(...)
		local M = ns.Modules -- only registered modules can be turned off
		if M and M.defs[module] and not M.IsActive(module) then
			return
		end
		return After(xpcall(fn, handler, ...))
	end
end

function Guard.Call(module, fn, ...)
	return After(xpcall(fn, handlers[module], ...))
end

-- Copyable text for the error report.
function Guard:Report()
	local out = {}
	for i = 1, #self.list do
		local e = self.list[i]
		out[#out + 1] = ("%dx [%s] %s"):format(e.count, e.module, e.msg)
	end
	table.sort(out)
	return table.concat(out, "\n")
end
