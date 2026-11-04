-- SPDX-License-Identifier: GPL-3.0-or-later
-- A game session for the interface tests: real route data (human warrior, Elwynn Forest), the UI
-- stand-ins of spec/helpers/ui.lua and a few quest titles in the player's language.
local wow = require("spec.helpers.wow")

local S = {}

-- The route starts with a783 (accept 783 "A Threat Within") at the place where the player stands after the
-- login (spec/helpers/ui.lua: -136.5 west, -8933.5 north). Tests that need the first goal at a distance stand
-- here instead: 70 yd south-west of it, so the goal lies 70 yd north-east of the player.
S.AWAY = { west = -110.0, north = -8998.0 }

-- Login option `before` that puts the player at S.AWAY.
function S.away(W)
	W.player.west, W.player.north = S.AWAY.west, S.AWAY.north
end

-- Titles the stand-in client knows (C_QuestLog.GetTitleForQuestID); IDs from the Elwynn route.
S.TITLES = {
	enUS = { [33] = "Wolves Across the Border", [783] = "A Threat Within", [7] = "Kobold Camp Cleanup" },
	deDE = { [33] = "Wölfe an der Grenze", [783] = "Eine Bedrohung von innen", [7] = "Säuberung im Koboldlager" },
}

-- opts: locale, saved (BraindeadForeverDB), char, version (TOC version), level, xp, xpMax, style (default
-- "arrow" = speed route),
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
	wow.reset({ saved = saved, char = opts.char, locale = opts.locale, version = opts.version })
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
		table.insert(files, 2, "Braindead4Ever/Locales/deDE.lua") -- the TOC loads it only in German clients
	end
	local ns = wow.loadFiles(files)
	if opts.loaded then
		opts.loaded(ns) -- the addon files are loaded, nothing has run yet (e.g. to change route data)
	end
	wow.fire("ADDON_LOADED", "Braindead4Ever")
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

-- What the client does when a dragged frame is released (Frame:StopMovingOrSizing, warcraft.wiki.gg):
-- the frame stays where it is on screen and is anchored at the point closest to a UIParent point. The
-- stand-in screen is UIParent in its own units (spec/helpers/ui.lua U.layout), window scale 1.
function S.drop(f, left, top)
	local ui = _G.UIParent
	local w, h = f:GetWidth() or 0, f:GetHeight() or 0
	f.left, f.top, f.right, f.bottom = left, top, left + w, top - h
	local best
	for _, v in ipairs({ { "TOP", 1 }, { "", 0.5 }, { "BOTTOM", 0 } }) do
		for _, hz in ipairs({ { "LEFT", 0 }, { "", 0.5 }, { "RIGHT", 1 } }) do
			local name = (v[1] .. hz[1] ~= "") and (v[1] .. hz[1]) or "CENTER"
			local fx, fy = left + w * hz[2], top - h * (1 - v[2])
			local px, py = ui.w * hz[2], ui.h * v[2]
			local d = (fx - px) ^ 2 + (fy - py) ^ 2
			if not best or d < best[1] then
				best = { d, name, fx - px, fy - py }
			end
		end
	end
	f:ClearAllPoints()
	f:SetPoint(best[2], ui, best[2], best[3], best[4])
	return best[2]
end

-- The atlas Navigation-Tracked-Arrow is not white: its fill is orange gold. Median of the fill pixels in
-- file 3308452 (interface/navigation/ingamenavigationui, region 0.0156..0.3594 x 0.5625..0.8438 after
-- Ketho AtlasInfo forever), downloaded from wago.tools and decoded on 2026-11-02: 194/113/0.
S.ARROW_ATLAS = { 194 / 255, 113 / 255, 0 }

-- Color of the arrow as the client draws it: texture times vertex color, desaturated textures gray
-- (luminance weights 0.299/0.587/0.114), an additive copy adds its own color; clamped to 1. The own
-- arrow texture (Media/arrow.tga, since 0.9.1) is white; the old atlas was orange gold.
function S.drawnArrow(F)
	local function layer(tex)
		local a = S.ARROW_ATLAS
		if rawget(tex, "file") then
			a = { 1, 1, 1 }
		end
		local base = { a[1], a[2], a[3] }
		if rawget(tex, "desaturated") then
			local g = 0.299 * a[1] + 0.587 * a[2] + 0.114 * a[3]
			base = { g, g, g }
		end
		local v = rawget(tex, "vertex") or { 1, 1, 1 }
		return { base[1] * v[1], base[2] * v[2], base[3] * v[3] }
	end
	local out = layer(F.tex)
	local lift = rawget(F, "lift")
	if lift and rawget(lift, "shown") ~= false and lift.blend == "ADD" then
		local add = layer(lift)
		for i = 1, 3 do
			out[i] = out[i] + add[i]
		end
	end
	for i = 1, 3 do
		out[i] = math.min(1, out[i])
	end
	return out
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
