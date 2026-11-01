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

-- Locales/enUS.lua: English texts, also the fallback for every other client language.
-- Loads first. Other locale files only overwrite keys; a missing key falls back to its own name.
local _, ns = ...

local L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})
ns.L = L

-- Module states as shown by /pathmark status
L.STATE_planned = "planned"
L.STATE_on = "on"
L.STATE_off = "off"
L.STATE_error = "error"
L.STATE_disabled = "disabled"

-- Reasons why a module is not running
L.WHY_FLAG = "turned off"
L.WHY_SAFE_MODE = "safe mode"
L.WHY_MISSING_API = "missing %s"
L.WHY_MISSING_EVENT = "missing event %s"
L.WHY_INIT = "start failed"
L.WHY_ERROR_BURST = "%d errors in %d s"

-- Chat messages
L.MSG_MODULE_DISABLED = "%s: module %s turned off (%s). Everything else keeps running. /%s status"
L.MSG_SAFE_MODE_AUTO = "%s: did not start cleanly twice, safe mode is on. /%s safe off"
L.MSG_NOT_LOADED = "%s: not loaded yet"
L.MSG_SAFE_MODE_SET = "%s: safe mode %s, takes effect after /reload"
L.MSG_FLAG_SET = "%s: %s %s, takes effect after /reload"
L.WORD_ON = "on"
L.WORD_OFF = "off"

-- Slash command extras
L.MSG_FLAG_MANDATORY = "%s: %s is part of the addon and cannot be turned off"
L.MSG_AFTER_COMBAT = "Pathmark: try again after combat"

-- Copy window
L.COPY_STATUS = "%d characters. Press Ctrl+C to copy."
L.COPY_DONE = "Copied."

-- Export
L.EXPORT_TITLE = "Pathmark: share data"
L.EXPORT_MORE = "More data waiting: run /pathmark export again after pasting."
L.EXPORT_NOTHING = "Pathmark: no new data to share yet"
L.EXPORT_FAILED = "Pathmark: export failed (%s)"
L.EXPORT_OFF = "Pathmark: the data collector is not running, see /pathmark status"
L.ERR_COLLECT_NEWER = "data from a newer addon version, recording stays off and the data is kept"

-- Report a problem
L.REPORT_TITLE = "Pathmark: report a problem"
L.REPORT_OFF = "%s: the report is not running, see /pathmark status"

-- Developer probe
L.PROBE_TITLE = "Pathmark probe"
L.PROBE_RUN_DONE = "%s probe: %d checks saved. /pathmark probe report shows them; /reload writes them to disk."
L.PROBE_STATUS_SET = "%s probe: status set"
L.PROBE_UNKNOWN = "%s probe: unknown id or status"
L.PROBE_USAGE = "%s probe: run [label] | report | check <id> | status <id> planned|built|verified|blocked"

-- Data-dependent values (time forecast, prerequisites nobody has confirmed yet) before enough runs
L.STATUS_COLLECTING = "collecting data"

-- Explorer mode (Routes/Discover.lua). {where}, {zone} are filled from the data; nothing else is added.
-- Riddle (hint level 1, catalog): type, zone and part of the zone.
L.RIDDLE_quest = "Someone {where} has a task to give."
L.RIDDLE_treasure = "Something of value lies hidden {where}."
L.RIDDLE_book = "A book waits to be read {where}."
L.RIDDLE_rare = "A rare creature roams {where}."
L.RIDDLE_flightpath = "A flight master waits {where}."
L.RIDDLE_place = "There is a place to discover {where}."
L.WHERE_n = "in the north of {zone}"
L.WHERE_ne = "in the north-east of {zone}"
L.WHERE_e = "in the east of {zone}"
L.WHERE_se = "in the south-east of {zone}"
L.WHERE_s = "in the south of {zone}"
L.WHERE_sw = "in the south-west of {zone}"
L.WHERE_w = "in the west of {zone}"
L.WHERE_nw = "in the north-west of {zone}"
L.WHERE_c = "in the middle of {zone}"
-- Rumor (hint level 1, finds of other players): type and zone only.
L.RUMOR_quest = "Other players found a task in {zone}."
L.RUMOR_treasure = "Other players found something of value in {zone}."
L.RUMOR_book = "Other players found a book in {zone}."
L.RUMOR_rare = "Other players saw a rare creature in {zone}."
L.RUMOR_flightpath = "Other players found a flight master in {zone}."
L.RUMOR_place = "Other players found a place in {zone}."
