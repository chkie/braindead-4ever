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

-- Locales/deDE.lua: German texts. The TOC loads this file only on deDE clients;
-- the locale check below is a second wall for clients that ignore the TOC condition.
local _, ns = ...
if GetLocale() ~= "deDE" then
	return
end
local L = ns.L

L.STATE_planned = "geplant"
L.STATE_on = "an"
L.STATE_off = "aus"
L.STATE_error = "Fehler"
L.STATE_disabled = "abgeschaltet"

L.WHY_FLAG = "ausgeschaltet"
L.WHY_SAFE_MODE = "sicherer Modus"
L.WHY_MISSING_API = "fehlt: %s"
L.WHY_MISSING_EVENT = "Ereignis fehlt: %s"
L.WHY_INIT = "Start fehlgeschlagen"
L.WHY_ERROR_BURST = "%d Fehler in %d s"

L.MSG_MODULE_DISABLED = "%s: Modul %s abgeschaltet (%s). Der Rest läuft weiter. /%s status"
L.MSG_SAFE_MODE_AUTO = "%s: zweimal nicht sauber gestartet, der sichere Modus ist an. /%s safe off"
L.MSG_NOT_LOADED = "%s: noch nicht geladen"
L.MSG_SAFE_MODE_SET = "%s: sicherer Modus %s, wirkt nach /reload"
L.MSG_FLAG_SET = "%s: %s %s, wirkt nach /reload"
L.WORD_ON = "an"
L.WORD_OFF = "aus"
