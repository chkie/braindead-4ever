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

-- Interface (UI/, Welle 5). FrameXML globals the pinned annotations do not declare; names checked in
-- the Forever inventories (Ketho BlizzardInterfaceResources branch forever, wow-ui-source forever).

---Blizzard settings panel (Blizzard_Settings_Shared, 11.0.2+ signatures).
---@type table<string, any>
Settings = {}

---@param name string
---@param buttonText string
---@param buttonClick function
---@param tooltip string?
---@param addSearchTags boolean
---@return table
function CreateSettingsButtonInitializer(name, buttonText, buttonClick, tooltip, addSearchTags) end

---@param name string
---@param tooltip string?
---@return table
function CreateSettingsListSectionHeaderInitializer(name, tooltip) end

---@type table<string, any>
MinimalSliderWithSteppersMixin = {}

---Context help bubble (Blizzard_SharedXML/HelpTip.lua).
---@type table<string, any>
HelpTip = {}

---Dialogs by name (Blizzard_StaticPopup).
---@type table<string, table>
StaticPopupDialogs = {}

---@param which string
---@param text_arg1? string
---@param text_arg2? string
---@param data? any
---@return table?
function StaticPopup_Show(which, text_arg1, text_arg2, data) end

---Hides the shown dialog of that name (Blizzard_StaticPopup/StaticPopup.lua, live and forever).
---@param which string
---@param data? any
function StaticPopup_Hide(which, data) end

---Calls func for every shown dialog (Blizzard_StaticPopup/StaticPopup.lua, live and forever).
---@param func fun(dialog: table)
function StaticPopup_ForEachShownDialog(func) end

---Blizzard's settings window (Blizzard_Settings_Shared/Blizzard_SettingsPanel.xml, live and forever).
---@type table<string, any>
SettingsPanel = {}

---Addon compartment at the minimap (Blizzard_Minimap/Mainline/AddonCompartment.lua).
---@type table<string, any>
AddonCompartmentFrame = {}

---@type table<string, any>
UIErrorsFrame = {}

---World map (Blizzard_WorldMap) with its pin pools.
---@type table<string, any>
WorldMapFrame = {}

---@type table<string, any>
MapCanvasDataProviderMixin = {}

---@type table<string, any>
MapCanvasPinMixin = {}

---@type table<string, any>
UiMapPoint = {}

---Frame pools (Blizzard_SharedXMLBase/Pools.lua).
---@param frameType string
---@param parent? table
---@return table
function CreateFramePool(frameType, parent) end

---@param template string
---@return table
function CreateUnsecuredRegionPoolInstance(template) end

---Tracker colors (Blizzard_ObjectiveTrackerShared.lua): Normal, Complete, Failed, ...
---@type table<string, table>
OBJECTIVE_TRACKER_COLOR = {}

---Sound kit IDs (Mainline/SoundKitConstants.lua).
---@type table<string, number>
SOUNDKIT = {}

---GlobalStrings (deDE / enUS values in brain chapter 18 §1.7).
---@type string
IN_GAME_NAVIGATION_RANGE = "%s |4yd:yds"
---@type string
NAVIGATION_DESTINATION_REACHED_MESSAGE = ""
---@type string
HUD_EDIT_MODE_MENU = ""
---@type string
CANCEL = ""
---@type string
OPTIONAL = ""
---@type string
LFG_TYPE_DUNGEON = ""
---@type string
XP = ""

-- Welle 5b: scroll list of the step window (wow-ui-source forever Blizzard_SharedXML/Shared/Scroll).

---@type table<string, any>
ScrollUtil = {}

---@type table<string, any>
ScrollBoxConstants = {}

---Linear view for static scroll boxes (ScrollBoxLinearView.lua).
---@param top? number
---@param bottom? number
---@param left? number
---@param right? number
---@param spacing? number
---@return table
function CreateScrollBoxLinearView(top, bottom, left, right, spacing) end

---Blizzard's quest tracker (Blizzard_ObjectiveTracker/Blizzard_ObjectiveTracker.xml); Pathmark only
---reads and sets its alpha (UI/QuestWatch.lua).
---@type table<string, any>
ObjectiveTrackerFrame = {}

---Blizzard's minimap cluster (Blizzard_Minimap/Mainline/Minimap.xml, 256x256 at the top right);
---Pathmark only reads its edges for the step window's default place (UI/StepFrame.lua, Welle 5c).
---@type table<string, any>
MinimapCluster = {}

-- Welle 8: tabs of the page "Your run" (Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua, forever).

---@param frame table
---@param id number
function PanelTemplates_SetTab(frame, id) end

---@param frame table
---@param numTabs number
function PanelTemplates_SetNumTabs(frame, numTabs) end

---@param tab table
---@param padding? number
---@param absoluteSize? number
---@param minWidth? number
---@param maxWidth? number
---@param absoluteTextSize? number
function PanelTemplates_TabResize(tab, padding, absoluteSize, minWidth, maxWidth, absoluteTextSize) end
