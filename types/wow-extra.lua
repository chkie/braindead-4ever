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
