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

-- Collector/Version.lua: the version notice (requirement A47, concept §1.5, brain chapter 17 §5 and
-- pattern F). Plain Lua, no WoW API. Other players' addon versions arrive through the exchange (message
-- "a", Collector/Proto.lua); the notice comes only when at least MIN_SENDERS different players report
-- a newer version (DBM and BigWigs ask for more than one, so one player cannot fake it), and only once
-- per session. Pre-release versions ("-beta", "-alpha") count only for players who run one themselves.
-- There is no remote switch-off: anyone could fake it. Sender names live in this table for the session
-- only and are never saved.
local _, ns = ...

local V = {
	MIN_SENDERS = 2, -- chosen value after DBM (2) and BigWigs (more than 1), brain chapter 17 §5
}
V.__index = V
ns.Version = V

-- "v1.2.3", "1.2.3", "v0.1.0-beta.2" -> { 1, 2, 3, pre = bool }; nil for anything else ("dev", a
-- commit hash of an untagged build): such a build neither announces nor compares.
function V.Parse(s)
	if type(s) ~= "string" then
		return nil
	end
	local a, b, c, rest = s:match("^v?(%d+)%.(%d+)%.(%d+)(.*)$")
	if not a or (rest ~= "" and not rest:match("^%-")) then
		return nil
	end
	return { tonumber(a), tonumber(b), tonumber(c), pre = rest ~= "" }
end

-- True when version x is newer than y. With the same numbers a release is newer than its pre-release.
function V.Newer(x, y)
	for i = 1, 3 do
		if x[i] ~= y[i] then
			return x[i] > y[i]
		end
	end
	return y.pre and not x.pre
end

-- "1.2.3" for the status line.
function V.Text(v)
	return ("%d.%d.%d"):format(v[1], v[2], v[3])
end

-- own: the parsed version of this installation (nil: nothing is compared).
function V.New(own)
	return setmetatable({ own = own, seen = {}, told = false }, V)
end

-- A player reported version v. Returns the newest reported version once, when enough players report
-- a newer one; nil otherwise.
function V:Heard(who, v)
	local own = self.own
	if not own or self.told or type(who) ~= "string" then
		return nil
	end
	if v.pre and not own.pre then
		return nil -- pre-releases only for testers who run one
	end
	if not V.Newer(v, own) then
		self.seen[who] = nil
		return nil
	end
	self.seen[who] = v
	local count, newest = 0, nil
	for _, s in pairs(self.seen) do
		count = count + 1
		if not newest or V.Newer(s, newest) then
			newest = s
		end
	end
	if count >= V.MIN_SENDERS then
		self.told = true
		return newest
	end
	return nil
end
