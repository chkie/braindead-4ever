-- SPDX-License-Identifier: GPL-3.0-or-later
-- A game session for the interface tests: real route data (human warrior, Elwynn Forest), the UI
-- stand-ins of spec/helpers/ui.lua and a few quest titles in the player's language.
local wow = require("spec.helpers.wow")

local S = {}

-- Titles the stand-in client knows (C_QuestLog.GetTitleForQuestID); IDs from the Elwynn route.
S.TITLES = {
	enUS = { [33] = "Wolves Across the Border", [783] = "A Threat Within", [7] = "Kobold Camp Cleanup" },
	deDE = { [33] = "Wölfe an der Grenze", [783] = "Eine Bedrohung von innen", [7] = "Säuberung im Koboldlager" },
}

-- opts: locale, saved (PathmarkDB), char, level, xp, xpMax, style (default "arrow" = speed route),
-- setup (false = first start, setup not done), hint (false = usage hint not seen yet), combat,
-- before(world) to change the client state before the files load.
function S.login(opts)
	opts = opts or {}
	local saved = opts.saved or {}
	if opts.setup ~= false then
		saved.ui = saved.ui or {}
		saved.ui.setupDone = true
		saved.ui.style = saved.ui.style or opts.style or "arrow"
		if opts.hint ~= false then
			saved.ui.hintsSeen = saved.ui.hintsSeen or { rightclick = true }
		end
	end
	wow.reset({ saved = saved, char = opts.char, locale = opts.locale })
	local W = wow.world
	local P = W.player
	P.level, P.xp, P.xpMax = opts.level or 1, opts.xp or 0, opts.xpMax or 400
	for q, title in pairs(S.TITLES[opts.locale or "enUS"] or S.TITLES.enUS) do
		W.titles[q] = title
	end
	W.combat = opts.combat == true
	if opts.before then
		opts.before(W)
	end
	local files = wow.addonFiles(opts.probe)
	if opts.locale == "deDE" then
		table.insert(files, 2, "Pathmark/Locales/deDE.lua") -- the TOC loads it only in German clients
	end
	local ns = wow.loadFiles(files)
	if opts.loaded then
		opts.loaded(ns) -- the addon files are loaded, nothing has run yet (e.g. to change route data)
	end
	wow.fire("ADDON_LOADED", "Pathmark")
	wow.fire("PLAYER_LOGIN")
	wow.fire("PLAYER_ENTERING_WORLD", true, false)
	wow.advance(0.5)
	return ns
end

-- Combat on and off like the client: lockdown starts after PLAYER_REGEN_DISABLED, ends before ENABLED.
function S.combat(on)
	if on then
		wow.fire("PLAYER_REGEN_DISABLED")
		wow.world.combat = true
	else
		wow.world.combat = false
		wow.fire("PLAYER_REGEN_ENABLED")
	end
end

-- Puts the player at a world position (west, north) on continent inst.
function S.place(west, north, inst)
	local P = wow.world.player
	P.west, P.north, P.inst = west, north, inst or 0
end

-- The player faces so that the goal lies `deg` degrees off the course (counterclockwise).
function S.face(ns, target, deg)
	local _, angle = ns.Nav.Vector(target)
	wow.world.player.facing = angle - math.rad(deg)
end

-- Text of a menu item by its position, and the item itself.
function S.menu(ns)
	local W = ns.StepFrame.frame
	W.scripts.OnMouseUp(W, "RightButton")
	return wow.menu
end

function S.item(menu, text)
	for _, item in ipairs(menu.items) do
		if item.text == text then
			return item
		end
	end
end

return S
