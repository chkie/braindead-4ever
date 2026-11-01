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

L.MSG_FLAG_MANDATORY = "%s: %s gehört zum Addon und lässt sich nicht ausschalten"
L.MSG_AFTER_COMBAT = "Pathmark: nach dem Kampf erneut versuchen"

L.COPY_STATUS = "%d Zeichen. Mit Strg+C kopieren."
L.COPY_DONE = "Kopiert."

L.EXPORT_TITLE = "Pathmark: Daten teilen"
L.EXPORT_MORE = "Weitere Daten warten: nach dem Einfügen /pathmark export erneut ausführen."
L.EXPORT_NOTHING = "Pathmark: noch keine neuen Daten zum Teilen"
L.EXPORT_FAILED = "Pathmark: Export fehlgeschlagen (%s)"
L.EXPORT_OFF = "Pathmark: der Datensammler läuft nicht, siehe /pathmark status"
L.ERR_COLLECT_NEWER =
	"Daten aus einer neueren Addon-Version, die Aufzeichnung bleibt aus und die Daten bleiben erhalten"

L.REPORT_TITLE = "Pathmark: Fehler melden"
L.REPORT_OFF = "%s: der Fehlerbericht läuft nicht, siehe /pathmark status"

L.PROBE_TITLE = "Pathmark-Sonde"
L.PROBE_RUN_DONE =
	"%s-Sonde: %d Prüfungen gespeichert. /pathmark probe report zeigt sie, /reload schreibt sie auf die Platte."
L.PROBE_STATUS_SET = "%s-Sonde: Status gesetzt"
L.PROBE_UNKNOWN = "%s-Sonde: unbekannte ID oder unbekannter Status"
L.PROBE_USAGE = "%s-Sonde: run [Bezeichnung] | report | check <ID> | status <ID> planned|built|verified|blocked"

L.STATUS_COLLECTING = "sammelt noch Daten"

L.RIDDLE_quest = "Jemand {where} hat eine Aufgabe zu vergeben."
L.RIDDLE_treasure = "Etwas Wertvolles liegt {where} verborgen."
L.RIDDLE_book = "Ein Buch wartet {where} darauf, gelesen zu werden."
L.RIDDLE_rare = "Ein seltenes Wesen streift {where} umher."
L.RIDDLE_flightpath = "Ein Flugmeister wartet {where}."
L.RIDDLE_place = "Es gibt {where} einen Ort zu entdecken."
L.WHERE_n = "im Norden des Gebiets {zone}"
L.WHERE_ne = "im Nordosten des Gebiets {zone}"
L.WHERE_e = "im Osten des Gebiets {zone}"
L.WHERE_se = "im Südosten des Gebiets {zone}"
L.WHERE_s = "im Süden des Gebiets {zone}"
L.WHERE_sw = "im Südwesten des Gebiets {zone}"
L.WHERE_w = "im Westen des Gebiets {zone}"
L.WHERE_nw = "im Nordwesten des Gebiets {zone}"
L.WHERE_c = "in der Mitte des Gebiets {zone}"
L.RUMOR_quest = "Andere Spieler haben im Gebiet {zone} eine Aufgabe gefunden."
L.RUMOR_treasure = "Andere Spieler haben im Gebiet {zone} etwas Wertvolles gefunden."
L.RUMOR_book = "Andere Spieler haben im Gebiet {zone} ein Buch gefunden."
L.RUMOR_rare = "Andere Spieler haben im Gebiet {zone} ein seltenes Wesen gesehen."
L.RUMOR_flightpath = "Andere Spieler haben im Gebiet {zone} einen Flugmeister gefunden."
L.RUMOR_place = "Andere Spieler haben im Gebiet {zone} einen Ort gefunden."
