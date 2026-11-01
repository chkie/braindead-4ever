-- SPDX-License-Identifier: GPL-3.0-or-later
-- WoW API stand-ins for offline tests on stock Lua 5.1.
-- Unknown names stay nil, so a missing stand-in cannot silently change a test.
-- Values follow the Forever docs (Gethe/wow-ui-source branch forever, build 70532);
-- they describe what the code expects, not measurements from a live client.
local M = {}

local stock_xpcall = xpcall
M.stock_xpcall = stock_xpcall

-- WoW's xpcall passes extra arguments to f (stock Lua 5.1 does not).
local function wow_xpcall(f, handler, ...)
	local n = select("#", ...)
	if n == 0 then
		return stock_xpcall(f, handler)
	end
	local args = { ... }
	return stock_xpcall(function()
		return f(unpack(args, 1, n))
	end, handler)
end

-- Opaque value that issecretvalue() reports as secret.
M.SECRET = setmetatable({}, {
	__tostring = function()
		return "SECRET-VALUE"
	end,
})

local BASE_EVENTS = {
	"ADDON_LOADED",
	"PLAYER_LOGIN",
	"PLAYER_ENTERING_WORLD",
	"PLAYER_LOGOUT",
	"QUEST_ACCEPTED",
	"PLAYER_XP_UPDATE",
	"PLAYER_STARTED_MOVING",
}

local FLAVORS = {
	forever = {
		build = { "1.60.1", "70532", "Oct 20 2026", 16001 },
		project = 18,
		extraEvents = { "GAME_RULES_CHANGED" },
	},
	retail = {
		build = { "12.1.5", "70448", "Oct 14 2026", 120105 },
		project = 1,
		extraEvents = {},
	},
}

local Frame = {}
Frame.__index = Frame

function Frame:RegisterEvent(event)
	-- Since 8.0.1 the client throws for unknown event names.
	if not M.knownEvents[event] then
		error(('Attempt to register unknown event "%s"'):format(tostring(event)), 2)
	end
	self.events[event] = true
end

function Frame:UnregisterEvent(event)
	self.events[event] = nil
end

function Frame:SetScript(name, fn)
	self.scripts[name] = fn
end

function Frame:GetScript(name)
	return self.scripts[name]
end

local function join(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	return table.concat(parts, " ")
end

-- Fresh client state. opts: flavor ("forever" | "retail"), locale, version, saved (PathmarkDB).
function M.reset(opts)
	opts = opts or {}
	local flavor = FLAVORS[opts.flavor or "forever"]
	M.flavor = opts.flavor or "forever"
	M.clock = 1000
	M.timers = {}
	M.frames = {}
	M.errors = {}
	M.printed = {}
	M.knownEvents = {}
	for _, e in ipairs(BASE_EVENTS) do
		M.knownEvents[e] = true
	end
	for _, e in ipairs(flavor.extraEvents) do
		M.knownEvents[e] = true
	end

	_G.xpcall = wow_xpcall
	_G.GetTime = function()
		return M.clock
	end
	_G.issecretvalue = function(v)
		return v == M.SECRET
	end
	_G.geterrorhandler = function()
		return function(msg)
			M.errors[#M.errors + 1] = msg
		end
	end
	_G.debugstack = function()
		return "stack"
	end
	_G.print = function(...)
		M.printed[#M.printed + 1] = join(...)
	end
	_G.CreateFrame = function(frameType)
		local f = setmetatable({ type = frameType, events = {}, scripts = {} }, Frame)
		M.frames[#M.frames + 1] = f
		return f
	end
	_G.C_EventUtils = {
		IsEventValid = function(event)
			return M.knownEvents[event] == true
		end,
	}
	_G.C_Timer = {
		After = function(seconds, callback)
			M.timers[#M.timers + 1] = { at = M.clock + seconds, fn = callback }
		end,
	}
	_G.C_AddOns = {
		GetAddOnMetadata = function(_, field)
			if field == "Version" then
				return opts.version or "@project-version@"
			end
		end,
	}
	_G.GetLocale = function()
		return opts.locale or "enUS"
	end
	_G.GetBuildInfo = function()
		return unpack(flavor.build)
	end
	_G.WOW_PROJECT_MAINLINE = 1
	_G.WOW_PROJECT_CLASSIC = 2
	_G.WOW_PROJECT_ID = flavor.project
	if M.flavor == "forever" then
		_G.WOW_PROJECT_CAMELOT = 18
		_G.C_QuestLog = {
			GetTrivialRange = function()
				return 5
			end,
		}
		_G.C_SkillInfo = { AbandonSkill = function() end }
	else
		_G.WOW_PROJECT_CAMELOT = nil
		_G.C_QuestLog = {}
		-- Retail 12.1.5 documents C_SkillInfo with no functions: a namespace without the call.
		_G.C_SkillInfo = {}
	end
	_G.SlashCmdList = {}
	_G.SLASH_PATHMARK1 = nil
	_G.PathmarkDB = opts.saved
end

-- Fire an event at every frame that registered it (like the client).
function M.fire(event, ...)
	for _, f in ipairs(M.frames) do
		local handler = f.scripts.OnEvent
		if f.events[event] and handler then
			handler(f, event, ...)
		end
	end
end

-- Advance the clock and run due timers in order.
function M.advance(seconds)
	M.clock = M.clock + seconds
	local due, rest = {}, {}
	for _, t in ipairs(M.timers) do
		if t.at <= M.clock then
			due[#due + 1] = t
		else
			rest[#rest + 1] = t
		end
	end
	M.timers = rest
	table.sort(due, function(a, b)
		return a.at < b.at
	end)
	for _, t in ipairs(due) do
		t.fn()
	end
end

-- Load one addon file like the client: with (addonName, ns) as varargs.
function M.loadFile(path, addonName, ns)
	local chunk = assert(loadfile(path))
	chunk(addonName, ns)
	return ns
end

-- Load several addon files into one namespace.
function M.loadFiles(paths, addonName, ns)
	ns = ns or {}
	for _, p in ipairs(paths) do
		M.loadFile(p, addonName or "Pathmark", ns)
	end
	return ns
end

-- Lines printed so far, as one string.
function M.output()
	return table.concat(M.printed, "\n")
end

return M
