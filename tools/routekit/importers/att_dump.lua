-- SPDX-License-Identifier: GPL-3.0-or-later
-- Reads the All The Things Forever database (.contrib/.db, MIT) in a Lua 5.1 sandbox and
-- prints one JSON object per line. Usage:
--   lua att_dump.lua <path to .contrib/.db> > att.jsonl
-- Lines without "kind" are quests (zone files and dungeon files); "kind":"dungeon" is an
-- instance (instanceroot in "dungeons & raids"), "kind":"find" an entry under the TREASURES,
-- RARES or FLIGHT_PATHS header of a zone file (discovery catalog).
-- Only facts are written: IDs, coordinates (map percent), prerequisites, races, classes,
-- levels, flags. Names, comments and descriptions are not read.
local root = assert(arg[1], "usage: lua att_dump.lua <.contrib/.db>")

-- Placeholder for every unknown global: callable, indexable, arithmetic-safe.
local Placeholder = {}
local function placeholder(name)
	return setmetatable({ _ph = name }, Placeholder)
end
Placeholder.__index = function(t, k)
	return placeholder(rawget(t, "_ph") .. "." .. tostring(k))
end
-- Calls of unknown functions become nodes; a node can be concatenated (ATT builds tooltip
-- code strings with calls like WOWAPI_GetItemCount(id)).
local NodeMT = {
	__concat = function()
		return ""
	end,
}
Placeholder.__call = function(t, ...)
	return setmetatable({ _k = rawget(t, "_ph"), args = { ... } }, NodeMT)
end
for _, mm in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__unm", "__concat" }) do
	Placeholder[mm] = function()
		return placeholder("arith")
	end
end

local env = {}
local std = {
	"string",
	"table",
	"math",
	"pairs",
	"ipairs",
	"type",
	"tostring",
	"tonumber",
	"select",
	"unpack",
	"setmetatable",
	"getmetatable",
	"rawget",
	"rawset",
	"next",
	"error",
	"pcall",
	"assert",
}
for _, k in ipairs(std) do
	env[k] = _G[k]
end
env._G = env
env.print = function() end
env.tinsert = function(t, ...)
	if type(t) == "table" and getmetatable(t) ~= Placeholder then
		table.insert(t, ...)
	end
end
env.MAP = {}
setmetatable(env, {
	__index = function(_, k)
		return placeholder(k)
	end,
})

-- Constructors the dump looks at. Everything else becomes a generic node via the placeholder.
local function node(kind)
	return function(...)
		return { _k = kind, args = { ... } }
	end
end
env.q = node("q")
env.m = node("m")
env.maproot = node("maproot")
env.objective = node("objective")

local function runFile(path)
	local chunk, err = loadfile(path)
	if not chunk then
		return false, err
	end
	setfenv(chunk, env)
	return pcall(chunk)
end

local function mustRun(path)
	local ok, err = runFile(path)
	if not ok then
		io.stderr:write("constants failed: " .. path .. ": " .. tostring(err) .. "\n")
		os.exit(2)
	end
end

-- raceIDs.lua and classIDs.lua define their constants first and then cross-check them against
-- export tables this sandbox does not have; the error after the definitions is expected.
runFile(root .. "/shared/constants/raceIDs.lua")
runFile(root .. "/shared/constants/classIDs.lua")
for _, k in ipairs({ "HUMAN", "DWARF", "NIGHTELF", "GNOME", "SKYBORNE_ALLIANCE", "ORC", "UNDEAD", "TAUREN", "TROLL" }) do
	if type(rawget(env, k)) ~= "number" then
		io.stderr:write("race constant missing: " .. k .. "\n")
		os.exit(2)
	end
end
for _, k in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
	if type(rawget(env, k)) ~= "number" then
		io.stderr:write("class constant missing: " .. k .. "\n")
		os.exit(2)
	end
end
mustRun(root .. "/forever/.config/constants/timelines.lua")
mustRun(root .. "/forever/.config/constants/maps.lua")
mustRun(root .. "/forever/.config/constants/races.lua")

-- Collect every zone file; maproot/root register their trees through these calls.
local roots = {}
local currentFile
env.maproot = function(...)
	local n = { _k = "maproot", args = { ... }, file = currentFile }
	roots[#roots + 1] = n
	return n
end
env.root = function(...)
	local n = { _k = "root", args = { ... }, file = currentFile }
	roots[#roots + 1] = n
	return n
end
env.instanceroot = function(...)
	local n = { _k = "instanceroot", args = { ... }, file = currentFile }
	roots[#roots + 1] = n
	return n
end

-- Zone files, dungeon files and the library books (only to tell book objects from chests).
local DUNGEONS = root .. "/forever/dungeons & raids"
local BOOKS = root .. "/forever/expansion features/library books.lua"
local files = {}
for _, dir in ipairs({ root .. "/forever/zones", DUNGEONS }) do
	local p = io.popen('find "' .. dir .. '" -name "*.lua" | sort')
	for line in p:lines() do
		files[#files + 1] = line
	end
	p:close()
end
files[#files + 1] = BOOKS
local failed = 0
for _, f in ipairs(files) do
	currentFile = f
	local ok, err = runFile(f)
	if not ok then
		failed = failed + 1
		io.stderr:write("file failed: " .. f .. ": " .. tostring(err) .. "\n")
	end
end
currentFile = nil

-- JSON output (numbers, strings, booleans, arrays, objects).
local function isArray(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n == #t
end
local function json(v)
	local tv = type(v)
	if tv == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return "null"
		end
		if v == math.floor(v) and math.abs(v) < 1e15 then
			return string.format("%d", v)
		end
		return string.format("%.4f", v)
	elseif tv == "string" then
		return '"' .. v:gsub('[%c"\\]', function(c)
			return string.format("\\u%04x", c:byte())
		end) .. '"'
	elseif tv == "boolean" then
		return tostring(v)
	elseif tv == "table" then
		local out = {}
		if isArray(v) then
			for i = 1, #v do
				out[i] = json(v[i])
			end
			return "[" .. table.concat(out, ",") .. "]"
		end
		local keys = {}
		for k in pairs(v) do
			keys[#keys + 1] = tostring(k)
		end
		table.sort(keys)
		for _, k in ipairs(keys) do
			out[#out + 1] = json(k) .. ":" .. json(v[k])
		end
		return "{" .. table.concat(out, ",") .. "}"
	end
	return "null"
end

local function num(v)
	return type(v) == "number" and v or nil
end

local function numList(v)
	if type(v) == "number" then
		return { v }
	end
	if type(v) ~= "table" or getmetatable(v) == Placeholder then
		return nil
	end
	local out = {}
	for _, x in ipairs(v) do
		if type(x) == "number" then
			out[#out + 1] = x
		end
	end
	return #out > 0 and out or nil
end

local function coordList(t)
	local out = {}
	local function add(c)
		if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number" then
			out[#out + 1] = { c[1], c[2], c[3] }
		end
	end
	add(t.coord)
	if type(t.coords) == "table" and getmetatable(t.coords) ~= Placeholder then
		for _, c in ipairs(t.coords) do
			add(c)
		end
	end
	return #out > 0 and out or nil
end

local function providerList(t)
	local out = {}
	local function add(pv)
		if type(pv) == "table" and type(pv[1]) == "string" and type(pv[2]) == "number" then
			out[#out + 1] = { pv[1], pv[2] }
		end
	end
	add(t.provider)
	if type(t.providers) == "table" and getmetatable(t.providers) ~= Placeholder then
		for _, pv in ipairs(t.providers) do
			add(pv)
		end
	end
	return #out > 0 and out or nil
end

local function timelineList(t)
	if type(t.timeline) ~= "table" or getmetatable(t.timeline) == Placeholder then
		return nil
	end
	local out = {}
	for _, s in ipairs(t.timeline) do
		if type(s) == "string" then
			out[#out + 1] = s
		end
	end
	return #out > 0 and out or nil
end

local count, dungeons, finds = 0, 0, 0
local seenTables = {}
local walk

local function emitQuest(n, ctx)
	local id = n.args[1]
	local t = n.args[2]
	if type(id) ~= "number" then
		return
	end
	if type(t) ~= "table" or getmetatable(t) == Placeholder then
		t = {}
	end
	local objectives = {}
	if type(t.groups) == "table" then
		for _, g in ipairs(t.groups) do
			if type(g) == "table" and g._k == "objective" then
				local ot = g.args[2]
				if type(ot) == "table" then
					objectives[#objectives + 1] = {
						n = num(g.args[1]),
						providers = providerList(ot),
						cr = numList(ot.cr) or numList(ot.crs),
						coords = coordList(ot),
					}
				end
			end
		end
	end
	local rec = {
		q = id,
		zoneMap = ctx.map,
		side = ctx.side,
		instance = ctx.instance,
		coords = coordList(t),
		qg = numList(t.qg) or numList(t.qgs),
		providers = providerList(t),
		sourceQuests = numList(t.sourceQuest) or numList(t.sourceQuests),
		altQuests = numList(t.altQuests),
		races = numList(t.races),
		classes = numList(t.classes),
		lvl = num(t.lvl),
		breadcrumb = t.isBreadcrumb == true or nil,
		repeatable = t.repeatable == true or nil,
		timeline = timelineList(t),
		objectives = #objectives > 0 and objectives or nil,
	}
	io.write(json(rec), "\n")
	count = count + 1
	-- nested quests (rare) and faction variants
	walk(t, ctx)
end

-- Item IDs in the groups of a node (rewards, contents of a chest).
local function groupItems(t)
	local out = {}
	if type(t) == "table" and type(t.groups) == "table" and getmetatable(t.groups) ~= Placeholder then
		for _, g in ipairs(t.groups) do
			if type(g) == "table" and g._k == "i" and type(g.args[1]) == "number" then
				out[#out + 1] = g.args[1]
			end
		end
	end
	return out
end

-- Book items: providers of the library book quests (expansion features/library books.lua).
local bookItems = {}

-- Discovery catalog: treasures (chests, objects), books (objects holding a library book),
-- rares, flight paths. Only entries with a coordinate are useful as a hint.
local HEADERS = { TREASURES = "treasure", RARES = "rare", FLIGHT_PATHS = "flightpath" }
local FIND_NODES = { treasure = "o", rare = "n", flightpath = "fp" }

local function emitFind(n, ctx)
	local id, t = n.args[1], n.args[2]
	if type(id) ~= "number" then
		return
	end
	if type(t) ~= "table" or getmetatable(t) == Placeholder then
		t = {}
	end
	local coords = coordList(t)
	if not coords then
		return
	end
	local ftype = ctx.header
	local items = groupItems(t)
	if ftype == "treasure" then
		for _, it in ipairs(items) do
			if bookItems[it] then
				ftype = "book"
				break
			end
		end
	end
	io.write(
		json({
			kind = "find",
			type = ftype,
			id = id,
			zoneMap = ctx.map,
			coords = coords,
			races = numList(t.races),
			timeline = timelineList(t),
		}),
		"\n"
	)
	finds = finds + 1
end

local function emitDungeon(n)
	local id, t = n.args[1], n.args[2]
	if type(id) ~= "number" or type(t) ~= "table" then
		return
	end
	io.write(
		json({
			kind = "dungeon",
			id = id,
			area = num(t.zoneTextAreaID),
			mapID = num(t.mapID),
			coords = coordList(t),
			lvl = num(t.lvl),
			timeline = timelineList(t),
		}),
		"\n"
	)
	dungeons = dungeons + 1
end

walk = function(t, ctx)
	if type(t) ~= "table" or getmetatable(t) == Placeholder or seenTables[t] then
		return
	end
	seenTables[t] = true
	if t._k == "q" then
		emitQuest(t, ctx)
		return
	end
	if ctx.header and t._k == FIND_NODES[ctx.header] then
		emitFind(t, ctx)
		return
	end
	local nctx = ctx
	if t._k == "maproot" and type(t.args[2]) == "number" then
		nctx = { map = t.args[2], side = ctx.side }
	elseif t._k == "instanceroot" and type(t.args[1]) == "number" then
		emitDungeon(t)
		nctx = { instance = t.args[1], side = ctx.side }
	elseif t._k == "m" and type(t.args[1]) == "number" and not ctx.map then
		nctx = { map = t.args[1], side = ctx.side, instance = ctx.instance }
	elseif t._k == "n" and type(t.args[1]) == "table" and getmetatable(t.args[1]) == Placeholder then
		local header = HEADERS[rawget(t.args[1], "_ph")]
		if header and nctx.map and not nctx.instance then
			nctx = { map = nctx.map, side = nctx.side, header = header }
		end
	end
	for k, v in pairs(t) do
		if k == "allianceQuestData" then
			walk(v, { map = nctx.map, side = "Alliance", instance = nctx.instance, header = nctx.header })
		elseif k == "hordeQuestData" then
			walk(v, { map = nctx.map, side = "Horde", instance = nctx.instance, header = nctx.header })
		elseif type(v) == "table" then
			walk(v, nctx)
		end
	end
end

-- Library books first: their quests name the book items; they are not route quests.
for _, r in ipairs(roots) do
	if r.file == BOOKS then
		local stack = { r }
		while #stack > 0 do
			local entry = table.remove(stack)
			if type(entry) == "table" and getmetatable(entry) ~= Placeholder then
				if entry._k == "q" and type(entry.args[2]) == "table" then
					for _, pv in ipairs(providerList(entry.args[2]) or {}) do
						if pv[1] == "i" then
							bookItems[pv[2]] = true
						end
					end
				else
					for _, v in pairs(entry) do
						if type(v) == "table" then
							stack[#stack + 1] = v
						end
					end
				end
			end
		end
	end
end
-- Quests of dungeon and raid files carry their instance; files without an instanceroot (raids,
-- sets, world bosses) get instance 0, so no quest of these files can pass for an open-world quest.
for _, r in ipairs(roots) do
	if r.file ~= BOOKS then
		local inDungeons = r.file and r.file:sub(1, #DUNGEONS) == DUNGEONS
		walk(r, inDungeons and { instance = 0 } or {})
	end
end
io.stderr:write(
	string.format(
		"att_dump: %d files, %d failed, %d quest records, %d dungeons, %d finds\n",
		#files,
		failed,
		count,
		dungeons,
		finds
	)
)
if failed > 0 then
	os.exit(3)
end
