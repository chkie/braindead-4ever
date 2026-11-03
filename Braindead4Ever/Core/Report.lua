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

-- Core/Report.lua: "report a problem" as copyable text: version, build, module states, current step,
-- position, quest log state and the error buffer. No character, realm or other player names.
-- The player's note is marked as player input and never goes into route data.
-- The body is a fixed English format (like an error log) so the team's tools can read every report;
-- only the window title is localized.
local _, ns = ...
local U = ns.Util
local M = ns.Modules
local Num, Str = U.Num, U.Str

local Report = {}
ns.Report = Report

-- Current route step, set by the route module (Routes/Guide.lua). Without a route the report says "-".
function Report.Step()
	local fn = ns.CurrentStep
	local step = type(fn) == "function" and fn() or nil
	return step and tostring(step) or "-"
end

function Report.Build(note)
	local lines = {}
	local function add(fmt, ...)
		lines[#lines + 1] = fmt:format(...)
	end
	local _, build, _, toc = GetBuildInfo()
	add(
		"Braindead 4ever report v1 | addon %s | build %s | toc %s | %s",
		tostring(ns.version),
		tostring(build),
		tostring(toc),
		GetLocale()
	)
	add("Step: %s", Report.Step())
	local _, race = UnitRace("player")
	local _, class = UnitClass("player")
	add(
		"Level %s | %s/%s | %s",
		tostring(Num(UnitLevel("player")) or "?"),
		Str(race) or "?",
		Str(class) or "?",
		Str((UnitFactionGroup("player"))) or "?"
	)
	local map, x, y = U.Pos()
	if map and x and y then
		add("Position: map %d | %.2f, %.2f", map, x / 100, y / 100)
	else
		add("Position: map %s | no coordinate", tostring(map or "-"))
	end
	add("Modules:")
	for line in M.Report():gmatch("[^\n]+") do
		add("  %s", line)
	end
	add("Quest log:")
	local shown = Num((C_QuestLog.GetNumQuestLogEntries())) or 0
	for i = 1, shown do
		local info = C_QuestLog.GetInfo(i)
		local q = info and not info.isHeader and Num(info.questID)
		if q and q > 0 then
			local objs = {}
			for j, o in ipairs(C_QuestLog.GetQuestObjectives(q) or {}) do
				objs[j] = ("%d/%d%s"):format(
					Num(o.numFulfilled) or 0,
					Num(o.numRequired) or 0,
					o.finished and "+" or ""
				)
			end
			add(
				"  %d [%s] %s%s",
				q,
				C_QuestLog.IsComplete(q) and "done" or "open",
				table.concat(objs, " "),
				C_QuestLog.IsFailed(q) and " FAILED" or ""
			)
		end
	end
	add("Errors:")
	local errors = ns.Guard:Report()
	if errors == "" then
		add("  none")
	else
		for line in errors:gmatch("[^\n]+") do
			add("  %s", line)
		end
	end
	-- Interface: atlases the client did not have (UI/Theme.lua, rule N2).
	if ns.Theme and ns.Theme.ReportLines then
		for _, line in ipairs(ns.Theme.ReportLines()) do
			add("%s", line)
		end
	end
	if type(note) == "string" and note ~= "" then
		add("Note (player input): %s", (note:gsub("[\r\n]", " ")))
	end
	return table.concat(lines, "\n")
end

function Report.Show(note)
	return ns.ShowCopy(ns.L.REPORT_TITLE, Report.Build(note))
end

ns.Commands.report = function(rest)
	if not M.IsActive("report") then
		print(ns.L.REPORT_OFF:format(ns.L.TITLE))
		return
	end
	ns.Guard.Call("report", Report.Show, rest)
end

M.Define("report", {
	core = true,
	requires = {
		funcs = {
			"C_QuestLog.GetNumQuestLogEntries",
			"C_QuestLog.GetInfo",
			"C_QuestLog.GetQuestObjectives",
			"C_QuestLog.IsComplete",
			"C_QuestLog.IsFailed",
			"C_Map.GetBestMapForUnit",
			"C_Map.GetPlayerMapPosition",
		},
	},
})
