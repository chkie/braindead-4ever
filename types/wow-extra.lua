---@meta
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Type stubs for WoW globals that the pinned Ketho annotations (WoW 12.0.1) do not declare.
-- Only for the Lua Language Server; never loaded by the game, never packaged.
-- Sources: Gethe/wow-ui-source branch forever (1.60.1, build 70532).

---Slash command handlers, keyed by the name used in SLASH_<NAME>1. FrameXML (ChatFrame).
---@type table<string, fun(msg: string, editBox: table?)>
SlashCmdList = {}

---Project ID of WoW: Forever. Defined only in the Forever client
---(Blizzard_ProjectConstants/Camelot/ProjectConstants.lua), nil elsewhere.
---@type number?
WOW_PROJECT_CAMELOT = 18

---Close button text (GlobalStrings). Forever: Ketho GlobalStrings forever, used by Blizzard frames.
---@type string
CLOSE = "Close"

---"New flight path discovered!" (GlobalStrings, deDE "Neue Flugroute entdeckt!").
---@type string
ERR_NEWTAXIPATH = ""

---Frames closed by the Escape key (FrameXML UIParentPanelManager).
---@type string[]
UISpecialFrames = {}

---Number of chat windows (FrameXML ChatFrame constants).
---@type number
NUM_CHAT_WINDOWS = 10

---Party category of instance groups (FrameXML constant; IsInGroup(LE_PARTY_CATEGORY_INSTANCE)).
---@type number
LE_PARTY_CATEGORY_INSTANCE = 2

---"Firstname Lastname" in Forever, name without realm in Retail; Forever ignores the second argument
---(FrameXML Mainline/UnitFrame.lua, Camelot/NameUtil.lua).
---@param unit string
---@param showServerName? boolean
---@return string?
function GetUnitName(unit, showServerName) end
