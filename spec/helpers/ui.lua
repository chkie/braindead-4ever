-- SPDX-License-Identifier: GPL-3.0-or-later
-- Interface stand-ins for the offline tests (Welle 5): widget methods the windows use, Blizzard's
-- settings panel, menus, HelpTip, StaticPopup, fonts, colors, atlases, sounds, tooltip, positions,
-- world map, minimap and the addon compartment. Shapes follow the Forever sources the code was written
-- against (Gethe/wow-ui-source branch forever, build 70532; brain chapters 04, 07, 18); they describe
-- what the code expects, not a live client.
--
-- Combat audit (release rule "no protected call in combat"): calls that are restricted or that the
-- design forbids in combat record their name in M.blocked while W.combat is true, like the client's
-- ADDON_ACTION_BLOCKED. spec/ui_combat_spec.lua asserts the list stays empty.
local U = {}

-- Calls audited in combat. Settings.OpenToCategory and the waypoint calls carry restrictions in the
-- docs or are unconfirmed (chapters 04 §9, 07 §3); HelpTip:Show may taint (chapter 18 §3.2); PlaySound
-- and the setup window are forbidden in combat by the design (rules N7, R1).
U.AUDITED = {
	"Settings.OpenToCategory",
	"HelpTip.Show",
	"C_Map.SetUserWaypoint",
	"C_Map.ClearUserWaypoint",
	"C_SuperTrack.SetSuperTrackedUserWaypoint",
	"PlaySound",
	"BraindeadForeverSetupFrame:Show",
	-- Welle 5b: sizing the step window and Blizzard's quest tracker are kept out of fights by the
	-- owner's decision (ENTWURF-LESUNG points 14 and 15)
	"Frame:StartSizing",
	"C_QuestLog.AddQuestWatch",
	"C_QuestLog.RemoveQuestWatch",
	"ObjectiveTrackerFrame:SetAlpha",
	-- Welle 5c: windows move by drag outside Edit Mode, never in a fight (ENTWURF-LESUNG point 16)
	"Frame:StartMoving",
	-- Welle 8: the page "Your run" and the review card open only out of a fight
	"BraindeadForeverStatsFrame:Show",
	"BraindeadForeverRecapFrame:Show",
}

local function Color(r, g, b)
	return {
		r = r,
		g = g,
		b = b,
		GetRGB = function(self)
			return self.r, self.g, self.b
		end,
		WrapTextInColorCode = function(self, text)
			return ("|cff%02x%02x%02x%s|r"):format(self.r * 255, self.g * 255, self.b * 255, tostring(text))
		end,
	}
end
U.Color = Color

local function Vector(x, y)
	return {
		x = x,
		y = y,
		GetXY = function(self)
			return self.x, self.y
		end,
	}
end

local function copyInto(dst, src)
	for k, v in pairs(src) do
		dst[k] = v
	end
	return dst
end

function U.install(M, W, opts)
	local Frame, NewWidget = M.Frame, M.NewWidget
	local de = opts.locale == "deDE"
	M.blocked = {}
	local function audit(name)
		if W.combat then
			M.blocked[#M.blocked + 1] = name
		end
	end
	M.audit = audit
	M.knownEvents.CVAR_UPDATE = true
	for _, e in ipairs({
		"MODIFIER_STATE_CHANGED",
		"EDIT_MODE_LAYOUTS_UPDATED",
		"DISPLAY_SIZE_CHANGED",
		"UI_SCALE_CHANGED",
	}) do
		M.knownEvents[e] = true
	end
	-- Named frames and fonts of the last session (the client starts a new UI session empty).
	for _, name in ipairs({
		"BraindeadForeverSetupFrame",
		"BraindeadForeverStatsFrame",
		"BraindeadForeverStatsFrameTab1",
		"BraindeadForeverStatsFrameTab2",
		"BraindeadForeverStatsFrameTab3",
		"BraindeadForeverRecapFrame",
		"BraindeadForeverFontHeader",
		"BraindeadForeverFontStep",
		"BraindeadForeverFontLine",
		"BraindeadForeverFontSmall",
		"BraindeadForeverFontStatus",
	}) do
		_G[name] = nil
	end

	-- World state the windows read
	local P = W.player
	P.north, P.west, P.inst, P.facing = -8933.5, -136.5, 0, 0
	W.cvars.userFontScale = "1"
	W.cvars.colorblindMode = "0"
	W.cvars.rotateMinimap = "0"
	W.titles = {} -- questID -> title (C_QuestLog.GetTitleForQuestID)
	W.titleRequests = {}
	W.items = {}
	W.missingAtlas = {}
	W.sounds = {}
	W.helptips = {}
	W.helptipResult = true
	W.uiErrors = {}
	W.waypoint = nil
	W.areas = { [1581] = de and "Die Todesminen" or "The Deadmines" }
	W.supertrack = nil
	-- Elwynn Forest 1429 has the same world bounds in Forever as in Classic (brain chapter 07 §2).
	W.continents = { [1429] = 0, [1436] = 0, [1453] = 0, [1411] = 1 }
	W.mapBounds = { [1429] = { n1 = -10254.17, n2 = -7939.58, w1 = -1935.42, w2 = 1535.42 } }
	W.mapInfo[1429] = { mapID = 1429, name = de and "Wald von Elwynn" or "Elwynn Forest", parentMapID = 1415 }
	W.mapInfo[1436] = { mapID = 1436, name = "Westfall", parentMapID = 1415 }
	W.mapInfo[1415] = { mapID = 1415, name = de and "Östliche Königreiche" or "Eastern Kingdoms" }

	-- Widget methods ----------------------------------------------------------------------------------
	function Frame:SetSize(w, h)
		self.w, self.h = w, h
	end
	function Frame:SetWidth(w)
		self.w = w
	end
	function Frame:SetHeight(h)
		self.h = h
	end
	function Frame:GetWidth()
		return rawget(self, "w")
	end
	function Frame:GetHeight()
		return rawget(self, "h")
	end
	function Frame:SetPoint(point, rel, relPoint, x, y)
		if type(rel) == "number" then
			rel, relPoint, x, y = nil, point, rel, relPoint
		elseif type(relPoint) == "number" then
			relPoint, x, y = point, relPoint, x
		end
		local list = rawget(self, "points") or {}
		self.points = list
		list[#list + 1] = { point, rel, relPoint or point, x or 0, y or 0 }
	end
	function Frame:ClearAllPoints()
		self.points = {}
	end
	function Frame:GetPoint(i)
		local p = rawget(self, "points") and rawget(self, "points")[i or 1]
		if p then
			return p[1], p[2], p[3], p[4], p[5]
		end
	end
	function Frame:SetAllPoints(rel)
		self.points = { { "TOPLEFT", rel }, { "BOTTOMRIGHT", rel } }
	end
	function Frame:Show()
		local was = rawget(self, "shown")
		self.shown = true
		if not was and self.scripts.OnShow then
			self.scripts.OnShow(self)
		end
	end
	function Frame:Hide()
		local was = rawget(self, "shown")
		self.shown = false
		if was and self.scripts.OnHide then
			self.scripts.OnHide(self)
		end
	end
	function Frame:SetShown(on)
		if on then
			self:Show()
		else
			self:Hide()
		end
	end
	function Frame:IsVisible()
		local f = self
		while f do
			if rawget(f, "shown") ~= true and f ~= _G.UIParent and f ~= _G.Minimap then
				return false
			end
			f = rawget(f, "parent")
		end
		return true
	end
	function Frame:SetAlpha(a)
		self.alpha = a
	end
	function Frame:GetAlpha()
		return rawget(self, "alpha") or 1
	end
	function Frame:SetScale(s)
		self.scale = s
	end
	function Frame:GetScale()
		return rawget(self, "scale") or 1
	end
	function Frame:GetEffectiveScale()
		return rawget(self, "scale") or 1
	end
	function Frame:GetCenter()
		return 0, 0
	end
	function Frame:SetAtlas(name)
		self.atlas, self.colorTexture = name, nil
	end
	function Frame:SetColorTexture(r, g, b, a)
		self.atlas, self.colorTexture = nil, { r, g, b, a }
	end
	function Frame:SetVertexColor(r, g, b, a)
		self.vertex = { r, g, b, a }
	end
	function Frame:SetRotation(r)
		self.rotation = r
	end
	function Frame:SetDesaturated(on)
		self.desaturated = on and true or false
	end
	function Frame:SetBlendMode(mode)
		self.blend = mode
	end
	function Frame:SetTextColor(r, g, b)
		self.textColor = { r, g, b }
	end
	function Frame:SetFontObject(o)
		self.font = o
	end
	function Frame:SetMaxLines(n)
		self.maxLines = n
	end
	function Frame:GetStringHeight()
		local t = rawget(self, "text")
		if t == nil or t == "" then
			return 0
		end
		local lines = 1
		for _ in tostring(t):gmatch("\n") do
			lines = lines + 1
		end
		lines = lines + math.floor(#tostring(t) / 48)
		if rawget(self, "maxLines") and lines > rawget(self, "maxLines") then
			lines = rawget(self, "maxLines")
		end
		return lines * 14
	end
	function Frame:GetStringWidth()
		return #tostring(rawget(self, "text") or "") * 6
	end
	function Frame:GetFontString()
		local fs = rawget(self, "fs") or NewWidget("FontString", nil, nil, self)
		self.fs = fs
		fs.text = rawget(self, "text")
		return fs
	end
	function Frame:EnableMouse(on)
		self.mouse = on
	end
	function Frame:SetChecked(on)
		self.checked = on and true or false
	end
	function Frame:GetChecked()
		return rawget(self, "checked") == true
	end
	function Frame:SetMouseMotionEnabled(on)
		self.motion = on
	end
	function Frame:SetMouseClickEnabled(on)
		self.clicks = on
	end
	function Frame:SetMovable(on)
		self.movable = on
	end
	function Frame:StartMoving()
		audit("Frame:StartMoving")
		if not rawget(self, "movable") then
			error("Frame is not movable", 2)
		end
		self.moving = true
	end
	function Frame:StopMovingOrSizing()
		self.moving = false
		self.sizingPoint = nil
	end
	function Frame:SetResizable(on)
		self.resizable = on
	end
	function Frame:SetResizeBounds(minW, minH, maxW, maxH)
		self.bounds = { minW, minH, maxW, maxH }
	end
	function Frame:StartSizing(point)
		audit("Frame:StartSizing")
		if not rawget(self, "resizable") then
			error("Frame is not resizable", 2)
		end
		self.sizingPoint = point or "BOTTOMRIGHT"
	end
	-- Screen edges: a fixed spot unless a test sets left/top. norect = true: the frame has no rectangle
	-- yet and all four return nil, like the client before the frame's first layout.
	function Frame:GetLeft()
		if rawget(self, "norect") then
			return nil
		end
		return rawget(self, "left") or 100
	end
	function Frame:GetTop()
		if rawget(self, "norect") then
			return nil
		end
		return rawget(self, "top") or 700
	end
	function Frame:GetRight()
		if rawget(self, "norect") then
			return nil
		end
		return rawget(self, "right") or (self:GetLeft() + (self:GetWidth() or 0))
	end
	function Frame:GetBottom()
		if rawget(self, "norect") then
			return nil
		end
		return rawget(self, "bottom") or (self:GetTop() - (self:GetHeight() or 0))
	end
	function Frame:SetHighlightTexture(texture)
		self.highlight = texture
	end
	function Frame:SetEnabled(on)
		self.enabled = on and true or false
	end
	function Frame:IsEnabled()
		return rawget(self, "enabled") ~= false
	end
	function Frame:Click(button)
		local fn = self.scripts.OnClick
		if fn then
			fn(self, button or "LeftButton")
		end
	end
	function Frame:HookScript(name, fn)
		local old = self.scripts[name]
		self.scripts[name] = function(...)
			if old then
				old(...)
			end
			fn(...)
		end
	end
	function Frame:CreateAnimationGroup()
		local g = { played = 0, scripts = {} }
		g.CreateAnimation = function()
			return setmetatable({}, {
				__index = function()
					return function() end
				end,
			})
		end
		g.Restart = function(group)
			group.played = group.played + 1
		end
		g.Play = g.Restart
		g.Stop = function() end
		g.SetScript = function(group, name, fn)
			group.scripts[name] = fn
		end
		local list = rawget(self, "animations") or {}
		self.animations = list
		list[#list + 1] = g
		return g
	end
	-- Font objects
	function Frame:CopyFontObject(o)
		self.copyOf, self.size = o, o and o.size
	end
	function Frame:SetFontHeight(h)
		self.size = h
	end
	function Frame:GetFont()
		return "Fonts\\FRIZQT__.TTF", rawget(self, "size") or 12, ""
	end

	local baseCreate = _G.CreateFrame
	_G.CreateFrame = function(kind, name, parent, template)
		local f = baseCreate(kind, name, parent, template)
		if template == "BasicFrameTemplateWithInset" then
			f.TitleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			f.CloseButton = baseCreate("Button", nil, f)
			f.CloseButton:SetScript("OnClick", function()
				f:Hide()
			end)
		end
		if template == "WowScrollBox" then
			f.updates, f.offset = 0, 0
			function f.SetPanExtent(box, n)
				box.pan = n
			end
			-- Blizzard measures the scrollable child against its own height (ScrollBoxLinearView.lua).
			function f.FullUpdate(box)
				box.updates = box.updates + 1
				local child = rawget(box, "child")
				local extent, visible = child and child:GetHeight() or 0, box:GetHeight() or 0
				box.scrollable = extent > visible + 0.5
				-- ScrollBarMixin:Update (ScrollBar.lua, live and forever): the bar toggles itself only
				-- while hideIfUnscrollable is on; otherwise the owner's Show and Hide stay.
				local bar = rawget(box, "bar")
				if bar and rawget(bar, "hideIfUnscrollable") then
					bar:SetShown(box.scrollable)
				end
			end
			function f.ScrollToBegin(box)
				box.offset = 0
			end
		elseif template == "MinimalScrollBar" then
			function f.SetHideIfUnscrollable(bar, on)
				bar.hideIfUnscrollable = on
				local box = rawget(bar, "box")
				if on and box then -- SetHideIfUnscrollable calls Update
					bar:SetShown(rawget(box, "scrollable") == true)
				end
			end
		end
		if
			name == "BraindeadForeverSetupFrame"
			or name == "BraindeadForeverStatsFrame"
			or name == "BraindeadForeverRecapFrame"
		then
			local show = f.Show
			f.Show = function(self)
				audit(name .. ":Show")
				show(self)
			end
		end
		return f
	end
	-- Static scroll box (wow-ui-source forever Shared/Scroll): the view takes the children flagged
	-- `scrollable`; the scroll bar follows the box.
	_G.ScrollBoxConstants = { UpdateImmediately = true, NoScrollInterpolation = true, RetainScrollPosition = true }
	_G.CreateScrollBoxLinearView = function()
		return {
			SetPanExtent = function(view, n)
				view.pan = n
			end,
		}
	end
	_G.ScrollUtil = {
		InitScrollBoxWithScrollBar = function(box, bar, view)
			assert(view and bar and box, "scroll box, bar and view needed")
			box.view, box.bar, bar.box = view, bar, box
			for _, w in ipairs(M.frames) do
				if rawget(w, "parent") == box and rawget(w, "scrollable") then
					box.child = w
				end
			end
		end,
	}
	_G.CreateFont = function(name)
		return NewWidget("Font", name)
	end
	local function Font(size, color)
		local f = NewWidget("Font")
		f.size, f.color = size, color
		return f
	end
	_G.ObjectiveTrackerHeaderFont = Font(14)
	_G.ObjectiveTrackerFont15 = Font(15)
	_G.ObjectiveTrackerFont13 = Font(13)
	_G.ObjectiveTrackerFont12 = Font(12)
	_G.ObjectiveTrackerLineFont = Font(12)
	_G.GameFontNormal = Font(12)
	_G.GameFontHighlight = Font(12)
	_G.GameFontHighlightSmall = Font(10)
	_G.GameFontNormalSmall = Font(10)
	_G.GameFontNormalMed3 = Font(14)
	_G.GameFontNormalLarge = Font(16)
	-- Outline fonts (Blizzard_Fonts_Shared/Shared/FontStyles.xml, live and forever)
	_G.GameFontNormalOutline = Font(12)
	_G.GameFontHighlightOutline = Font(12)

	-- Colors, strings, sounds -------------------------------------------------------------------------
	_G.NORMAL_FONT_COLOR = Color(1, 0.82, 0)
	_G.HIGHLIGHT_FONT_COLOR = Color(1, 1, 1)
	_G.DIM_RED_FONT_COLOR = Color(0.8, 0.1, 0.1)
	_G.OBJECTIVE_TRACKER_COLOR = {
		Normal = Color(0.8, 0.8, 0.8),
		Complete = Color(0.6, 0.6, 0.6),
		Failed = _G.DIM_RED_FONT_COLOR,
	}
	_G.IN_GAME_NAVIGATION_RANGE = de and "%s |4m" or "%s |4yd:yds"
	_G.NAVIGATION_DESTINATION_REACHED_MESSAGE = de and "Ziel erreicht" or "Reached destination"
	_G.HUD_EDIT_MODE_MENU = de and "Bearbeitungsmodus" or "Edit Mode"
	_G.XP = de and "EP" or "XP"
	_G.CANCEL = de and "Abbrechen" or "Cancel"
	_G.OPTIONAL = "Optional"
	_G.LFG_TYPE_DUNGEON = "Dungeon"
	_G.BreakUpLargeNumbers = function(n)
		local s = tostring(math.floor(n))
		local sep = de and "." or ","
		local out = s:reverse():gsub("(%d%d%d)", "%1" .. sep):reverse():gsub("^%" .. sep, "")
		return out
	end
	_G.SOUNDKIT = {
		IG_QUEST_LIST_COMPLETE = 878,
		UI_EXPERIENCE_PRESET_SELECT_CLICK = 366430,
		UI_EXPERIENCE_PRESET_OPTION_CLICK = 366431,
	}
	_G.PlaySound = function(id)
		audit("PlaySound")
		W.sounds[#W.sounds + 1] = id
	end
	_G.UIErrorsFrame = NewWidget("Frame")
	function _G.UIErrorsFrame.AddMessage(_, msg)
		W.uiErrors[#W.uiErrors + 1] = msg
	end

	-- Tooltip
	local tip = NewWidget("GameTooltip", "GameTooltip")
	W.tooltip = { lines = {} }
	function tip.SetOwner(_, owner)
		W.tooltip = { owner = owner, lines = {} }
	end
	function tip.SetText(_, text)
		W.tooltip.lines = { text }
	end
	function tip.AddLine(_, text)
		W.tooltip.lines[#W.tooltip.lines + 1] = text
	end

	-- Atlases
	_G.C_Texture = {
		GetAtlasInfo = function(name)
			if W.missingAtlas[name] then
				return nil
			end
			return { width = 19, height = 19, file = 1 }
		end,
	}

	-- Quest titles and items
	_G.C_QuestLog.GetTitleForQuestID = function(q)
		return W.titles[q]
	end
	_G.C_QuestLog.RequestLoadQuestByID = function(q)
		W.titleRequests[q] = true
	end
	-- Quest watch list (QuestLogDocumentation.lua forever). W.watch(q, on) is Blizzard's own mark or a
	-- click of the player (not addon code, not audited); the addon's calls are audited.
	M.knownEvents.QUEST_WATCH_LIST_CHANGED = true
	W.watches = {}
	local function setWatch(q, on)
		for i, w in ipairs(W.watches) do
			if w == q then
				if on then
					return false
				end
				table.remove(W.watches, i)
				M.fire("QUEST_WATCH_LIST_CHANGED", q, false)
				return true
			end
		end
		if not on or #W.watches >= 25 or not _G.C_QuestLog.GetLogIndexForQuestID(q) then
			return false
		end
		W.watches[#W.watches + 1] = q
		M.fire("QUEST_WATCH_LIST_CHANGED", q, true)
		return true
	end
	W.watch = setWatch
	_G.C_QuestLog.AddQuestWatch = function(q)
		audit("C_QuestLog.AddQuestWatch")
		return setWatch(q, true)
	end
	_G.C_QuestLog.RemoveQuestWatch = function(q)
		audit("C_QuestLog.RemoveQuestWatch")
		return setWatch(q, false)
	end
	_G.C_QuestLog.GetNumQuestWatches = function()
		return #W.watches
	end
	_G.C_QuestLog.GetQuestIDForQuestWatchIndex = function(i)
		return W.watches[i]
	end
	_G.Constants = { QuestWatchConsts = { MAX_QUEST_WATCHES = 25 } }
	-- Blizzard's quest tracker: only its alpha is touched.
	local tracker = NewWidget("Frame", "ObjectiveTrackerFrame")
	function tracker.SetAlpha(self, a)
		audit("ObjectiveTrackerFrame:SetAlpha")
		self.alpha = a
	end

	_G.C_Item = {
		GetItemNameByID = function(id)
			return W.items[id]
		end,
	}

	-- Positions and maps
	_G.UnitPosition = function(u)
		if u == "player" and P.north then
			return P.north, P.west, 0, P.inst
		end
	end
	_G.GetPlayerFacing = function()
		return P.facing
	end
	_G.CreateVector2D = Vector
	_G.C_Map.GetWorldPosFromMapPos = function(map, vec)
		local c = W.continents[map]
		if not c then
			return nil
		end
		local b = W.mapBounds[map]
		if not b then
			return c, Vector(0, 0)
		end
		local x, y = vec:GetXY()
		return c, Vector(b.n2 - y * (b.n2 - b.n1), b.w2 - x * (b.w2 - b.w1)) -- worldPosition.x = north
	end
	-- width and height of a map in yards (C_Map.GetMapWorldSize, live and forever)
	_G.C_Map.GetMapWorldSize = function(map)
		local b = W.mapBounds[map]
		if b then
			return b.w2 - b.w1, b.n2 - b.n1
		end
		return 0, 0
	end
	_G.C_Map.GetAreaInfo = function(area)
		return W.areas[area]
	end
	_G.C_Map.GetMapPosFromWorldPos = function(cont, world, map)
		local b = W.mapBounds[map]
		if not b or W.continents[map] ~= cont then
			return nil
		end
		local north, west = world:GetXY()
		return map, Vector((b.w2 - west) / (b.w2 - b.w1), (b.n2 - north) / (b.n2 - b.n1))
	end
	_G.C_Map.CanSetUserWaypointOnMap = function()
		return true
	end
	_G.C_Map.SetUserWaypoint = function(point)
		audit("C_Map.SetUserWaypoint")
		W.waypoint = point
		return true
	end
	_G.C_Map.ClearUserWaypoint = function()
		audit("C_Map.ClearUserWaypoint")
		W.waypoint = nil
	end
	_G.UiMapPoint = {
		CreateFromCoordinates = function(map, x, y)
			return { uiMapID = map, x = x, y = y }
		end,
	}
	_G.C_SuperTrack = {
		SetSuperTrackedUserWaypoint = function(on)
			audit("C_SuperTrack.SetSuperTrackedUserWaypoint")
			W.supertrack = on
		end,
	}
	_G.C_Minimap = {
		GetViewRadius = function()
			return 200
		end,
	}
	_G.Minimap = NewWidget("Frame")
	_G.Minimap:SetSize(140, 140)
	W.cursor = { 0, 0 }
	_G.GetCursorPosition = function()
		return W.cursor[1], W.cursor[2]
	end
	W.shift = false
	_G.IsShiftKeyDown = function()
		return W.shift == true
	end
	M.layout = function(o)
		U.layout(M, W, o)
	end
	U.layout(M, W, {})

	-- Mixins and pools
	_G.Mixin = function(obj, ...)
		for i = 1, select("#", ...) do
			copyInto(obj, (select(i, ...)))
		end
		return obj
	end
	_G.CreateFromMixins = function(...)
		return _G.Mixin({}, ...)
	end
	_G.CreateFramePool = function()
		return {}
	end
	_G.MapCanvasPinMixin = {
		SetPosition = function(self, x, y)
			self.x, self.y = x, y
		end,
		UseFrameLevelType = function() end,
		OnLoad = function() end,
		GetMap = function(self)
			return self.owningMap
		end,
		SetIgnoreGlobalPinScale = function(self, on)
			self.ignoreGlobalPinScale = on
		end,
	}
	_G.MapCanvasDataProviderMixin = {
		GetMap = function(self)
			return self.owningMap
		end,
		OnAdded = function(self, map)
			self.owningMap = map
		end,
	}
	local wm = NewWidget("Frame", "WorldMapFrame")
	wm.pinPools, wm.pins, wm.providers, wm.mapID = {}, {}, {}, 1429
	wm.canvas = NewWidget("Frame", nil, nil, wm)
	wm.canvas:SetSize(1002, 668) -- size of Blizzard's world map canvas for a zone
	function wm.GetCanvas(self)
		return self.canvas
	end
	function wm.GetMapID(self)
		return self.mapID
	end
	function wm.AddDataProvider(self, p)
		self.providers[#self.providers + 1] = p
		p:OnAdded(self)
	end
	-- Order and wiring of MapCanvasMixin:AcquirePin (Blizzard_MapCanvas.lua forever): owning map, motion
	-- scripts only for a new pin that takes mouse motion, OnLoad, Show, OnAcquired.
	function wm.AcquirePin(self, template, ...)
		local pool = self.pinPools[template]
		local pin = pool.createFunc()
		pin.owningMap = self
		if rawget(pin, "motion") then
			pin:SetScript("OnEnter", pin.OnMouseEnter)
			pin:SetScript("OnLeave", pin.OnMouseLeave)
		end
		pin:OnLoad()
		pin:Show()
		pin:OnAcquired(...)
		pin.pinTemplate = template
		self.pins[#self.pins + 1] = pin
		return pin
	end
	function wm.RemoveAllPinsByTemplate(self, template)
		for i = #self.pins, 1, -1 do
			if self.pins[i].pinTemplate == template then
				table.remove(self.pins, i)
			end
		end
	end

	-- Events through EventRegistry (Edit Mode, text size)
	_G.EventRegistry = {
		callbacks = {},
		RegisterCallback = function(self, event, fn, owner)
			self.callbacks[event] = self.callbacks[event] or {}
			table.insert(self.callbacks[event], { fn = fn, owner = owner })
		end,
		TriggerEvent = function(self, event, ...)
			for _, c in ipairs(self.callbacks[event] or {}) do
				c.fn(c.owner, ...)
			end
		end,
	}

	-- Addon compartment
	_G.AddonCompartmentFrame = {
		registered = {},
		RegisterAddon = function(self, data)
			self.registered[#self.registered + 1] = data
		end,
	}

	-- HelpTip (Blizzard_SharedXML/HelpTip.lua): false when help tips are off, gamepad UI, kiosk.
	-- Hide closes the tip; it counts as seen only with acknowledgeOnHide (HelpTipTemplateMixin:Close).
	local function tipMatches(t, parent, text)
		return t.visible and t.parent == parent and (text == nil or t.info.text == text)
	end
	_G.HelpTip = {
		ButtonStyle = { None = 1, Close = 2, Okay = 3, GotIt = 4 },
		Point = { LeftEdgeCenter = 10 },
		Show = function(_, parent, info)
			audit("HelpTip.Show")
			W.helptips[#W.helptips + 1] = { parent = parent, info = info, visible = W.helptipResult == true }
			return W.helptipResult
		end,
		IsShowing = function(_, parent, text)
			for _, t in ipairs(W.helptips) do
				if tipMatches(t, parent, text) then
					return true
				end
			end
			return false
		end,
		Hide = function(_, parent, text)
			for _, t in ipairs(W.helptips) do
				if tipMatches(t, parent, text) then
					t.visible = false
					if t.info.acknowledgeOnHide and t.info.onAcknowledgeCallback then
						t.info.onAcknowledgeCallback()
					end
					return
				end
			end
		end,
	}
	-- Blizzard's settings window (Blizzard_Settings): OpenToCategory shows it.
	local panel = NewWidget("Frame", "SettingsPanel")
	panel.shown = false

	-- StaticPopup
	_G.StaticPopupDialogs = {}
	M.popup = nil
	_G.StaticPopup_Show = function(which, a1, a2, data)
		local d = _G.StaticPopupDialogs[which]
		assert(d, "Dialog " .. tostring(which) .. " does not exist.")
		M.popup = { which = which, text = d.text:format(a1, a2), data = data, dialog = d }
		return M.popup
	end
	_G.StaticPopup_Hide = function(which)
		if M.popup and M.popup.which == which then
			M.popup = nil
		end
	end
	-- Blizzard_StaticPopup/StaticPopup.lua (live and forever): calls func for every shown dialog.
	_G.StaticPopup_ForEachShownDialog = function(func)
		if M.popup then
			func(M.popup)
		end
	end

	-- Menus (Blizzard_Menu): the root description records its elements.
	M.menu = nil
	local function Description()
		local root = { items = {} }
		local function add(e)
			root.items[#root.items + 1] = e
			e.enabled = true
			function e.SetEnabled(item, on)
				item.enabled = on
			end
			return e
		end
		function root.CreateTitle(_, text)
			return add({ kind = "title", text = text })
		end
		function root.CreateButton(_, text, fn)
			return add({ kind = "button", text = text, fn = fn })
		end
		function root.CreateCheckbox(_, text, get, set)
			return add({ kind = "checkbox", text = text, get = get, set = set })
		end
		function root.CreateDivider()
			return add({ kind = "divider" })
		end
		return root
	end
	_G.MenuUtil = {
		CreateContextMenu = function(owner, generator)
			local root = Description()
			generator(owner, root)
			M.menu = root
			return root
		end,
	}

	-- Settings panel (Blizzard_Settings_Shared, 11.0.2+ signatures; brain chapter 04 §9, 18 §2)
	local reg = { categories = {}, settings = {}, opened = {} }
	W.settings = reg
	local function Category(name, parent, canvas)
		local c = { name = name, parent = parent, canvas = canvas, inits = {}, id = #reg.categories + 1 }
		function c.GetID(self)
			return self.id
		end
		local layout = {
			AddInitializer = function(_, init)
				c.inits[#c.inits + 1] = init
			end,
		}
		c.layout = layout
		reg.categories[#reg.categories + 1] = c
		return c, layout
	end
	local function Initializer(cat, t)
		function t.SetParentInitializer(self, parent, predicate)
			self.parentInit, self.modifyPredicate = parent, predicate
		end
		cat.inits[#cat.inits + 1] = t
		return t
	end
	_G.Settings = {
		VarType = { Boolean = "boolean", Number = "number", String = "string" },
		RegisterVerticalLayoutCategory = function(name)
			return Category(name)
		end,
		RegisterVerticalLayoutSubcategory = function(parent, name)
			return Category(name, parent)
		end,
		RegisterCanvasLayoutSubcategory = function(parent, frame, name)
			local c = Category(name, parent, true)
			c.frame = frame
			return c
		end,
		RegisterAddOnCategory = function(cat)
			cat.registered = true
		end,
		RegisterAddOnSetting = function(cat, variable, key, tbl, vtype, name, default)
			assert(type(tbl) == "table", "variableTbl must be a table")
			assert(reg.settings[variable] == nil, "setting registered twice: " .. variable)
			if tbl[key] == nil then
				tbl[key] = default
			end
			local s =
				{ variable = variable, key = key, tbl = tbl, vtype = vtype, name = name, default = default, cat = cat }
			function s.GetValue(self)
				return self.tbl[self.key]
			end
			function s.SetValue(self, v)
				if self.tbl[self.key] == v then
					return
				end
				self.tbl[self.key] = v
				if self.cb then
					self.cb(self, v)
				end
			end
			function s.SetValueChangedCallback(self, fn)
				self.cb = fn
			end
			reg.settings[variable] = s
			return s
		end,
		CreateCheckbox = function(cat, setting, tooltip)
			assert(setting.vtype == "boolean")
			return Initializer(cat, { kind = "checkbox", setting = setting, tooltip = tooltip })
		end,
		CreateSliderOptions = function(min, max, step)
			return {
				min = min,
				max = max,
				step = step,
				SetLabelFormatter = function(self, _, fn)
					self.formatter = fn
				end,
			}
		end,
		CreateSlider = function(cat, setting, options, tooltip)
			assert(setting.vtype == "number" and options)
			return Initializer(cat, { kind = "slider", setting = setting, options = options, tooltip = tooltip })
		end,
		CreateControlTextContainer = function()
			return {
				data = {},
				Add = function(self, value, label, tooltip)
					self.data[#self.data + 1] = { value = value, label = label, tooltip = tooltip }
				end,
				GetData = function(self)
					return self.data
				end,
			}
		end,
		CreateDropdown = function(cat, setting, getOptions, tooltip)
			return Initializer(cat, { kind = "dropdown", setting = setting, options = getOptions, tooltip = tooltip })
		end,
		OpenToCategory = function(id)
			audit("Settings.OpenToCategory")
			reg.opened[#reg.opened + 1] = id
			_G.SettingsPanel:Show()
		end,
		GetValue = function(variable)
			local s = reg.settings[variable]
			return s and s:GetValue()
		end,
		SetValue = function(variable, v)
			local s = reg.settings[variable]
			assert(s, "unknown setting " .. tostring(variable))
			s:SetValue(v)
		end,
	}
	_G.MinimalSliderWithSteppersMixin = { Label = { Left = 1, Right = 2 } }
	_G.CreateSettingsButtonInitializer = function(name, text, click, tooltip, addSearchTags)
		assert(addSearchTags ~= nil, "addSearchTags is required")
		return { kind = "button", name = name, text = text, click = click, tooltip = tooltip }
	end
	_G.CreateSettingsListSectionHeaderInitializer = function(name, tooltip)
		return { kind = "header", name = name, tooltip = tooltip }
	end
end

-- Screen and Blizzard's frames at the top right in Retail measures (Welle 5c, owner readings 16 and 17).
-- Formulas and numbers from Gethe/wow-ui-source live 12.1.5 (d07eb00), forever 1.60.1 (ca8368f):
--   * UIParent 1920x1080 units at UI scale 0.711 on a 1080p screen ("1080"), 1366x768 at scale 1
--     ("768"); left and bottom 0.
--   * MinimapCluster 256x256 at TOPRIGHT (Blizzard_Minimap/Mainline/Minimap.xml).
--   * MultiBarRight and MultiBarLeft: 12 buttons of 45 with padding 2 in one column, 45x562 (Mainline/
--     ActionButtonTemplate.xml, EditModePresetLayouts.lua IconPadding 2). EditModeManagerFrameMixin:
--     UpdateRightActionBarPositions anchors them RIGHT of UIParent at x -5 and -55 (bar width 45 + 5),
--     y -77, and scales them by the space between MinimapCluster:GetBottom() - 10 and
--     MicroButtonAndBagsBar:GetTop() + 24 (bags bar 232x80 at BOTTOMRIGHT -6/6, MicroMenuContainer.xml).
--     A bar's GetLeft counts in its own scale, so the stand-in returns its edges divided by that scale.
--   * ObjectiveTrackerFrame 260 wide in the right container: TOPRIGHT at x -(GetRightActionBarWidth()
--     + 5), y -260 (EditModeUtil.lua, RIGHT_CONTAINER_OFFSET_Y), down to the screen bottom.
-- o.screen = "1080" (default) | "768"; o.bars = right bars shown, 2 (default) | 1 | 0.
function U.layout(M, W, o)
	local NewWidget = M.NewWidget
	local w, h = 1920, 1080
	if o.screen == "768" then
		w, h = 1366, 768
	end
	local function frame(name)
		local f = _G[name]
		if not (type(f) == "table" and f.events) then
			f = NewWidget("Frame", name)
		end
		return f
	end
	local function place(f, l, r, t, b, scale)
		scale = scale or 1
		f.norect = nil
		f.left, f.right, f.top, f.bottom = l / scale, r / scale, t / scale, b / scale
		f.w, f.h, f.scale = (r - l) / scale, (t - b) / scale, scale
	end
	local ui = _G.UIParent
	ui.left, ui.right, ui.top, ui.bottom, ui.w, ui.h = 0, w, h, 0, w, h
	ui.shown = true
	place(frame("MinimapCluster"), w - 256, w, h, h - 256)
	local avail = (h - 256 - 10) - (6 + 80 + 24)
	local barH = 12 * 45 + 11 * 2
	local scale = barH > avail and avail / barH or 1
	local bars = o.bars or 2
	local cy = h / 2 - 77 * scale
	for i, name in ipairs({ "MultiBarRight", "MultiBarLeft" }) do
		local f = frame(name)
		local right = w - (i == 1 and 5 or 55) * scale
		place(f, right - 45 * scale, right, cy + barH / 2 * scale, cy - barH / 2 * scale, scale)
		f.shown = i <= bars
	end
	-- bars 6 to 8 stand in the middle (EditModePresetLayouts.lua ExtraBar1..3: TOP at CENTER, 0/-50/-100)
	for i, name in ipairs({ "MultiBar5", "MultiBar6", "MultiBar7" }) do
		local width = 12 * 45 + 11 * 2
		local top = h / 2 - (i - 1) * 50
		place(frame(name), w / 2 - width / 2, w / 2 + width / 2, top, top - 45)
	end
	local barsWidth = ({ [0] = 0, [1] = 5 + 45, [2] = 55 + 45 })[bars] or 0
	local tracker = frame("ObjectiveTrackerFrame")
	place(tracker, w - barsWidth - 5 - 260, w - barsWidth - 5, h - 260, 0)
	W.screen = { w = w, h = h, barScale = scale }
end

return U
