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

-- Collector/Migrate.lua: versioned migration of SavedVariables (pattern after JourneyTracker, MIT; own code).
-- Rules: a migration runs on a COPY. If one step fails, the saved table stays exactly as it was and the
-- caller keeps recording off for the session, so a half-migrated table is never saved.
local _, ns = ...
local Copy = ns.Util.Copy

local Migrate = {}
ns.Migrate = Migrate

-- saved: table from SavedVariables; schema: target version; steps[v] lifts version v-1 to v.
-- Returns the table to use (the same one when nothing changed) or nil plus the reason.
function Migrate.Upgrade(saved, schema, steps)
	local from = tonumber(saved.schema) or 0
	if from > schema then
		return nil, "newer"
	end
	if from == schema then
		return saved
	end
	local work = Copy(saved)
	for v = from + 1, schema do
		local ok, err = pcall(steps[v], work)
		if not ok then
			return nil, ("step %d: %s"):format(v, tostring(err))
		end
		work.schema = v
	end
	return work
end
