-- SPDX-License-Identifier: GPL-3.0-or-later
-- Luacheck for Pathmark (pattern after BigWigs/Questie). WoW Lua is 5.1.
-- read_globals is the API inventory: list only what the addon really uses, and check each
-- new name against the Forever API dump before adding it.
std = "lua51"
max_line_length = false
codes = true
exclude_files = { ".tools/**", ".release/**", ".lua/**", ".luarocks/**", "types/**" }
ignore = {
	"212/self", -- unused self in methods
	"211/_.*", -- deliberately ignored locals with _ prefix
}
read_globals = {
	-- WoW API used by the addon
	-- namespaces list their used functions, so a misspelled field is W143
	C_AddOns = { fields = { "GetAddOnMetadata" } },
	C_EventUtils = { fields = { "IsEventValid" } },
	C_Timer = { fields = { "After" } },
	"CreateFrame",
	"GetBuildInfo",
	"GetLocale",
	"GetTime",
	-- error handling and secret values
	"debugstack",
	"geterrorhandler",
	"issecretvalue",
	-- flavor constants (WOW_PROJECT_CAMELOT exists only in Forever)
	"WOW_PROJECT_ID",
}
globals = {
	"PathmarkDB", -- ## SavedVariables
	"SLASH_PATHMARK1",
	"SlashCmdList",
}
files["spec/**/*.lua"] = { std = "+busted", globals = { "_G" } }
